//
//  AgentSessionsTile.swift
//  FunNotch
//
//  Claude Code and Codex sessions, and which of them is actually working.
//

import SwiftUI

struct AgentSessionsTile: View {
    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            list
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { agents.addSubscriber() }
        .onDisappear { agents.removeSubscriber() }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("AGENTS")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.38))

            if agents.liveCount > 0 {
                LiveDot()
                Text("\(agents.liveCount) working")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.green.opacity(0.9))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var list: some View {
        if agents.sessions.isEmpty {
            Text(agents.scannedAt == nil ? "Looking…" : "Nothing in the last day")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(agents.sessions.prefix(4)) { session in
                    row(session)
                }
            }
        }
    }

    private func row(_ session: AgentSessionsManager.Session) -> some View {
        HStack(spacing: 6) {
            Image(systemName: session.agent.symbol)
                .font(.system(size: 9))
                .foregroundStyle(session.agent.tint)
                .frame(width: 11)

            Text(session.project)
                .font(.system(size: 10.5, weight: session.isLive ? .semibold : .regular))
                .foregroundStyle(.white.opacity(session.isLive ? 0.92 : 0.62))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(session.relativeTime)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(session.isLive
                                 ? Color.green.opacity(0.85)
                                 : .white.opacity(0.35))
        }
    }
}

/// A slow pulse, so "working" is visible without reading anything.
private struct LiveDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let t: Double = context.date.timeIntervalSinceReferenceDate
            let amount: Double = (sin(t * 3) + 1) / 2
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .opacity(0.45 + amount * 0.55)
        }
    }
}
