//
//  FocusView.swift
//  FunNotch
//
//  The Focus tab: focus sessions, a countdown timer and a stopwatch, around
//  one dial. They used to be two tabs, Focus and Timer, which was one tab too
//  many for a row that has to share its space with the camera — and they are
//  the same kind of thing: time, counted.
//
//  The dial is the control as well as the display. While nothing is running
//  it can be dragged round like a kitchen timer to set the length (once round
//  is an hour, and it winds on past that), and clicking the middle starts,
//  pauses and resumes.
//

import AppKit
import SwiftUI

/// The three things the tab can count.
enum TimeMode: String, CaseIterable, Identifiable {
    case focus = "Focus"
    case timer = "Timer"
    case stopwatch = "Stopwatch"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .focus: return "cup.and.saucer.fill"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch.fill"
        }
    }
}

/// Which mode the tab is showing. Shared rather than view state so a timer
/// going off can bring the tab up on the timer.
@MainActor
final class FocusTabState: ObservableObject {
    static let shared = FocusTabState()

    @Published var mode: TimeMode = .focus

    private init() {}
}

/// Each mode has a colour of its own, so a glance at the dial says which one
/// it is showing. Focus takes the accent colour.
enum ClockPalette {
    static let timer = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let stopwatch = Color(red: 0.36, green: 0.8, blue: 1.0)
    static let rest = Color(red: 0.38, green: 0.9, blue: 0.66)
    static let alarm = Color(red: 1.0, green: 0.42, blue: 0.28)
    static let fastest = Color(red: 0.36, green: 0.9, blue: 0.5)
    static let slowest = Color(red: 1.0, green: 0.42, blue: 0.4)

    @MainActor
    static func tint(for mode: TimeMode) -> Color {
        switch mode {
        case .focus: return FocusManager.shared.isOnBreak ? rest : Settings.shared.accentColor
        case .timer: return TimerManager.shared.finished ? alarm : timer
        case .stopwatch: return stopwatch
        }
    }
}

struct FocusView: View {
    /// On the home screen the tab is a tile, and may be given far less room.
    var isTile = false

    @ObservedObject private var state = FocusTabState.shared

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let dial = min(size.height - (isTile ? 4 : 10), size.width >= 300 ? 124 : size.width - 8, 124)

            Group {
                // The column hangs from the top of the dial, so switching mode
                // or starting something does not make it jump up and down.
                let drop = max((size.height - dial) / 2, 0)
                if size.width >= 560 {
                    HStack(alignment: .center, spacing: 20) {
                        TimeDial(mode: state.mode, size: dial)
                        ModeColumn(mode: state.mode)
                            .padding(.top, drop)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        SidePanel(mode: state.mode)
                            .frame(width: min(200, size.width * 0.3))
                    }
                } else if size.width >= 300 {
                    HStack(alignment: .center, spacing: 14) {
                        TimeDial(mode: state.mode, size: dial)
                        ModeColumn(mode: state.mode, compact: true)
                            .padding(.top, drop)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    VStack(spacing: 6) {
                        TimeDial(mode: state.mode, size: min(dial, size.height - 30))
                        ModeSwitcher(iconsOnly: true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .leading)
        }
        .padding(.top, isTile ? 0 : 6)
    }
}

// MARK: - Mode switcher

private struct ModeSwitcher: View {
    var iconsOnly = false

    @ObservedObject private var state = FocusTabState.shared
    @ObservedObject private var focus = FocusManager.shared
    @ObservedObject private var timer = TimerManager.shared
    @EnvironmentObject private var settings: Settings
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TimeMode.allCases) { mode in
                segment(mode)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }

    private func segment(_ mode: TimeMode) -> some View {
        let selected = state.mode == mode
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { state.mode = mode }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mode.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                if !iconsOnly {
                    Text(mode.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                }
                if isLive(mode) {
                    // Something is counting here, whether or not you are
                    // looking at it.
                    Circle()
                        .fill(ClockPalette.tint(for: mode))
                        .frame(width: 5, height: 5)
                        .shadow(color: ClockPalette.tint(for: mode).opacity(0.8), radius: 2)
                }
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.5))
            .padding(.horizontal, iconsOnly ? 7 : 9)
            .padding(.vertical, 4)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .matchedGeometryEffect(id: "mode", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(mode.rawValue)
    }

    private func isLive(_ mode: TimeMode) -> Bool {
        switch mode {
        case .focus: return focus.isActive
        case .timer: return timer.countdownIsSet
        case .stopwatch: return timer.isStopwatchRunning
        }
    }
}

// MARK: - Dial

/// What the dial shows for the mode and state it is in.
private struct DialReading {
    /// How far round the current lap the arc reaches, 0 to 1.
    var fraction: Double
    /// Whole laps already wound, drawn as a full ring underneath.
    var laps = 0
    var tint: Color
    var text: String
    /// Hundredths, set smaller beside the stopwatch's seconds.
    var fine: String?
    var caption: String
    var symbol: String
    /// Whether dragging round the dial sets a length.
    var isAdjustable = false
    var pulses = false
}

private struct TimeDial: View {
    let mode: TimeMode
    let size: CGFloat

