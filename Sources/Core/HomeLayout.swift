//
//  HomeLayout.swift
//  FunNotch
//
//  The home tab as a user-composed grid.
//
//  Two rows of tiles. Each tile declares a span, and a row divides its width
//  between its tiles in proportion to those spans — so "resize" is a matter of
//  giving a tile more of the row rather than dragging pixel edges, which is the
//  only thing that works in a space this small.
//

import Foundation
import SwiftUI

/// Everything that can be dropped on the home screen.
enum HomeTileKind: String, CaseIterable, Identifiable {
    // Large tiles, at home in the top row.
    case nowPlaying = "Now playing"
    case weather = "Weather"
    case calendar = "Calendar"
    case mirror = "Camera mirror"
    case agents = "Agent sessions"
    case notes = "Note"
    case timer = "Timer"

    // Compact tiles, at home in the bottom row.
    case quickActions = "Quick actions"
    case systemStats = "System stats"
    case battery = "Battery"
    case devices = "Device batteries"
    case focusStreak = "Focus streak"
    case recentShelf = "Recent files"
    case clipboard = "Last copied"
    case wifi = "Wi-Fi"
    case openApp = "Open app"
    case mediaScrubber = "Media scrubber"
    case nextEvent = "Next event"
    case diskSpace = "Disk space"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .nowPlaying:   return "music.note"
        case .weather:      return "cloud.sun.fill"
        case .calendar:     return "calendar"
        case .mirror:       return "person.crop.square"
        case .agents:       return "sparkle"
        case .notes:        return "note.text"
        case .timer:        return "timer"
        case .quickActions: return "bolt.fill"
        case .systemStats:  return "waveform.path.ecg"
        case .battery:      return "battery.75"
        case .devices:      return "airpods"
        case .focusStreak:  return "flame.fill"
        case .recentShelf:  return "tray.full"
        case .clipboard:    return "doc.on.clipboard"
        case .wifi:         return "wifi"
        case .openApp:      return "app.badge"
        case .mediaScrubber: return "waveform"
        case .nextEvent:    return "calendar.badge.clock"
        case .diskSpace:    return "internaldrive"
        }
    }

    /// Which row this belongs in by default. Nothing stops a tile being put in
    /// the other row; this only decides where a freshly added one lands.
    var naturalRow: Int {
        switch self {
        case .nowPlaying, .weather, .calendar, .mirror, .agents, .notes, .timer:
            return 0
        default:
            return 1
        }
    }

    var defaultSpan: Int {
        switch self {
        case .nowPlaying:   return 6
        case .weather:      return 5
        case .calendar:     return 3
        case .agents:       return 4
        case .notes, .timer: return 4
        case .mirror:       return 2
        case .quickActions, .systemStats, .clipboard: return 2
        case .openApp:      return 1
        case .mediaScrubber: return 3
        case .nextEvent:    return 2
        default:            return 2
        }
    }

    /// Below this a tile has nothing left to show but a label.
    var minimumSpan: Int {
        switch self {
        case .nowPlaying, .weather, .agents: return 3
        case .calendar, .notes, .timer, .clipboard, .mediaScrubber: return 2
        default: return 1
        }
    }

    /// Only "Open app" makes sense more than once, since each points somewhere
    /// different. The rest would simply say the same thing twice.
    var allowsDuplicates: Bool { self == .openApp }
}

/// A situation the notch can have its own layout for.
///
/// Modelled as whole layouts rather than a condition on each tile. "While media
/// is playing, show me this instead" is a different notch, not the same notch
/// with two things hidden — and editing it as a notch is far easier to reason
/// about than reading a condition off every tile in turn.
enum LayoutCase: String, CaseIterable, Identifiable {
    case standard = "Default"
    case meetingSoon = "Before a meeting"
    case mediaPlaying = "Media playing"
    case focusActive = "Focus session"
    case charging = "Charging"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .standard:     return "house"
        case .meetingSoon:  return "video.fill"
        case .mediaPlaying: return "play.fill"
        case .focusActive:  return "cup.and.saucer.fill"
        case .charging:     return "bolt.fill"
        }
    }

    var explanation: String {
        switch self {
        case .standard:     return "Whenever nothing more specific applies."
        case .meetingSoon:  return "In the ten minutes before a calendar event with a video link, and while it runs."
        case .mediaPlaying: return "While something is playing."
        case .focusActive:  return "During a focus session."
        case .charging:     return "While plugged in."
        }
    }

    /// Checked in this order, so the most specific situation wins. A meeting
    /// beats music, because you are about to be on camera either way.
    static var priority: [LayoutCase] {
        [.meetingSoon, .focusActive, .mediaPlaying, .charging]
    }
}

