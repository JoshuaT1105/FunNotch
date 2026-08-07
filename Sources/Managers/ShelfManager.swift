//
//  ShelfManager.swift
//  FunNotch
//
//  The file shelf: drop things on the notch, keep them around, drag them back
//  out, AirDrop them, or preview them with Quick Look.
//

import AppKit
import Combine
import Quartz
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var name: String
    var size: Int64
    var addedAt: Date
    /// True for content we copied into our own cache (dragged text, images from
    /// a web page) rather than a file the user already had on disk.
    var isTemporary: Bool
    var thumbnail: NSImage?

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.thumbnail === rhs.thumbnail
    }

    var typeDescription: String {
        let type = UTType(filenameExtension: url.pathExtension)
        return type?.localizedDescription ?? url.pathExtension.uppercased()
    }
}

@MainActor
final class ShelfManager: NSObject, ObservableObject {
    static let shared = ShelfManager()

    @Published private(set) var items: [ShelfItem] = []
    @Published var selection: Set<UUID> = []

    private let bookmarksKey = "shelfBookmarks"
    private var accessedURLs: [URL] = []

    private lazy var temporaryDirectory: URL = {
        let base = FileManager.default.standardDirectory(.cachesDirectory, fallback: "Library/Caches")
            .appendingPathComponent("com.funnotch.FunNotch/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private var expiryTimer: Timer?

    private override init() {
        super.init()
        restore()
        startExpiryTimer()
    }

    // MARK: - Expiry

    private func startExpiryTimer() {
        expiryTimer?.invalidate()
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.dropExpiredItems() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
        dropExpiredItems()
    }

    /// Removes anything older than the configured age. 0 means "never".
    func dropExpiredItems() {
        let hours = Settings.shared.shelfExpiryHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let doomed = items.filter { $0.addedAt < cutoff }
        guard !doomed.isEmpty else { return }
        for item in doomed { remove(id: item.id) }
        DiagnosticLog.write("shelf", "dropped \(doomed.count) expired item(s)")
    }

    // MARK: - Renaming

    /// Renames the underlying file, so the new name survives a drag back out.
    @discardableResult
    func rename(id: UUID, to newName: String) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != items[index].name else { return false }

        let item = items[index]
        // Keep the extension unless the user typed one themselves.
        var finalName = trimmed
        let existingExtension = item.url.pathExtension
        if !existingExtension.isEmpty, (trimmed as NSString).pathExtension.isEmpty {
            finalName += "." + existingExtension
        }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(finalName)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return false }

        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
        } catch {
            DiagnosticLog.write("shelf", "rename failed: \(error.localizedDescription)")
            return false
        }

