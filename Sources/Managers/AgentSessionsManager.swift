//
//  AgentSessionsManager.swift
//  FunNotch
//
//  Knows which Claude Code and Codex sessions are running and what each one is
//  doing, and announces the moments worth seeing: a session starting work,
//  finishing, or stopping to ask you something.
//
//  Claude Code keeps a live registry of its sessions in
//  `~/.claude/sessions/<pid>.json` — one small file per running process with
//  the session's name, its working directory, and a status of `busy`,
//  `waiting` or `idle`. It is the same registry Claude Code's own session list
//  reads, so it is exact: no guessing from file times, and nothing is read
//  from the conversations themselves. The file goes away when the process
//  exits.
//
//  The first version of this watched transcript modification times instead,
//  one entry per project folder. Everything run from the same folder — which
//  is every session in the Claude app, if you always open the same one —
//  collapsed into a single row named after the folder, and "working" only
//  meant "a file was written in the last two minutes".
//
//  Codex has no registry, so it keeps the old signal: its rollout file is
//  written while it works, and one that has gone quiet has finished.
//

import AppKit
import Darwin
import Foundation
import SwiftUI

@MainActor
final class AgentSessionsManager: ObservableObject {
    static let shared = AgentSessionsManager()

    enum Agent: String {
        case claude = "Claude Code"
        case codex = "Codex"

        var tint: Color {
            switch self {
            case .claude: return AgentPalette.claude
            case .codex: return AgentPalette.codex
            }
        }
    }

    enum Status: Equatable {
        case working
        /// Stopped for you. The reason is Claude Code's own wording:
        /// "permission prompt", "input needed", "dialog open"…
        case waiting(String)
        case idle

        var isActive: Bool { self != .idle }

        var isWaiting: Bool {
            if case .waiting = self { return true }
            return false
        }
    }

    /// Where the session lives, so clicking it can bring that window forward.
    enum Host: Equatable {
        case claudeApp
        case codexApp
        /// A terminal or an editor — found from the process tree on demand.
        case process
    }

    struct Session: Identifiable, Equatable {
        let id: String
        let agent: Agent
        var name: String
        var project: String
        var status: Status
        /// When the current status began.
        var statusSince: Date
        /// When the current stretch of work began. Survives a pause for
        /// permission, so a turn is timed from its first message to its end.
        var turnStartedAt: Date?
        /// How long the last finished turn took, when it was seen finishing.
        var lastTurnDuration: TimeInterval?
        let startedAt: Date
        let pid: pid_t?
        let host: Host

        var waitingReason: String? {
            if case let .waiting(reason) = status { return reason }
            return nil
        }
    }

    enum Event: Equatable {
        case started
        case finished(TimeInterval)
        case needsInput(String)
    }

    struct Announcement: Equatable {
        let session: Session
        let event: Event
        let date: Date
    }

    /// Working first, then waiting, then the most recently finished.
    @Published private(set) var sessions: [Session] = []
    /// The event the notch is currently announcing, if any.
    @Published private(set) var announcement: Announcement?
    @Published private(set) var hasScanned = false

    var workingCount: Int { sessions.filter { $0.status == .working }.count }
    var waitingCount: Int { sessions.filter(\.status.isWaiting).count }
    var activeCount: Int { sessions.filter(\.status.isActive).count }

    /// The one to talk about when there is only room for one.
    var headline: Session? { sessions.first }