/// One tile on the grid./// One tile on the grid.
struct HomeTile: Identifiable, Equatable {
    let id: UUID
    var kind: HomeTileKind
    var row: Int
    var span: Int
    /// Path of the app to launch, for `.openApp`.
    var appPath: String?

    init(id: UUID = UUID(), kind: HomeTileKind, row: Int? = nil,
         span: Int? = nil, appPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.row = row ?? kind.naturalRow
        self.span = span ?? kind.defaultSpan
        self.appPath = appPath
    }

    var appName: String? {
        appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
    }

    /// `kind ␟ row ␟ span ␟ path`, so the whole layout is a plain string array
    /// in preferences and stays readable in `defaults read`.
    var encoded: String {
        [kind.rawValue, String(row), String(span), appPath ?? ""]
            .joined(separator: "\u{1F}")
    }

    static func decode(_ raw: String) -> HomeTile? {
        let parts = raw.components(separatedBy: "\u{1F}")
        guard let kind = HomeTileKind(rawValue: parts.first ?? "") else { return nil }
        let row = parts.count > 1 ? Int(parts[1]) ?? kind.naturalRow : kind.naturalRow
        let span = parts.count > 2 ? Int(parts[2]) ?? kind.defaultSpan : kind.defaultSpan
        let path = parts.count > 3 && !parts[3].isEmpty ? parts[3] : nil
        // A fifth field is a per-tile condition from the version before cases
        // existed. It is ignored rather than rejected, so an old layout still
        // loads instead of silently reverting to the default.
        return HomeTile(kind: kind, row: row, span: max(span, kind.minimumSpan),
                        appPath: path)
    }
}

enum HomeLayout {
    /// What the home tab looked like before it was configurable. Kept exactly,
    /// because "reset" has to mean something specific and this is what people
    /// already know.
    static var `default`: [HomeTile] {
        [
            HomeTile(kind: .nowPlaying, row: 0, span: 6),
            HomeTile(kind: .calendar, row: 0, span: 3),
            HomeTile(kind: .mirror, row: 0, span: 2),
            HomeTile(kind: .quickActions, row: 1, span: 2),
            HomeTile(kind: .systemStats, row: 1, span: 2),
            HomeTile(kind: .battery, row: 1, span: 2)
        ]
    }

    /// What a case starts as when you first give it its own layout. Better
    /// than an empty notch, which is a blank page problem.
    static func starter(for layoutCase: LayoutCase) -> [HomeTile] {
        switch layoutCase {
        case .standard:
            return `default`
        case .meetingSoon:
            return [
                HomeTile(kind: .mirror, row: 0, span: 4),
                HomeTile(kind: .calendar, row: 0, span: 5),
                HomeTile(kind: .quickActions, row: 1, span: 2),
                HomeTile(kind: .battery, row: 1, span: 2)
            ]
        case .mediaPlaying:
            return [
                HomeTile(kind: .nowPlaying, row: 0, span: 8),
                HomeTile(kind: .calendar, row: 0, span: 3),
                HomeTile(kind: .mediaScrubber, row: 1, span: 3),
                HomeTile(kind: .battery, row: 1, span: 2)
            ]
        case .focusActive:
            return [
                HomeTile(kind: .timer, row: 0, span: 6),
                HomeTile(kind: .agents, row: 0, span: 5),
                HomeTile(kind: .focusStreak, row: 1, span: 2),
                HomeTile(kind: .systemStats, row: 1, span: 2)
            ]
        case .charging:
            return [
                HomeTile(kind: .nowPlaying, row: 0, span: 6),
                HomeTile(kind: .calendar, row: 0, span: 5),
                HomeTile(kind: .battery, row: 1, span: 3),
                HomeTile(kind: .devices, row: 1, span: 2)
            ]
        }
    }

    static func tiles(in layout: [HomeTile], row: Int) -> [HomeTile] {
        layout.filter { $0.row == row }
    }
}
