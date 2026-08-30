//
//  HUDManager.swift
//  FunNotch
//
//  Volume, brightness and keyboard backlight, shown in the notch.
//
//  This shipped once before and was removed because it drew a second HUD next
//  to the system's own. That was the whole problem: watching for a change after
//  the fact is always too late, because by then macOS has already put its own
//  panel on screen.
//
//  The fix is to get in front of it. A CGEventTap on the system-defined media
//  keys sees F10/F11/F12 and the brightness and backlight keys *before* the
//  window server acts on them, applies the change itself, and swallows the
//  event. macOS never learns a key was pressed, so it never draws anything, and
//  the only HUD on screen is this one.
//
//  That needs Accessibility. Without it there is no tap, and rather than
//  pretending, the feature reports itself as unavailable in Diagnostics and
//  leaves the system HUD alone.
//

import AppKit
import AudioToolbox
import Combine
import CoreAudio
import CoreGraphics
import Foundation

@MainActor
final class HUDManager: ObservableObject {
    static let shared = HUDManager()

    enum Kind: Equatable {
        case volume
        case brightness
        case keyboardBacklight

        var symbol: String {
            switch self {
            case .volume: return "speaker.wave.2.fill"
            case .brightness: return "sun.max.fill"
            case .keyboardBacklight: return "keyboard.fill"
            }
        }

        var mutedSymbol: String { "speaker.slash.fill" }
    }

    /// What the notch should currently be showing, if anything.
    @Published private(set) var showing: Kind?
    @Published private(set) var value: Float = 0
    @Published private(set) var isMuted = false

    /// True when the tap is live. Without it nothing here is intercepted.
    @Published private(set) var isIntercepting = false
    @Published private(set) var lastError: String?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Lifecycle

    func start() {
        guard Settings.shared.hudEnabled else {
            stop()
            return
        }
        guard AXIsProcessTrusted() else {
            isIntercepting = false
            lastError = "Accessibility access not granted"
            return
        }
        guard tap == nil else { return }
        installTap()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        isIntercepting = false
    }

