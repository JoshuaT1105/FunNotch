//
//  BrowserScriptAccess.swift
//  FunNotch
//
//  Turns on "Allow JavaScript from Apple Events" for the user.
//
//  Without it a browser hands over a tab's URL and title and nothing else: no
//  artist, no artwork, no position. It is a menu item rather than a preference,
//  so there is no file to write and no defaults key to set — Chrome and Safari
//  both keep it out of their preference files entirely. Driving the menu bar
//  through the accessibility API is the only way to flip it, and that needs
//  Accessibility permission, so it happens only when the user asks for it.
//
//  Nothing here is trusted blind: whether it worked is decided by asking the
//  browser to run a trivial script afterwards, not by assuming the click landed.
//

import AppKit
import ApplicationServices
import Foundation

@MainActor
final class BrowserScriptAccess: ObservableObject {
    static let shared = BrowserScriptAccess()

    enum Outcome: Equatable {
        case idle
        case working
        /// It was already on; nothing needed doing.
        case alreadyOn(String)
        case turnedOn(String)
        case needsAccessibility
        /// Safari hides its Develop menu until web-developer features are on.
        case needsSafariDevelopMenu
        case noBrowser
        case noWindows(String)
        case failed(String)

        var message: String {
            switch self {
            case .idle: return ""
            case .working: return "Checking…"
            case let .alreadyOn(name): return "\(name) already allows it — progress and artwork should be live."
            case let .turnedOn(name): return "Turned on in \(name). Progress and artwork are live now."
            case .needsAccessibility:
                return "macOS needs to allow Fun Notch to control other apps first. Grant it under Privacy & Security → Accessibility, then press this again."
            case .needsSafariDevelopMenu:
                return "Safari hides the switch until its Develop menu exists. Turn on Safari → Settings → Advanced → \"Show features for web developers\", then press this again."
            case .noBrowser: return "No supported browser is running."
            case let .noWindows(name): return "Open a tab in \(name) first."
            case let .failed(reason): return reason
            }
        }

        var isGood: Bool {
            switch self {
            case .alreadyOn, .turnedOn: return true
            default: return false
            }
        }
    }

    @Published private(set) var outcome: Outcome = .idle

    private init() {}

    private struct Target {
        let name: String
        let isChromeFamily: Bool
    }

    // MARK: - Entry point

    func enable() {
        guard let target = firstRunningBrowser() else {
            outcome = .noBrowser
            return
        }

        outcome = .working
        probe(target) { [weak self] state in
            guard let self else { return }
            switch state {
            case .working:
                self.outcome = .alreadyOn(target.name)
                MusicManager.shared.refreshNow()
            case .noWindows:
                self.outcome = .noWindows(target.name)
            case .blocked:
                self.flipSwitch(for: target)
            }
        }
    }

    /// Re-checks without changing anything, so settings can show the state.
    func check() {
        guard let target = firstRunningBrowser() else {
            outcome = .noBrowser
            return
        }
        outcome = .working
        probe(target) { [weak self] state in
            switch state {
            case .working: self?.outcome = .alreadyOn(target.name)
            case .noWindows: self?.outcome = .noWindows(target.name)
            case .blocked: self?.outcome = .failed("\(target.name) is not allowing page access yet.")
            }
        }
    }

    private func firstRunningBrowser() -> Target? {
        for browser in BrowserMediaController.scriptableBrowsers
        where AppleScriptRunner.isRunning(browser.bundleIdentifier) {
            return Target(name: browser.name, isChromeFamily: browser.isChromeFamily)
        }
        return nil
    }

    // MARK: - Probing

    private enum ProbeState {
        case working
        case blocked
        case noWindows
    }

    /// Asks the browser to evaluate a trivial expression. Every tab of the front
    /// window gets a turn, because internal pages refuse scripts even when the
    /// switch is on.
    private func probe(_ target: Target, completion: @escaping (ProbeState) -> Void) {
        let script = Self.probeScript(browser: target.name, isChromeFamily: target.isChromeFamily)

        AppleScriptRunner.shared.runForString(script) { result in
            switch result {
            case "ok": completion(.working)
            case "nowindows": completion(.noWindows)
            default: completion(.blocked)
            }
        }
    }

