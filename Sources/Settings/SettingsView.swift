//
//  SettingsView.swift
//  FunNotch
//
//  Every preference, grouped the same way the notch's features are.
//

import AVFoundation
import AppKit
import EventKit
import SwiftUI

/// Which pane the settings window is showing, so other parts of the app can
/// send the user straight to the relevant one.
enum SettingsTab: Hashable {
    case general, appearance, themes, media, shelf, clipboard, focus, devices, calendar
    case diagnostics, about
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
    private init() {}
}

struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsTab.appearance)
            ThemeSettings()
                .tabItem { Label("Themes", systemImage: "swatchpalette") }
                .tag(SettingsTab.themes)
            MediaSettings()
                .tabItem { Label("Media", systemImage: "music.note") }
                .tag(SettingsTab.media)
            ShelfSettings()
                .tabItem { Label("Shelf", systemImage: "tray.full") }
                .tag(SettingsTab.shelf)
            ClipboardSettings()
                .tabItem { Label("Clipboard", systemImage: "doc.on.clipboard") }
                .tag(SettingsTab.clipboard)
            FocusSettings()
                .tabItem { Label("Focus", systemImage: "cup.and.saucer") }
                .tag(SettingsTab.focus)
            DeviceSettings()
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.right") }
                .tag(SettingsTab.devices)
            CalendarSettings()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(SettingsTab.calendar)
            DiagnosticsSettings()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 640, height: 500)
        .padding(.top, 8)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject private var settings = Settings.shared
    @State private var launchAtLogin = LoginItemManager.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        settings.launchAtLogin = newValue
                        LoginItemManager.setEnabled(newValue)
                    }
                Toggle("Show menu bar icon", isOn: $settings.menubarIcon)

                Picker("Icon", selection: $settings.menubarGlyph) {
                    ForEach(MenuBarGlyph.allCases) { glyph in
                        Text(glyph.rawValue).tag(glyph)
                    }
                }
                .disabled(!settings.menubarIcon)

                Picker("Show beside it", selection: $settings.menubarReadout) {
                    ForEach(MenuBarReadout.allCases) { readout in
                        Text(readout.rawValue).tag(readout)
                    }
                }
                .disabled(!settings.menubarIcon)

                if settings.menubarReadout == .nowPlaying || settings.menubarReadout == .nextEvent {
                    LabeledContent("Trim long titles to") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(settings.menubarReadoutLength) },
                                    set: { settings.menubarReadoutLength = Int($0) }
                                ),
                                in: 8 ... 60,
                                step: 1
                            )
                            Text("\(settings.menubarReadoutLength)")
                                .monospacedDigit()
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                    .disabled(!settings.menubarIcon)
                }

                Text("The readout only refreshes while something is set, so an unused menu bar item costs nothing. Pick \"No icon\" with a readout for text on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Displays") {
                Toggle("Show on all displays", isOn: $settings.showOnAllDisplays)
                Toggle("Follow the pointer between displays", isOn: $settings.automaticallySwitchDisplay)
                    .disabled(settings.showOnAllDisplays)

                if !settings.showOnAllDisplays, !settings.automaticallySwitchDisplay {
                    Picker("Display", selection: $settings.preferredScreenName) {
                        Text("Automatic").tag("")
                        ForEach(NSScreen.screens, id: \.displayIdentifier) { screen in
                            Text(screen.localizedName).tag(screen.displayIdentifier)
                        }
                    }
                }
            }

            Section("Opening") {
                Toggle("Open on hover", isOn: $settings.openNotchOnHover)
                if settings.openNotchOnHover {
                    LabeledContent("Hover delay") {
                        HStack {
                            Slider(value: $settings.minimumHoverDuration, in: 0 ... 1, step: 0.05)
                            Text(String(format: "%.2fs", settings.minimumHoverDuration))
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                Toggle("Extend the hover area below the notch", isOn: $settings.extendHoverArea)
                Toggle("Haptic feedback", isOn: $settings.enableHaptics)
            }

            Section("Gestures") {
                Toggle("Swipe down on the notch to open", isOn: $settings.enableGestures)
                Toggle("Swipe up to close", isOn: $settings.closeGestureEnabled)
                    .disabled(!settings.enableGestures)
                LabeledContent("Sensitivity") {
                    Slider(value: $settings.gestureSensitivity, in: 50 ... 400, step: 10)
                        .disabled(!settings.enableGestures)
                }
            }

            Section("HUD") {
                Toggle("Show volume, brightness and backlight in the notch", isOn: $settings.hudEnabled)
                    .onChange(of: settings.hudEnabled) { _, on in
                        if on { HUDManager.shared.requestAccessAndStart() } else { HUDManager.shared.stop() }
                    }

                Toggle("Volume", isOn: $settings.hudShowsVolume).disabled(!settings.hudEnabled)
                Toggle("Brightness", isOn: $settings.hudShowsBrightness)
                    .disabled(!settings.hudEnabled || !DisplayBrightness.isAvailable)
                Toggle("Keyboard backlight", isOn: $settings.hudShowsBacklight)
                    .disabled(!settings.hudEnabled || !KeyboardBacklight.isAvailable)

                HUDStatusRow()

                Text("The only way to replace the system panels is to catch the key before macOS does, apply the change here, and swallow it — which is why this needs Accessibility. Categories left off are passed straight through and keep their normal HUD.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Toggle("Hide from screen recordings", isOn: $settings.hideFromScreenRecording)
                Toggle("Show on the lock screen", isOn: $settings.showOnLockScreen)
            }
        }
        .formStyle(.grouped)
    }
}

/// Says plainly whether the HUD is actually intercepting anything.
private struct HUDStatusRow: View {
    @ObservedObject private var hud = HUDManager.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        if settings.hudEnabled {
            if hud.isIntercepting {
                Label("Intercepting the media keys — the system HUD will not appear.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(hud.lastError ?? "Not intercepting yet.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Grant Accessibility and retry") {
                        HUDManager.shared.requestAccessAndStart()
                    }
                    .controlSize(.small)
                }
            }

            if !DisplayBrightness.isAvailable || !KeyboardBacklight.isAvailable {
                Text(unavailableNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var unavailableNote: String {
        var missing: [String] = []
        if !DisplayBrightness.isAvailable { missing.append("display brightness") }
        if !KeyboardBacklight.isAvailable { missing.append("keyboard backlight") }
        return "This Mac does not expose \(missing.joined(separator: " or ")) to apps, so those keys keep the system HUD."
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Form {
            Section("Notch size") {
                Picker("Height on notched displays", selection: $settings.notchHeightMode) {
                    ForEach(WindowHeightMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                if settings.notchHeightMode == .custom {
                    LabeledContent("Custom height") {
                        HStack {
                            Slider(value: $settings.notchHeight, in: 20 ... 60, step: 1)
                            Text("\(Int(settings.notchHeight))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }

                Picker("Height on other displays", selection: $settings.nonNotchHeightMode) {
                    ForEach(WindowHeightMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                if settings.nonNotchHeightMode == .custom {
                    LabeledContent("Custom height") {
                        HStack {
                            Slider(value: $settings.nonNotchHeight, in: 20 ... 60, step: 1)
                            Text("\(Int(settings.nonNotchHeight))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }

                LabeledContent("Width fine-tuning") {
                    HStack {
                        Slider(value: $settings.notchWidthPadding, in: -10 ... 20, step: 1)
                        Text("\(Int(settings.notchWidthPadding))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
            }

            Section("Beside the notch") {
                Toggle("Show information while the notch is idle", isOn: $settings.idleWidgetsEnabled)
                WidgetListEditor(
                    title: "Left of the camera",
                    widgets: Binding(
                        get: { settings.idleLeftWidgets },
                        set: { settings.idleLeftWidgets = $0 }
                    )
                )
                .disabled(!settings.idleWidgetsEnabled)
                WidgetListEditor(
                    title: "Right of the camera",
                    widgets: Binding(
                        get: { settings.idleRightWidgets },
                        set: { settings.idleRightWidgets = $0 }
                    )
                )
                .disabled(!settings.idleWidgetsEnabled)

                Picker("While media is playing", selection: $settings.closedMediaDisplay) {
                    ForEach(ClosedMediaDisplay.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .disabled(!settings.idleWidgetsEnabled)

                Text("Widgets step aside for a drag or a focus countdown. For media you decide: the artwork and spectrum can keep the row to themselves, share it with the widgets on the outside, or hand it over entirely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Clicking a widget opens the thing it is about.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Style") {
                Toggle("Drop shadow under the open notch", isOn: $settings.enableShadow)
                Toggle("Scale corner radius when open", isOn: $settings.cornerRadiusScaling)
                Toggle("Show tab labels", isOn: $settings.tileShowLabels)
                Toggle("Settings button in the notch", isOn: $settings.settingsIconInNotch)
                Toggle("Show the game tab", isOn: $settings.showGame)
            }

            Section("Accent colour") {
                Toggle("Use a custom accent colour", isOn: $settings.useCustomAccentColor)

                AccentSwatches()

                if settings.useCustomAccentColor {
                    ColorPicker("Exact colour", selection: $settings.customAccentColor)
                }

                Text("The accent tints shuffle and repeat, the focus ring, the drop zone, and anything set to \"Accent colour\" below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Border") {
                Toggle("Outline the notch", isOn: $settings.notchBorderEnabled)

                LabeledContent("Thickness") {
                    HStack {
                        Slider(value: $settings.notchBorderWidth, in: 0.5 ... 3, step: 0.5)
                        Text(String(format: "%.1f pt", settings.notchBorderWidth))
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!settings.notchBorderEnabled)

                LabeledContent("Strength") {
                    HStack {
                        Slider(value: $settings.notchBorderOpacity, in: 0.05 ... 1)
                        Text("\(Int(settings.notchBorderOpacity * 100))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(!settings.notchBorderEnabled)

                Picker("Colour", selection: $settings.notchBorderColorSource) {
                    ForEach(BorderColorSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .disabled(!settings.notchBorderEnabled)

                Toggle("Also outline the collapsed notch", isOn: $settings.notchBorderWhenClosed)
                    .disabled(!settings.notchBorderEnabled)

                Text("A hairline traced along the notch's own outline, on the inside. Unlike the shadow it never paints outside the panel, so it defines the edge without marking whatever is behind it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notch colour") {
                LabeledContent("Tint strength") {
                    HStack {
                        Slider(value: $settings.notchTintIntensity, in: 0 ... 1)
                        Text("\(Int(settings.notchTintIntensity * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                ColorPicker("Tint colour", selection: $settings.notchTintColor)
                    .disabled(settings.notchTintIntensity == 0)

                TintPresets()
                    .disabled(settings.notchTintIntensity == 0)
            }

            Section("Element colours") {
                Picker("Progress bar", selection: $settings.sliderColor) {
                    ForEach(SliderColorEnum.allCases) { colour in
                        Text(colour.rawValue).tag(colour)
                    }
                }
                Picker("Spectrum bars", selection: $settings.spectrumColor) {
                    ForEach(SliderColorEnum.allCases) { colour in
                        Text(colour.rawValue).tag(colour)
                    }
                }
                .disabled(!settings.coloredSpectrogram)
                Toggle("Colour the spectrum bars", isOn: $settings.coloredSpectrogram)
            }

            Section("Mirror") {
                Toggle("Show the camera mirror", isOn: $settings.showMirror)
                Picker("Mirror shape", selection: $settings.mirrorShape) {
                    ForEach(MirrorShapeEnum.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .disabled(!settings.showMirror)

                if settings.showMirror, AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                    Button("Grant camera access") {
                        WebcamManager.shared.requestAccessIfNeeded { _ in }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One-click accent colours. Picking "System" turns the override back off.
private struct AccentSwatches: View {
    @ObservedObject private var settings = Settings.shared

    private let columns = [GridItem(.adaptive(minimum: 30), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AccentPreset.allCases) { preset in
                Swatch(
                    color: preset.color,
                    label: preset.rawValue,
                    isSelected: isSelected(preset)
                ) {
                    if preset == .system {
                        settings.useCustomAccentColor = false
                    } else {
                        settings.customAccentColor = preset.color
                        settings.useCustomAccentColor = true
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func isSelected(_ preset: AccentPreset) -> Bool {
        if preset == .system { return !settings.useCustomAccentColor }
        guard settings.useCustomAccentColor else { return false }
        return NSColor(settings.customAccentColor).isApproximately(NSColor(preset.color))
    }
}

/// Quick tints for the notch background.
private struct TintPresets: View {
    @ObservedObject private var settings = Settings.shared

    private let columns = [GridItem(.adaptive(minimum: 30), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AccentPreset.allCases.filter { $0 != .system }) { preset in
                Swatch(
                    color: preset.color,
                    label: preset.rawValue,
                    isSelected: NSColor(settings.notchTintColor).isApproximately(NSColor(preset.color))
                ) {
                    settings.notchTintColor = preset.color
                    if settings.notchTintIntensity == 0 {
                        settings.notchTintIntensity = 0.25
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct Swatch: View {
    let color: Color
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.5)
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                        .padding(-3)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Add, remove and reorder the widgets on one side of the cutout.
private struct WidgetListEditor: View {
    let title: String
    @Binding var widgets: [NotchWidget]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Menu {
                    ForEach(available) { widget in
                        Button {
                            widgets.append(widget)
                        } label: {
                            Label(widget.rawValue, systemImage: widget.symbol)
                        }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(available.isEmpty)
            }

            if widgets.isEmpty {
                Text("Nothing on this side")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(widgets.enumerated()), id: \.offset) { index, widget in
                    HStack(spacing: 6) {
                        Image(systemName: widget.symbol)
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(widget.rawValue)
                        Spacer()
                        Button {
                            widgets.swapAt(index, index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == 0)
                        Button {
                            widgets.swapAt(index, index + 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.plain)
                        .disabled(index == widgets.count - 1)
                        Button {
                            widgets.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Offering the same widget twice on one side is never what you want.
    private var available: [NotchWidget] {
        NotchWidget.allCases.filter { !widgets.contains($0) }
    }
}

// MARK: - Themes

private struct ThemeSettings: View {
    @ObservedObject private var settings = Settings.shared
    @State private var newName = ""

    private var allThemes: [NotchTheme] {
        NotchTheme.builtIns + settings.savedThemes
    }

    var body: some View {
        Form {
            Section("Themes") {
                ForEach(allThemes) { theme in
                    HStack(spacing: 10) {
                        ThemeSwatches(theme: theme)
                        Text(theme.name)
                        if settings.activeThemeName == theme.name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Apply") { settings.apply(theme: theme) }
                        if settings.savedThemes.contains(where: { $0.name == theme.name }) {
                            Button {
                                settings.savedThemes.removeAll { $0.name == theme.name }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Save the current look") {
                HStack {
                    TextField("Theme name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
                Text("Captures the accent colour, notch tint and strength, glow, and the progress and spectrum colours from the Appearance tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var trimmedName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let name = trimmedName
        guard !name.isEmpty else { return }
        var themes = settings.savedThemes
        themes.removeAll { $0.name == name }
        themes.append(settings.currentTheme(named: name))
        settings.savedThemes = themes
        settings.activeThemeName = name
        newName = ""
    }
}

private struct ThemeSwatches: View {
    let theme: NotchTheme

    var body: some View {
        HStack(spacing: -4) {
            Circle().fill(theme.accentColor).frame(width: 14, height: 14)
            Circle().fill(theme.tintColor).frame(width: 14, height: 14)
        }
        .overlay(
            Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Reads YouTube, YouTube Music, Spotify's web player, SoundCloud, Apple Music, Bandcamp, Twitch and Vimeo. The tab title is always readable; artist, artwork and the progress bar need the browser to run a small script for Fun Notch.")

            HStack(spacing: 10) {
                Button("Turn on page access") {
                    access.enable()
                }
                .disabled(access.outcome == .working)

                Button(showingSteps ? "Hide the manual steps" : "Do it myself") {
                    showingSteps.toggle()
                }
                .buttonStyle(.link)
            }

            if access.outcome != .idle {
                Label(access.outcome.message, systemImage: access.outcome.isGood
                    ? "checkmark.circle.fill"
                    : "info.circle")
                    .foregroundStyle(access.outcome.isGood ? Color.green : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Pressing the button drives the browser's own menu bar through the
            // accessibility API, so macOS asks for Accessibility the first time.
            Text("The button flips the browser's menu item for you, which is why macOS asks to let Fun Notch control other apps. Nothing else uses that permission.")
                .foregroundStyle(.tertiary)

            if showingSteps {
                ForEach(BrowserPageAccessHelp.steps, id: \.browser) { step in
                    if BrowserMediaController.installedBrowsers.contains(step.browser) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(step.browser)
                                .fontWeight(.semibold)
                                .frame(width: 100, alignment: .leading)
                            Text(step.path)
                        }
                    }
                }
            }

            Toggle("Mention this in the notch when a tab has no progress", isOn: $settings.showPageAccessHint)
                .font(.caption)

            Text("YouTube thumbnails are fetched straight from youtube.com, so those show up either way.")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let steps: [(browser: String, path: String)] = [
        (
            "Safari",
            "Settings → Advanced → Show features for web developers, then Develop → Allow JavaScript from Apple Events"
        ),
        ("Google Chrome", "View → Developer → Allow JavaScript from Apple Events"),
        ("Brave Browser", "View → Developer → Allow JavaScript from Apple Events"),
        ("Microsoft Edge", "View → Developer → Allow JavaScript from Apple Events"),
        ("Arc", "View → Developer → Allow JavaScript from Apple Events"),
    ]
}

// MARK: - Diagnostics

/// Everything here depends on a permission or on a switch inside another app.
/// When one is missing the feature quietly does less, which from the outside
/// looks exactly like a bug. This is the page that tells them apart.
private struct DiagnosticsSettings: View {
    @ObservedObject private var report = DiagnosticsReport.shared
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
                Button("Reveal log") {
                    NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
                }
                Button(copied ? "Copied" : "Copy report") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.plainText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                Button("Re-check") { report.refresh() }
                    .keyboardShortcut("r")
            }
            .padding(12)
        }
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

// MARK: - Media

private struct MediaSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        Form {
            Section("Source") {
                Picker("Read now playing from", selection: $settings.mediaController) {
                    ForEach(MediaControllerType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if music.isNowPlayingDeprecated {
                    Label(
                        "macOS 15.4 and later no longer let third-party apps read system-wide Now Playing, so \"Now Playing\" falls back to whichever player is running.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if settings.mediaController == .browser {
                    BrowserPageAccessHelp()
                }

                if let active = music.activeControllerType, active != settings.mediaController {
                    Text("Currently reading from \(active.rawValue).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Player") {
                Toggle("Coloured spectrum bars", isOn: $settings.coloredSpectrogram)
                Toggle("Animated spectrum in the closed notch", isOn: $settings.useMusicVisualizer)
                Toggle("Tint the player with the album art", isOn: $settings.playerColorTinting)
                Toggle("Show shuffle and repeat", isOn: $settings.showShuffleAndRepeat)
                Picker("Progress bar colour", selection: $settings.sliderColor) {
                    ForEach(SliderColorEnum.allCases) { colour in
                        Text(colour.rawValue).tag(colour)
                    }
                }
            }

            Section("Sneak peek") {
                Toggle("Announce track changes", isOn: $settings.enableSneakPeek)
                Picker("Style", selection: $settings.sneakPeekStyle) {
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .disabled(!settings.enableSneakPeek)
                LabeledContent("Show for") {
                    HStack {
                        Slider(value: $settings.waitInterval, in: 1 ... 10, step: 0.5)
                        Text(String(format: "%.1fs", settings.waitInterval))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .disabled(!settings.enableSneakPeek)
            }

            Section("Fullscreen") {
                Picker("Hide the notch in fullscreen", selection: $settings.hideNotchOption) {
                    ForEach(HideNotchOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            Section("Battery") {
                Toggle("Show the battery indicator", isOn: $settings.showBatteryIndicator)
                Toggle("Show the percentage", isOn: $settings.showBatteryPercentage)
                Toggle("Show charging icons", isOn: $settings.showPowerStatusIcons)
                Toggle("Announce plugging in and unplugging", isOn: $settings.showPowerStatusNotifications)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shelf

private struct ShelfSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var shelf = ShelfManager.shared

    var body: some View {
        Form {
            Section("Shelf") {
                Toggle("Enable the shelf", isOn: $settings.shelfEnabled)
                Toggle("Open the shelf when a drag starts", isOn: $settings.openShelfByDefault)
                Toggle("Reopen on the last tab I used", isOn: $settings.rememberLastTab)
                    .disabled(!settings.shelfEnabled)
                Toggle("Detect drags anywhere on screen", isOn: $settings.expandedDragDetection)
                    .disabled(!settings.shelfEnabled)
            }

            Section("Dragging out") {
                Toggle("Copy instead of moving", isOn: $settings.copyOnDrag)
                Toggle("Remove items once dragged out", isOn: $settings.autoRemoveShelfItems)
                    .disabled(settings.copyOnDrag)
            }

            Section("Screenshots") {
                Toggle("Catch new screenshots automatically", isOn: $settings.catchScreenshots)
                Toggle("Catch screen recordings too", isOn: $settings.catchScreenRecordings)
                    .disabled(!settings.catchScreenshots)
                LabeledContent("Watching") {
                    Text(ScreenshotWatcher.screenshotDirectory().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Text("New screenshots land on the shelf on their own, so there is nothing to drag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Housekeeping") {
                Picker("Remove items after", selection: $settings.shelfExpiryHours) {
                    Text("Never").tag(0)
                    Text("1 hour").tag(1)
                    Text("6 hours").tag(6)
                    Text("1 day").tag(24)
                    Text("1 week").tag(168)
                }
            }

            Section("Send-to folders") {
                Text("Folders listed here appear in the shelf so an item can be filed with one click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(settings.shelfFolderTargets, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                        Text((path as NSString).lastPathComponent)
                        Spacer()
                        Button {
                            settings.shelfFolderTargets.removeAll { $0 == path }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Add a folder…", action: pickFolder)
            }

            Section("Downloads") {
                Toggle("Announce finished downloads", isOn: $settings.catchDownloads)
                Toggle("Put finished downloads on the shelf", isOn: $settings.downloadsToShelf)
                    .disabled(!settings.catchDownloads)
            }

            Section("Contents") {
                LabeledContent("Items on the shelf") {
                    Text("\(shelf.items.count)")
                }
                Button("Clear the shelf", role: .destructive) {
                    shelf.clear()
                }
                .disabled(shelf.items.isEmpty)
            }
        }
        .formStyle(.grouped)
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

// MARK: - Clipboard

private struct ClipboardSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var clipboard = ClipboardManager.shared

    var body: some View {
        Form {
            Section("History") {
                Toggle("Remember what I copy", isOn: $settings.clipboardHistoryEnabled)
                Picker("Keep", selection: $settings.clipboardHistoryLimit) {
                    ForEach([10, 20, 50, 100], id: \.self) { count in
                        Text("\(count) items").tag(count)
                    }
                }
                .disabled(!settings.clipboardHistoryEnabled)

                Picker("Forget after", selection: $settings.clipboardExpiryHours) {
                    Text("1 hour").tag(1)
                    Text("8 hours").tag(8)
                    Text("24 hours").tag(24)
                    Text("3 days").tag(72)
                    Text("7 days").tag(168)
                    Text("30 days").tag(720)
                    Text("Never").tag(0)
                }
                .disabled(!settings.clipboardHistoryEnabled)

                Text(settings.clipboardExpiryHours == 0
                     ? "Entries are kept until they fall off the end of the list. Pinned entries are always kept."
                     : "Entries older than this are deleted automatically. Pinned entries are never deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Stored now") {
                    Text("\(clipboard.entries.count)")
                }
                Button("Clear history", role: .destructive) { clipboard.clear() }
                    .disabled(clipboard.entries.isEmpty)
            }

            Section("Privacy") {
                Text("Entries marked concealed, transient or auto-generated are skipped, so passwords copied from a password manager are never recorded. Only text survives a restart — copied images and files are kept for the current session only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Devices

private struct DeviceSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var bluetooth = BluetoothMonitor.shared

    var body: some View {
        Form {
            Section("Bluetooth") {
                Toggle("Announce devices connecting and disconnecting", isOn: $settings.bluetoothActivity)
            }

            Section("Paired devices") {
                if bluetooth.devices.isEmpty {
                    Text("No paired devices found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bluetooth.devices, id: \.address) { device in
                        HStack(spacing: 8) {
                            Image(systemName: device.symbol)
                                .frame(width: 20)
                                .foregroundStyle(device.isConnected ? .primary : .secondary)
                            Text(device.name)
                                .foregroundStyle(device.isConnected ? .primary : .secondary)
                            Spacer()
                            if let battery = device.battery, battery > 0 {
                                Text("\(Int(battery * 100))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Text(device.isConnected ? "Connected" : "Not connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Focus

private struct FocusSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var focus = FocusManager.shared

    @State private var newSite = ""

    var body: some View {
        Form {
            Section("Session") {
                Picker("Default length", selection: $settings.focusDefaultMinutes) {
                    ForEach([15, 25, 45, 60, 90], id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                Toggle("Show the countdown in the closed notch", isOn: $settings.focusShowInClosedNotch)
                Toggle("Pause playback when a session starts", isOn: $settings.focusPauseMusic)
                Toggle("Pomodoro cycles", isOn: $settings.focusPomodoro)
                Picker("Break length", selection: $settings.focusBreakMinutes) {
                    ForEach([3, 5, 10, 15], id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }
                .disabled(!settings.focusPomodoro)
                if settings.focusPomodoro {
                    Text("A finished stretch rolls into a break and back again, instead of ending the session.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if focus.isActive {
                    LabeledContent("Running") {
                        HStack {
                            Text(focus.remainingText).monospacedDigit()
                            Button("Stop") { focus.stop() }
                        }
                    }
                }
            }

            Section("Website blocking") {
                Toggle("Block distracting sites during a session", isOn: $settings.focusBlockWebsites)

                let browsers = FocusManager.supportedInstalledBrowsers
                if browsers.isEmpty {
                    Label("No supported browser found. Safari, Chrome, Brave, Edge and Arc can be policed.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tabs on the blocklist are sent to a placeholder page in \(browsers.joined(separator: ", ")). Fun Notch asks for Automation access the first time it does this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Apps") {
                Text("Listed apps get hidden while a session runs. Hiding needs no special access — actually stopping an app would.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(settings.focusBlockedApps, id: \.self) { identifier in
                    HStack(spacing: 8) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 16, height: 16)
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

                Button("Add an app…", action: pickApp)
            }

            Section("Shortcuts") {
                TextField("Run at start", text: $settings.focusStartShortcut, prompt: Text("Shortcut name"))
                TextField("Run at end", text: $settings.focusEndShortcut, prompt: Text("Shortcut name"))
                Text("Names must match a workflow in the Shortcuts app. This is the practical way to flip a macOS Focus mode, which apps cannot set directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Statistics") {
                LabeledContent("Sessions completed") { Text("\(settings.focusSessionsCompleted)") }
                LabeledContent("Time focused") { Text(focusedTimeText) }
                Button("Reset statistics") {
                    settings.focusSessionsCompleted = 0
                    settings.focusMinutesTotal = 0
                }
            }

            Section("Blocklist") {
                HStack {
                    TextField("example.com", text: $newSite)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSite)
                    Button("Add", action: addSite)
                        .disabled(cleanedNewSite.isEmpty)
                }

                ForEach(settings.focusBlocklist, id: \.self) { site in
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        Text(site)
                        Spacer()
                        Button {
                            remove(site)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Button("Restore defaults") {
                        settings.focusBlocklist = Settings.defaultBlocklist
                    }
                    Button("Remove all") {
                        settings.focusBlocklist = []
                    }
                    .disabled(settings.focusBlocklist.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var cleanedNewSite: String {
        newSite
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .components(separatedBy: "/")
            .first ?? ""
    }

    private func addSite() {
        let site = cleanedNewSite
        guard !site.isEmpty, !settings.focusBlocklist.contains(site) else { return }
        settings.focusBlocklist.append(site)
        newSite = ""
    }

    private func remove(_ site: String) {
        settings.focusBlocklist.removeAll { $0 == site }
    }

    private var focusedTimeText: String {
        let minutes = settings.focusMinutesTotal
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var blocked = settings.focusBlockedApps
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
            if !blocked.contains(identifier) { blocked.append(identifier) }
        }
        settings.focusBlockedApps = blocked
    }
}

// MARK: - Calendar

private struct CalendarSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        Form {
            Section("Agenda") {
                Toggle("Show the calendar in the notch", isOn: $settings.showCalendar)
                Toggle("Hide all-day events", isOn: $settings.hideAllDayEvents)
                Toggle("Show full event titles", isOn: $settings.showFullEventTitles)
                Toggle("Include reminders", isOn: $settings.showReminders)
                Toggle("Hide completed reminders", isOn: $settings.hideCompletedReminders)
                    .disabled(!settings.showReminders)
            }

            // Lives here rather than under Appearance: it is the same thing as
            // every other setting on this tab — what the agenda shows — and
            // somebody looking for it will look here first.
            Section("Examples") {
                Toggle("Fill an empty agenda with examples", isOn: $settings.showSampleAgenda)
                    .disabled(!settings.showCalendar)
                Text("""
                A day with nothing on it shows a few example events and reminders \
                instead of empty space — useful for screenshots, or if you simply \
                prefer the panel to look occupied. They are badged Sample, they \
                never replace or hide anything real, and the collapsed notch will \
                not count them as your next event.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                if !settings.showCalendar {
                    Text("The calendar is switched off above, so there is no agenda to fill.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Calendars") {
                if !manager.hasEventAccess {
                    Button("Grant calendar access") { manager.requestAccess() }
                } else if manager.calendars.isEmpty {
                    Text("No calendars found.").foregroundStyle(.secondary)
                } else {
                    Text("Leave everything unchecked to include all calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(manager.calendars, id: \.calendarIdentifier) { calendar in
                        CalendarToggle(calendar: calendar)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarToggle: View {
    let calendar: EKCalendar

    @ObservedObject private var settings = Settings.shared

    var body: some View {
        Toggle(isOn: binding) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: NSColor(cgColor: calendar.cgColor) ?? .systemBlue))
                    .frame(width: 9, height: 9)
                Text(calendar.title)
            }
        }
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

private struct AboutSettings: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updates = UpdateManager.shared
    @State private var autoUpdate = UpdateManager.shared.automaticallyChecks

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 52))
                .foregroundStyle(.primary)

            Text("Fun Notch")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)

            Text("Turns the MacBook notch into a Dynamic Island: media controls, a file shelf, your agenda, the camera mirror, battery status, and HUD replacements.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .font(.callout)

            VStack(spacing: 8) {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .disabled(!updates.canCheckForUpdates)

                Toggle("Check automatically", isOn: $autoUpdate)
                    .toggleStyle(.checkbox)
                    .onChange(of: autoUpdate) { _, value in
                        updates.automaticallyChecks = value
                    }

                if let last = updates.lastCheckedAt {
                    Text("Last checked \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not checked yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            HStack {
                Button("Reset all settings") {
                    settings.resetAll()
                }
                Button("Restart") {
                    LoginItemManager.relaunch()
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.top, 6)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
