//
//  NotesManager.swift
//  FunNotch
//
//  One persistent scratchpad, written to a real file on the Desktop.
//
//  The file is the point. A note trapped in UserDefaults is invisible and
//  unbackupable; a plain .txt in ~/Desktop/notes can be opened, searched by
//  Spotlight, synced, and read long after this app is gone. UserDefaults is
//  kept only as a mirror, so a note is never lost if the Desktop is
//  unwritable — which happens: the folder can be in iCloud, or the user may
//  never have granted Desktop access.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    /// The live text. Views bind straight to this.
    @Published var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            scheduleSave()
        }
    }

    /// Nil until a save has happened, so the UI can stay quiet at first.
    @Published private(set) var savedAt: Date?
    /// Set when the Desktop write fails, so the UI can say so rather than
    /// pretending everything is fine.
    @Published private(set) var saveError: String?

    private var saveWorkItem: DispatchWorkItem?
    private let mirrorKey = "notesText"

    /// ~/Desktop/notes/Notes.txt
    var fileURL: URL {
        let desktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return desktop
            .appendingPathComponent("notes", isDirectory: true)
            .appendingPathComponent("Notes.txt")
    }

    private init() {
        load()
    }

    // MARK: - Loading

    private func load() {
        // The file wins when it exists: the user may have edited it in another
        // app, and the thing they can see should beat the copy they cannot.
        if let onDisk = try? String(contentsOf: fileURL, encoding: .utf8) {
            text = onDisk
            savedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
            return
        }
        text = UserDefaults.standard.string(forKey: mirrorKey) ?? ""
    }

    // MARK: - Saving

    /// Typing should not hit the disk on every keystroke, but a note that only
    /// saves on quit is a note you lose. Roughly a second after you stop.
    private func scheduleSave() {
        UserDefaults.standard.set(text, forKey: mirrorKey)

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Writes immediately. Called on the debounce, and on the way out.
    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic so an interrupted write cannot truncate the note.
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedAt = Date()
            saveError = nil
        } catch {
            // The mirror in UserDefaults already has the text, so nothing is
            // lost; the user just needs to know the file is not updating.
            saveError = error.localizedDescription
        }
    }

    func revealInFinder() {
        // Make sure there is something to reveal before asking Finder.
        if !FileManager.default.fileExists(atPath: fileURL.path) { saveNow() }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