    /// Asks for Accessibility, then starts. Used by the settings button.
    func requestAccessAndStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        start()
    }

    private func installTap() {
        let mask = CGEventMask(1 << NX_SYSDEFINED)
        let callback: CGEventTapCallBack = { _, type, event, _ in
            MainActor.assumeIsolated {
                HUDManager.shared.handle(type: type, event: event)
            }
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: nil
        ) else {
            isIntercepting = false
            lastError = "macOS refused the event tap"
            DiagnosticLog.write("hud", "event tap refused")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        isIntercepting = true
        lastError = nil
        DiagnosticLog.write("hud", "intercepting media keys")
    }

    // MARK: - Interception

    /// Returns the event to pass along, or nil to swallow it.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // A tap that times out is disabled by the system; switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard Settings.shared.hudEnabled,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let keyCode = Int32((nsEvent.data1 & 0xFFFF_0000) >> 16)
        let keyFlags = nsEvent.data1 & 0x0000_FFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let isRepeat = (keyFlags & 0x1) == 1

        guard isDown || isRepeat else { return Unmanaged.passUnretained(event) }
        guard let action = Self.action(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        // A key for a category the user switched off is none of our business.
        guard Self.isEnabled(Self.kind(of: action)) else {
            return Unmanaged.passUnretained(event)
        }

        // Fine adjustment is what Shift+Option does system-wide.
        let fine = nsEvent.modifierFlags.contains([.shift, .option])
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16

        let applied: Bool
        switch action {
        case .volumeUp: applied = adjustVolume(by: step)
        case .volumeDown: applied = adjustVolume(by: -step)
        case .mute: applied = toggleMute()
        case .brightnessUp: applied = adjustBrightness(by: step)
        case .brightnessDown: applied = adjustBrightness(by: -step)
        case .backlightUp: applied = adjustBacklight(by: step)
        case .backlightDown: applied = adjustBacklight(by: -step)
        }

        // Only swallow a key that was actually acted on. A Mac with no backlit
        // keyboard, or one where DisplayServices has gone away, cannot apply the
        // change — and swallowing there left the key doing nothing whatsoever,
        // neither this HUD nor the system's. Passing it through means macOS
        // handles it as it always did.
        guard applied else { return Unmanaged.passUnretained(event) }

        // Swallowed: macOS never sees it, so it never draws its own HUD.
        return nil
    }

    private enum Action {
        case volumeUp, volumeDown, mute
        case brightnessUp, brightnessDown
        case backlightUp, backlightDown
    }

    private static func kind(of action: Action) -> Kind {
        switch action {
        case .volumeUp, .volumeDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        case .backlightUp, .backlightDown: return .keyboardBacklight
        }
    }

    static func isEnabled(_ kind: Kind) -> Bool {
        switch kind {
        case .volume: return Settings.shared.hudShowsVolume
        case .brightness: return Settings.shared.hudShowsBrightness
        case .keyboardBacklight: return Settings.shared.hudShowsBacklight
        }
    }

    private static func action(for keyCode: Int32) -> Action? {
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP: return .volumeUp
        case NX_KEYTYPE_SOUND_DOWN: return .volumeDown
        case NX_KEYTYPE_MUTE: return .mute
        case NX_KEYTYPE_BRIGHTNESS_UP: return .brightnessUp
        case NX_KEYTYPE_BRIGHTNESS_DOWN: return .brightnessDown
        case NX_KEYTYPE_ILLUMINATION_UP: return .backlightUp
        case NX_KEYTYPE_ILLUMINATION_DOWN: return .backlightDown
        default: return nil
        }
    }

    // MARK: - Applying the change

    /// Each of these returns whether the change was actually applied. This runs
    /// inside the event tap, and the tap is on a deadline: take too long and
    /// macOS disables it. So each one resolves the output device once and
    /// reuses it, rather than asking CoreAudio to look it up for every
    /// individual read and write.
    /// Nudge the system volume from outside the event tap, e.g. scrolling
    /// sideways on the closed notch. Shows the same HUD as the volume keys.
    @discardableResult
    func nudgeVolume(by delta: Float) -> Bool {
        adjustVolume(by: delta)
    }

    private func adjustVolume(by delta: Float) -> Bool {
        guard let device = SystemAudio.defaultOutputDevice,
              let current = SystemAudio.volume(of: device)
        else {
            lastError = "No readable audio output device"
            return false
        }
        let next = min(max(current + delta, 0), 1)
        SystemAudio.setVolume(next, on: device)

        var muted = SystemAudio.isMuted(device) ?? false
        if next > 0, muted {
            SystemAudio.setMuted(false, on: device)
            muted = false
        }
        present(.volume, value: next, muted: muted)
        return true
    }

    private func toggleMute() -> Bool {
        guard let device = SystemAudio.defaultOutputDevice else {
            lastError = "No readable audio output device"
            return false
        }
        let muted = !(SystemAudio.isMuted(device) ?? false)
        SystemAudio.setMuted(muted, on: device)
        present(.volume, value: SystemAudio.volume(of: device) ?? 0, muted: muted)
        return true
    }

    private func adjustBrightness(by delta: Float) -> Bool {
        guard let current = DisplayBrightness.value else {
            lastError = "Display brightness is not readable on this Mac"
            return false
        }
        let next = min(max(current + delta, 0), 1)
        DisplayBrightness.value = next
        present(.brightness, value: next, muted: false)
        return true
    }

    private func adjustBacklight(by delta: Float) -> Bool {
        guard let current = KeyboardBacklight.value else {
            lastError = "Keyboard backlight is not readable on this Mac"
            return false
        }
        let next = min(max(current + delta, 0), 1)
        KeyboardBacklight.value = next
        present(.keyboardBacklight, value: next, muted: false)
        return true
    }

    // MARK: - Presentation

    private func present(_ kind: Kind, value: Float, muted: Bool) {
        self.value = value
        isMuted = muted
        if showing != kind { showing = kind }

        // Reuse the notch's own announcement strip rather than inventing a
        // second one.
        if Self.isEnabled(kind) {
            let icon = muted && kind == .volume ? kind.mutedSymbol : kind.symbol
            NotchWindowManager.shared.broadcast { model in
                model.showExpandingView(
                    type: .hud,
                    value: CGFloat(muted && kind == .volume ? 0 : value),
                    icon: icon,
                    duration: 1.4
                )
            }
        }

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.showing = nil }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    /// Drives the HUD from a preview or a test without touching the hardware.
    func injectPreview(_ kind: Kind, value: Float, muted: Bool = false) {
        present(kind, value: value, muted: muted)
    }

    func clearPreview() {
        hideWorkItem?.cancel()
        showing = nil
    }
}