    /// Every tab of the front window gets a turn, because internal pages refuse
    /// scripts even when the switch is on.
    static func probeScript(browser: String, isChromeFamily: Bool) -> String {
        // Chrome takes the tab first and labels the code; Safari takes the code
        // first and locates the tab with `in`.
        let call = isChromeFamily
            ? "execute t javascript \"'fnok'\""
            : "do JavaScript \"'fnok'\" in t"
        return """
        tell application "\(browser)"
            if (count of windows) is 0 then return "nowindows"
            repeat with t in tabs of window 1
                try
                    if (\(call)) is "fnok" then return "ok"
                end try
            end repeat
            return "blocked"
        end tell
        """
    }

    // MARK: - Flipping the switch

    private func flipSwitch(for target: Target) {
        guard requestAccessibilityTrust() else {
            outcome = .needsAccessibility
            return
        }

        guard let application = runningApplication(named: target.name) else {
            outcome = .noBrowser
            return
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)
        // Chrome-family browsers file it under View → Developer; Safari puts it
        // straight in its Develop menu.
        let path = target.isChromeFamily
            ? ["View", "Developer", "Allow JavaScript from Apple Events"]
            : ["Develop", "Allow JavaScript from Apple Events"]

        guard let item = Self.menuItem(in: element, path: path) else {
            outcome = target.isChromeFamily
                ? .failed("Could not find View → Developer → Allow JavaScript from Apple Events in \(target.name).")
                : .needsSafariDevelopMenu
            return
        }

        if Self.isChecked(item) {
            // The menu says yes but scripts are still refused, which means the
            // block is somewhere else entirely; do not toggle it back off.
            outcome = .failed("\(target.name) says it is on, but it is still refusing scripts. Try quitting and reopening it.")
            return
        }

        let status = AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard status == .success else {
            outcome = .failed("macOS refused the click (error \(status.rawValue)). Check Privacy & Security → Accessibility.")
            return
        }

        // Confirm rather than assume.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated {
                self?.probe(target) { state in
                    if state == .working {
                        self?.outcome = .turnedOn(target.name)
                        MusicManager.shared.refreshNow()
                    } else {
                        self?.outcome = .failed(
                            "The switch was clicked in \(target.name) but scripts are still refused. Reload the tab and try again."
                        )
                    }
                }
            }
        }
    }

    private func runningApplication(named name: String) -> NSRunningApplication? {
        let identifier = BrowserMediaController.scriptableBrowsers
            .first { $0.name == name }?
            .bundleIdentifier
        guard let identifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
    }

    /// Prompts once, then reports whether Fun Notch is trusted.
    private func requestAccessibilityTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    var isTrustedForAccessibility: Bool { AXIsProcessTrusted() }

    // MARK: - Menu walking

    /// Follows a menu path by title. Every menu bar item owns a single menu, so
    /// each step is "find the titled child, then step into its menu".
    static func menuItem(in application: AXUIElement, path: [String]) -> AXUIElement? {
        guard var current = copyElement(application, attribute: kAXMenuBarAttribute) else { return nil }

        for (index, title) in path.enumerated() {
            guard let children = copyChildren(current) else { return nil }
            guard let match = children.first(where: { copyString($0, attribute: kAXTitleAttribute) == title })
            else { return nil }

            if index == path.count - 1 { return match }
            // Step into the submenu this item owns.
            guard let submenu = copyChildren(match)?.first else { return nil }
            current = submenu
        }
        return nil
    }

    static func isChecked(_ item: AXUIElement) -> Bool {
        guard let mark = copyString(item, attribute: kAXMenuItemMarkCharAttribute) else { return false }
        return !mark.isEmpty
    }

    private static func copyElement(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyChildren(_ element: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    private static func copyString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
