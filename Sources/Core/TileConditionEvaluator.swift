//
//  TileConditionEvaluator.swift
//  FunNotch
//
//  Decides whether a tile's condition is currently met.
//

import Foundation
import SwiftUI

@MainActor
enum TileConditionEvaluator {
    /// How long before a video meeting the "before a meeting" tiles appear.
    static let meetingLeadTime: TimeInterval = 10 * 60

    static func isSatisfied(_ condition: TileCondition, notchIsOpen: Bool) -> Bool {
        switch condition {
        case .always:
            return true
        case .mediaPlaying:
            return MusicManager.shared.isPlaying
        case .mediaIdle:
            return !MusicManager.shared.isPlaying
        case .meetingSoon:
            return meetingIsImminent
        case .notchOpen:
            return notchIsOpen
        case .focusActive:
            return FocusManager.shared.isActive
        case .charging:
            return BatteryManager.shared.isCharging || BatteryManager.shared.isPluggedIn
        case .onBattery:
            return !BatteryManager.shared.isPluggedIn
        }
    }

    /// True when the next agenda item is a video call starting shortly, or one
    /// that has already started and is presumably still running.
    ///
    /// Only items with a real meeting link count. "Before a meeting" is about
    /// checking your camera before you appear on it, and a dentist reminder is
    /// not that.
    private static var meetingIsImminent: Bool {
        guard let next = CalendarManager.shared.nextItem,
              next.meetingURL != nil,
              !next.isSample,
              let start = next.start
        else { return false }

        let untilStart = start.timeIntervalSinceNow
        if untilStart > meetingLeadTime { return false }
        // Still counted as imminent while the meeting runs, up to its end.
        if let end = next.end, Date() > end { return false }
        return untilStart > -3600
    }
}
