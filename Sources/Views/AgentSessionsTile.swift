//
//  AgentSessionsTile.swift
//  FunNotch
//
//  Every Claude Code and Codex session on this Mac, what each one is doing,
//  and a click to jump to it.
//

import SwiftUI

struct AgentSessionsTile: View {
    /// The strip along the bottom has room for one session; the main row for
    /// a short list.
    var compact = false

    @ObservedObject private var agents = AgentSessionsManager.shared

    /// Enough to fill the main row without clipping the last one.
    private let maxRows = 3

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                fullBody
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: agents.sessions.map(\.id))
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: agents.sessions.map(\.status))
    }

    // MARK: Main row

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if agents.sessions.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(agents.sessions.prefix(maxRows)) { session in
                        AgentRow(session: session)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("AGENTS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.38))
            Spacer(minLength: 0)
            summaryBadge
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private var summaryBadge: some View {
        let hidden = max(agents.sessions.count - maxRows, 0)
        HStack(spacing: 4) {
            if agents.waitingCount > 0 {
                Circle().fill(AgentPalette.waiting).frame(width: 5, height: 5)
                Text("\(agents.waitingCount) need\(agents.waitingCount == 1 ? "s" : "") you")
                    .foregroundStyle(AgentPalette.waiting)
            } else if agents.workingCount > 0 {
                ClaudeSpinner(size: 8)
                Text("\(agents.workingCount) working")
                    .foregroundStyle(AgentPalette.claude)
            } else if !agents.sessions.isEmpty {
                Text("All quiet")
                    .foregroundStyle(.white.opacity(0.35))
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .font(.system(size: 9, weight: .semibold))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 15))
                .foregroundStyle(AgentPalette.claude.opacity(0.75))
            Text("No agents running")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Claude Code sessions show up here")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Strip

    @ViewBuilder
    private var compactBody: some View {
        if let session = agents.headline {
            Button {
                agents.bringForward(session)
            } label: {
                HStack(spacing: 7) {
                    AgentStatusIcon(session: session, size: 13)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                        Text(compactDetail(for: session))
                            .font(.system(size: 9))
                            .foregroundStyle(AgentRow.detailColor(for: session))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    AgentRowTime(session: session)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(session.name)")
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(AgentPalette.claude.opacity(0.7))
                Text("No agents running")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
        }
    }

    private func compactDetail(for session: AgentSessionsManager.Session) -> String {
        let others = agents.sessions.count - 1
        let base = AgentRow.detail(for: session)
        guard others > 0 else { return base }
        let busyOthers = agents.activeCount - (session.status.isActive ? 1 : 0)
        return busyOthers > 0 ? "\(base) · \(busyOthers) more busy" : "\(base) · \(others) more"
    }
}

// MARK: - Rows

private struct AgentRow: View {
    let session: AgentSessionsManager.Session

    @State private var hovering = false

    var body: some View {
        Button {
            AgentSessionsManager.shared.bringForward(session)
        } label: {
            HStack(spacing: 7) {
                AgentStatusIcon(session: session, size: 12)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(session.status.isActive ? 0.95 : 0.7))
                        .lineLimit(1)
                    Text(Self.detail(for: session))
                        .font(.system(size: 9.5))
                        .foregroundStyle(Self.detailColor(for: session))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                AgentRowTime(session: session)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(session.agent.rawValue) in \(session.project) — click to show it")
    }

    static func detail(for session: AgentSessionsManager.Session) -> String {
        switch session.status {
        case .working:
            return session.name == session.project ? "Working" : "Working · \(session.project)"
        case let .waiting(reason):
            return AgentSessionsManager.waitingText(reason)
        case .idle:
            if let duration = session.lastTurnDuration {
                return "Finished in \(AgentSessionsManager.duration(duration))"
            }
            return session.name == session.project ? "Idle" : "Idle · \(session.project)"
        }
    }

    static func detailColor(for session: AgentSessionsManager.Session) -> Color {
        switch session.status {
        case .working: return AgentPalette.claude.opacity(0.9)
        case .waiting: return AgentPalette.waiting
        case .idle:
            return session.lastTurnDuration != nil
                ? AgentPalette.done.opacity(0.85)
                : .white.opacity(0.4)
        }
    }
}

/// A running clock while the session works, how long ago it stopped after.
private struct AgentRowTime: View {
    let session: AgentSessionsManager.Session

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(label(now: context.date))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func label(now: Date) -> String {
        if session.status.isActive {
            let since = session.turnStartedAt ?? session.statusSince
            return AgentSessionsManager.clock(now.timeIntervalSince(since))
        }
        return AgentSessionsManager.ago(session.statusSince, now: now)
    }

    private var color: Color {
        switch session.status {
        case .working: return AgentPalette.claude
        case .waiting: return AgentPalette.waiting
        case .idle: return .white.opacity(0.35)
        }
    }
}

/// Spinner, waving hand, check, or a quiet dot.
struct AgentStatusIcon: View {
    let session: AgentSessionsManager.Session
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch session.status {
            case .working:
                AgentWorkingGlyph(agent: session.agent, size: size)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .waiting:
                AgentWaitingGlyph(size: size)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            case .idle:
                if session.lastTurnDuration != nil {
                    // Only a check that has just happened draws itself; one
                    // from earlier is simply there when the notch opens.
                    if Date().timeIntervalSince(session.statusSince) < 6 {
                        IntroTimeline(duration: 1.2) { time in
                            CheckmarkBurst(time: time, size: size + 1)
                        }
                    } else {
                        CheckmarkBurst(time: 60, size: size + 1)
                    }
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .id(statusKey)
    }

    private var statusKey: String {
        switch session.status {
        case .working: return "working"
        case .waiting: return "waiting"
        case .idle: return session.lastTurnDuration == nil ? "idle" : "done"
        }
    }
}
