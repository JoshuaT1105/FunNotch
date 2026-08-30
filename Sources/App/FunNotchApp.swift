//
//  FunNotchApp.swift
//  FunNotch
//
//  Entry point. The app is an accessory (no Dock icon); everything lives in the
//  notch panel and the menu bar item.
//

import AppKit
import SwiftUI

@main
enum FunNotchApp {
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings.shared

        // Snapshot mode renders each notch state to disk and exits.
        if let directory = PreviewRenderer.requestedDirectory() {
            PreviewRenderer.run(into: directory)
            return
        }

        if let path = SelfTest.fileToCheck {
            SelfTest.checkFile(path)
            return
        }

        if SelfTest.isRequested {
            SelfTest.run()
            return
        }

        if SelfTest.diagnosticsRequested {
            SelfTest.printDiagnostics()
            return
        }

        // Managers that observe the system start before the windows so the very
        // first render already has real data in it.
        // Before the pollers, so they can back off from their first tick.
        SystemActivityMonitor.shared.start()
        MusicManager.shared.start()
        BatteryManager.shared.start()
        CalendarManager.shared.start()
        FullscreenMediaDetector.shared.start()
        ScreenshotWatcher.shared.start()
        DownloadWatcher.shared.start()
        ClipboardManager.shared.start()
        UpdateManager.shared.start()
        LoginItemManager.repairRegistration()
        BluetoothMonitor.shared.start()

        NotchWindowManager.shared.start()
        // After the windows: the HUD broadcasts to them.
        HUDManager.shared.start()

        statusBar = StatusBarController()
        statusBar?.refreshVisibility()

        LoginItemManager.syncWithSettings()

        if !settings.hasCompletedOnboarding {
            settings.hasCompletedOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NotchWindowManager.shared.activeViewModel?.open()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MouseTracker.shared.stop()
        WebcamManager.shared.stop()
    }

    /// Reopening from Finder or a second launch just shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}
