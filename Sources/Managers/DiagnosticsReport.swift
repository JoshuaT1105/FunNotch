//
//  DiagnosticsReport.swift
//  FunNotch
//
//  What the app can and cannot currently see, in one place.
//
//  Almost everything here depends on a permission the user may not have given,
//  or on a switch inside another application. When one of those is missing the
//  feature does not crash, it just quietly does less — which from the outside
//  is indistinguishable from a bug. This is the screen that tells them apart.
//

import AVFoundation
import AppKit
import ApplicationServices
import CoreLocation
import EventKit
import Foundation

/// Which read path each browser ended up on. Written by the media controller,
/// which is created and destroyed as backends change, so it lives out here.
enum BrowserReadModes {
    /// Browser name → true when the page itself answered, false when only the
    /// tab title was readable.
    nonisolated(unsafe) private(set) static var modes: [String: Bool] = [:]
    private static let lock = NSLock()

    static func record(browser: String, scripted: Bool) {
        lock.lock()
        modes[browser] = scripted
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        modes.removeAll()
        lock.unlock()
    }
}

@MainActor
final class DiagnosticsReport: ObservableObject {
    static let shared = DiagnosticsReport()

    enum Verdict {
        case good(String)
        case missing(String)
        case unknown(String)

        var text: String {
            switch self {
            case let .good(text), let .missing(text), let .unknown(text): return text
            }
        }

