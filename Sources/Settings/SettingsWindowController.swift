//
//  SettingsWindowController.swift
//  FunNotch
//
//  Hosts the settings UI in a normal window. The app is an accessory, so it
//  temporarily becomes a regular app while settings are on screen — otherwise
//  the window could never take keyboard focus.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Opens settings on a specific pane, for links from inside the notch.
    func show(tab: SettingsTab) {
        SettingsNavigation.shared.tab = tab
        show()
    }

    func show() {
        if let window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView().environmentObject(Settings.shared)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Fun Notch Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 660, height: 520))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Drop back to accessory so the Dock icon disappears again.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
