//
//  StatusBarController.swift
//  FunNotch
//
//  The menu bar item and its menu, plus login-item management.
//

import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var readoutTimer: Timer?

    private static let watchedKeys: Set<String> = [
        "menubarIcon", "menubarGlyph", "menubarReadout", "menubarReadoutLength",
    ]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .settingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                // A nil key means "everything changed", so refresh either way.
                let key = notification.object as? String
                guard key.map(Self.watchedKeys.contains) ?? true else { return }
                self?.refreshVisibility()
                self?.refreshAppearance()
            }
        }
    }

    func refreshVisibility() {
        if Settings.shared.menubarIcon {
            install()
            refreshAppearance()
        } else {
            remove()
        }
    }

    /// Redraws the glyph and the readout beside it.
    private func refreshAppearance() {
        guard let button = statusItem?.button else { return }
        let settings = Settings.shared

        if let symbol = settings.menubarGlyph.symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Fun Notch")
            image?.isTemplate = true
            button.image = image
        } else {
            button.image = nil
        }

        let text = readoutText()
        button.title = text.isEmpty ? "" : (button.image == nil ? text : " " + text)
        button.imagePosition = button.image == nil ? .noImage : (text.isEmpty ? .imageOnly : .imageLeading)

        // A glyph of "none" with no readout would leave nothing to click, so
        // fall back to the notch mark rather than vanishing.
        if button.image == nil, text.isEmpty {
            let image = NSImage(
                systemSymbolName: MenuBarGlyph.notch.symbol!,
                accessibilityDescription: "Fun Notch"
            )
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }

        scheduleReadoutRefresh(needed: settings.menubarReadout != .nothing)
    }

    /// Only ticks while something is actually being written up there.
    private func scheduleReadoutRefresh(needed: Bool) {
        readoutTimer?.invalidate()
        readoutTimer = nil
        guard needed else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAppearance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        readoutTimer = timer
    }

    private func readoutText() -> String {
        let settings = Settings.shared
        switch settings.menubarReadout {
        case .nothing:
            return ""
        case .nowPlaying:
            let track = MusicManager.shared.track
            guard !track.isEmpty else { return "" }
            return truncated(track.title, to: settings.menubarReadoutLength)
        case .battery:
            let battery = BatteryManager.shared
            return "\(Int(battery.level * 100))%"
        case .focusTimer:
            let focus = FocusManager.shared
            return focus.isActive ? focus.compactRemainingText : ""
        case .nextEvent:
            guard let event = CalendarManager.shared.nextItem else { return "" }
            return truncated(event.title, to: settings.menubarReadoutLength)
        case .shelfCount:
            let count = ShelfManager.shared.items.count
            return count == 0 ? "" : "\(count)"
        }
    }

    private func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    private func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Fun Notch"
            )
            image?.isTemplate = true
            button.image = image
        }
        item.menu = makeMenu()
        statusItem = item
    }

    private func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let nowPlaying = NSMenuItem(title: "Nothing playing", action: nil, keyEquivalent: "")
        nowPlaying.tag = 100
        nowPlaying.isEnabled = false
        menu.addItem(nowPlaying)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Open Notch", action: #selector(openNotch), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Close Notch", action: #selector(closeNotch), keyEquivalent: "w").target = self
        menu.addItem(.separator())

        let focus = NSMenuItem(title: "Start Focus", action: #selector(toggleFocus), keyEquivalent: "f")
        focus.target = self
        focus.tag = 102
        menu.addItem(focus)

        let shelf = NSMenuItem(title: "Clear Shelf", action: #selector(clearShelf), keyEquivalent: "")
        shelf.target = self
        shelf.tag = 101
        menu.addItem(shelf)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Restart Fun Notch", action: #selector(restart), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Fun Notch", action: #selector(quit), keyEquivalent: "q").target = self

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let track = MusicManager.shared.track
        if let item = menu.item(withTag: 100) {
            if track.isEmpty {
                item.title = "Nothing playing"
            } else {
                let symbol = track.isPlaying ? "▶︎" : "❚❚"
                item.title = "\(symbol)  \(track.title) — \(track.artist)"
            }
        }
        if let item = menu.item(withTag: 101) {
            let count = ShelfManager.shared.items.count
            item.title = count == 0 ? "Shelf is Empty" : "Clear Shelf (\(count))"
            item.isEnabled = count > 0
        }
        if let item = menu.item(withTag: 102) {
            let focus = FocusManager.shared
            item.title = focus.isActive
                ? "Stop Focus (\(focus.remainingText) left)"
                : "Start Focus (\(Settings.shared.focusDefaultMinutes) min)"
        }
    }

    @objc private func toggleFocus() {
        let focus = FocusManager.shared
        if focus.isActive {
            focus.stop()
        } else {
            focus.start(minutes: Settings.shared.focusDefaultMinutes)
        }
    }

    @objc private func openNotch() {
        NotificationCenter.default.post(name: .openNotchRequested, object: nil)
    }

    @objc private func closeNotch() {
        NotificationCenter.default.post(name: .closeNotchRequested, object: nil)
    }

    @objc private func clearShelf() {
        ShelfManager.shared.clear()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func restart() {
        LoginItemManager.relaunch()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Login item registration and app relaunching.
@MainActor
enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("FunNotch: could not update login item — \(error.localizedDescription)")
        }
    }

    /// Brings the stored preference and the real registration back in sync.
    static func syncWithSettings() {
        let wanted = Settings.shared.launchAtLogin
        if wanted != isEnabled {
            setEnabled(wanted)
        }
    }

    static func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
