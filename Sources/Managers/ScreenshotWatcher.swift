//
//  ScreenshotWatcher.swift
//  FunNotch
//
//  Watches wherever macOS saves screenshots and puts new ones straight on the
//  shelf, so a screenshot never has to be dragged there by hand.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ScreenshotWatcher: ObservableObject {
    static let shared = ScreenshotWatcher()

    @Published private(set) var watchedDirectory: URL?
    /// The last file caught, so the notch can show it.
    @Published private(set) var lastCatch: URL?

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var seen: Set<String> = []
    private var startedAt = Date()
    private var cancellables = Set<AnyCancellable>()
    private var rescanWork: DispatchWorkItem?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf"]
    private static let movieExtensions: Set<String> = ["mov", "mp4"]

    private init() {}

    func start() {
        NotificationCenter.default.publisher(for: .settingsChanged)
            .compactMap { $0.object as? String }
            .filter { $0 == "catchScreenshots" }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.restart() }
            .store(in: &cancellables)

        restart()
    }

    func restart() {
        stop()
        guard Settings.shared.catchScreenshots else { return }

        let directory = Self.screenshotDirectory()
        watchedDirectory = directory

        // Everything already there is old news.
        seen = Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        startedAt = Date()

        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DiagnosticLog.write("screenshots", "could not watch \(directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scheduleScan() }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source

        DiagnosticLog.write("screenshots", "watching \(directory.path)")
    }

    func stop() {
        rescanWork?.cancel()
        rescanWork = nil
        source?.cancel()
        source = nil
    }

    /// Screenshots are written in a couple of steps, so settle before looking.
    private func scheduleScan() {
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func scan() {
        guard let directory = watchedDirectory else { return }

        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let fresh = names.filter { !seen.contains($0) }
        seen.formUnion(names)

        for name in fresh {
            guard !name.hasPrefix(".") else { continue }
            let url = directory.appendingPathComponent(name)
            guard isCatchable(url) else { continue }

            // A screen recording keeps growing; wait until it stops changing.
            if Self.movieExtensions.contains(url.pathExtension.lowercased()) {
                waitUntilStable(url)
            } else {
                catchFile(url)
            }
        }
    }

    private func isCatchable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let isImage = Self.imageExtensions.contains(ext)
        let isMovie = Self.movieExtensions.contains(ext)

        guard isImage || isMovie else { return false }
        if isMovie, !Settings.shared.catchScreenRecordings { return false }

        // Only files created since we started watching, so a busy folder does
        // not dump its history onto the shelf.
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        guard let created = values?.creationDate, created >= startedAt.addingTimeInterval(-2) else {
            return false
        }

        // When macOS marks the file as a screen capture, trust that outright;
        // otherwise fall back to it simply being a new image in this folder.
        if let marked = Self.isMarkedAsScreenCapture(url) {
            return marked
        }
        return true
    }

    /// Reads the `kMDItemIsScreenCapture` extended attribute, if present.
    private static func isMarkedAsScreenCapture(_ url: URL) -> Bool? {
        let name = "com.apple.metadata:kMDItemIsScreenCapture"
        let length = getxattr(url.path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(url.path, name, &buffer, length, 0, 0) == length else { return nil }
        // Stored as a binary plist holding a boolean.
        let data = Data(buffer)
        let value = try? PropertyListSerialization.propertyList(from: data, format: nil)
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue
    }

    private func waitUntilStable(_ url: URL, attempt: Int = 0) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let now = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if now == size, now > 0 {
                self.catchFile(url)
            } else if attempt < 60 {
                self.waitUntilStable(url, attempt: attempt + 1)
            }
        }
    }

    /// Sets a fixed caught file, for snapshots.
    func injectPreviewCatch(_ name: String) {
        lastCatch = URL(fileURLWithPath: "/tmp/\(name)")
    }

    private func catchFile(_ url: URL) {
        guard ShelfManager.shared.add(url: url) else { return }
        lastCatch = url
        DiagnosticLog.write("screenshots", "caught \(url.lastPathComponent)")

        NotchWindowManager.shared.broadcast { viewModel in
            viewModel.showExpandingView(
                type: .screenshot,
                value: 1,
                icon: "camera.viewfinder",
                duration: 3.0
            )
        }
    }

    /// Where `screencapture` is currently configured to save, defaulting to the
    /// Desktop the way macOS does.
    static func screenshotDirectory() -> URL {
        let fallback = FileManager.default.standardDirectory(.desktopDirectory, fallback: "Desktop")

        guard let defaults = UserDefaults(suiteName: "com.apple.screencapture"),
              let location = defaults.string(forKey: "location"),
              !location.isEmpty
        else { return fallback }

        let expanded = (location as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return fallback }

        return URL(fileURLWithPath: expanded)
    }
}
