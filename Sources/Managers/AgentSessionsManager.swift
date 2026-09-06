//
//  AgentSessionsManager.swift
//  FunNotch
//
//  Tracks Claude Code and Codex sessions by watching the transcript files each
//  one writes as it works.
//
//  Watching files rather than processes is deliberate. A running `claude`
//  process tells you a terminal is open, not that anything is happening in it,
//  and both tools spawn helpers that look like sessions but are not. The
//  transcript is written as the conversation happens, so its modification time
//  is the honest answer to "is this session doing something".
//
//  Nothing is read from inside the transcripts. Names come from directory and
//  file names only — the contents are the user's conversations.
//

import Foundation
import SwiftUI

@MainActor
final class AgentSessionsManager: ObservableObject {
    static let shared = AgentSessionsManager()

    enum Agent: String {
        case claude = "Claude Code"
        case codex = "Codex"

        var symbol: String {
            switch self {
            case .claude: return "sparkle"
            case .codex: return "chevron.left.forwardslash.chevron.right"
            }
        }

        var tint: Color {
            switch self {
            case .claude: return Color(red: 0.85, green: 0.55, blue: 0.35)
            case .codex: return Color(red: 0.45, green: 0.78, blue: 0.72)
            }
        }
    }

    struct Session: Identifiable, Equatable {
        let id: String
        let agent: Agent
        let project: String
        let lastActivity: Date

        /// Anything touched in the last two minutes is treated as live. Long
        /// enough to survive a pause for thought, short enough that a session
        /// abandoned an hour ago does not still claim to be running.
        var isLive: Bool { Date().timeIntervalSince(lastActivity) < 120 }

        var relativeTime: String {
            let seconds = Int(Date().timeIntervalSince(lastActivity))
            if seconds < 60 { return "now" }
            if seconds < 3600 { return "\(seconds / 60)m" }
            if seconds < 86_400 { return "\(seconds / 3600)h" }
            return "\(seconds / 86_400)d"
        }
    }

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var scannedAt: Date?

    private var timer: Timer?
    private var subscribers = 0

    var liveCount: Int { sessions.filter(\.isLive).count }

    private init() {}

    func addSubscriber() {
        subscribers += 1
        if subscribers == 1 { start() }
        if sessions.isEmpty { refresh() }
    }

    func removeSubscriber() {
        subscribers = max(subscribers - 1, 0)
        if subscribers == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    private func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        // Scanning directories touches the disk, so it happens off the main
        // thread; only the finished list comes back.
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run {
                self.sessions = found
                self.scannedAt = Date()
            }
        }
    }

    // MARK: - Scanning

    private nonisolated static func scan() -> [Session] {
        var all: [Session] = []
        all += scanClaude()
        all += scanCodex()
        // Newest first, and only the last day: older than that is history, not
        // something worth a slot in the notch.
        let cutoff = Date().addingTimeInterval(-86_400)
        return all
            .filter { $0.lastActivity > cutoff }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// `~/.claude/projects/<encoded path>/<session uuid>.jsonl`
    private nonisolated static func scanClaude() -> [Session] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        guard let projects = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ) else { return [] }

        var out: [Session] = []
        for project in projects {
            let name = prettyProjectName(project.lastPathComponent)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            // One entry per project, using its most recent session: a project
            // with forty old transcripts is one thing you are working on, not
            // forty.
            let newest = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let date = modified(url) else { return nil }
                    return (url, date)
                }
                .max { $0.1 < $1.1 }
            guard let newest else { continue }
            out.append(Session(id: newest.0.path, agent: .claude,
                               project: name, lastActivity: newest.1))
        }
        return out
    }

    /// `~/.codex/sessions/<yyyy>/<mm>/<dd>/<rollout>.jsonl`
    private nonisolated static func scanCodex() -> [Session] {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }

        var newest: (URL, Date)?
        var count = 0
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let date = modified(url) else { continue }
            count += 1
            if newest == nil || date > newest!.1 { newest = (url, date) }
            // The tree can hold months of history; there is no reason to walk
            // all of it to find out whether anything happened today.
            if count > 400 { break }
        }
        guard let newest else { return [] }
        return [Session(id: newest.0.path, agent: .codex,
                        project: "Codex", lastActivity: newest.1)]
    }

    private nonisolated static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// "-Users-joshuat1-untitled-folder" is how Claude Code encodes a path.
    /// The last component is the part worth showing.
    private nonisolated static func prettyProjectName(_ encoded: String) -> String {
        let parts = encoded.split(separator: "-").filter { !$0.isEmpty }
        guard let last = parts.last else { return encoded }
        return String(last)
    }
}
