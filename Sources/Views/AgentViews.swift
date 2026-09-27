//
//  AgentViews.swift
//  FunNotch
//
//  The pieces a Claude Code or Codex session is drawn with: Claude's own
//  spinner while it works, an orange hand while it waits for you, and a check
//  that draws itself when it is done. Plus the small motion toolkit every
//  announcement in the notch uses.
//

import SwiftUI

// MARK: - Motion

/// Easing and springs as plain functions of time.
///
/// Announcements animate procedurally — each piece works out where it should
/// be from the seconds since it appeared — rather than through SwiftUI's
/// implicit animations. The entrances then play identically every time, can
/// be layered with precise delays, and render correctly in the snapshot
/// renderer, which cannot wait for SwiftUI to animate anything.
enum Motion {
    /// Set by the snapshot renderer: every entrance is drawn finished.
    nonisolated(unsafe) static var snapshotMode = false

    /// Set by the film renderer (`--render-film`): seconds since the shot
    /// began. Every clock-driven view reads this instead of the wall clock, so
    /// a video can be rendered one exact frame at a time.
    nonisolated(unsafe) static var filmTime: Double?

    /// The wall-clock time the film pretends it is, advancing with the shot.
    nonisolated(unsafe) static var filmDate: Date?

    /// Set by the film renderer: the soundtrack's level in each of the
    /// spectrum's bars for this frame, 0...1, so the bars in the video move
    /// to the music playing under it.
    nonisolated(unsafe) static var filmSpectrum: [Double]?

    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }

    /// 0 → 1 over `duration`, starting after `delay`.
    static func progress(_ t: Double, delay: Double = 0, duration: Double) -> Double {
        clamp((t - delay) / max(duration, 0.0001))
    }

    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }

    static func easeInOut(_ x: Double) -> Double {
        let t = clamp(x)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// An underdamped spring's step response: overshoots, then settles on 1.
    /// The same curve SwiftUI's `.spring(response:dampingFraction:)` follows.
    static func spring(_ t: Double, response: Double = 0.42, damping: Double = 0.55) -> Double {
        guard t > 0 else { return 0 }
        let natural = 2 * Double.pi / response
        let zeta = min(max(damping, 0.01), 0.99)
        let damped = natural * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * natural * t)
        return 1 - decay * (cos(damped * t) + (zeta * natural / damped) * sin(damped * t))
    }
}

/// Hands its content the seconds elapsed since it first appeared, then stops
/// ticking once the entrance is over.
struct IntroTimeline<Content: View>: View {
    /// How long the content keeps changing. Past this it is drawn once more
    /// and left alone.
    var duration: Double = 1.2
    @ViewBuilder let content: (Double) -> Content

    @State private var start = Date()
    @State private var settled = false

    var body: some View {
        if let film = Motion.filmTime {
            content(film)
        } else if Motion.snapshotMode {
            content(60)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: settled)) { context in
                content(settled ? 60 : context.date.timeIntervalSince(start))
            }
            .task {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                settled = true
            }
        }
    }
}

// MARK: - Working

/// Claude Code's own spinner — the glyph that turns beside "Thinking…" in the
/// terminal — so a working session looks the way it does in Claude.
struct ClaudeSpinner: View {
    var size: CGFloat = 13
    var tint: Color = AgentPalette.claude

    private static let frames = ["·", "✢", "✳", "✶", "✻", "✽", "✻", "✶", "✳", "✢"]
    private static let interval = 0.12

    var body: some View {
        if let film = Motion.filmTime {
            glyph(Self.frames[Int(film / Self.interval) % Self.frames.count])
        } else if Motion.snapshotMode {
            glyph(Self.frames[4])
        } else {
            TimelineView(.periodic(from: .now, by: Self.interval)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / Self.interval) % Self.frames.count
                glyph(Self.frames[index])
            }
        }
    }

    private func glyph(_ character: String) -> some View {
        Text(character)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(tint)
            .shadow(color: tint.opacity(0.6), radius: size * 0.3)
            .frame(width: size * 1.3, height: size * 1.3)
    }
}

/// Codex has no signature glyph, so it gets a quiet orbit.
struct OrbitSpinner: View {
    var size: CGFloat = 13
    var tint: Color = AgentPalette.codex

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle = Motion.filmTime.map { $0 * 300 }
                ?? (Motion.snapshotMode ? 40 : context.date.timeIntervalSinceReferenceDate * 300)
            ZStack {
                Circle().stroke(tint.opacity(0.25), lineWidth: 1.6)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
    }
}

/// Whichever spinner belongs to the agent.
struct AgentWorkingGlyph: View {
    let agent: AgentSessionsManager.Agent
    var size: CGFloat = 13

