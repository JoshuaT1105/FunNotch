//
//  NotesManager.swift
//  FunNotch
//
//  A scratchpad that starts fresh each day and keeps every day it has been.
//
//  Notes are written to two places. `~/Desktop/notes` is the visible copy: a
//  plain .txt you can open, search with Spotlight, sync or edit elsewhere.
//  Application Support holds a mirror, because the Desktop is exactly the
//  folder people tidy — a note should not disappear because its file was
//  dragged to the Trash during a clear-out.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    /// The text of the day currently being edited.
    @Published var text: String = "" {
        didSet {
            guard text != oldValue, !isLoading else { return }
            scheduleSave()
        }
    }

    /// Which day is on screen, as `yyyy-MM-dd`. Usually today, but the user can
    /// go back and carry on writing in an earlier one.
    @Published private(set) var day: String = ""

    /// Every day that has a note, newest first.
    @Published private(set) var days: [String] = []

    @Published private(set) var savedAt: Date?
    /// Set when the Desktop copy could not be written. The Application Support
    /// copy is separate, so a note is not lost when this is non-nil.
    @Published private(set) var saveError: String?

    private var saveWorkItem: DispatchWorkItem?
    private var isLoading = false
    private var rolloverTimer: Timer?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Locations

    /// The visible copy, on the Desktop.
    var desktopFolder: URL {
        let desktop = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        return desktop.appendingPathComponent("notes", isDirectory: true)
    }

    /// The backup, inside the app's own support folder.
    var backupFolder: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("FunNotch", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
    }

    func desktopURL(for day: String) -> URL {
        desktopFolder.appendingPathComponent("\(day).txt")
    }

    func backupURL(for day: String) -> URL {
        backupFolder.appendingPathComponent("\(day).txt")
    }

    /// The file the user is most likely to want to open.
    var fileURL: URL { desktopURL(for: day) }

    static func today() -> String { dayFormatter.string(from: Date()) }

    /// "Today", "Yesterday", or a written date.
    func displayName(for day: String) -> String {
        guard let date = Self.dayFormatter.date(from: day) else { return day }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var isToday: Bool { day == Self.today() }

    // MARK: - Lifecycle

    private init() {
        day = Self.today()
        migrateLegacyNote()
        loadDay(day)
        refreshDays()
        startRolloverWatch()
    }

    /// Notes used to be a single `Notes.txt`. Anything in it belongs to the day
    /// it was last touched, so it is moved there rather than left orphaned in a
    /// file nothing reads any more.
    private func migrateLegacyNote() {
        let legacy = desktopFolder.appendingPathComponent("Notes.txt")
        guard let contents = try? String(contentsOf: legacy, encoding: .utf8) else { return }

        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Empty, so nothing to keep and no reason to leave it lying around.
            try? FileManager.default.removeItem(at: legacy)
            return
        }

        let modified = (try? FileManager.default
            .attributesOfItem(atPath: legacy.path)[.modificationDate]) as? Date ?? Date()
        let target = Self.dayFormatter.string(from: modified)
        let destination = desktopURL(for: target)

        // Never overwrite a day that already has a note; append instead.
        if let existing = try? String(contentsOf: destination, encoding: .utf8), !existing.isEmpty {
            write(existing + "\n\n" + contents, to: destination, report: false)
            write(existing + "\n\n" + contents, to: backupURL(for: target), report: false)
        } else {
            write(contents, to: destination, report: false)
            write(contents, to: backupURL(for: target), report: false)
        }
        try? FileManager.default.removeItem(at: legacy)
        DiagnosticLog.write("notes", "migrated Notes.txt into \(target).txt")
    }

    /// Notices midnight passing while the app is running, so a note left open
    /// overnight does not quietly keep appending to yesterday.
    private func startRolloverWatch() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let today = Self.today()
                // Only roll the view over if the user is looking at what was
                // today. If they have deliberately opened an older day, leave
                // them where they are.
                guard self.day != today, self.day == self.previousDayBeforeRollover else { return }
                self.saveNow()
                self.openDay(today)
            }
        }
        timer.tolerance = 20
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
        previousDayBeforeRollover = day
    }

    private var previousDayBeforeRollover: String = ""

    // MARK: - Days

    func refreshDays() {
        var found = Set<String>()
        for folder in [desktopFolder, backupFolder] {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in contents where name.hasSuffix(".txt") {
                let stem = String(name.dropLast(4))
                if Self.dayFormatter.date(from: stem) != nil { found.insert(stem) }
            }
        }
        found.insert(Self.today())
        days = found.sorted(by: >)
    }

    /// Switch to a different day, saving whatever is open first.
    func openDay(_ newDay: String) {
        guard newDay != day else { return }
        saveNow()
        day = newDay
        previousDayBeforeRollover = newDay == Self.today() ? newDay : previousDayBeforeRollover
        loadDay(newDay)
        refreshDays()
    }

    func openToday() { openDay(Self.today()) }

    private func loadDay(_ day: String) {
        isLoading = true
        defer { isLoading = false }

        // The Desktop copy wins: the user may have edited it in another app,
        // and what they can see should beat the copy they cannot.
        if let onDisk = try? String(contentsOf: desktopURL(for: day), encoding: .utf8) {
            text = onDisk
            savedAt = (try? FileManager.default
                .attributesOfItem(atPath: desktopURL(for: day).path)[.modificationDate]) as? Date
            return
        }
        if let backup = try? String(contentsOf: backupURL(for: day), encoding: .utf8) {
            text = backup
            // The Desktop copy is missing — probably deleted. Put it back.
            saveNow()
            return
        }
        text = ""
        savedAt = nil
    }

    // MARK: - Saving

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        saveWorkItem = nil

        // The backup goes first and its failure is not reported: it is the copy
        // that exists so the visible one can be lost.
        write(text, to: backupURL(for: day), report: false)
        write(text, to: desktopURL(for: day), report: true)
        refreshDays()
    }

    private func write(_ contents: String, to url: URL, report: Bool) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Atomic, so an interrupted write cannot truncate a note.
            try contents.write(to: url, atomically: true, encoding: .utf8)
            if report {
                savedAt = Date()
                saveError = nil
            }
        } catch {
            if report { saveError = error.localizedDescription }
        }
    }

    func revealInFinder() {
        if !FileManager.default.fileExists(atPath: fileURL.path) { saveNow() }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
