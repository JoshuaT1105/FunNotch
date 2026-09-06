//
//  TileConditionEvaluator.swift
//  FunNotch
//
//  Picks which layout the home tab should be showing.
//

import Foundation
import SwiftUI

@MainActor
enum LayoutCaseResolver {
    /// How long before a video meeting the meeting layout takes over.
    static let meetingLeadTime: TimeInterval = 10 * 60

    /// The most specific case that both applies and has a layout of its own.
    /// A case the user has not customised is skipped rather than showing an
    /// empty notch.
    static func active(settings: Settings) -> LayoutCase {
        for candidate in LayoutCase.priority
        where isSatisfied(candidate) && settings.homeTiles(for: candidate) != nil {
            return candidate
        }
        return .standard
    }

    static func isSatisfied(_ layoutCase: LayoutCase) -> Bool {
        switch layoutCase {
        case .standard:     return true
        case .mediaPlaying: return MusicManager.shared.isPlaying
        case .meetingSoon:  return meetingIsImminent
        case .focusActive:  return FocusManager.shared.isActive
        case .charging:     return BatteryManager.shared.isPluggedIn
        }
    }

    /// True when the next agenda item is a video call starting shortly, or one
    /// already under way.
    ///
    /// Only items with a real meeting link count. This layout exists so you can
    /// check your camera before you appear on it, and a dentist reminder is not
    /// that.
    private static var meetingIsImminent: Bool {
        guard let next = CalendarManager.shared.nextItem,
              next.meetingURL != nil,
              !next.isSample,
              let start = next.start
        else { return false }

        let untilStart = start.timeIntervalSinceNow
        if untilStart > meetingLeadTime { return false }
        if let end = next.end, Date() > end { return false }
        return untilStart > -3600
    }
}
