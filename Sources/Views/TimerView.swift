//
//  TimerView.swift
//  FunNotch
//
//  The Timer tab: a countdown or a stopwatch, whichever you asked for.
//

import SwiftUI

struct TimerView: View {
    @ObservedObject private var timer = TimerManager.shared
    @EnvironmentObject private var settings: Settings

    private let presets: [(String, TimeInterval)] = [
        ("1m", 60), ("3m", 180), ("5m", 300), ("10m", 600), ("25m", 1500)
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TimerDial()
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                modePicker

                if timer.mode == .timer {
                    timerControls
                } else {
                    stopwatchControls
                }

                Spacer(minLength: 0)
            }
            .frame(width: 200, alignment: .leading)

            // The third column is always occupied: without it the tab was two
            // thirds empty space, which read as unfinished rather than roomy.
            Group {
                if timer.mode == .timer {
                    timerSidebar
                } else {
                    stopwatchSidebar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Mode

    private var modePicker: some View {
        HStack(spacing: 3) {
            ForEach(TimerManager.Mode.allCases) { mode in
                Button {
                    guard timer.mode != mode else { return }
                    timer.reset()
                    timer.mode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(timer.mode == mode ? .black : .white.opacity(0.65))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(timer.mode == mode
                                           ? AnyShapeStyle(settings.accentColor)
                                           : AnyShapeStyle(Color.white.opacity(0.08)))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Countdown

    @ViewBuilder
    private var timerControls: some View {
        if timer.finished {
            VStack(alignment: .leading, spacing: 6) {
                Text("Time's up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                HStack(spacing: 6) {
                    TimerChip(label: "Dismiss", isPrimary: true) { timer.acknowledge() }
                    TimerChip(label: "Again") {
                        timer.start(seconds: max(timer.duration, 60))
                    }
                }
            }
        } else if timer.isActive {
            VStack(alignment: .leading, spacing: 7) {
                Text(TimerManager.clock(timer.remaining))
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    TimerChip(label: timer.isRunning ? "Pause" : "Resume", isPrimary: true) {
                        timer.toggle()
                    }
                    TimerChip(label: "+1m") { timer.addTime(60) }
                    TimerChip(label: "Reset", isDestructive: true) { timer.reset() }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Set a timer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Runs on its own clock, so it stays accurate even when the Mac is busy.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForEach(presets, id: \.0) { preset in
                        TimerChip(label: preset.0, isPrimary: preset.1 == 300) {
                            timer.start(seconds: preset.1)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Stopwatch

    @ViewBuilder
    private var stopwatchControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(TimerManager.stopwatchClock(timer.elapsed))
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                if timer.isRunning {
                    TimerChip(label: "Stop", isPrimary: true) { timer.pause() }
                    TimerChip(label: "Lap") { timer.lap() }
                } else {
                    TimerChip(label: timer.elapsed > 0 ? "Resume" : "Start", isPrimary: true) {
                        timer.elapsed > 0 ? timer.resume() : timer.startStopwatch()
                    }
                    if timer.elapsed > 0 {
                        TimerChip(label: "Reset", isDestructive: true) { timer.reset() }
                    }
                }
            }
        }
    }

    /// Presets stay reachable while a timer runs, so starting a different one
    /// does not mean cancelling first.
    private var timerSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("QUICK START")
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.35))

            HStack(spacing: 5) {
                ForEach(presets, id: \.0) { preset in
                    TimerChip(label: preset.0) { timer.start(seconds: preset.1) }
                }
            }

            if timer.duration > 0 {
                PixelProgressBar(progress: timer.progress,
                                 tint: timer.finished ? .orange : settings.accentColor)
                    .frame(height: 10)
                    .padding(.top, 4)

                HStack {
                    Text(TimerManager.clock(timer.duration - timer.remaining))
                    Spacer()
                    Text(TimerManager.clock(timer.duration))
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var stopwatchSidebar: some View {
        if timer.laps.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAPS")
                    .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.35))
                Text("Press Lap while it runs to mark a split.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else {
            lapList
        }
    }

    private var lapList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LAPS")
                .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.35))
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(timer.laps.enumerated()), id: \.offset) { index, lap in
                        HStack {
                            Text("\(timer.laps.count - index)")
                                .foregroundStyle(.white.opacity(0.4))
                            Spacer()
                            Text(TimerManager.stopwatchClock(lap))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .font(.system(size: 9.5))
                    }
                }
            }
        }
    }
}

// MARK: - Dial

/// Fills as a countdown runs down, and sweeps like a second hand for the
/// stopwatch — the two modes need different motion or the dial says nothing.
private struct TimerDial: View {
    @ObservedObject private var timer = TimerManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.10), lineWidth: 6)

            Circle()
                .trim(from: 0, to: sweep)
                .stroke(
                    timer.finished ? Color.orange : settings.accentColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: sweep)

            VStack(spacing: 0) {
                Text(centreText)
                    .font(.system(size: timer.mode == .stopwatch ? 13 : 15,
                                  weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.95))
                Text(timer.mode == .stopwatch ? "elapsed" : (timer.finished ? "done" : "left"))
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    private var sweep: CGFloat {
        switch timer.mode {
        case .timer:
            return timer.duration > 0 ? CGFloat(1 - timer.progress) : 0
        case .stopwatch:
            // One turn per minute, so it reads like a watch face.
            return CGFloat(timer.elapsed.truncatingRemainder(dividingBy: 60) / 60)
        }
    }

    private var centreText: String {
        switch timer.mode {
        case .timer: return TimerManager.clock(timer.remaining)
        case .stopwatch: return TimerManager.stopwatchClock(timer.elapsed)
        }
    }
}

// MARK: - Chip

private struct TimerChip: View {
    let label: String
    var isPrimary: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var foreground: Color {
        if isDestructive { return .white }
        return isPrimary ? .black : .white.opacity(isHovering ? 1 : 0.8)
    }

    private var background: Color {
        if isDestructive { return .red.opacity(isHovering ? 0.85 : 0.65) }
        if isPrimary { return settings.accentColor.opacity(isHovering ? 1 : 0.9) }
        return .white.opacity(isHovering ? 0.16 : 0.08)
    }
}

/// A chunky segmented progress bar, matching the pixel language used by the
/// weather panel and the game.
private struct PixelProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 3
            let gap: CGFloat = 1
            let count = max(Int(size.width / (cell + gap)), 1)
            let filled = Int((progress * Double(count)).rounded())
            for i in 0 ..< count {
                let x = CGFloat(i) * (cell + gap)
                let rect = CGRect(x: x, y: 0, width: cell, height: size.height)
                ctx.fill(
                    Path(rect),
                    with: .color(i < filled ? tint.opacity(0.9) : .white.opacity(0.08))
                )
            }
        }
    }
}