// MARK: - System audio

/// Default output device volume and mute, via CoreAudio. No permissions, no
/// private API.
enum SystemAudio {
    static var defaultOutputDevice: AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    // MARK: Device-scoped

    /// These take the device rather than looking it up, so a caller changing
    /// several properties at once pays for the lookup once.
    static func volume(of device: AudioDeviceID) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    static func setVolume(_ value: Float, on device: AudioDeviceID) {
        var value = value
        var address = volumeAddress
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value
        )
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value == 1 : nil
    }

    static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
        var value: UInt32 = muted ? 1 : 0
        var address = muteAddress
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
        )
    }

    // MARK: Convenience

    /// Kept for callers that touch one property in isolation — diagnostics,
    /// the self-test — where a second device lookup costs nothing.
    static var volume: Float? {
        get { defaultOutputDevice.flatMap(volume(of:)) }
        set {
            guard let device = defaultOutputDevice, let newValue else { return }
            setVolume(newValue, on: device)
        }
    }

    static var isMuted: Bool? {
        get { defaultOutputDevice.flatMap(isMuted(_:)) }
        set {
            guard let device = defaultOutputDevice, let newValue else { return }
            setMuted(newValue, on: device)
        }
    }
}

// MARK: - Display brightness

/// Built-in display brightness through DisplayServices.
///
/// There is no public API for this — `CGDisplaySetDisplayTransferByFormula` is
/// gamma, not backlight. Every app that adjusts a MacBook's screen uses these
/// two symbols; they are looked up at runtime so a future macOS that drops them
/// degrades to "not readable" instead of failing to launch.
enum DisplayBrightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private static let getter: GetBrightness? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private static let setter: SetBrightness? = {
        guard let handle, let symbol = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    static var isAvailable: Bool { getter != nil && setter != nil }

    private static var display: CGDirectDisplayID {
        CGMainDisplayID()
    }

    static var value: Float? {
        get {
            guard let getter else { return nil }
            var brightness: Float = 0
            return getter(display, &brightness) == 0 ? brightness : nil
        }
        set {
            guard let setter, let newValue else { return }
            _ = setter(display, newValue)
        }
    }
}

// MARK: - Keyboard backlight

/// Keyboard backlight through CoreBrightness's `KeyboardBrightnessClient`.
///
/// Also private, also resolved at runtime, and genuinely absent on Macs with no
/// backlit keyboard — in which case this reports nil and the key is passed
/// straight through to macOS.
enum KeyboardBacklight {
    private static let client: AnyObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return nil }
        return cls.init()
    }()

    static var isAvailable: Bool { client != nil && value != nil }

    static var value: Float? {
        get {
            guard let client else { return nil }
            let selector = NSSelectorFromString("brightnessForKeyboard:")
            guard client.responds(to: selector) else { return nil }
            typealias Getter = @convention(c) (AnyObject, Selector, UInt64) -> Float
            guard let method = class_getInstanceMethod(type(of: client), selector) else { return nil }
            let implementation = unsafeBitCast(method_getImplementation(method), to: Getter.self)
            return implementation(client, selector, 1)
        }
        set {
            guard let client, let newValue else { return }
            let selector = NSSelectorFromString("setBrightness:forKeyboard:")
            guard client.responds(to: selector),
                  let method = class_getInstanceMethod(type(of: client), selector)
            else { return }
            typealias Setter = @convention(c) (AnyObject, Selector, Float, UInt64) -> Void
            let implementation = unsafeBitCast(method_getImplementation(method), to: Setter.self)
            implementation(client, selector, newValue, 1)
        }
    }
}