    @ObservedObject private var focus = FocusManager.shared
    @ObservedObject private var timer = TimerManager.shared
    @EnvironmentObject private var settings: Settings

    /// Laps wound on during the current drag, and where the pointer last was,
    /// so crossing twelve o'clock can add or take off an hour.
    @State private var dragLaps: Int?
    @State private var lastFraction: Double = 0
    @State private var isHovering = false
    @State private var ringing = false

    private var ring: CGFloat { max(size * 0.065, 5) }

    var body: some View {
        let reading = self.reading
        ZStack {
            DialTicks(inset: ring + 4)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: ring)

            if reading.laps > 0 {
                Circle()
                    .stroke(reading.tint.opacity(0.32), lineWidth: ring)
            }

            Circle()
                .trim(from: 0, to: max(reading.fraction, 0.0001))
                .stroke(
                    AngularGradient(
                        colors: [reading.tint.opacity(0.45), reading.tint],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(reading.fraction, 0.02))
                    ),
                    style: StrokeStyle(lineWidth: ring, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: reading.tint.opacity(0.55), radius: ring * 0.9)
                .opacity(reading.fraction > 0.0005 || reading.laps > 0 ? 1 : 0)

            knob(reading)

            centre(reading)
        }
        .frame(width: size, height: size)
        .scaleEffect(ringing ? 1.035 : 1)
        .contentShape(Circle())
        .gesture(adjust, including: reading.isAdjustable ? .all : .none)
        .onTapGesture { tap() }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .onChange(of: reading.pulses) { _, pulses in
            ring(pulses)
        }
        .onAppear { ring(reading.pulses) }
        .help(helpText(reading))
    }

    // MARK: Pieces

    private func knob(_ reading: DialReading) -> some View {
        let radius = (size - ring) / 2
        let angle = reading.fraction * 2 * .pi - .pi / 2
        let visible = reading.isAdjustable || (reading.fraction > 0.001 && reading.fraction < 0.999)
        let side = reading.isAdjustable ? ring * 1.9 : ring * 0.8
        return Circle()
            .fill(reading.isAdjustable ? Color.white : Color.white.opacity(0.95))
            .frame(width: side, height: side)
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .overlay {
                if reading.isAdjustable {
                    Circle().fill(reading.tint).frame(width: side * 0.38, height: side * 0.38)
                }
            }
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(visible ? 1 : 0)
            .scaleEffect(reading.isAdjustable && isHovering ? 1.12 : 1)
    }