        var symbol: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .missing: return "exclamationmark.triangle.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let verdict: Verdict
        /// What to do about it, when there is something to do.
        var remedy: String?
    }

    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let rows: [Row]
    }

    @Published private(set) var sections: [Section] = []
    @Published private(set) var generated = Date()
    @Published private(set) var recentLog: [String] = []

    private init() {}

    func refresh() {
        sections = [
            buildAbout(),
            buildMedia(),
            buildScriptErrors(),
            buildPermissions(),
            buildActivity(),
        ]
        recentLog = Self.tailOfLog(lines: 40)
        generated = Date()
    }

    // MARK: - Sections

    private func buildAbout() -> Section {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        #if arch(arm64)
        let architecture = "Apple Silicon"
        #else
        let architecture = "Intel"
        #endif

        return Section(title: "Fun Notch", rows: [
            Row(label: "Version", verdict: .good("\(version) (\(build)) · \(architecture)")),
            Row(label: "macOS", verdict: .good(ProcessInfo.processInfo.operatingSystemVersionString)),
            Row(
                label: "Displays with a notch",
                verdict: NSScreen.screens.contains(where: \.hasPhysicalNotch)
                    ? .good("yes")
                    : .unknown("none — the panel is drawn where the notch would be")
            ),
        ])
    }

    private func buildMedia() -> Section {
        let music = MusicManager.shared
        let settings = Settings.shared
        var rows: [Row] = []

        let chosen = settings.mediaController
        let active = music.activeControllerType
        if let active, active != chosen {
            rows.append(Row(
                label: "Backend",
                verdict: .unknown("set to \(chosen.rawValue), actually reading \(active.rawValue)"),
                remedy: "\(chosen.rawValue) had nothing to report, so Fun Notch fell through to one that did."
            ))
        } else {
            rows.append(Row(label: "Backend", verdict: .good(active?.rawValue ?? chosen.rawValue)))
        }

        let track = music.track
        rows.append(Row(
            label: "Now playing",
            verdict: track.isEmpty
                ? .unknown("nothing")
                : .good("\(track.title)\(track.artist.isEmpty ? "" : " — \(track.artist)")")
        ))

        rows.append(Row(
            label: "Playback position",
            verdict: track.isEmpty
                ? .unknown("nothing playing")
                : (track.hasTiming ? .good("known") : .missing("not reported")),
            remedy: track.isEmpty || track.hasTiming
                ? nil
                : "Needs the browser's \"Allow JavaScript from Apple Events\"; see the Media tab."
        ))

        for browser in BrowserMediaController.scriptableBrowsers {
            guard AppleScriptRunner.isRunning(browser.bundleIdentifier) else { continue }
            let mode = BrowserReadModes.modes[browser.name]
            rows.append(Row(
                label: browser.name,
                verdict: {
                    switch mode {
                    case .some(true): return .good("reading the page — title, artist, artwork, position")
                    case .some(false): return .missing("reading the tab title only")
                    case nil: return .unknown("running, no media tab seen yet")
                    }
                }(),
                remedy: mode == false
                    ? "Turn on page access in the Media tab for artist, artwork and the progress bar."
                    : nil
            ))
        }

        return Section(title: "Media", rows: rows)
    }

    private func buildPermissions() -> Section {
        var rows: [Row] = []

        rows.append(Row(
            label: "Calendars",
            verdict: Self.verdict(
                for: EKEventStore.authorizationStatus(for: .event),
                granted: "the agenda and next-event widget work"
            ),
            remedy: "Privacy & Security → Calendars"
        ))
        rows.append(Row(
            label: "Reminders",
            verdict: Self.verdict(
                for: EKEventStore.authorizationStatus(for: .reminder),
                granted: "reminders appear in the agenda"
            ),
            remedy: "Privacy & Security → Reminders"
        ))

        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        rows.append(Row(
            label: "Camera",
            verdict: {
                switch camera {
                case .authorized: return .good("the mirror works")
                case .notDetermined: return .unknown("not asked yet — only needed for the mirror")
                default: return .missing("denied — the mirror cannot run")
                }
            }(),
            remedy: camera == .denied ? "Privacy & Security → Camera" : nil
        ))

        let location = WeatherManager.shared.authorization
        rows.append(Row(
            label: "Location",
            verdict: {
                switch location {
                case .authorized, .authorizedAlways: return .good("weather and the Wi-Fi name work")
                case .notDetermined: return .unknown("not asked yet")
                default: return .missing("denied — no weather, and no Wi-Fi network name")
                }
            }(),
            remedy: "macOS hides the Wi-Fi network name behind location access too."
        ))

        rows.append(Row(
            label: "Accessibility",
            verdict: AXIsProcessTrusted()
                ? .good("the \"Turn on page access\" button can work")
                : .unknown("not granted — only needed for that one button"),
            remedy: "Privacy & Security → Accessibility"
        ))

        rows.append(Row(
            label: "Automation",
            verdict: BrowserReadModes.modes.isEmpty && MusicManager.shared.track.isEmpty
                ? .unknown("not exercised yet — play something to find out")
                : .good("Fun Notch can talk to the player it is reading"),
            remedy: "Privacy & Security → Automation, if a player is running but never appears here."
        ))

        return Section(title: "Permissions", rows: rows)
    }

    /// The failures the app used to hide. An error here names the exact reason
    /// a player is being read badly, or not at all.
    private func buildScriptErrors() -> Section {
        let failures = ScriptErrors.current
        guard !failures.isEmpty else {
            return Section(title: "Scripting", rows: [
                Row(label: "Last error", verdict: .good("none since launch")),
            ])
        }

        return Section(title: "Scripting", rows: failures.map { failure in
            Row(
                label: failure.application,
                verdict: .missing(failure.message),
                remedy: Self.remedy(for: failure.message)
            )
        })
    }

    private static func remedy(for message: String) -> String? {
        let lowered = message.lowercased()
        if lowered.contains("not allowed") || lowered.contains("-1743") {
            return "Automation access. Privacy & Security → Automation."
        }
        if lowered.contains("-1728") || lowered.contains("can’t get") || lowered.contains("can't get") {
            return "The app answered but not with what was asked for — usually a window or tab that has since closed."
        }
        return nil
    }

    private func buildActivity() -> Section {
        Section(title: "Activity", rows: [
            Row(
                label: "Screen",
                verdict: SystemActivityMonitor.shared.isIdle
                    ? .unknown("locked or asleep — polling has backed off to every 30s")
                    : .good("awake")
            ),
            Row(
                label: "Focus session",
                verdict: FocusManager.shared.isActive
                    ? .good("running — \(FocusManager.shared.compactRemainingText) left, the game is hidden")
                    : .unknown("not running")
            ),
            Row(
                label: "HUD",
                verdict: {
                    guard Settings.shared.hudEnabled else { return .unknown("off") }
                    return HUDManager.shared.isIntercepting
                        ? .good("intercepting the media keys")
                        : .missing(HUDManager.shared.lastError ?? "not intercepting")
                }(),
                remedy: Settings.shared.hudEnabled && !HUDManager.shared.isIntercepting
                    ? "Privacy & Security → Accessibility, then re-enable it in Settings → General."
                    : nil
            ),
            Row(
                label: "Brightness control",
                verdict: DisplayBrightness.isAvailable
                    ? .good("available")
                    : .missing("this Mac does not expose it")
            ),
            Row(
                label: "Keyboard backlight",
                verdict: KeyboardBacklight.isAvailable
                    ? .good("available")
                    : .unknown("not present or not exposed")
            ),
            Row(
                label: "AirDrop",
                verdict: ShelfManager.canAirDrop
                    ? .good("available from the shelf")
                    : .missing("macOS is not offering the AirDrop service")
            ),
            Row(label: "Log file", verdict: .good(DiagnosticLog.fileURL.path)),
        ])
    }

    // MARK: - Helpers

    private static func verdict(for status: EKAuthorizationStatus, granted: String) -> Verdict {
        switch status {
        case .fullAccess, .authorized: return .good(granted)
        case .writeOnly: return .missing("write-only — Fun Notch cannot read your events")
        case .notDetermined: return .unknown("not asked yet")
        default: return .missing("denied")
        }
    }

    private static func tailOfLog(lines: Int) -> [String] {
        // Only the end of the file is read. This is called while building the
        // Diagnostics screen on the main thread, and the log is allowed to grow
        // to a few hundred kilobytes — pulling all of it in to show the last
        // handful of lines was work nobody asked for.
        let text = DiagnosticLog.tail(bytes: 64 * 1024)
        guard !text.isEmpty else { return [] }
        return Array(text.components(separatedBy: "\n").filter { !$0.isEmpty }.suffix(lines))
    }

    /// The whole report as plain text, for pasting into a bug report.
    var plainText: String {
        var out = "Fun Notch diagnostics — \(generated.formatted())\n"
        for section in sections {
            out += "\n## \(section.title)\n"
            for row in section.rows {
                out += "  \(row.label): \(row.verdict.text)\n"
                if let remedy = row.remedy {
                    out += "      → \(remedy)\n"
                }
            }
        }
        if !recentLog.isEmpty {
            out += "\n## Recent log\n"
            out += recentLog.map { "  \($0)" }.joined(separator: "\n")
            out += "\n"
        }
        return out
    }
}