    private var isRunning = false
    private var timer: Timer?
    private var stream: FSEventStreamRef?
    private var scanInFlight = false
    private var rescanRequested = false
    /// A finish is held back briefly: Claude Code can drop to idle between two
    /// steps of the same job, and announcing that would be a false alarm.
    private var pendingFinishes: [String: DispatchWorkItem] = [:]
    /// Codex has no status, so "working" is inferred; this remembers when each
    /// rollout was first seen being written.
    private var codexWorkingSince: [String: Date] = [:]

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startWatchingRegistry()
        // The watcher makes changes instant; the timer catches what it cannot
        // see — a process killed without cleaning up after itself, and Codex.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        stopWatchingRegistry()
        pendingFinishes.values.forEach { $0.cancel() }
        pendingFinishes.removeAll()
        sessions = []
        hasScanned = false
    }

    func refresh() {
        if stream == nil, isRunning { startWatchingRegistry() }
        guard !scanInFlight else {
            rescanRequested = true
            return
        }
        scanInFlight = true
        let now = Date()
        DispatchQueue.global(qos: .utility).async {
            let claude = Self.readClaudeRegistry()
            let codex = Self.readCodexRollouts(now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanInFlight = false
                    self.apply(claude: claude, codex: codex, now: now)
                    if self.rescanRequested {
                        self.rescanRequested = false
                        self.refresh()
                    }
                }
            }
        }
    }

    // MARK: - Merging a scan

    private func apply(claude: [ClaudeEntry], codex: [CodexEntry], now: Date) {
        let previous = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next: [Session] = []
        var events: [(Session, Event)] = []

        for entry in claude {
            let status: Status
            switch entry.status {
            case "busy": status = .working
            case "waiting": status = .waiting(entry.waitingFor ?? "input needed")
            default: status = .idle
            }
            var session = Session(
                id: "claude:" + entry.sessionID,
                agent: .claude,
                name: entry.name,
                project: entry.project,
                status: status,
                statusSince: entry.statusUpdatedAt,
                turnStartedAt: nil,
                lastTurnDuration: nil,
                startedAt: entry.startedAt,
                pid: entry.pid,
                host: entry.entrypoint == "claude-desktop" ? .claudeApp : .process
            )
            for event in Self.transition(from: previous[session.id], to: &session) {
                events.append((session, event))
            }
            next.append(session)
        }

        for entry in codex {
            let id = "codex:" + entry.fileName
            let working = now.timeIntervalSince(entry.modified) < Self.codexQuietPeriod
            if working {
                if codexWorkingSince[id] == nil { codexWorkingSince[id] = entry.modified }
            } else {
                codexWorkingSince[id] = nil
            }
            var session = Session(
                id: id,
                agent: .codex,
                name: "Codex",
                project: entry.label,
                status: working ? .working : .idle,
                statusSince: working ? (codexWorkingSince[id] ?? entry.modified) : entry.modified,
                turnStartedAt: nil,
                lastTurnDuration: nil,
                startedAt: entry.created,
                pid: nil,
                host: .codexApp
            )
            for event in Self.transition(from: previous[id], to: &session) {
                events.append((session, event))
            }
            next.append(session)
        }

        // Anything that vanished takes its pending announcement with it.
        let alive = Set(next.map(\.id))
        for (id, work) in pendingFinishes where !alive.contains(id) {
            work.cancel()
            pendingFinishes[id] = nil
        }
        codexWorkingSince = codexWorkingSince.filter { alive.contains($0.key) }

        let sorted = next.sorted(by: Self.ordering)
        if sorted != sessions { sessions = sorted }

        // The first scan is a baseline. Announcing everything already running
        // at launch as though it had just started would be noise.
        if hasScanned {
            for (session, event) in events { handle(event, for: session) }
        }
        hasScanned = true
    }

    /// Carries a session's history across from the previous scan and reports
    /// what changed in between. Pure, so the self-test can drive it.
    nonisolated static func transition(from previous: Session?, to session: inout Session) -> [Event] {
        guard let previous else {
            if session.status.isActive { session.turnStartedAt = session.statusSince }
            switch session.status {
            case .working: return [.started]
            case let .waiting(reason): return [.needsInput(reason)]
            case .idle: return []
            }
        }

        session.turnStartedAt = previous.turnStartedAt
        session.lastTurnDuration = previous.lastTurnDuration

        switch (previous.status, session.status) {
        case (.idle, .working):
            session.turnStartedAt = session.statusSince
            return [.started]
        case let (.idle, .waiting(reason)):
            session.turnStartedAt = session.statusSince
            return [.needsInput(reason)]
        case let (.working, .waiting(reason)):
            return [.needsInput(reason)]
        case (.working, .idle), (.waiting, .idle):
            let began = previous.turnStartedAt ?? previous.statusSince
            let duration = max(session.statusSince.timeIntervalSince(began), 0)
            session.lastTurnDuration = duration
            return [.finished(duration)]
        default:
            if session.status.isActive, session.turnStartedAt == nil {
                session.turnStartedAt = session.statusSince
            }
            return []
        }
    }

    private static func ordering(_ a: Session, _ b: Session) -> Bool {
        func rank(_ status: Status) -> Int {
            switch status {
            case .waiting: return 0
            case .working: return 1
            case .idle: return 2
            }
        }
        if rank(a.status) != rank(b.status) { return rank(a.status) < rank(b.status) }
        return a.statusSince > b.statusSince
    }

    // MARK: - Announcing

    private func handle(_ event: Event, for session: Session) {
        switch event {
        case .started:
            // Back to work within the grace period: the earlier "idle" was a
            // pause, not an ending. Neither the finish nor this start is news.
            if let pending = pendingFinishes.removeValue(forKey: session.id) {
                pending.cancel()
                return
            }
            announce(.started, for: session)
        case .needsInput:
            pendingFinishes.removeValue(forKey: session.id)?.cancel()
            announce(event, for: session)
        case .finished:
            pendingFinishes.removeValue(forKey: session.id)?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.pendingFinishes[session.id] = nil
                    // Only if it is still finished, under its latest name.
                    guard let current = self.sessions.first(where: { $0.id == session.id }),
                          current.status == .idle else { return }
                    self.announce(event, for: current)
                }
            }
            pendingFinishes[session.id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishGracePeriod, execute: work)
        }
    }

    private func announce(_ event: Event, for session: Session) {
        let settings = Settings.shared
        let duration: Double
        switch event {
        case .started:
            guard settings.agentAnnounceStart else { return }
            duration = 2.4
        case .finished:
            guard settings.agentAnnounceFinish else { return }
            duration = 4.2
        case .needsInput:
            guard settings.agentAnnounceWaiting else { return }
            duration = 5.0
        }

        announcement = Announcement(session: session, event: event, date: Date())
        DiagnosticLog.write("agents", "\(session.agent.rawValue) \(Self.logName(for: event))")

        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showExpandingView(type: .agent, value: 0, icon: "", duration: duration)
        }
    }

    private static func logName(for event: Event) -> String {
        switch event {
        case .started: return "started"
        case let .finished(duration): return "finished after \(Int(duration))s"
        case let .needsInput(reason): return "waiting: \(reason)"
        }
    }

    /// Fires an announcement without a real session, for the Settings preview
    /// buttons and the snapshot renderer.
    func injectPreview(_ event: Event, name: String = "FunNotch", broadcast: Bool = true) {
        let now = Date()
        let session = Session(
            id: "preview", agent: .claude, name: name, project: "untitled folder",
            status: {
                switch event {
                case .started: return .working
                case let .needsInput(reason): return .waiting(reason)
                case .finished: return .idle
                }
            }(),
            statusSince: now, turnStartedAt: now.addingTimeInterval(-194),
            lastTurnDuration: nil, startedAt: now.addingTimeInterval(-600), pid: nil, host: .claudeApp
        )
        announcement = Announcement(session: session, event: event, date: now)
        guard broadcast else { return }
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showExpandingView(type: .agent, value: 0, icon: "", duration: 4)
        }
    }

    /// Replaces the session list, for the snapshot renderer.
    func injectPreviewSessions(_ list: [Session]) {
        sessions = list.sorted(by: Self.ordering)
        hasScanned = true
    }

    // MARK: - Bringing a session forward

    func bringForward(_ session: Session) {
        switch session.host {
        case .claudeApp:
            activateApp(bundleIdentifier: "com.anthropic.claudefordesktop")
        case .codexApp:
            activateApp(bundleIdentifier: "com.openai.codex")
        case .process:
            guard let pid = session.pid, let app = Self.hostingApplication(of: pid) else { return }
            app.activate()
        }
    }

    private func activateApp(bundleIdentifier: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Walks up from the agent's process to the first real app above it —
    /// Terminal, iTerm, Ghostty, VS Code — which is the window it lives in.
    private static func hostingApplication(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0 ..< 16 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = ProcessInfoReader.parent(of: current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    // MARK: - Watching the registry

    private nonisolated static var registryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    private func startWatchingRegistry() {
        guard stream == nil else { return }
        let path = Self.registryURL.path
        guard FileManager.default.fileExists(atPath: path) else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let manager = Unmanaged<AgentSessionsManager>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { manager.refresh() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    private func stopWatchingRegistry() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    // MARK: - Reading

    private static let finishGracePeriod: TimeInterval = 1.2
    /// How long a Codex rollout has to go unwritten before its turn counts as over.
    private static let codexQuietPeriod: TimeInterval = 20

    struct ClaudeEntry: Sendable {
        let pid: pid_t
        let sessionID: String
        let name: String
        let project: String
        let status: String
        let waitingFor: String?
        let statusUpdatedAt: Date
        let startedAt: Date
        let entrypoint: String
    }

    struct CodexEntry: Sendable {
        let fileName: String
        let label: String
        let created: Date
        let modified: Date
    }

    /// Reads every live session out of Claude Code's registry.
    ///
    /// A file only counts while its process is alive *and is the same
    /// process* — a crash leaves the file behind, and its pid can be handed to
    /// something else entirely later on. Pre-warmed spare processes and parked
    /// jobs are not sessions anyone is using, so they are skipped the way
    /// Claude Code's own list skips them.
    nonisolated static func readClaudeRegistry() -> [ClaudeEntry] {
        let directory = registryURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }

        var entries: [ClaudeEntry] = []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pidNumber = object["pid"] as? NSNumber,
                  let sessionID = object["sessionId"] as? String
            else { continue }

            if object["spare"] as? Bool == true { continue }
            if object["parkedJobId"] is String { continue }

            let pid = pid_t(truncating: pidNumber)
            guard ProcessInfoReader.isAlive(pid) else { continue }
            if let recorded = object["procStart"] as? String,
               let claimed = parseProcStart(recorded),
               let actual = ProcessInfoReader.startDate(of: pid),
               abs(claimed.timeIntervalSince(actual)) > 5 {
                continue
            }

            let cwd = object["cwd"] as? String ?? ""
            let project = projectName(for: cwd)
            let rawName = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            entries.append(ClaudeEntry(
                pid: pid,
                sessionID: sessionID,
                name: rawName.isEmpty ? project : rawName,
                project: project,
                status: object["status"] as? String ?? "idle",
                waitingFor: object["waitingFor"] as? String,
                statusUpdatedAt: date(fromMilliseconds: object["statusUpdatedAt"])
                    ?? date(fromMilliseconds: object["updatedAt"]) ?? Date(),
                startedAt: date(fromMilliseconds: object["startedAt"]) ?? Date(),
                entrypoint: object["entrypoint"] as? String ?? ""
            ))
        }
        return entries
    }

    /// Codex rollouts from today and yesterday that were touched in the last
    /// few hours. Only names and file dates are used.
    nonisolated static func readCodexRollouts(now: Date) -> [CodexEntry] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        var entries: [CodexEntry] = []
        for offset in 0 ... 1 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else { continue }
            let folder = root.appendingPathComponent(
                String(format: "%04d/%02d/%02d", year, month, dayOfMonth), isDirectory: true
            )
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey]
            ) else { continue }

            for url in files where url.pathExtension == "jsonl" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
                guard let modified = values?.contentModificationDate,
                      now.timeIntervalSince(modified) < 6 * 3600 else { continue }
                let created = values?.creationDate ?? modified
                entries.append(CodexEntry(
                    fileName: url.lastPathComponent,
                    label: "Started \(formatter.string(from: created))",
                    created: created,
                    modified: modified
                ))
            }
        }
        return entries
    }

    private nonisolated static func date(fromMilliseconds value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1000)
    }

    /// `procStart` is written the way `ps -o lstart` prints a date, in UTC.
    private nonisolated static func parseProcStart(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let squashed = text.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return formatter.date(from: squashed)
    }

    /// The folder a session was started in, as a person would name it.
    nonisolated static func projectName(for cwd: String) -> String {
        guard !cwd.isEmpty, cwd != "?" else { return "Claude Code" }
        let url = URL(fileURLWithPath: cwd)
        if url.path == FileManager.default.homeDirectoryForCurrentUser.path { return "Home" }
        let last = url.lastPathComponent
        return last.isEmpty ? cwd : last
    }

    // MARK: - Formatting

    /// "0:42", "12:05", "1:02:10" — a running clock.
    nonisolated static func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "45s", "3m 12s", "1h 5m" — a finished duration.
    nonisolated static func duration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval.rounded()), 0)
        if total < 60 { return "\(total)s" }
        if total < 3600 {
            let seconds = total % 60
            return seconds == 0 ? "\(total / 60)m" : "\(total / 60)m \(seconds)s"
        }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// "now", "5m", "2h" — how long ago.
    nonisolated static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    /// What a waiting session is waiting for, in plain words.
    nonisolated static func waitingText(_ reason: String) -> String {
        switch reason {
        case "permission prompt": return "Needs your permission"
        case "sandbox request": return "Needs sandbox access"
        case "dialog open": return "Waiting on a dialog"
        default: return "Needs your input"
        }
    }
}

/// Colours the agents are drawn in.
enum AgentPalette {
    /// Claude's own terracotta.
    static let claude = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let codex = Color(red: 0.45, green: 0.78, blue: 0.72)
    static let done = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let waiting = Color(red: 1.0, green: 0.62, blue: 0.20)
}

/// The two process facts the registry check needs, from `sysctl`.
enum ProcessInfoReader {
    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static func startDate(of pid: pid_t) -> Date? {
        guard let info = kinfo(pid) else { return nil }
        let time = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    static func parent(of pid: pid_t) -> pid_t? {
        kinfo(pid).map { $0.kp_eproc.e_ppid }
    }

    private static func kinfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