    var body: some View {
        switch agent {
        case .claude: ClaudeSpinner(size: size)
        case .codex: OrbitSpinner(size: size * 0.95)
        }
    }
}

// MARK: - Waiting

/// A raised hand that waves every couple of seconds, with a ring that keeps
/// pulsing out from it — hard to miss, easy to ignore.
struct AgentWaitingGlyph: View {
    var size: CGFloat = 13
    /// Seconds since the wait began, when the caller already has a clock.
    var time: Double?

    var body: some View {
        if let time = time ?? Motion.filmTime {
            drawn(time)
        } else if Motion.snapshotMode {
            drawn(1.1)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                drawn(context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func drawn(_ t: Double) -> some View {
        let period = 2.2
        let local = t.truncatingRemainder(dividingBy: period)
        let wave = max(0, 1 - local / 0.9)
        let ring = t.truncatingRemainder(dividingBy: 1.4) / 1.4
        return ZStack {
            Circle()
                .stroke(AgentPalette.waiting.opacity(0.55 * (1 - ring)), lineWidth: 1.2)
                .scaleEffect(0.7 + ring * 0.9)
            Image(systemName: "hand.raised.fill")
                .font(.system(size: size * 0.82, weight: .semibold))
                .foregroundStyle(AgentPalette.waiting)
                .rotationEffect(.degrees(sin(local * 16) * 16 * wave), anchor: .bottom)
        }
        .frame(width: size * 1.3, height: size * 1.3)
    }
}

// MARK: - Done

/// A circle that draws itself, a check inside it, and a small burst of sparks
/// as it lands.
struct CheckmarkBurst: View {
    /// Seconds since the check started drawing.
    let time: Double
    var size: CGFloat = 17
    var tint: Color = AgentPalette.done

    var body: some View {
        let ring = Motion.easeOut(Motion.progress(time, duration: 0.36))
        let tick = Motion.easeOut(Motion.progress(time, delay: 0.24, duration: 0.26))
        let pop = Motion.spring(time, response: 0.46, damping: 0.48)
        let burst = Motion.progress(time, delay: 0.32, duration: 0.62)

        return ZStack {
            ForEach(0 ..< 8, id: \.self) { index in
                let angle = Double(index) / 8 * 2 * Double.pi + 0.2
                let radius = Double(size) * (0.58 + 0.5 * Motion.easeOut(burst))
                Circle()
                    .fill(index.isMultiple(of: 2) ? tint : .white)
                    .frame(width: 2.3, height: 2.3)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .opacity(burst > 0 && burst < 1 ? 1 - burst : 0)
            }
            Circle()
                .fill(tint.opacity(0.18 * ring))
            Circle()
                .trim(from: 0, to: ring)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: tick)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .scaleEffect(0.5 + 0.5 * pop)
    }
}

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.1))
        return path
    }
}

// MARK: - Beside the cutout

/// The small light beside the camera while any session is busy: Claude's
/// spinner, or the waving hand if one of them is waiting for you, with a count
/// when there is more than one.
struct AgentPip: View {
    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        HStack(spacing: 2) {
            if agents.waitingCount > 0 {
                AgentWaitingGlyph(size: 12)
            } else {
                AgentWorkingGlyph(agent: agents.headline?.agent ?? .claude, size: 12)
            }
            if agents.activeCount > 1 {
                Text("\(agents.activeCount)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.numericText(value: Double(agents.activeCount)))
            }
        }
        // Clear of the camera housing, the way the widgets beside it are.
        .padding(.leading, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .transition(.scale(scale: 0.3).combined(with: .opacity))
        .help(summary)
    }

    private var summary: String {
        let working = agents.workingCount
        let waiting = agents.waitingCount
        var parts: [String] = []
        if working > 0 { parts.append("\(working) working") }
        if waiting > 0 { parts.append("\(waiting) waiting for you") }
        return parts.joined(separator: ", ")
    }
}

/// With nothing else beside the cutout, a working session gets both wings:
/// the spinner on the left…
struct AgentWingGlyph: View {
    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        Group {
            if agents.waitingCount > 0 {
                AgentWaitingGlyph(size: 13)
            } else {
                AgentWorkingGlyph(agent: agents.headline?.agent ?? .claude, size: 13)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// …and how long it has been at it on the right.
struct AgentWingClock: View {
    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let session = agents.headline
            let since = session?.turnStartedAt ?? session?.statusSince ?? context.date
            Text(agents.activeCount > 1
                 ? "×\(agents.activeCount)"
                 : AgentSessionsManager.clock(context.date.timeIntervalSince(since)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(agents.waitingCount > 0 ? AgentPalette.waiting : .white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