    private func centre(_ reading: DialReading) -> some View {
        VStack(spacing: size * 0.012) {
            Image(systemName: reading.symbol)
                .font(.system(size: max(size * 0.085, 8), weight: .semibold))
                .foregroundStyle(reading.tint)
                .symbolEffect(.bounce, value: ringing)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(reading.text)
                    .font(.system(size: size * (reading.fine == nil ? 0.19 : 0.17), weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(countsDown: mode != .stopwatch))
                if let fine = reading.fine {
                    Text(fine)
                        .font(.system(size: size * 0.1, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(reading.caption)
                .font(.system(size: max(size * 0.07, 7.5), weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(width: size - ring * 4)
        .animation(.easeOut(duration: 0.2), value: reading.text)
    }

    // MARK: Reading

    private var reading: DialReading {
        switch mode {
        case .focus: return focusReading
        case .timer: return timerReading
        case .stopwatch: return stopwatchReading
        }
    }

    private var focusReading: DialReading {
        let tint = ClockPalette.tint(for: .focus)
        if focus.isActive {
            return DialReading(
                fraction: 1 - focus.progress,
                tint: tint,
                text: focus.remainingText,
                caption: focus.isOnBreak ? "break" : "focus",
                symbol: focus.isOnBreak ? "figure.walk" : "cup.and.saucer.fill"
            )
        }
        let minutes = settings.focusDefaultMinutes
        let (laps, fraction) = Self.wound(Double(minutes) / 60)
        return DialReading(
            fraction: fraction, laps: laps, tint: tint,
            text: TimerManager.clock(TimeInterval(minutes * 60)),
            caption: isHovering ? "drag to set" : "focus",
            symbol: "cup.and.saucer.fill",
            isAdjustable: true
        )
    }

    private var timerReading: DialReading {
        let tint = ClockPalette.tint(for: .timer)
        if timer.finished {
            return DialReading(
                fraction: 1, tint: tint, text: "00:00", caption: "time's up",
                symbol: "bell.fill", pulses: true
            )
        }
        if timer.countdownIsSet {
            return DialReading(
                fraction: timer.duration > 0 ? timer.remaining / timer.duration : 0,
                tint: tint,
                text: TimerManager.clock(timer.remaining),
                caption: timer.isCountdownRunning ? "left" : "paused",
                symbol: timer.isCountdownRunning ? "timer" : "pause.fill"
            )
        }
        let (laps, fraction) = Self.wound(timer.draft / 3600)
        return DialReading(
            fraction: fraction, laps: laps, tint: tint,
            text: TimerManager.clock(timer.draft),
            caption: isHovering ? "drag to set" : "timer",
            symbol: "timer",
            isAdjustable: true
        )
    }

    private var stopwatchReading: DialReading {
        let elapsed = timer.elapsed
        let whole = TimerManager.stopwatchClock(elapsed)
        let split = whole.split(separator: ".")
        return DialReading(
            fraction: elapsed.truncatingRemainder(dividingBy: 60) / 60,
            tint: ClockPalette.stopwatch,
            text: String(split.first ?? ""),
            fine: split.count > 1 ? "." + split[1] : nil,
            caption: timer.laps.isEmpty ? (timer.isStopwatchRunning ? "running" : "stopwatch") : "lap \(timer.laps.count + 1)",
            symbol: "stopwatch.fill"
        )
    }

    /// Splits hours into laps round the dial and how far into the next one.
    /// Exactly on the hour reads as a full ring, not an empty one.
    static func wound(_ hours: Double) -> (Int, Double) {
        let laps = Int(hours)
        let fraction = hours - Double(laps)
        if fraction < 0.0001, laps > 0 { return (laps - 1, 1) }
        return (laps, fraction)
    }

    private func helpText(_ reading: DialReading) -> String {
        switch mode {
        case .focus: return focus.isActive ? "" : "Drag round to set the length · click to start"
        case .timer:
            if timer.finished { return "Click to dismiss" }
            if timer.countdownIsSet { return timer.isCountdownRunning ? "Click to pause" : "Click to resume" }
            return "Drag round to set · click to start"
        case .stopwatch: return timer.isStopwatchRunning ? "Click to stop" : "Click to start"
        }
    }

    // MARK: Interaction

    private func tap() {
        switch mode {
        case .focus:
            if !focus.isActive { focus.start(minutes: settings.focusDefaultMinutes) }
        case .timer:
            if timer.finished {
                timer.acknowledge()
            } else if timer.countdownIsSet {
                timer.toggleCountdown()
            } else {
                timer.startDraft()
            }
        case .stopwatch:
            timer.toggleStopwatch()
        }
    }

    /// Dragging round the ring, like winding a kitchen timer.
    private var adjust: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let dx = value.location.x - size / 2
                let dy = value.location.y - size / 2
                guard hypot(dx, dy) > size * 0.16 else { return }
                var fraction = atan2(dx, -dy) / (2 * .pi)
                if fraction < 0 { fraction += 1 }

                if dragLaps == nil {
                    dragLaps = currentLaps
                    lastFraction = fraction
                }
                var laps = dragLaps ?? 0
                if lastFraction > 0.75, fraction < 0.25 { laps += 1 }
                if lastFraction < 0.25, fraction > 0.75 { laps -= 1 }
                dragLaps = laps
                lastFraction = fraction
                set(hours: Double(laps) + fraction)
            }
            .onEnded { _ in dragLaps = nil }
    }

    private var currentLaps: Int {
        switch mode {
        case .focus: return Self.wound(Double(settings.focusDefaultMinutes) / 60).0
        case .timer: return Self.wound(timer.draft / 3600).0
        case .stopwatch: return 0
        }
    }

    private func set(hours: Double) {
        switch mode {
        case .focus:
            // Five-minute steps, from five minutes to three hours.
            let minutes = min(max(Int((hours * 12).rounded()) * 5, 5), 180)
            guard minutes != settings.focusDefaultMinutes else { return }
            settings.focusDefaultMinutes = minutes
            tick()
        case .timer:
            // Whole minutes, from one to three hours.
            let minutes = min(max((hours * 60).rounded(), 1), TimerManager.maximumDraft / 60)
            let seconds = minutes * 60
            guard seconds != timer.draft else { return }
            timer.draft = seconds
            tick()
        case .stopwatch:
            break
        }
    }

    /// A detent under the finger on a Force Touch trackpad.
    private func tick() {
        guard settings.enableHaptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func ring(_ pulses: Bool) {
        guard pulses else {
            withAnimation(.easeOut(duration: 0.2)) { ringing = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
            ringing = true
        }
    }
}

/// Minute marks round the inside of the ring, every fifth one longer.
private struct DialTicks: View {
    let inset: CGFloat

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = size.width / 2 - inset
            for index in 0 ..< 60 {
                let major = index % 5 == 0
                let length: CGFloat = major ? 4 : 2
                let angle = CGFloat(index) / 60 * 2 * .pi - .pi / 2
                let dx: CGFloat = cos(angle)
                let dy: CGFloat = sin(angle)
                var path = Path()
                path.move(to: CGPoint(x: centre.x + dx * outer, y: centre.y + dy * outer))
                path.addLine(to: CGPoint(x: centre.x + dx * (outer - length), y: centre.y + dy * (outer - length)))
                context.stroke(path, with: .color(.white.opacity(major ? 0.26 : 0.1)),
                               style: StrokeStyle(lineWidth: major ? 1.2 : 0.8, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Middle column

private struct ModeColumn: View {
    let mode: TimeMode
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 9) {
            ModeSwitcher(iconsOnly: compact)

            Group {
                switch mode {
                case .focus: FocusControls(compact: compact)
                case .timer: TimerControls(compact: compact)
                case .stopwatch: StopwatchControls(compact: compact)
                }
            }
            .transition(.opacity.combined(with: .offset(y: 4)))
            .id(mode)
        }
    }
}

private struct Headline: View {
    let title: String
    let detail: String
    var tint: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.opacity)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: Focus

private struct FocusControls: View {
    var compact = false

    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    private let lengths = [15, 25, 45, 60, 90]

    var body: some View {
        if focus.isActive {
            active
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(title: "Ready to focus", detail: idleDetail)

            HStack(spacing: 6) {
                ClockButton(
                    title: "Start \(settings.focusDefaultMinutes) min",
                    symbol: "play.fill",
                    style: .primary,
                    tint: ClockPalette.tint(for: .focus)
                ) {
                    focus.start(minutes: settings.focusDefaultMinutes)
                }
                if !compact {
                    LengthPicker(values: lengths, selection: settings.focusDefaultMinutes) { minutes in
                        withAnimation(.easeOut(duration: 0.2)) { settings.focusDefaultMinutes = minutes }
                    }
                }
            }

            HStack(spacing: 5) {
                ToggleChip(
                    title: "Block sites",
                    symbol: settings.focusBlockWebsites ? "hand.raised.fill" : "hand.raised.slash",
                    isOn: settings.focusBlockWebsites,
                    help: settings.focusBlockWebsites
                        ? "Distracting sites are sent to a blocked page while you focus"
                        : "Turn on to keep distracting sites away while you focus"
                ) {
                    settings.focusBlockWebsites.toggle()
                }
                ToggleChip(
                    title: compact ? "Pomodoro" : "Pomodoro · \(settings.focusBreakMinutes) min breaks",
                    symbol: "arrow.triangle.2.circlepath",
                    isOn: settings.focusPomodoro,
                    help: "Roll into a break at the end, then back to work"
                ) {
                    settings.focusPomodoro.toggle()
                }
            }
        }
    }

    private var idleDetail: String {
        var parts: [String] = []
        if settings.focusBlockWebsites {
            let count = settings.focusBlocklist.count
            if FocusManager.supportedInstalledBrowsers.isEmpty {
                parts.append("No supported browser to block sites in")
            } else {
                parts.append("Blocks \(count) site\(count == 1 ? "" : "s")")
            }
        }
        let apps = settings.focusBlockedApps.count
        if apps > 0 { parts.append("hides \(apps) app\(apps == 1 ? "" : "s")") }
        if settings.focusPauseMusic { parts.append("pauses music") }
        return parts.isEmpty ? "Just you and a countdown." : parts.joined(separator: " · ")
    }

    private var active: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(
                title: focus.isOnBreak ? "On a break" : "Focusing",
                detail: activeDetail,
                tint: focus.isOnBreak ? ClockPalette.rest : .white
            )

            HStack(spacing: 6) {
                if focus.isOnBreak {
                    ClockButton(title: "Back to work", symbol: "forward.fill", style: .primary,
                                tint: ClockPalette.tint(for: .focus)) {
                        focus.skipBreak()
                    }
                } else {
                    ClockButton(title: "5 min", symbol: "plus", style: .secondary) {
                        focus.extend(byMinutes: 5)
                    }
                }
                ClockButton(title: "End", symbol: "stop.fill", style: .destructive) {
                    focus.stop()
                }
            }

            if settings.focusPomodoro {
                CycleDots(completed: focus.completedCycles, onBreak: focus.isOnBreak)
            } else if let host = focus.lastBlockedHost {
                Label("Sent \(host) away", systemImage: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    private var activeDetail: String {
        guard let end = focus.endDate else { return "" }
        let time = FocusView.timeText(end)
        if focus.isOnBreak { return "Back to work at \(time)" }
        var parts = ["Until \(time)"]
        if focus.blockedCount > 0 {
            parts.append("\(focus.blockedCount) tab\(focus.blockedCount == 1 ? "" : "s") sent back")
        }
        return parts.joined(separator: " · ")
    }
}

/// Four dots to a set, filling as work stretches finish.
private struct CycleDots: View {
    let completed: Int
    let onBreak: Bool

    @EnvironmentObject private var settings: Settings

    var body: some View {
        HStack(spacing: 5) {
            let inSet = completed % 4
            ForEach(0 ..< 4, id: \.self) { index in
                Capsule()
                    .fill(index < inSet || (inSet == 0 && completed > 0 && onBreak)
                          ? settings.accentColor
                          : Color.white.opacity(0.14))
                    .frame(width: index == inSet && !onBreak ? 16 : 8, height: 5)
            }
            Text(completed == 0 ? "First round" : "\(completed) round\(completed == 1 ? "" : "s") done")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.leading, 3)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: completed)
    }
}

// MARK: Timer

private struct TimerControls: View {
    var compact = false

    @ObservedObject private var timer = TimerManager.shared

    private let presets: [TimeInterval] = [60, 180, 300, 600, 900, 1800]

    var body: some View {
        if timer.finished {
            finished
        } else if timer.countdownIsSet {
            running
        } else {
            idle
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(title: "Set a timer", detail: "Drag the dial round, or pick a length.")

            HStack(spacing: 6) {
                ClockButton(title: "Start", symbol: "play.fill", style: .primary, tint: ClockPalette.timer) {
                    timer.startDraft()
                }
                StepButton(symbol: "minus", help: "One minute less") { timer.addTime(-60) }
                StepButton(symbol: "plus", help: "One minute more") { timer.addTime(60) }
            }

            HStack(spacing: 4) {
                ForEach(compact ? Array(presets.prefix(4)) : presets, id: \.self) { seconds in
                    PresetChip(title: "\(Int(seconds) / 60)m", help: TimerManager.shortLength(seconds)) {
                        timer.start(seconds: seconds)
                    }
                }
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(
                title: timer.isCountdownRunning ? "Timer running" : "Timer paused",
                detail: runningDetail
            )
            HStack(spacing: 6) {
                ClockButton(
                    title: timer.isCountdownRunning ? "Pause" : "Resume",
                    symbol: timer.isCountdownRunning ? "pause.fill" : "play.fill",
                    style: .primary,
                    tint: ClockPalette.timer
                ) {
                    timer.toggleCountdown()
                }
                ClockButton(title: "1 min", symbol: "plus", style: .secondary, iconOnly: compact) { timer.addTime(60) }
                ClockButton(title: "Cancel", symbol: "xmark", style: .destructive, iconOnly: compact) {
                    timer.resetCountdown()
                }
            }
            ProgressLine(progress: timer.progress, tint: ClockPalette.timer)
                .frame(height: 4)
                .frame(maxWidth: 240)
        }
    }

    private var runningDetail: String {
        if let end = timer.endDate {
            return "\(TimerManager.shortLength(timer.duration)) · rings at \(FocusView.timeText(end))"
        }
        return "\(TimerManager.clock(timer.remaining)) left of \(TimerManager.shortLength(timer.duration))"
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(title: "Time's up", detail: "\(TimerManager.shortLength(timer.duration)) timer",
                     tint: ClockPalette.alarm)
            HStack(spacing: 6) {
                ClockButton(title: "Dismiss", symbol: "checkmark", style: .primary, tint: ClockPalette.alarm) {
                    timer.acknowledge()
                }
                ClockButton(title: "1 min", symbol: "plus", style: .secondary, iconOnly: compact) { timer.addTime(60) }
                ClockButton(title: "Again", symbol: "arrow.counterclockwise", style: .secondary, iconOnly: compact) {
                    timer.start(seconds: max(timer.duration, 60))
                }
            }
        }
    }
}

// MARK: Stopwatch

private struct StopwatchControls: View {
    var compact = false

    @ObservedObject private var timer = TimerManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Headline(title: title, detail: detail)

            HStack(spacing: 6) {
                ClockButton(
                    title: timer.isStopwatchRunning ? "Stop" : (timer.elapsed > 0 ? "Resume" : "Start"),
                    symbol: timer.isStopwatchRunning ? "stop.fill" : "play.fill",
                    style: timer.isStopwatchRunning ? .destructive : .primary,
                    tint: ClockPalette.stopwatch
                ) {
                    timer.toggleStopwatch()
                }
                if timer.isStopwatchRunning {
                    ClockButton(title: "Lap", symbol: "flag.fill", style: .secondary) { timer.lap() }
                } else if timer.elapsed > 0 {
                    ClockButton(title: "Reset", symbol: "arrow.counterclockwise", style: .secondary) {
                        timer.resetStopwatch()
                    }
                }
            }

            if compact, let last = timer.laps.first {
                Text("Last lap \(TimerManager.stopwatchClock(last))")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var title: String {
        if timer.isStopwatchRunning { return "Running" }
        return timer.elapsed > 0 ? "Stopped" : "Stopwatch"
    }

    private var detail: String {
        if timer.elapsed == 0 { return "Click the dial or Start. Lap marks a split." }
        let current = "Lap \(timer.laps.count + 1) · \(TimerManager.stopwatchClock(timer.currentLap))"
        return current
    }
}

// MARK: - Side panel

private struct SidePanel: View {
    let mode: TimeMode

    var body: some View {
        Group {
            switch mode {
            case .focus: FocusWeekPanel()
            case .timer: RecentTimersPanel()
            case .stopwatch: LapsPanel()
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .padding(.vertical, 4)
        .transition(.opacity)
        .id(mode)
    }
}

private struct PanelTitle: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// The last seven days as bars, today in colour, with the streak under them.
private struct FocusWeekPanel: View {
    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        let week = focus.week
        let total = week.reduce(0) { $0 + $1.seconds }
        // An hour is the smallest full-height bar, so one short session does
        // not look like a heroic day.
        let top = max(week.map(\.seconds).max() ?? 0, 3600)

        VStack(alignment: .leading, spacing: 6) {
            PanelTitle(title: "This week", trailing: FocusManager.duration(total))

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                    let isToday = index == week.count - 1
                    VStack(spacing: 3) {
                        GeometryReader { bar in
                            ZStack(alignment: .bottom) {
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(isToday
                                          ? AnyShapeStyle(LinearGradient(
                                              colors: [settings.accentColor, settings.accentColor.opacity(0.55)],
                                              startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.white.opacity(0.28)))
                                    .frame(height: day.seconds == 0
                                           ? 0
                                           : max(CGFloat(day.seconds) / CGFloat(top) * bar.size.height, 5))
                                    .shadow(color: isToday ? settings.accentColor.opacity(0.5) : .clear, radius: 4)
                            }
                        }
                        .frame(width: 10)
                        Text(Self.letter(for: day.day))
                            .font(.system(size: 8, weight: isToday ? .bold : .medium))
                            .foregroundStyle(.white.opacity(isToday ? 0.85 : 0.35))
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(Self.weekday(day.day)): \(FocusManager.duration(day.seconds))")
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: week.map(\.seconds))

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(focus.streak > 0 ? Color.orange : .white.opacity(0.3))
                    Text(focus.streak == 0 ? "No streak yet" : "\(focus.streak)-day streak")
                }
                Spacer(minLength: 0)
                Text("Today \(FocusManager.duration(focus.todaySeconds))")
            }
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
    }

    private static func letter(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: day)
    }

    private static func weekday(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: day)
    }
}

/// Lengths run before, one click to run again.
private struct RecentTimersPanel: View {
    @ObservedObject private var timer = TimerManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        let recent = Array(timer.recentDurations.prefix(4))
        VStack(alignment: .leading, spacing: 5) {
            PanelTitle(title: "Recent")

            if recent.isEmpty {
                Text("Timers you run show up here, ready to run again.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 3) {
                    ForEach(recent, id: \.self) { seconds in
                        RecentRow(seconds: seconds) { timer.start(seconds: seconds) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RecentRow: View {
    let seconds: TimeInterval
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(ClockPalette.timer)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(ClockPalette.timer.opacity(0.18)))
                Text(TimerManager.shortLength(seconds))
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                TimelineView(.everyMinute) { context in
                    Text("ends \(FocusView.timeText(context.date.addingTimeInterval(seconds)))")
                        .font(.system(size: 9.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(isHovering ? 0.6 : 0.35))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.1 : 0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

/// Laps, newest first, the fastest in green and the slowest in red once
/// there are enough of them for that to mean anything.
private struct LapsPanel: View {
    @ObservedObject private var timer = TimerManager.shared

    var body: some View {
        let laps = timer.laps
        let fastest = laps.count >= 2 ? laps.min() : nil
        let slowest = laps.count >= 2 ? laps.max() : nil

        VStack(alignment: .leading, spacing: 4) {
            PanelTitle(title: "Laps", trailing: laps.isEmpty ? nil : "\(laps.count)")

            if laps.isEmpty, !timer.isStopwatchRunning {
                Text("Press Lap while it runs to mark a split.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        if timer.isStopwatchRunning || timer.elapsed > 0 {
                            lapRow(number: laps.count + 1, time: timer.currentLap, colour: .white.opacity(0.55))
                        }
                        ForEach(Array(laps.enumerated()), id: \.offset) { index, lap in
                            lapRow(
                                number: laps.count - index,
                                time: lap,
                                colour: lap == fastest ? ClockPalette.fastest
                                    : (lap == slowest ? ClockPalette.slowest : .white.opacity(0.85))
                            )
                        }
                    }
                }
            }
        }
    }

    private func lapRow(number: Int, time: TimeInterval, colour: Color) -> some View {
        HStack {
            Text("Lap \(number)")
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
            Text(TimerManager.stopwatchClock(time))
                .monospacedDigit()
                .foregroundStyle(colour)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .padding(.vertical, 1)
    }
}

// MARK: - Controls

/// Tinted pill buttons, in the style of the Clock app: a wash of the colour
/// behind a label in the colour itself.
struct ClockButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    var symbol: String?
    var style: Style = .secondary
    var tint: Color = .white
    /// Just the symbol in a circle, where there is no room for words.
    var iconOnly = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: iconOnly ? 10 : 9, weight: .bold))
                }
                if !iconOnly || symbol == nil {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : 11)
            .frame(width: iconOnly ? 25 : nil, height: 25)
            .background(Capsule().fill(background))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help(iconOnly ? title : "")
        .fixedSize()
    }

    private var foreground: Color {
        switch style {
        case .primary: return tint
        case .secondary: return .white.opacity(isHovering ? 1 : 0.85)
        case .destructive: return ClockPalette.slowest
        }
    }

    private var background: Color {
        switch style {
        case .primary: return tint.opacity(isHovering ? 0.32 : 0.22)
        case .secondary: return .white.opacity(isHovering ? 0.16 : 0.09)
        case .destructive: return ClockPalette.slowest.opacity(isHovering ? 0.28 : 0.18)
        }
    }
}

/// Shrinks a touch while held, so a click is felt as well as seen.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct StepButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 25, height: 25)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.16 : 0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help(help)
    }
}

private struct PresetChip: View {
    let title: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.75))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.15 : 0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help("Start a \(help) timer")
    }
}

/// A row of lengths in one capsule, the chosen one lit.
private struct LengthPicker: View {
    let values: [Int]
    let selection: Int
    let choose: (Int) -> Void

    @EnvironmentObject private var settings: Settings
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { minutes in
                Button {
                    choose(minutes)
                } label: {
                    Text("\(minutes)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == minutes ? .white : .white.opacity(0.5))
                        .frame(width: 26, height: 21)
                        .background {
                            if selection == minutes {
                                Capsule()
                                    .fill(settings.accentColor.opacity(0.35))
                                    .matchedGeometryEffect(id: "length", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(minutes) minutes")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }
}

private struct ToggleChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 8.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isOn ? settings.accentColor : .white.opacity(isHovering ? 0.75 : 0.45))
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(
                Capsule().fill(isOn ? settings.accentColor.opacity(0.16) : Color.white.opacity(isHovering ? 0.1 : 0.05))
            )
            .overlay(
                Capsule().strokeBorder(isOn ? settings.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .help(help)
        .fixedSize()
    }
}

/// A slim bar for how much of the countdown has gone.
private struct ProgressLine: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.6), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(proxy.size.width * progress, proxy.size.height))
            }
        }
    }
}

extension FocusView {
    /// A clock time in the user's own 12- or 24-hour style.
    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Locale.current.hasTwelveHourClock ? "h:mm a" : "HH:mm"
        return formatter.string(from: date)
    }
}
