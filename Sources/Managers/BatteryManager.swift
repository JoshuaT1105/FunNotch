//
//  BatteryManager.swift
//  FunNotch
//
//  Reads the power source over IOKit and turns plug/unplug events into a notch
//  live activity.
//

import AppKit
import Combine
import IOKit.ps
import SwiftUI

@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    @Published private(set) var level: Float = 1.0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isCharged = false
    @Published private(set) var isLowPowerMode = false
    @Published private(set) var hasBattery = false
    /// Minutes remaining, or nil while the estimate is still being calculated.
    @Published private(set) var timeRemaining: Int?

    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var lastPluggedState: Bool?

    private init() {}

    func start() {
        // IOKit calls back whenever the power source changes.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { manager.refresh() }
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        // The notification does not fire for slow percentage drift.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }

        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        refresh(announce: false)
    }

    func refresh(announce: Bool = true) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                as? [String: Any] else { continue }
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            hasBattery = true

            let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            level = maximum > 0 ? Float(capacity) / Float(maximum) : 0

            isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String
            isPluggedIn = state == kIOPSACPowerValue

            let minutes = isCharging
                ? description[kIOPSTimeToFullChargeKey] as? Int
                : description[kIOPSTimeToEmptyKey] as? Int
            timeRemaining = (minutes ?? -1) > 0 ? minutes : nil

            break
        }

        guard announce else {
            lastPluggedState = isPluggedIn
            return
        }

        if let previous = lastPluggedState, previous != isPluggedIn {
            announcePowerChange()
        }
        lastPluggedState = isPluggedIn
    }

    private func announcePowerChange() {
        guard Settings.shared.showPowerStatusNotifications else { return }
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showExpandingView(
                type: .battery,
                value: CGFloat(level),
                icon: isPluggedIn ? "battery.100.bolt" : "battery.50",
                duration: 3.0
            )
        }
    }

    /// SF Symbol matching the current charge, mirroring the menu bar's icon set.
    var symbolName: String {
        if isCharging || (isPluggedIn && !isCharged) { return "battery.100.bolt" }
        if isPluggedIn && isCharged { return "battery.100.bolt" }
        switch level {
        case ..<0.10: return "battery.0"
        case ..<0.30: return "battery.25"
        case ..<0.60: return "battery.50"
        case ..<0.85: return "battery.75"
        default: return "battery.100"
        }
    }

    var indicatorColor: Color {
        if isCharging || isPluggedIn { return .green }
        if isLowPowerMode { return .yellow }
        if level <= 0.10 { return .red }
        if level <= 0.20 { return .orange }
        return .white
    }

    var percentageText: String {
        "\(Int(round(level * 100)))%"
    }

    var timeRemainingText: String? {
        guard let timeRemaining else { return nil }
        let hours = timeRemaining / 60
        let minutes = timeRemaining % 60
        let suffix = isCharging ? "until full" : "remaining"
        if hours > 0 {
            return "\(hours)h \(minutes)m \(suffix)"
        }
        return "\(minutes)m \(suffix)"
    }
}
