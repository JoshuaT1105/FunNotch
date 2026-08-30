//
//  Settings.swift
//  FunNotch
//
//  A small UserDefaults-backed preferences store. Every property is a computed
//  accessor so SwiftUI can bind directly to `Settings.shared` via
//  `@ObservedObject`, and every write publishes a change plus a targeted
//  notification for managers that need to react to a specific key.
//

import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let settingsChanged = Notification.Name("funnotch.settingsChanged")
    static let mediaControllerChanged = Notification.Name("funnotch.mediaControllerChanged")
    static let notchGeometryChanged = Notification.Name("funnotch.notchGeometryChanged")
    static let openNotchRequested = Notification.Name("funnotch.openNotchRequested")
    static let closeNotchRequested = Notification.Name("funnotch.closeNotchRequested")
}

final class Settings: ObservableObject {
    static let shared = Settings()

    private let store = UserDefaults.standard

    private init() {
        migrateFromPreviousBundleIdentifier()
    }

    /// The app used to ship as `com.boringnotch.BoringNotch`, and preferences
    /// live under the bundle identifier. Carry the old ones across once so the
    /// rename does not silently reset everything.
    private func migrateFromPreviousBundleIdentifier() {
        let flag = "didMigrateFromBoringNotch"
        guard !store.bool(forKey: flag) else { return }
        defer { store.set(true, forKey: flag) }

        guard let legacy = UserDefaults(suiteName: "com.boringnotch.BoringNotch") else { return }

        for key in Self.allKeys + ["shelfBookmarks", "clipboardTextHistory"] {
            guard store.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key)
            else { continue }
            store.set(value, forKey: key)
        }
    }

    // MARK: - Primitive access

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        store.object(forKey: key) as? Bool ?? fallback
    }

    private func number(_ key: String, _ fallback: CGFloat) -> CGFloat {
        guard let value = store.object(forKey: key) as? Double else { return fallback }
        return CGFloat(value)
    }

    private func integer(_ key: String, _ fallback: Int) -> Int {
        store.object(forKey: key) as? Int ?? fallback
    }

    private func string(_ key: String, _ fallback: String) -> String {
        store.object(forKey: key) as? String ?? fallback
    }

    private func option<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
        guard let raw = store.object(forKey: key) as? String, let value = T(rawValue: raw) else {
            return fallback
        }
        return value
    }

    private func write(_ key: String, _ value: Any?) {
        objectWillChange.send()
        if let value {
            store.set(value, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .settingsChanged, object: key)
    }

    /// Restores every preference to its shipped default.
    func resetAll() {
        objectWillChange.send()
        for key in Self.allKeys {
            store.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        NotificationCenter.default.post(name: .notchGeometryChanged, object: nil)
    }

    // MARK: - General

    var menubarIcon: Bool {
        get { bool("menubarIcon", true) }
        set { write("menubarIcon", newValue) }
    }

    var menubarGlyph: MenuBarGlyph {
        get { option("menubarGlyph", MenuBarGlyph.notch) }
        set { write("menubarGlyph", newValue.rawValue) }
    }

    var menubarReadout: MenuBarReadout {
        get { option("menubarReadout", MenuBarReadout.nothing) }
        set { write("menubarReadout", newValue.rawValue) }
    }

    /// How much of a long readout — a track title — the menu bar keeps.
    var menubarReadoutLength: Int {
        get { integer("menubarReadoutLength", 24) }
        set { write("menubarReadoutLength", newValue) }
    }

    // MARK: - HUD

    /// Replaces the system volume / brightness / keyboard-backlight panels with
    /// one drawn in the notch.
    ///
    /// On by default, but nothing is intercepted until Accessibility is granted
    /// — until then the tap is never installed, the system's own HUD is left
    /// alone, and Diagnostics reports the feature as unavailable. So the app
    /// still does not act before it has been allowed to.
    var hudEnabled: Bool {
        get { bool("hudEnabled", true) }
        set { write("hudEnabled", newValue) }
    }

    var hudShowsVolume: Bool {
        get { bool("hudShowsVolume", true) }
        set { write("hudShowsVolume", newValue) }
    }

    var hudShowsBrightness: Bool {
        get { bool("hudShowsBrightness", true) }
        set { write("hudShowsBrightness", newValue) }
    }

    var hudShowsBacklight: Bool {
        get { bool("hudShowsBacklight", true) }
        set { write("hudShowsBacklight", newValue) }
    }

    var showOnAllDisplays: Bool {
        get { bool("showOnAllDisplays", false) }
        set { write("showOnAllDisplays", newValue); postGeometryChange() }
    }

    var automaticallySwitchDisplay: Bool {
        get { bool("automaticallySwitchDisplay", true) }
        set { write("automaticallySwitchDisplay", newValue); postGeometryChange() }
    }

    var preferredScreenName: String {
        get { string("preferredScreenName", "") }
        set { write("preferredScreenName", newValue); postGeometryChange() }
    }

    var launchAtLogin: Bool {
        get { bool("launchAtLogin", false) }
        set { write("launchAtLogin", newValue) }
    }

    // MARK: - Behaviour

    var openNotchOnHover: Bool {
        get { bool("openNotchOnHover", true) }
        set { write("openNotchOnHover", newValue) }
    }

    var minimumHoverDuration: TimeInterval {
        get { Double(number("minimumHoverDuration", 0.05)) }
        set { write("minimumHoverDuration", Double(newValue)) }
    }

    var enableHaptics: Bool {
        get { bool("enableHaptics", true) }
        set { write("enableHaptics", newValue) }
    }

    var extendHoverArea: Bool {
        get { bool("extendHoverArea", false) }
        set { write("extendHoverArea", newValue); postGeometryChange() }
    }

    var notchHeightMode: WindowHeightMode {
        get { option("notchHeightMode", WindowHeightMode.matchRealNotchSize) }
        set { write("notchHeightMode", newValue.rawValue); postGeometryChange() }
    }

    var nonNotchHeightMode: WindowHeightMode {
        get { option("nonNotchHeightMode", WindowHeightMode.matchMenuBar) }
        set { write("nonNotchHeightMode", newValue.rawValue); postGeometryChange() }
    }

    var notchHeight: CGFloat {
        get { number("notchHeight", 32) }
        set { write("notchHeight", Double(newValue)); postGeometryChange() }
    }

    var nonNotchHeight: CGFloat {
        get { number("nonNotchHeight", 32) }
        set { write("nonNotchHeight", Double(newValue)); postGeometryChange() }
    }

    var notchWidthPadding: CGFloat {
        get { number("notchWidthPadding", 0) }
        set { write("notchWidthPadding", Double(newValue)); postGeometryChange() }
    }

    var showOnLockScreen: Bool {
        get { bool("showOnLockScreen", false) }
        set { write("showOnLockScreen", newValue) }
    }

    var hideFromScreenRecording: Bool {
        get { bool("hideFromScreenRecording", false) }
        set { write("hideFromScreenRecording", newValue); postGeometryChange() }
    }

    // MARK: - Appearance

    var showEmojis: Bool {
        get { bool("showEmojis", false) }
        set { write("showEmojis", newValue) }
    }

    var showMirror: Bool {
        get { bool("showMirror", false) }
        set { write("showMirror", newValue) }
    }

    var mirrorShape: MirrorShapeEnum {
        get { option("mirrorShape", MirrorShapeEnum.rectangle) }
        set { write("mirrorShape", newValue.rawValue) }
    }

    var settingsIconInNotch: Bool {
        get { bool("settingsIconInNotch", true) }
        set { write("settingsIconInNotch", newValue) }
    }

    /// Drop shadow under the expanded panel. Off by default: the notch hangs
    /// over other people's windows, and anything it paints outside its own
    /// silhouette shows up as a smudge on them.
    var enableShadow: Bool {
        get { bool("enableShadow", false) }
        set { write("enableShadow", newValue) }
    }

    // MARK: - Border
    //
    // A hairline traced along the notch's own outline. Unlike the shadow it
    // stays strictly inside the silhouette, so it defines the edge without
    // touching anything behind the panel.

    var notchBorderEnabled: Bool {
        get { bool("notchBorderEnabled", false) }
        set { write("notchBorderEnabled", newValue) }
    }

    var notchBorderWidth: CGFloat {
        get { number("notchBorderWidth", 1) }
        set { write("notchBorderWidth", Double(newValue)) }
    }

    var notchBorderOpacity: CGFloat {
        get { number("notchBorderOpacity", 0.08) }
        set { write("notchBorderOpacity", Double(newValue)) }
    }

    var notchBorderColorSource: BorderColorSource {
        get { option("notchBorderColorSource", BorderColorSource.white) }
        set { write("notchBorderColorSource", newValue.rawValue) }
    }

    /// Whether the border is also drawn around the collapsed notch. Off by
    /// default: on a notched display the collapsed panel sits inside the real
    /// cutout, and outlining that just draws a box around the hardware.
    var notchBorderWhenClosed: Bool {
        get { bool("notchBorderWhenClosed", false) }
        set { write("notchBorderWhenClosed", newValue) }
    }

    /// The resolved border colour, before opacity.
    func resolvedBorderColor(albumArt: Color) -> Color {
        switch notchBorderColorSource {
        case .white: return .white
        case .accent: return accentColor
        case .albumArt: return albumArt
        }
    }

    var cornerRadiusScaling: Bool {
        get { bool("cornerRadiusScaling", true) }
        set { write("cornerRadiusScaling", newValue) }
    }

    var showNotHumanFace: Bool {
        get { bool("showNotHumanFace", false) }
        set { write("showNotHumanFace", newValue) }
    }

    var tileShowLabels: Bool {
        get { bool("tileShowLabels", false) }
        set { write("tileShowLabels", newValue) }
    }

    var showCalendar: Bool {
        get { bool("showCalendar", true) }
        set { write("showCalendar", newValue) }
    }

    var sliderColor: SliderColorEnum {
        get { option("sliderColor", SliderColorEnum.white) }
        set { write("sliderColor", newValue.rawValue) }
    }

    var playerColorTinting: Bool {
        get { bool("playerColorTinting", true) }
        set { write("playerColorTinting", newValue) }
    }

    var useMusicVisualizer: Bool {
        get { bool("useMusicVisualizer", true) }
        set { write("useMusicVisualizer", newValue) }
    }

    var useCustomAccentColor: Bool {
        get { bool("useCustomAccentColor", false) }
        set { write("useCustomAccentColor", newValue) }
    }

    private func color(_ key: String, _ fallback: Color) -> Color {
        guard let data = store.data(forKey: key),
              let value = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return fallback }
        return Color(nsColor: value)
    }

    private func writeColor(_ key: String, _ value: Color) {
        let data = try? NSKeyedArchiver.archivedData(
            withRootObject: NSColor(value),
            requiringSecureCoding: false
        )
        write(key, data)
    }

    var customAccentColor: Color {
        get { color("customAccentColorData", .accentColor) }
        set { writeColor("customAccentColorData", newValue) }
    }

    /// Colour washed over the notch background.
    var notchTintColor: Color {
        get { color("notchTintColorData", .blue) }
        set { writeColor("notchTintColorData", newValue) }
    }

    /// 0 keeps the notch pure black; 1 is a full wash of `notchTintColor`.
    var notchTintIntensity: CGFloat {
        get { number("notchTintIntensity", 0) }
        set { write("notchTintIntensity", Double(newValue)) }
    }

    /// Where the spectrum bars take their colour from.
    var spectrumColor: SliderColorEnum {
        get { option("spectrumColor", SliderColorEnum.albumArt) }
        set { write("spectrumColor", newValue.rawValue) }
    }

    /// The tint used throughout the UI, honouring the custom accent override.
    var accentColor: Color {
        useCustomAccentColor ? customAccentColor : .accentColor
    }

    // MARK: - Notch widgets

    /// Show something beside the cutout while the notch is just sitting there.
    var idleWidgetsEnabled: Bool {
        get { bool("idleWidgetsEnabled", true) }
        set { write("idleWidgetsEnabled", newValue) }
    }

    /// Who gets the space beside the cutout once music starts. Keeps the
    /// widgets alongside the track rather than letting music take the whole row.
    var closedMediaDisplay: ClosedMediaDisplay {
        get { option("closedMediaDisplay", ClosedMediaDisplay.mediaAndWidgets) }
        set { write("closedMediaDisplay", newValue.rawValue) }
    }

    var idleLeftWidgets: [NotchWidget] {
        get { widgetList("idleLeftWidgets", default: [.clock]) }
        set { write("idleLeftWidgets", newValue.map(\.rawValue)) }
    }

    var idleRightWidgets: [NotchWidget] {
        get { widgetList("idleRightWidgets", default: [.battery]) }
        set { write("idleRightWidgets", newValue.map(\.rawValue)) }
    }

    private func widgetList(_ key: String, default fallback: [NotchWidget]) -> [NotchWidget] {
        guard let raw = store.stringArray(forKey: key) else { return fallback }
        return raw.compactMap(NotchWidget.init(rawValue:))
    }

    // MARK: - Gestures

    var enableGestures: Bool {
        get { bool("enableGestures", true) }
        set { write("enableGestures", newValue) }
    }

    /// Scrolling sideways across the closed notch changes the system volume.
    /// Horizontal on purpose: vertical already opens and closes the notch, and
    /// one axis doing two jobs makes both feel unreliable.
    var scrollToChangeVolume: Bool {
        get { bool("scrollToChangeVolume", true) }
        set { write("scrollToChangeVolume", newValue) }
    }

    var closeGestureEnabled: Bool {
        get { bool("closeGestureEnabled", true) }
        set { write("closeGestureEnabled", newValue) }
    }

    var gestureSensitivity: CGFloat {
        get { number("gestureSensitivity", 200) }
        set { write("gestureSensitivity", Double(newValue)) }
    }

    // MARK: - Media playback

    var mediaController: MediaControllerType {
        get { option("mediaController", MediaControllerType.browser) }
        set {
            write("mediaController", newValue.rawValue)
            NotificationCenter.default.post(name: .mediaControllerChanged, object: nil)
        }
    }

    /// Whether the player nags about page access when a browser tab cannot
    /// report a position. On by default, because otherwise the missing progress
    /// bar looks like a bug rather than a switch.
    var showPageAccessHint: Bool {
        get { bool("showPageAccessHint", true) }
        set { write("showPageAccessHint", newValue) }
    }

    var coloredSpectrogram: Bool {
        get { bool("coloredSpectrogram", true) }
        set { write("coloredSpectrogram", newValue) }
    }

    var enableSneakPeek: Bool {
        get { bool("enableSneakPeek", true) }
        set { write("enableSneakPeek", newValue) }
    }

    var sneakPeekStyle: SneakPeekStyle {
        get { option("sneakPeekStyles", SneakPeekStyle.standard) }
        set { write("sneakPeekStyles", newValue.rawValue) }
    }

    var waitInterval: Double {
        get { Double(number("waitInterval", 3)) }
        set { write("waitInterval", Double(newValue)) }
    }

    var showShuffleAndRepeat: Bool {
        get { bool("showShuffleAndRepeat", true) }
        set { write("showShuffleAndRepeat", newValue) }
    }

    var hideNotchOption: HideNotchOption {
        get { option("hideNotchOption", HideNotchOption.nowPlayingOnly) }
        set { write("hideNotchOption", newValue.rawValue) }
    }

    // MARK: - Battery

    var showPowerStatusNotifications: Bool {
        get { bool("showPowerStatusNotifications", true) }
        set { write("showPowerStatusNotifications", newValue) }
    }

    var showBatteryIndicator: Bool {
        get { bool("showBatteryIndicator", true) }
        set { write("showBatteryIndicator", newValue) }
    }

    var showBatteryPercentage: Bool {
        get { bool("showBatteryPercentage", true) }
        set { write("showBatteryPercentage", newValue) }
    }

    var showPowerStatusIcons: Bool {
        get { bool("showPowerStatusIcons", true) }
        set { write("showPowerStatusIcons", newValue) }
    }

    // MARK: - Downloads

    var enableDownloadListener: Bool {
        get { bool("enableDownloadListener", true) }
        set { write("enableDownloadListener", newValue) }
    }

    var selectedDownloadIndicatorStyle: DownloadIndicatorStyle {
        get { option("selectedDownloadIndicatorStyle", DownloadIndicatorStyle.progress) }
        set { write("selectedDownloadIndicatorStyle", newValue.rawValue) }
    }

    var selectedDownloadIconStyle: DownloadIconStyle {
        get { option("selectedDownloadIconStyle", DownloadIconStyle.onlyAppIcon) }
        set { write("selectedDownloadIconStyle", newValue.rawValue) }
    }

    // MARK: - Shelf

    var shelfEnabled: Bool {
        // Storage key predates the rename; leaving it alone keeps the setting.
        get { bool("boringShelf", true) }
        set { write("boringShelf", newValue) }
    }

    var openShelfByDefault: Bool {
        get { bool("openShelfByDefault", true) }
        set { write("openShelfByDefault", newValue) }
    }

    var copyOnDrag: Bool {
        get { bool("copyOnDrag", true) }
        set { write("copyOnDrag", newValue) }
    }

    var autoRemoveShelfItems: Bool {
        get { bool("autoRemoveShelfItems", false) }
        set { write("autoRemoveShelfItems", newValue) }
    }

    /// Drop shelf items older than this, in hours. 0 keeps them forever.
    var shelfExpiryHours: Int {
        get { integer("shelfExpiryHours", 0) }
        set { write("shelfExpiryHours", newValue) }
    }

    /// Folders offered as one-click destinations in the shelf.
    var shelfFolderTargets: [String] {
        get { store.stringArray(forKey: "shelfFolderTargets") ?? [] }
        set { write("shelfFolderTargets", newValue) }
    }

    var expandedDragDetection: Bool {
        get { bool("expandedDragDetection", true) }
        set { write("expandedDragDetection", newValue) }
    }

    // MARK: - Downloads

    var catchDownloads: Bool {
        get { bool("catchDownloads", true) }
        set { write("catchDownloads", newValue) }
    }

    /// Put finished downloads on the shelf as well as announcing them.
    var downloadsToShelf: Bool {
        get { bool("downloadsToShelf", true) }
        set { write("downloadsToShelf", newValue) }
    }

    // MARK: - Screenshots

    var catchScreenshots: Bool {
        get { bool("catchScreenshots", true) }
        set { write("catchScreenshots", newValue) }
    }

    var catchScreenRecordings: Bool {
        get { bool("catchScreenRecordings", true) }
        set { write("catchScreenRecordings", newValue) }
    }

    // MARK: - Clipboard

    var clipboardHistoryEnabled: Bool {
        get { bool("clipboardHistoryEnabled", true) }
        set { write("clipboardHistoryEnabled", newValue) }
    }

    /// Text of pinned clipboard entries, which survive the history limit.
    var clipboardPinned: [String] {
        get { store.stringArray(forKey: "clipboardPinned") ?? [] }
        set { write("clipboardPinned", newValue) }
    }

    var clipboardHistoryLimit: Int {
        get { integer("clipboardHistoryLimit", 50) }
        set { write("clipboardHistoryLimit", newValue) }
    }

    /// Drop unpinned clipboard entries older than this, in hours. 0 keeps them
    /// forever. A day is the default because clipboard history is a
    /// convenience, not an archive, and everything you have ever copied
    /// sitting on disk indefinitely is a liability rather than a feature.
    /// Pinned entries ignore this, the same way they ignore the count limit.
    var clipboardExpiryHours: Int {
        get { integer("clipboardExpiryHours", 24) }
        set { write("clipboardExpiryHours", newValue) }
    }

    // MARK: - Bluetooth

    var bluetoothActivity: Bool {
        get { bool("bluetoothActivity", true) }
        set { write("bluetoothActivity", newValue) }
    }

    // MARK: - Calendar

    /// Empty means "all calendars".
    var selectedCalendarIdentifiers: [String] {
        get { store.stringArray(forKey: "selectedCalendarIdentifiers") ?? [] }
        set { write("selectedCalendarIdentifiers", newValue) }
    }

    var hideAllDayEvents: Bool {
        get { bool("hideAllDayEvents", false) }
        set { write("hideAllDayEvents", newValue) }
    }

    var showFullEventTitles: Bool {
        get { bool("showFullEventTitles", false) }
        set { write("showFullEventTitles", newValue) }
    }

    var showReminders: Bool {
        get { bool("showReminders", true) }
        set { write("showReminders", newValue) }
    }

    /// Fills an empty agenda with example rows so the panel is not a blank
    /// space. Off by default: an agenda that invents things is only wanted when
    /// it is asked for.
    var showSampleAgenda: Bool {
        get { bool("showSampleAgenda", false) }
        set { write("showSampleAgenda", newValue) }
    }

    var hideCompletedReminders: Bool {
        get { bool("hideCompletedReminders", true) }
        set { write("hideCompletedReminders", newValue) }
    }

    // MARK: - Focus

    var focusDefaultMinutes: Int {
        get { integer("focusDefaultMinutes", 25) }
        set { write("focusDefaultMinutes", newValue) }
    }

    /// Hosts blocked while a focus session is running.
    var focusBlocklist: [String] {
        get {
            store.stringArray(forKey: "focusBlocklist") ?? Self.defaultBlocklist
        }
        set { write("focusBlocklist", newValue) }
    }

    var focusBlockWebsites: Bool {
        get { bool("focusBlockWebsites", true) }
        set { write("focusBlockWebsites", newValue) }
    }

    /// Keep the countdown visible in the collapsed notch.
    var focusShowInClosedNotch: Bool {
        get { bool("focusShowInClosedNotch", true) }
        set { write("focusShowInClosedNotch", newValue) }
    }

    /// Turn on Do Not Disturb-style silence by pausing playback at start.
    var focusPauseMusic: Bool {
        get { bool("focusPauseMusic", false) }
        set { write("focusPauseMusic", newValue) }
    }

    /// Run work/break cycles instead of one long stretch.
    var focusPomodoro: Bool {
        get { bool("focusPomodoro", false) }
        set { write("focusPomodoro", newValue) }
    }

    var focusBreakMinutes: Int {
        get { integer("focusBreakMinutes", 5) }
        set { write("focusBreakMinutes", newValue) }
    }

    /// Bundle identifiers hidden while a session runs.
    var focusBlockedApps: [String] {
        get { store.stringArray(forKey: "focusBlockedApps") ?? [] }
        set { write("focusBlockedApps", newValue) }
    }

    /// Shortcuts run at the start and end of a session, by name.
    var focusStartShortcut: String {
        get { string("focusStartShortcut", "") }
        set { write("focusStartShortcut", newValue) }
    }

    var focusEndShortcut: String {
        get { string("focusEndShortcut", "") }
        set { write("focusEndShortcut", newValue) }
    }

    var focusSessionsCompleted: Int {
        get { integer("focusSessionsCompleted", 0) }
        set { write("focusSessionsCompleted", newValue) }
    }

    var focusMinutesTotal: Int {
        get { integer("focusMinutesTotal", 0) }
        set { write("focusMinutesTotal", newValue) }
    }

    static let defaultBlocklist = [
        "youtube.com",
        "x.com",
        "twitter.com",
        "instagram.com",
        "facebook.com",
        "reddit.com",
        "tiktok.com",
        "twitch.tv",
        "netflix.com",
    ]

    // MARK: - Themes

    /// Named colour presets, stored as JSON.
    var savedThemes: [NotchTheme] {
        get {
            guard let data = store.data(forKey: "themes"),
                  let decoded = try? JSONDecoder().decode([NotchTheme].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            write("themes", data)
        }
    }

    var activeThemeName: String {
        get { string("activeThemeName", "") }
        set { write("activeThemeName", newValue) }
    }

    /// Reads the current colour settings as a theme.
    func currentTheme(named name: String) -> NotchTheme {
        NotchTheme(
            name: name,
            accent: useCustomAccentColor ? NotchTheme.encode(customAccentColor) : nil,
            notchTint: NotchTheme.encode(notchTintColor),
            tintIntensity: Double(notchTintIntensity),
            sliderColor: sliderColor.rawValue,
            spectrumColor: spectrumColor.rawValue
        )
    }

    /// Writes a theme's colours into the live settings.
    func apply(theme: NotchTheme) {
        if let accent = theme.accent {
            customAccentColor = NotchTheme.decode(accent)
            useCustomAccentColor = true
        } else {
            useCustomAccentColor = false
        }
        notchTintColor = NotchTheme.decode(theme.notchTint)
        notchTintIntensity = CGFloat(theme.tintIntensity)
        sliderColor = SliderColorEnum(rawValue: theme.sliderColor) ?? .white
        spectrumColor = SliderColorEnum(rawValue: theme.spectrumColor) ?? .albumArt
        activeThemeName = theme.name
    }

    // MARK: - Game

    /// Reopen on whichever tab you were last using instead of always Home.
    /// Off by default: resetting to Home makes each open predictable, which is
    /// right for most people and wrong for anyone who lives in the shelf.
    var rememberLastTab: Bool {
        get { bool("rememberLastTab", false) }
        set { write("rememberLastTab", newValue) }
    }

    /// The Notes scratchpad tab. On by default: it is the single most
    /// requested notch feature and it costs one tab.
    var showNotes: Bool {
        get { bool("showNotes", true) }
        set { write("showNotes", newValue) }
    }

    var showGame: Bool {
        get { bool("showGame", true) }
        set { write("showGame", newValue) }
    }

    var gameHighScore: Int {
        get { integer("gameHighScore", 0) }
        set { write("gameHighScore", newValue) }
    }

    // MARK: - Onboarding

    var hasCompletedOnboarding: Bool {
        get { bool("hasCompletedOnboarding", false) }
        set { write("hasCompletedOnboarding", newValue) }
    }

    private func postGeometryChange() {
        NotificationCenter.default.post(name: .notchGeometryChanged, object: nil)
    }

    private static let allKeys = [
        "menubarIcon", "showOnAllDisplays", "automaticallySwitchDisplay", "preferredScreenName",
        "launchAtLogin", "openNotchOnHover", "minimumHoverDuration", "enableHaptics",
        "extendHoverArea", "notchHeightMode", "nonNotchHeightMode", "notchHeight", "nonNotchHeight",
        "notchWidthPadding", "showOnLockScreen", "hideFromScreenRecording", "showEmojis",
        "showMirror", "mirrorShape", "settingsIconInNotch", "enableShadow",
        "cornerRadiusScaling", "showNotHumanFace", "tileShowLabels", "showCalendar", "sliderColor",
        "playerColorTinting", "useMusicVisualizer", "useCustomAccentColor", "customAccentColorData",
        "enableGestures", "closeGestureEnabled", "gestureSensitivity", "mediaController",
        "coloredSpectrogram", "enableSneakPeek", "sneakPeekStyles", "waitInterval",
        "showShuffleAndRepeat", "hideNotchOption", "showPowerStatusNotifications",
        "showBatteryIndicator", "showBatteryPercentage", "showPowerStatusIcons",
        "enableDownloadListener", "selectedDownloadIndicatorStyle", "selectedDownloadIconStyle",
        "boringShelf", "openShelfByDefault", "copyOnDrag",
        "autoRemoveShelfItems", "expandedDragDetection", "selectedCalendarIdentifiers",
        "hideAllDayEvents", "showFullEventTitles", "showReminders", "hideCompletedReminders",
        "notchTintColorData", "notchTintIntensity", "spectrumColor",
        "focusDefaultMinutes", "focusBlocklist", "focusBlockWebsites",
        "idleWidgetsEnabled", "idleLeftWidgets", "idleRightWidgets", "closedMediaDisplay",
        "focusPomodoro", "focusBreakMinutes", "focusBlockedApps", "focusStartShortcut",
        "focusEndShortcut", "focusSessionsCompleted", "focusMinutesTotal",
        "catchDownloads", "downloadsToShelf", "shelfExpiryHours", "shelfFolderTargets",
        "clipboardPinned", "themes", "activeThemeName", "gameHighScore", "showGame",
        "catchScreenshots", "catchScreenRecordings", "clipboardHistoryEnabled",
        "clipboardHistoryLimit", "bluetoothActivity",
        "focusShowInClosedNotch", "focusPauseMusic", "showPageAccessHint",
        "notchBorderEnabled", "notchBorderWidth", "notchBorderOpacity",
        "notchBorderColorSource", "notchBorderWhenClosed",
        "menubarGlyph", "menubarReadout", "menubarReadoutLength",
        "hudEnabled", "hudShowsVolume", "hudShowsBrightness", "hudShowsBacklight",
    ]
}