        items[index].url = destination
        items[index].name = destination.lastPathComponent
        persist()
        return true
    }

    // MARK: - Folder targets

    /// Copies (or moves) an item into one of the configured folders.
    @discardableResult
    func send(id: UUID, toFolder folder: URL, keepingOriginal: Bool = true) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }

        var destination = folder.appendingPathComponent(item.name)
        var counter = 1
        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        while FileManager.default.fileExists(atPath: destination.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            destination = folder.appendingPathComponent(name)
            counter += 1
        }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        do {
            if keepingOriginal {
                try FileManager.default.copyItem(at: item.url, to: destination)
            } else {
                try FileManager.default.moveItem(at: item.url, to: destination)
                remove(id: id)
            }
            DiagnosticLog.write("shelf", "sent \(item.name) to \(folder.lastPathComponent)")
            return true
        } catch {
            DiagnosticLog.write("shelf", "send failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Persistence

    private func restore() {
        guard let bookmarks = UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] else { return }
        var restored: [ShelfItem] = []

        for data in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
            restored.append(makeItem(for: url, isTemporary: url.path.hasPrefix(temporaryDirectory.path)))
        }

        items = restored
        loadThumbnails()
    }

    private func persist() {
        let bookmarks = items.compactMap { item in
            try? item.url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    // MARK: - Adding

    private func makeItem(for url: URL, isTemporary: Bool) -> ShelfItem {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        let size = Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
        return ShelfItem(
            id: UUID(),
            url: url,
            name: url.lastPathComponent,
            size: size,
            addedAt: Date(),
            isTemporary: isTemporary,
            thumbnail: nil
        )
    }

    @discardableResult
    func add(url: URL, isTemporary: Bool = false) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            DiagnosticLog.write("shelf", "rejected, file does not exist (or is unreadable): \(url.path)")
            return false
        }
        guard !items.contains(where: { $0.url == url }) else {
            DiagnosticLog.write("shelf", "rejected, already on the shelf: \(url.lastPathComponent)")
            return false
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURLs.append(url)
        }

        var item = makeItem(for: url, isTemporary: isTemporary)
        items.insert(item, at: 0)
        persist()
        DiagnosticLog.write("shelf", "added \(item.name), now holding \(items.count)")

        generateThumbnail(for: item) { [weak self] image in
            guard let self, let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            item.thumbnail = image
            self.items[index].thumbnail = image
        }
        return true
    }

    /// Writes arbitrary dragged data into the shelf's cache and adds it.
    @discardableResult
    func addTemporary(data: Data, preferredName: String) -> Bool {
        let destination = uniqueURL(for: preferredName)
        do {
            try data.write(to: destination)
            return add(url: destination, isTemporary: true)
        } catch {
            return false
        }
    }

    private func uniqueURL(for name: String) -> URL {
        var candidate = temporaryDirectory.appendingPathComponent(name)
        var counter = 1
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = temporaryDirectory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// Takes everything usable off a dropped pasteboard. Reading the pasteboard
    /// directly (rather than going through `NSItemProvider`) is what makes
    /// Finder drags land reliably.
    @discardableResult
    func addContents(of pasteboard: NSPasteboard) -> Bool {
        var didAdd = false

        DiagnosticLog.write("shelf", "reading drop, types=\(pasteboard.types?.map(\.rawValue) ?? [])")

        // Real files first — that is the overwhelmingly common case.
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        DiagnosticLog.write("shelf", "file URLs on pasteboard: \(fileURLs?.map(\.path) ?? [])")
        if let fileURLs {
            for url in fileURLs where add(url: url) {
                didAdd = true
            }
        }
        if didAdd { return true }

        // Then a web URL, saved as a .webloc so it can be dragged back out.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first, url.scheme?.hasPrefix("http") == true {
            let name = (url.host ?? "Link") + ".webloc"
            let plist: [String: String] = ["URL": url.absoluteString]
            if let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            ), addTemporary(data: data, preferredName: name) {
                return true
            }
        }

        // Then image data dragged out of a browser or an editor.
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let name = "Dropped Image \(Self.timestampSuffix()).png"
            if addTemporary(data: png, preferredName: name) { return true }
        }

        // Finally plain text.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            let name = "Dropped Text \(Self.timestampSuffix()).txt"
            if let data = text.data(using: .utf8), addTemporary(data: data, preferredName: name) {
                return true
            }
        }

        return didAdd
    }


    static func timestampSuffix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    // MARK: - Removing

    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        selection.remove(id)
        if item.isTemporary {
            try? FileManager.default.removeItem(at: item.url)
        }
        persist()
    }

    func removeSelected() {
        for id in selection { remove(id: id) }
        selection.removeAll()
    }

    func clear() {
        for item in items where item.isTemporary {
            try? FileManager.default.removeItem(at: item.url)
        }
        items.removeAll()
        selection.removeAll()
        persist()
    }

    /// Called after a successful drag out of the shelf.
    func handleDragCompleted(id: UUID) {
        guard Settings.shared.autoRemoveShelfItems, !Settings.shared.copyOnDrag else { return }
        remove(id: id)
    }

    // MARK: - Actions

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func quickLook(_ item: ShelfItem) {
        QuickLookPreview.shared.show(urls: [item.url], startingAt: 0)
    }

    /// Opens the standard share sheet anchored to a view, with AirDrop first.
    func share(_ urls: [URL], relativeTo view: NSView) {
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    /// Sends straight to AirDrop without going through the picker.
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop)
        else { return }
        service.perform(withItems: urls)
    }

    func copyToPasteboard(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// What a share or AirDrop acts on: the selection if there is one, else
    /// everything. Reaching for AirDrop with nothing ticked clearly means "this
    /// shelf", not "nothing".
    var shareURLs: [URL] {
        selection.isEmpty ? items.map(\.url) : selectedURLs
    }

    /// True when macOS can offer AirDrop at all.
    static var canAirDrop: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    var selectedURLs: [URL] {
        let selected = items.filter { selection.contains($0.id) }
        return (selected.isEmpty ? items : selected).map(\.url)
    }

    // MARK: - Thumbnails

    private func loadThumbnails() {
        for item in items {
            generateThumbnail(for: item) { [weak self] image in
                guard let self, let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
                self.items[index].thumbnail = image
            }
        }
    }

    private func generateThumbnail(for item: ShelfItem, completion: @escaping (NSImage?) -> Void) {
        let size = CGSize(width: 128, height: 128)
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let representation {
                        completion(NSImage(cgImage: representation.cgImage, size: size))
                    } else {
                        completion(NSWorkspace.shared.icon(forFile: item.url.path))
                    }
                }
            }
        }
    }
}

/// Thin wrapper around the Quick Look panel.
final class QuickLookPreview: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPreview()

    private var urls: [URL] = []

    func show(urls: [URL], startingAt index: Int) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = index
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
