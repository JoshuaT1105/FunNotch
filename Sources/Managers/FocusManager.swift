//
//  FocusManager.swift
//  FunNotch
//
//  Focus sessions: a countdown that, while running, keeps distracting sites out
//  of the way.
//
//  Blocking is done by watching the browsers over Apple Events and sending any
//  tab on the blocklist to a local "blocked" page. That is the only approach
//  available to an unprivileged app — editing /etc/hosts needs root, and a
//  network content filter needs a signed system extension.
//

import AppKit
import Combine
import Foundation

/// A browser we know how to inspect and redirect.
private struct BrowserTarget {
    let bundleIdentifier: String
    let applicationName: String
    /// Chrome-family browsers use `active tab index`, Safari uses `current tab`.
    let isChromeFamily: Bool
}

private let tabSeparator = "|~|"

@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    /// How many tabs have been redirected during this session.
    @Published private(set) var blockedCount = 0
    /// Host of the most recent redirect, for the UI to acknowledge.
    @Published private(set) var lastBlockedHost: String?
    /// True during the rest half of a pomodoro cycle.
    @Published private(set) var isOnBreak = false
    /// Work stretches finished in the current run of cycles.
    @Published private(set) var completedCycles = 0

    /// Minutes of the work stretch, remembered so breaks can hand back to it.
    private var workMinutes = 25
    private var appHideTimer: Timer?

    private var timer: Timer?
    private var enforcementTick = 0
    private var isEnforcing = false
    private let settings = Settings.shared

    private init() {}

    /// Fraction of the session already elapsed, for the progress ring.
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return min(max(1 - remaining / totalDuration, 0), 1)
    }

    var remainingText: String {
        let clamped = max(remaining, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Compact form for the collapsed notch, where space is tight.
    var compactRemainingText: String {
        let clamped = max(remaining, 0)
        let minutes = Int(clamped) / 60
        if minutes >= 60 {
            return "\(minutes / 60)h\(minutes % 60)"
        }
        if minutes >= 1 {
            return "\(minutes)m"
        }
        return "\(Int(clamped))s"
    }

    // MARK: - Session control

    func start(minutes: Int) {
        workMinutes = max(minutes, 1)
        completedCycles = 0
        isOnBreak = false
        runShortcut(named: settings.focusStartShortcut)
        startInterval(minutes: workMinutes)
    }

    /// Begins a work or break stretch without resetting the cycle count.
    private func startInterval(minutes: Int) {
        let duration = TimeInterval(max(minutes, 1) * 60)
        totalDuration = duration
        remaining = duration
        endDate = Date().addingTimeInterval(duration)
        blockedCount = 0
        lastBlockedHost = nil
        isActive = true

        writeBlockedPage()

        if settings.focusPauseMusic, MusicManager.shared.isPlaying {
            MusicManager.shared.togglePlayPause()
        }

        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        startHidingApps()
        announce(icon: isOnBreak ? "figure.walk" : "cup.and.saucer.fill")
        enforce()
    }

    func stop() {
        guard isActive else { return }
        recordCompletedTime()
        isActive = false
        isOnBreak = false
        endDate = nil
        remaining = 0
        timer?.invalidate()
        timer = nil
        stopHidingApps()
        runShortcut(named: settings.focusEndShortcut)
        announce(icon: "checkmark.circle.fill")
    }

    func extend(byMinutes minutes: Int) {
        guard isActive, let endDate else { return }
        let newEnd = endDate.addingTimeInterval(TimeInterval(minutes * 60))
        self.endDate = newEnd
        totalDuration += TimeInterval(minutes * 60)
        remaining = newEnd.timeIntervalSinceNow
    }

    private func tick() {
        guard isActive, let endDate else { return }
        remaining = max(endDate.timeIntervalSinceNow, 0)

        if remaining <= 0 {
            finish()
            return
        }

        // Checking every tick would hammer the browsers with Apple Events.
        enforcementTick += 1
        if enforcementTick % 2 == 0 {
            enforce()
        }
    }

    private func finish() {
        recordCompletedTime()

        // In pomodoro mode a finished stretch hands over to the other kind
        // rather than ending the session.
        if settings.focusPomodoro {
            if isOnBreak {
                isOnBreak = false
                startInterval(minutes: workMinutes)
            } else {
                completedCycles += 1
                settings.focusSessionsCompleted += 1
                isOnBreak = true
                startInterval(minutes: max(settings.focusBreakMinutes, 1))
            }
            NotchWindowManager.shared.broadcast { viewModel in
                viewModel.showExpandingView(
                    type: .focus,
                    value: 1,
                    icon: self.isOnBreak ? "figure.walk" : "cup.and.saucer.fill",
                    duration: 4.0
                )
            }
            return
        }

        settings.focusSessionsCompleted += 1
        isActive = false
        isOnBreak = false
        endDate = nil
        remaining = 0
        timer?.invalidate()
        timer = nil
        stopHidingApps()
        runShortcut(named: settings.focusEndShortcut)

        NotchWindowManager.shared.broadcast { viewModel in
            viewModel.showExpandingView(
                type: .focus,
                value: 1,
                icon: "checkmark.circle.fill",
                duration: 4.0
            )
        }
    }

    /// Adds the time actually spent working to the running total.
    private func recordCompletedTime() {
        guard !isOnBreak, totalDuration > 0 else { return }
        let elapsed = max(totalDuration - remaining, 0)
        settings.focusMinutesTotal += Int(elapsed / 60)
    }

    // MARK: - App blocking
    //
    // Hiding an app needs no special privileges, unlike actually preventing it
    // from running. It is a nudge in the same spirit as the website blocking.

    private func startHidingApps() {
        stopHidingApps()
        guard !settings.focusBlockedApps.isEmpty, !isOnBreak else { return }

        hideBlockedApps()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideBlockedApps() }
        }
        RunLoop.main.add(timer, forMode: .common)
        appHideTimer = timer
    }

    private func stopHidingApps() {
        appHideTimer?.invalidate()
        appHideTimer = nil
    }

    private func hideBlockedApps() {
        let blocked = Set(settings.focusBlockedApps)
        guard !blocked.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let identifier = app.bundleIdentifier, blocked.contains(identifier) else { continue }
            guard !app.isHidden else { continue }
            app.hide()
        }
    }

    // MARK: - Shortcuts

    /// Runs a Shortcuts workflow by name, if one is configured.
    private func runShortcut(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", trimmed]
        do {
            try process.run()
            DiagnosticLog.write("focus", "ran shortcut \(trimmed)")
        } catch {
            DiagnosticLog.write("focus", "could not run shortcut \(trimmed): \(error.localizedDescription)")
        }
    }

    private func announce(icon: String) {
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showExpandingView(type: .focus, value: progress, icon: icon, duration: 2.5)
        }
    }

    /// Puts the manager into a running-looking state without starting the timer
    /// or touching any browser. Used by the snapshot renderer.
    func injectPreviewSession(minutes: Int, elapsedFraction: Double) {
        totalDuration = TimeInterval(minutes * 60)
        remaining = totalDuration * (1 - elapsedFraction)
        endDate = Date().addingTimeInterval(remaining)
        blockedCount = 3
        isActive = true
    }

    /// Undoes `injectPreviewSession`.
    func clearPreviewSession() {
        isActive = false
        endDate = nil
        remaining = 0
        totalDuration = 0
        blockedCount = 0
        lastBlockedHost = nil
    }

    // MARK: - Website blocking

    private var blockedPageURL: URL {
        FileManager.default.standardDirectory(.cachesDirectory, fallback: "Library/Caches")
            .appendingPathComponent("com.funnotch.FunNotch", isDirectory: true)
            .appendingPathComponent("blocked.html")
    }

    private func writeBlockedPage() {
        let directory = blockedPageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = Locale.current.hasTwelveHourClock ? "h:mm a" : "HH:mm"
        let until = endDate.map { formatter.string(from: $0) } ?? ""

        let html = """
        <!doctype html>
        <meta charset="utf-8">
        <title>Blocked — Focus</title>
        <style>
          :root { color-scheme: dark light; }
          body {
            margin: 0; min-height: 100vh; display: grid; place-items: center;
            font: 16px/1.5 -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
            background: #0b0b0d; color: #f2f2f7; text-align: center;
          }
          .card { max-width: 34rem; padding: 2rem; }
          h1 { font-size: 1.6rem; margin: 0 0 .5rem; letter-spacing: -0.02em; }
          p { margin: .35rem 0; color: #a1a1aa; }
          .until { margin-top: 1.5rem; font-size: 2.6rem; font-weight: 600; color: #f2f2f7; letter-spacing: -0.03em; }
          .hint { margin-top: 1.75rem; font-size: .8rem; color: #71717a; }
        </style>
        <div class="card">
          <h1>Not right now</h1>
          <p>This site is on your blocklist while Focus is running.</p>
          <div class="until">until \(until)</div>
          <p class="hint">Stop the session from the notch to unblock.</p>
        </div>
        """

        try? html.write(to: blockedPageURL, atomically: true, encoding: .utf8)
    }

    private static let browsers: [BrowserTarget] = [
        BrowserTarget(bundleIdentifier: "com.apple.Safari", applicationName: "Safari", isChromeFamily: false),
        BrowserTarget(bundleIdentifier: "com.google.Chrome", applicationName: "Google Chrome", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "com.brave.Browser", applicationName: "Brave Browser", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "com.microsoft.edgemac", applicationName: "Microsoft Edge", isChromeFamily: true),
        BrowserTarget(bundleIdentifier: "company.thebrowser.Browser", applicationName: "Arc", isChromeFamily: true),
    ]

    private func enforce() {
        guard isActive, settings.focusBlockWebsites, !isEnforcing else { return }
        let blocklist = settings.focusBlocklist
        guard !blocklist.isEmpty else { return }

        for browser in Self.browsers where AppleScriptRunner.isRunning(browser.bundleIdentifier) {
            isEnforcing = true
            AppleScriptRunner.shared.runForString(Self.readTabsScript(for: browser)) { [weak self] result in
                guard let self else { return }
                self.isEnforcing = false
                guard let result, !result.isEmpty else { return }
                self.redirectBlockedTabs(in: browser, tabList: result, blocklist: blocklist)
            }
        }
    }

    private func redirectBlockedTabs(in browser: BrowserTarget, tabList: String, blocklist: [String]) {
        let destination = blockedPageURL.absoluteString

        for line in tabList.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: tabSeparator)
            guard parts.count >= 3,
                  let window = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let tab = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }

            let urlString = parts[2]
            // Never rewrite our own blocked page — that would loop forever.
            guard !urlString.hasPrefix(destination) else { continue }
            guard let host = Self.host(of: urlString), Self.isBlocked(host: host, by: blocklist) else { continue }

            AppleScriptRunner.shared.execute(
                Self.redirectScript(for: browser, window: window, tab: tab, destination: destination)
            )
            blockedCount += 1
            lastBlockedHost = host
        }
    }

    nonisolated static func host(of urlString: String) -> String? {
        guard let url = URL(string: urlString), let rawHost = url.host else { return nil }
        // Hosts are case-insensitive, and the blocklist is stored lower-cased.
        let host = rawHost.lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Matches the host itself and any subdomain of it.
    nonisolated static func isBlocked(host: String, by blocklist: [String]) -> Bool {
        blocklist.contains { entry in
            let target = entry
                .lowercased()
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "www.", with: "")
            guard !target.isEmpty else { return false }
            return host == target || host.hasSuffix("." + target)
        }
    }

    private static func readTabsScript(for browser: BrowserTarget) -> String {
        """
        tell application "\(browser.applicationName)"
            set out to ""
            try
                repeat with w from 1 to count of windows
                    try
                        repeat with t from 1 to count of tabs of window w
                            try
                                set u to (URL of tab t of window w) as string
                                set out to out & w & "\(tabSeparator)" & t & "\(tabSeparator)" & u & linefeed
                            end try
                        end repeat
                    end try
                end repeat
            end try
            return out
        end tell
        """
    }

    private static func redirectScript(
        for browser: BrowserTarget,
        window: Int,
        tab: Int,
        destination: String
    ) -> String {
        """
        tell application "\(browser.applicationName)"
            try
                set URL of tab \(tab) of window \(window) to "\(destination)"
            end try
        end tell
        """
    }

    /// Browsers installed on this Mac that Focus can police.
    static var supportedInstalledBrowsers: [String] {
        browsers
            .filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil }
            .map(\.applicationName)
    }
}
