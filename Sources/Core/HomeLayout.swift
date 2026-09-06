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
        default:            return 2
        }
    }

    /// Below this a tile has nothing left to show but a label.
    var minimumSpan: Int {
        switch self {
        case .nowPlaying, .weather, .agents: return 3
        case .calendar, .notes, .timer, .clipboard: return 2
        default: return 1
        }
    }

    /// Only "Open app" makes sense more than once, since each points somewhere
    /// different. The rest would simply say the same thing twice.
    var allowsDuplicates: Bool { self == .openApp }
}

/// One tile on the grid.
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
        return HomeTile(kind: kind, row: row, span: max(span, kind.minimumSpan), appPath: path)
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

    static func tiles(in layout: [HomeTile], row: Int) -> [HomeTile] {
        layout.filter { $0.row == row }
    }
}
