//
//  TimerManager.swift
//  FunNotch
//
//  Countdown timers and a stopwatch.
//
//  Deliberately separate from Focus. A focus session is a commitment with
//  consequences — sites blocked, apps hidden, a length you agreed to. A timer
//  is the opposite: start it, stop it, change your mind, run it for eleven
//  seconds. Sharing state between the two would make both worse.
//

import AppKit
import Combine
import Foundation

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    enum Mode: String, CaseIterable, Identifiable {
        case timer = "Timer"
        case stopwatch = "Stopwatch"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .timer

    /// Seconds left on the countdown.
    @Published private(set) var remaining: TimeInterval = 0
    /// What the countdown was set to, so the ring knows how full to be.
    @Published private(set) var duration: TimeInterval = 0
    /// Seconds on the stopwatch.
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var isRunning = false
    /// Set when a countdown reaches zero, cleared when it is acknowledged or
    /// restarted, so the view can make some noise about it.
    @Published private(set) var finished = false
    /// Stopwatch laps, newest first.
    @Published private(set) var laps: [TimeInterval] = []

    private var ticker: Timer?
    /// Wall-clock deadline rather than counting ticks down: a timer that loses
    /// a second every time the machine is busy is not a timer.
    private var deadline: Date?
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    private init() {}

    var isActive: Bool { isRunning || remaining > 0 || elapsed > 0 }

    // MARK: - Countdown

    func start(seconds: TimeInterval) {
        mode = .timer
        duration = seconds
        remaining = seconds
        deadline = Date().addingTimeInterval(seconds)
        finished = false
        isRunning = true
        startTicking()
    }

    func addTime(_ seconds: TimeInterval) {
        guard mode == .timer else { return }
        if isRunning, let deadline {
            self.deadline = deadline.addingTimeInterval(seconds)
            remaining = max(self.deadline!.timeIntervalSinceNow, 0)
        } else {
            remaining = max(remaining + seconds, 0)
        }
        duration = max(duration + seconds, remaining)
        if remaining > 0 { finished = false }
    }

    // MARK: - Stopwatch

    func startStopwatch() {
        mode = .stopwatch
        startedAt = Date()
        isRunning = true
        startTicking()
    }

    func lap() {
        guard mode == .stopwatch, isRunning else { return }
        laps.insert(elapsed, at: 0)
        if laps.count > 20 { laps.removeLast() }
    }

    // MARK: - Shared controls

    func pause() {
        guard isRunning else { return }
        isRunning = false
        switch mode {
        case .timer:
            remaining = max(deadline?.timeIntervalSinceNow ?? 0, 0)
            deadline = nil
        case .stopwatch:
            accumulated = elapsed
            startedAt = nil
        }
        stopTicking()
    }

    func resume() {
        guard !isRunning else { return }
        switch mode {
        case .timer:
            guard remaining > 0 else { return }
            deadline = Date().addingTimeInterval(remaining)
        case .stopwatch:
            startedAt = Date()
        }
        isRunning = true
        startTicking()
    }

    func toggle() {
        if isRunning { pause() } else { resume() }
    }

    func reset() {
        stopTicking()
        isRunning = false
        finished = false
        deadline = nil
        startedAt = nil
        accumulated = 0
        remaining = 0
        duration = 0
        elapsed = 0
        laps = []
    }

    func acknowledge() { finished = false }

    // MARK: - Ticking

    private func startTicking() {
        stopTicking()
        // Ten a second: the stopwatch shows hundredths, and a countdown that
        // visibly stutters feels broken even when it is accurate.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        switch mode {
        case .timer:
            guard let deadline else { return }
            remaining = max(deadline.timeIntervalSinceNow, 0)
            if remaining <= 0 { complete() }
        case .stopwatch:
            guard let startedAt else { return }
            elapsed = accumulated + Date().timeIntervalSince(startedAt)
        }
    }

    private func complete() {
        stopTicking()
        isRunning = false
        deadline = nil
        remaining = 0
        finished = true
        NSSound(named: "Glass")?.play()
        // Bring the notch out so the alert is seen, not just heard.
        NotchWindowManager.shared.broadcast { model in
            model.currentTab = .timer
            model.open()
        }
    }

    /// Development aid: pose the stopwatch for `--render-preview` without
    /// having to wait a real minute for it to reach an interesting state.
    func injectPreviewStopwatch(elapsed: TimeInterval, laps: [TimeInterval]) {
        mode = .stopwatch
        self.elapsed = elapsed
        accumulated = elapsed
        self.laps = laps
        isRunning = false
    }

    // MARK: - Formatting

    /// `mm:ss`, growing to `h:mm:ss` only when there are hours to show.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// Stopwatch precision, with hundredths.
    static func stopwatchClock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        let hundredths = Int((seconds - Double(total)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, secs, hundredths)
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return max(min(1 - remaining / duration, 1), 0)
    }
}
