//
//  SettingsPages.swift
//  FunNotch
//
//  The pages of the settings window. Each is a short run of cards, and each
//  setting says in a few words what it does — the long explanations the old
//  window carried under every switch are gone, and so are the switches for
//  things almost nobody changes.
//

import AVFoundation
import AppKit
import EventKit
import SwiftUI

// MARK: - Previews in the notch

/// Fires the real announcements, so a switch can be seen doing its job.
@MainActor
enum LiveActivityPreview {
    static func show(_ type: SneakContentType, value: CGFloat = 1, icon: String = "", duration: Double = 3.2) {
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showExpandingView(type: type, value: value, icon: icon, duration: duration)
        }
    }

    /// Three presses up, so the bar is seen moving rather than just sitting.
    static func hud(_ kind: HUDManager.Kind = .volume) {
        let steps: [Float] = [0.38, 0.5, 0.62]
        for (index, value) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.28) {
                HUDManager.shared.injectPreview(kind, value: value)
            }
        }
    }

    static func battery() {
        let battery = BatteryManager.shared
        show(.battery, value: CGFloat(battery.level), icon: battery.symbolName)
    }

    static func bluetooth() {
        let monitor = BluetoothMonitor.shared
        if let device = monitor.devices.first(where: \.isConnected) {
            monitor.injectPreviewChange(name: device.name, connected: true, battery: device.battery)
            show(.bluetooth, value: CGFloat(device.battery ?? 0), icon: device.symbol)
        } else {
            monitor.injectPreviewChange(name: "AirPods Pro", connected: true, battery: 0.82)
            show(.bluetooth, value: 0.82, icon: "airpods.pro")
        }
    }

    static func track() {
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showSneakPeek(type: .music)
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = LoginItemManager.isEnabled

    var body: some View {
        SettingsPage(
            title: "General",
            subtitle: "Startup, the menu bar, and when the notch opens.",
            symbol: SettingsTab.general.symbol,
            tint: SettingsTab.general.tint
        ) {
            SettingsCard(title: "Startup") {
                SettingsToggle(title: "Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        settings.launchAtLogin = value
                        LoginItemManager.setEnabled(value)
                    }
                SettingsToggle(title: "Menu bar icon", isOn: $settings.menubarIcon)
                if settings.menubarIcon {
                    SettingsPicker(title: "Icon", selection: $settings.menubarGlyph) {
                        ForEach(MenuBarGlyph.allCases) { glyph in
                            Text(glyph.rawValue).tag(glyph)
                        }
                    }
                    SettingsPicker(title: "Beside the icon", selection: $settings.menubarReadout) {
                        ForEach(MenuBarReadout.allCases) { readout in
                            Text(readout.rawValue).tag(readout)
                        }
                    }
                }
            }

            SettingsCard(title: "Opening") {
                SettingsToggle(
                    title: "Open on hover",
                    subtitle: "Otherwise, click the notch.",
                    isOn: $settings.openNotchOnHover
                )
                if settings.openNotchOnHover {
                    SettingsRow(title: "Hover delay") {
                        Picker("", selection: hoverDelay) {
                            Text("Instant").tag(0.05)
                            Text("Short").tag(0.25)
                            Text("Relaxed").tag(0.6)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsToggle(
                    title: "Larger hover area",
                    subtitle: "Also opens from just below the notch.",
                    isOn: $settings.extendHoverArea
                )
                SettingsToggle(title: "Haptic feedback", isOn: $settings.enableHaptics)
            }

            SettingsCard(title: "Displays") {
                SettingsPicker(title: "Show the notch on", selection: displayChoice) {
                    Text("The display with the pointer").tag(DisplayChoice.pointer)
                    Text("Every display").tag(DisplayChoice.all)
                    Divider()
                    Text("The built-in display").tag(DisplayChoice.fixed(""))
                    if NSScreen.screens.count > 1 {
                        ForEach(NSScreen.screens, id: \.displayIdentifier) { screen in
                            Text(screen.localizedName).tag(DisplayChoice.fixed(screen.displayIdentifier))
                        }
                    }
                }
                SettingsPicker(title: "In fullscreen apps", selection: $settings.hideNotchOption) {
                    Text("Hide the notch").tag(HideNotchOption.always)
                    Text("Hide it while media plays").tag(HideNotchOption.nowPlayingOnly)
                    Text("Keep it").tag(HideNotchOption.never)
                }
            }

            SettingsCard(title: "Privacy") {
                SettingsToggle(
                    title: "Hide from screen recordings",
                    subtitle: "Screenshots and screen shares won't include the notch.",
                    isOn: $settings.hideFromScreenRecording
                )
                SettingsToggle(title: "Show on the lock screen", isOn: $settings.showOnLockScreen)
            }
        }
    }

    /// The three delays offered, with whatever is stored snapped to the nearest.
    private var hoverDelay: Binding<Double> {
        Binding(
            get: {
                let stored = settings.minimumHoverDuration
                return [0.05, 0.25, 0.6].min { abs($0 - stored) < abs($1 - stored) } ?? 0.05
            },
            set: { settings.minimumHoverDuration = $0 }
        )
    }

    private enum DisplayChoice: Hashable {
        case pointer
        case all
        case fixed(String)
    }

    /// Two switches and a display name, as the one question they answer.
    private var displayChoice: Binding<DisplayChoice> {
        Binding(
            get: {
                if settings.showOnAllDisplays { return .all }
                if settings.automaticallySwitchDisplay { return .pointer }
                return .fixed(settings.preferredScreenName)
            },
            set: { choice in
                switch choice {
                case .all:
                    settings.showOnAllDisplays = true
                case .pointer:
                    settings.showOnAllDisplays = false
                    settings.automaticallySwitchDisplay = true
                case let .fixed(name):
                    settings.showOnAllDisplays = false
                    settings.automaticallySwitchDisplay = false
                    settings.preferredScreenName = name
                }
            }
        )
    }
}

// MARK: - Live Activities

struct LiveActivitiesPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        SettingsPage(
            title: "Live Activities",
            subtitle: "What the notch shows as things happen. Press ▶ to see one now.",
            symbol: SettingsTab.activities.symbol,
            tint: SettingsTab.activities.tint
        ) {
            SettingsCard(title: "Volume & brightness") {
                SettingsToggle(
                    title: "Show in the notch",
                    subtitle: "Instead of the system's volume and brightness panels.",
                    symbol: "speaker.wave.2.fill",
                    tint: SettingsStyle.purple,
                    isOn: hudEnabled,
                    preview: { LiveActivityPreview.hud() }
                )
                if settings.hudEnabled {
                    SettingsRow(title: "Covers") {
                        HStack(spacing: 6) {
                            ChipToggle(title: "Volume", symbol: "speaker.wave.2.fill", isOn: $settings.hudShowsVolume)
                            ChipToggle(title: "Brightness", symbol: "sun.max.fill", isOn: $settings.hudShowsBrightness)
                                .disabled(!DisplayBrightness.isAvailable)
                            ChipToggle(title: "Keyboard", symbol: "keyboard.fill", isOn: $settings.hudShowsBacklight)
                                .disabled(!KeyboardBacklight.isAvailable)
                        }
                    }
                    HUDStatusLine()
                }
            }

            SettingsCard(title: "Announcements") {
                SettingsToggle(
                    title: "Track changes",
                    subtitle: "Artwork and title as a new song starts.",
                    symbol: "music.note",
                    tint: SettingsStyle.pink,
                    isOn: $settings.enableSneakPeek,
                    preview: music.track.isEmpty ? nil : { LiveActivityPreview.track() }
                )
                SettingsToggle(
                    title: "Charging",
                    subtitle: "Plugging in and unplugging.",
                    symbol: "bolt.fill",
                    tint: SettingsStyle.green,
                    isOn: $settings.showPowerStatusNotifications,
                    preview: { LiveActivityPreview.battery() }
                )
                SettingsToggle(
                    title: "Bluetooth devices",
                    subtitle: "Headphones and keyboards connecting.",
                    symbol: "airpods",
                    tint: SettingsStyle.blue,
                    isOn: $settings.bluetoothActivity,
                    preview: { LiveActivityPreview.bluetooth() }
                )
                SettingsToggle(
                    title: "Downloads",
                    subtitle: "When a download finishes.",
                    symbol: "arrow.down.circle.fill",
                    tint: SettingsStyle.teal,
                    isOn: $settings.catchDownloads,
                    preview: { LiveActivityPreview.show(.download, icon: "arrow.down.circle.fill") }
                )
                SettingsToggle(
                    title: "Screenshots",
                    subtitle: "New screenshots are put on the shelf.",
                    symbol: "camera.viewfinder",
                    tint: SettingsStyle.gray,
                    isOn: $settings.catchScreenshots,
                    preview: { LiveActivityPreview.show(.screenshot, icon: "camera.viewfinder") }
                )
            }

            SettingsCard {
                SettingsRow(
                    title: "AI agents",
                    subtitle: "Claude Code sessions starting, finishing and asking for you.",
                    symbol: SettingsTab.agents.symbol,
                    tint: SettingsTab.agents.tint
                ) {
                    Button("Agent Settings") { navigation.tab = .agents }
                }
            }
        }
    }

    /// Turning the HUD on asks for Accessibility; turning it off lets go of the keys.
    private var hudEnabled: Binding<Bool> {
        Binding(
            get: { settings.hudEnabled },
            set: { on in
                settings.hudEnabled = on
                if on { HUDManager.shared.requestAccessAndStart() } else { HUDManager.shared.stop() }
            }
        )
    }
}

/// Says plainly whether the HUD is actually intercepting anything.
private struct HUDStatusLine: View {
    @ObservedObject private var hud = HUDManager.shared

    var body: some View {
        if hud.isIntercepting {
            SettingsStatus(
                text: "Working — the system panels won't appear.",
                symbol: "checkmark.circle.fill",
                tint: .green
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(hud.lastError ?? "Needs Accessibility access to catch the keys.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Allow…") { HUDManager.shared.requestAccessAndStart() }
                    .controlSize(.small)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Agents

struct AgentsPage: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        SettingsPage(
            title: "AI Agents",
            subtitle: "Claude Code and Codex sessions, live in the notch.",
            symbol: SettingsTab.agents.symbol,
            tint: SettingsTab.agents.tint
        ) {
            RunningAgentsCard()

            SettingsCard(
                title: "In the notch",
                footer: "Fun Notch reads the list of running sessions Claude Code keeps for itself, in ~/.claude/sessions. Your conversations are never opened."
            ) {
                SettingsToggle(
                    title: "Show working sessions",
                    subtitle: "Claude's spinner beside the camera while a session works.",
                    isOn: $settings.agentActivityEnabled
                )
                SettingsToggle(
                    title: "When a session starts",
                    isOn: $settings.agentAnnounceStart,
                    preview: { AgentSessionsManager.shared.injectPreview(.started) }
                )
                SettingsToggle(
                    title: "When a session finishes",
                    subtitle: "With how long it took.",
                    isOn: $settings.agentAnnounceFinish,
                    preview: { AgentSessionsManager.shared.injectPreview(.finished(194)) }
                )
                SettingsToggle(
                    title: "When a session needs you",
                    subtitle: "Permission prompts and questions.",
                    isOn: $settings.agentAnnounceWaiting,
                    preview: { AgentSessionsManager.shared.injectPreview(.needsInput("permission prompt")) }
                )
            }
        }
    }
}

/// Every session Fun Notch can see right now.
private struct RunningAgentsCard: View {
    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        SettingsCard(title: "Running now") {
            if agents.sessions.isEmpty {
                SettingsStatus(
                    text: agents.hasScanned
                        ? "No sessions running. Start Claude Code and it appears here straight away."
                        : "Looking…",
                    symbol: "sparkles",
                    tint: AgentPalette.claude
                )
            } else {
                ForEach(agents.sessions) { session in
                    SettingsAgentRow(session: session)
                }
            }
        }
    }
}

private struct SettingsAgentRow: View {
    let session: AgentSessionsManager.Session

    var body: some View {
        HStack(spacing: 11) {
            indicator
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(time(now: context.date))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Show") { AgentSessionsManager.shared.bringForward(session) }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .animation(.easeOut(duration: 0.2), value: session.status)
    }

    @ViewBuilder
    private var indicator: some View {
        switch session.status {
        case .working:
            AgentWorkingGlyph(agent: session.agent, size: 14)
        case .waiting:
            AgentWaitingGlyph(size: 14)
        case .idle:
            Image(systemName: session.lastTurnDuration == nil ? "moon.zzz.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(session.lastTurnDuration == nil ? Color.secondary : Color.green)
        }
    }

    private var detail: String {
        let place = "\(session.agent.rawValue) · \(session.project)"
        switch session.status {
        case .working: return "Working — \(place)"
        case let .waiting(reason): return "\(AgentSessionsManager.waitingText(reason)) — \(place)"
        case .idle:
            if let duration = session.lastTurnDuration {
                return "Finished in \(AgentSessionsManager.duration(duration)) — \(place)"
            }
            return "Idle — \(place)"
        }
    }

    private var detailColor: Color {
        switch session.status {
        case .working: return AgentPalette.claude
        case .waiting: return .orange
        case .idle: return .secondary
        }
    }

    private func time(now: Date) -> String {
        if session.status.isActive {
            return AgentSessionsManager.clock(now.timeIntervalSince(session.turnStartedAt ?? session.statusSince))
        }
        let ago = AgentSessionsManager.ago(session.statusSince, now: now)
        return ago == "now" ? "just now" : "\(ago) ago"
    }
}

// MARK: - Media

struct MediaPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        SettingsPage(
            title: "Media",
            subtitle: "Where the notch reads what's playing, and how the player looks.",
            symbol: SettingsTab.media.symbol,
            tint: SettingsTab.media.tint
        ) {
            SettingsCard(title: "Source") {
                SettingsPicker(title: "Read now playing from", selection: $settings.mediaController) {
                    ForEach(MediaControllerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                if music.isNowPlayingDeprecated, settings.mediaController == .nowPlaying {
                    SettingsStatus(
                        text: "macOS no longer shares system-wide Now Playing with other apps, so this falls back to whichever player is running.",
                        symbol: "info.circle.fill",
                        tint: .secondary
                    )
                }
                if let active = music.activeControllerType, active != settings.mediaController {
                    SettingsStatus(
                        text: "Currently reading from \(active.rawValue).",
                        symbol: "arrow.triangle.branch",
                        tint: .secondary
                    )
                }
            }

            if settings.mediaController == .browser {
                SettingsCard(title: "Browser") {
                    BrowserPageAccessHelp()
                        .padding(14)
                }
            }

            SettingsCard(title: "Player") {
                SettingsToggle(title: "Tint the player with the album art", isOn: $settings.playerColorTinting)
                SettingsToggle(title: "Shuffle and repeat buttons", isOn: $settings.showShuffleAndRepeat)
                SettingsToggle(
                    title: "Spectrum beside the notch",
                    subtitle: "Animated bars while something plays.",
                    isOn: $settings.useMusicVisualizer
                )
            }
        }
    }
}

/// Without page access the notch only sees a tab's title, which has no artist,
/// no artwork and no position. The switch that fixes it is buried in a
/// different place in every browser, so spell each one out.
private struct BrowserPageAccessHelp: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var access = BrowserScriptAccess.shared
    @State private var showingSteps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("YouTube, Spotify, SoundCloud and other players in the browser show their title straight away. Artwork, artist and the progress bar need the browser to allow a small script.")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Turn On Page Access") { access.enable() }
                    .disabled(access.outcome == .working)
                Button(showingSteps ? "Hide Steps" : "Do It Myself") { showingSteps.toggle() }
                    .buttonStyle(.link)
            }

            if access.outcome != .idle {
                Label(access.outcome.message, systemImage: access.outcome.isGood
                    ? "checkmark.circle.fill"
                    : "info.circle")
                    .foregroundStyle(access.outcome.isGood ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showingSteps {
                ForEach(Self.steps, id: \.browser) { step in
                    if BrowserMediaController.installedBrowsers.contains(step.browser) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(step.browser)
                                .fontWeight(.semibold)
                                .frame(width: 104, alignment: .leading)
                            Text(step.path)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Toggle("Mention it in the notch when a tab has no progress", isOn: $settings.showPageAccessHint)
                .toggleStyle(.checkbox)
        }
        .font(.system(size: 11.5))
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let steps: [(browser: String, path: String)] = [
        ("Safari", "Settings → Advanced → Show features for web developers, then Develop → Allow JavaScript from Apple Events"),
        ("Google Chrome", "View → Developer → Allow JavaScript from Apple Events"),
        ("Brave Browser", "View → Developer → Allow JavaScript from Apple Events"),
        ("Microsoft Edge", "View → Developer → Allow JavaScript from Apple Events"),
        ("Arc", "View → Developer → Allow JavaScript from Apple Events"),
    ]
}

// MARK: - Shelf & Clipboard

struct ShelfClipboardPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var shelf = ShelfManager.shared
    @ObservedObject private var clipboard = ClipboardManager.shared

    var body: some View {
        SettingsPage(
            title: "Shelf & Clipboard",
            subtitle: "Somewhere to park files, and a memory of what you copy.",
            symbol: SettingsTab.shelf.symbol,
            tint: SettingsTab.shelf.tint
        ) {
            SettingsCard(title: "Shelf") {
                SettingsToggle(
                    title: "Shelf",
                    subtitle: "Drop files on the notch to keep them for later.",
                    isOn: $settings.shelfEnabled
                )
                if settings.shelfEnabled {
                    SettingsToggle(title: "Open the shelf when a drag starts", isOn: $settings.openShelfByDefault)
                    SettingsToggle(title: "Catch drags from anywhere on screen", isOn: $settings.expandedDragDetection)
                    SettingsToggle(
                        title: "Copy instead of moving",
                        subtitle: "Dragging out leaves the original where it was.",
                        isOn: $settings.copyOnDrag
                    )
                    if !settings.copyOnDrag {
                        SettingsToggle(title: "Remove items once dragged out", isOn: $settings.autoRemoveShelfItems)
                    }
                    SettingsPicker(title: "Clear items after", selection: $settings.shelfExpiryHours) {
                        Text("Never").tag(0)
                        Text("1 hour").tag(1)
                        Text("6 hours").tag(6)
                        Text("1 day").tag(24)
                        Text("1 week").tag(168)
                    }
                }
            }

            if settings.shelfEnabled {
                SettingsCard(title: "Catch automatically") {
                    SettingsToggle(title: "New screenshots", isOn: $settings.catchScreenshots)
                    if settings.catchScreenshots {
                        SettingsToggle(title: "Screen recordings too", isOn: $settings.catchScreenRecordings)
                    }
                    SettingsToggle(title: "Finished downloads", isOn: $settings.downloadsToShelf)
                        .disabled(!settings.catchDownloads)
                }

                SettingsCard(
                    title: "Send-to folders",
                    footer: "Each folder becomes a one-click destination in the shelf."
                ) {
                    ForEach(settings.shelfFolderTargets, id: \.self) { path in
                        SettingsRow(title: (path as NSString).lastPathComponent, subtitle: (path as NSString).deletingLastPathComponent) {
                            Button {
                                settings.shelfFolderTargets.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    SettingsRow(title: settings.shelfFolderTargets.isEmpty ? "No folders yet" : "Add another") {
                        Button("Add Folder…", action: pickFolder)
                    }
                }
            }

            SettingsCard(
                title: "Clipboard",
                footer: "Passwords and anything marked private are never recorded. Only text is kept after a restart."
            ) {
                SettingsToggle(title: "Remember what I copy", isOn: $settings.clipboardHistoryEnabled)
                if settings.clipboardHistoryEnabled {
                    SettingsPicker(title: "Keep", selection: $settings.clipboardHistoryLimit) {
                        ForEach([10, 20, 50, 100], id: \.self) { count in
                            Text("\(count) items").tag(count)
                        }
                    }
                    SettingsPicker(title: "Forget after", selection: $settings.clipboardExpiryHours) {
                        Text("1 hour").tag(1)
                        Text("8 hours").tag(8)
                        Text("1 day").tag(24)
                        Text("3 days").tag(72)
                        Text("1 week").tag(168)
                        Text("30 days").tag(720)
                        Text("Never").tag(0)
                    }
                    SettingsRow(title: "\(clipboard.entries.count) saved") {
                        Button("Clear History", role: .destructive) { clipboard.clear() }
                            .disabled(clipboard.entries.isEmpty)
                    }
                }
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var targets = settings.shelfFolderTargets
        for url in panel.urls where !targets.contains(url.path) {
            targets.append(url.path)
        }
        settings.shelfFolderTargets = targets
    }
}

// MARK: - Focus

struct FocusPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var focus = FocusManager.shared
    @State private var editingSites = false
    @State private var editingApps = false

    var body: some View {
        SettingsPage(
            title: "Focus",
            subtitle: "A countdown in the notch, and fewer ways to wander off.",
            symbol: SettingsTab.focus.symbol,
            tint: SettingsTab.focus.tint
        ) {
            SettingsCard(title: "Sessions") {
                SettingsRow(title: "Default length") {
                    Picker("", selection: $settings.focusDefaultMinutes) {
                        ForEach([15, 25, 45, 60, 90], id: \.self) { minutes in
                            Text("\(minutes)m").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsToggle(
                    title: "Pomodoro cycles",
                    subtitle: "Roll into a break, then back to work.",
                    isOn: $settings.focusPomodoro
                )
                if settings.focusPomodoro {
                    SettingsPicker(title: "Break length", selection: $settings.focusBreakMinutes) {
                        ForEach([3, 5, 10, 15], id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                }
                SettingsToggle(title: "Pause music when a session starts", isOn: $settings.focusPauseMusic)
                SettingsToggle(title: "Countdown beside the notch", isOn: $settings.focusShowInClosedNotch)
                if focus.isActive {
                    SettingsRow(title: "Running now", subtitle: "\(focus.remainingText) left") {
                        Button("Stop") { focus.stop() }
                    }
                }
            }

            SettingsCard(title: "Distractions") {
                SettingsToggle(
                    title: "Block distracting websites",
                    subtitle: browserNote,
                    isOn: $settings.focusBlockWebsites
                )
                SettingsRow(
                    title: "Blocked sites",
                    subtitle: settings.focusBlocklist.isEmpty ? "None" : settings.focusBlocklist.prefix(3).joined(separator: ", ") + (settings.focusBlocklist.count > 3 ? " and \(settings.focusBlocklist.count - 3) more" : "")
                ) {
                    Button("Edit…") { editingSites = true }
                }
                SettingsRow(
                    title: "Apps to hide",
                    subtitle: settings.focusBlockedApps.isEmpty ? "None" : "\(settings.focusBlockedApps.count) app\(settings.focusBlockedApps.count == 1 ? "" : "s")"
                ) {
                    Button("Edit…") { editingApps = true }
                }
            }

            SettingsCard(
                title: "Shortcuts",
                footer: "Names must match a shortcut in the Shortcuts app — the practical way to switch on a Focus mode."
            ) {
                SettingsRow(title: "Run at the start") {
                    TextField("", text: $settings.focusStartShortcut, prompt: Text("Shortcut name"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
                SettingsRow(title: "Run at the end") {
                    TextField("", text: $settings.focusEndShortcut, prompt: Text("Shortcut name"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
            }

            SettingsCard(title: "So far") {
                SettingsRow(
                    title: "\(settings.focusSessionsCompleted) session\(settings.focusSessionsCompleted == 1 ? "" : "s")",
                    subtitle: "\(focusedTime) focused"
                ) {
                    Button("Reset") {
                        settings.focusSessionsCompleted = 0
                        settings.focusMinutesTotal = 0
                    }
                }
            }
        }
        .sheet(isPresented: $editingSites) { BlocklistEditor() }
        .sheet(isPresented: $editingApps) { BlockedAppsEditor() }
    }

    private var browserNote: String {
        let browsers = FocusManager.supportedInstalledBrowsers
        return browsers.isEmpty
            ? "Needs Safari, Chrome, Brave, Edge or Arc."
            : "In \(browsers.joined(separator: ", "))."
    }

    private var focusedTime: String {
        let minutes = settings.focusMinutesTotal
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

private struct BlocklistEditor: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var newSite = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Blocked sites")
                .font(.title3.weight(.semibold))
            HStack {
                TextField("example.com", text: $newSite)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(cleaned.isEmpty)
            }
            List {
                ForEach(settings.focusBlocklist, id: \.self) { site in
                    HStack {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                        Text(site)
                        Spacer()
                        Button {
                            settings.focusBlocklist.removeAll { $0 == site }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Button("Restore Defaults") { settings.focusBlocklist = Settings.defaultBlocklist }
                Button("Remove All") { settings.focusBlocklist = [] }
                    .disabled(settings.focusBlocklist.isEmpty)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 420)
    }

    private var cleaned: String {
        newSite
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/")
            .first ?? ""
    }

    private func add() {
        let site = cleaned
        guard !site.isEmpty, !settings.focusBlocklist.contains(site) else { return }
        settings.focusBlocklist.append(site)
        newSite = ""
    }
}

private struct BlockedAppsEditor: View {
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apps to hide")
                .font(.title3.weight(.semibold))
            Text("Hidden while a session runs, and back when it ends.")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(settings.focusBlockedApps, id: \.self) { identifier in
                    HStack(spacing: 8) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(url.deletingPathExtension().lastPathComponent)
                        } else {
                            Image(systemName: "questionmark.app")
                            Text(identifier)
                        }
                        Spacer()
                        Button {
                            settings.focusBlockedApps.removeAll { $0 == identifier }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(minHeight: 200)
            HStack {
                Button("Add App…", action: pick)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420, height: 400)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var blocked = settings.focusBlockedApps
        for url in panel.urls {
            guard let identifier = Bundle(url: url)?.bundleIdentifier else { continue }
            if !blocked.contains(identifier) { blocked.append(identifier) }
        }
        settings.focusBlockedApps = blocked
    }
}

// MARK: - Calendar

struct CalendarPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        SettingsPage(
            title: "Calendar",
            subtitle: "What the agenda on the home screen shows.",
            symbol: SettingsTab.calendar.symbol,
            tint: SettingsTab.calendar.tint
        ) {
            SettingsCard(title: "Agenda") {
                SettingsToggle(title: "Hide all-day events", isOn: $settings.hideAllDayEvents)
                SettingsToggle(title: "Show full event titles", isOn: $settings.showFullEventTitles)
                SettingsToggle(title: "Include reminders", isOn: $settings.showReminders)
                if settings.showReminders {
                    SettingsToggle(title: "Hide completed reminders", isOn: $settings.hideCompletedReminders)
                }
                SettingsToggle(
                    title: "Fill an empty day with examples",
                    subtitle: "Marked Sample, and never counted as your next event.",
                    isOn: $settings.showSampleAgenda
                )
            }

            SettingsCard(
                title: "Calendars",
                footer: manager.hasEventAccess ? "Leave them all off to include every calendar." : nil
            ) {
                if !manager.hasEventAccess {
                    SettingsRow(title: "Calendar access", subtitle: "Needed to show your events.") {
                        Button("Allow…") { manager.requestAccess() }
                    }
                } else if manager.calendars.isEmpty {
                    SettingsStatus(text: "No calendars found.", symbol: "calendar", tint: .secondary)
                } else {
                    ForEach(manager.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarToggleRow(calendar: calendar)
                    }
                }
            }
        }
    }
}

private struct CalendarToggleRow: View {
    let calendar: EKCalendar

    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .systemBlue))
                .frame(width: 10, height: 10)
            Text(calendar.title)
                .font(.system(size: 13))
            Spacer()
            Toggle("", isOn: binding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { settings.selectedCalendarIdentifiers.contains(calendar.calendarIdentifier) },
            set: { isOn in
                var identifiers = settings.selectedCalendarIdentifiers
                if isOn {
                    identifiers.append(calendar.calendarIdentifier)
                } else {
                    identifiers.removeAll { $0 == calendar.calendarIdentifier }
                }
                settings.selectedCalendarIdentifiers = identifiers
            }
        )
    }
}

// MARK: - About

struct AboutPage: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updates = UpdateManager.shared
    @State private var autoUpdate = UpdateManager.shared.automaticallyChecks
    @State private var confirmingReset = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                AppMark(size: 76)
                Text("Fun Notch")
                    .font(.system(size: 24, weight: .bold))
                Text("Version \(version)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Your notch, but useful — and a bit of fun.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link("funnotch.xyz", destination: URL(string: "https://funnotch.xyz")!)
                    Link("GitHub", destination: URL(string: "https://github.com/JoshuaT1105/FunNotch")!)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            SettingsCard(title: "Updates") {
                SettingsToggle(title: "Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, value in updates.automaticallyChecks = value }
                SettingsRow(
                    title: "Check now",
                    subtitle: updates.lastCheckedAt.map {
                        "Last checked \($0.formatted(date: .abbreviated, time: .shortened))"
                    } ?? "Not checked yet"
                ) {
                    Button("Check for Updates") { updates.checkForUpdates() }
                        .disabled(!updates.canCheckForUpdates)
                }
            }

            HealthCheckCard()

            SettingsCard(title: "Troubleshooting") {
                SettingsRow(title: "Restart Fun Notch") {
                    Button("Restart") { LoginItemManager.relaunch() }
                }
                SettingsRow(title: "Reset all settings", subtitle: "Every preference goes back to how it shipped.") {
                    Button("Reset…") { confirmingReset = true }
                }
                SettingsRow(title: "Quit Fun Notch") {
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .confirmationDialog("Reset every setting?", isPresented: $confirmingReset) {
            Button("Reset All Settings", role: .destructive) { settings.resetAll() }
        } message: {
            Text("Your shelf, clipboard history and notes are kept.")
        }
    }
}

/// Everything here depends on a permission or on a switch inside another app,
/// and when one is missing the feature quietly does less — which from the
/// outside looks exactly like a bug. This says which it is.
private struct HealthCheckCard: View {
    @ObservedObject private var report = DiagnosticsReport.shared
    @State private var showingReport = false

    private var problems: [DiagnosticsReport.Row] {
        report.sections.flatMap(\.rows).filter {
            if case .missing = $0.verdict { return true }
            return false
        }
    }

    var body: some View {
        SettingsCard(title: "Health check") {
            if problems.isEmpty {
                SettingsStatus(
                    text: "Everything Fun Notch needs is working.",
                    symbol: "checkmark.seal.fill",
                    tint: .green
                )
            } else {
                ForEach(problems.prefix(4)) { row in
                    SettingsRow(title: row.label, subtitle: row.remedy ?? row.verdict.text) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            SettingsRow(title: "Full report", subtitle: "Permissions, media sources and the recent log.") {
                Button("Open…") { showingReport = true }
            }
        }
        .onAppear { report.refresh() }
        .sheet(isPresented: $showingReport) {
            DiagnosticsReportView()
        }
    }
}

/// The full diagnostics report, with the log and a copyable summary.
private struct DiagnosticsReportView: View {
    @ObservedObject private var report = DiagnosticsReport.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingLog = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(report.sections) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.title)
                                .font(.headline)
                            ForEach(section.rows) { row in
                                DiagnosticsRow(row: row)
                            }
                        }
                    }

                    if !report.recentLog.isEmpty {
                        DisclosureGroup("Recent log", isExpanded: $showingLog) {
                            Text(report.recentLog.joined(separator: "\n"))
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .font(.headline)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("Checked \(report.generated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reveal Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
                }
                Button(copied ? "Copied" : "Copy Report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.plainText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button("Re-check") { report.refresh() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 540)
        .onAppear { report.refresh() }
    }
}

private struct DiagnosticsRow: View {
    let row: DiagnosticsReport.Row

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: row.verdict.symbol)
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(row.label)
                .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.verdict.text)
                    .textSelection(.enabled)
                if let remedy = row.remedy {
                    Text(remedy)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var tint: Color {
        switch row.verdict {
        case .good: return .green
        case .missing: return .orange
        case .unknown: return .secondary
        }
    }
}
