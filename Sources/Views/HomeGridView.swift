//
//  HomeGridView.swift
//  FunNotch
//
//  Renders the home tab from the user's tile layout.
//

import SwiftUI

struct HomeGridView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var focus = FocusManager.shared
    @ObservedObject private var battery = BatteryManager.shared
    @ObservedObject private var calendar = CalendarManager.shared

    var body: some View {
        // Conditions are evaluated here rather than inside each tile so a tile
        // that is not shown is never built, and the row divides its width
        // between what is actually visible.
        let tiles = settings.homeTiles.filter {
            TileConditionEvaluator.isSatisfied($0.condition,
                                               notchIsOpen: viewModel.notchState == .open)
        }
        let top = HomeLayout.tiles(in: tiles, row: 0)
        let bottom = HomeLayout.tiles(in: tiles, row: 1)

        // Widths are arithmetic, not measurement. The open notch is a fixed
        // 690 points wide with 22 of padding either side, so the row already
        // knows how much space it has and nothing needs to ask.
        //
        // Both of the obvious alternatives were tried and both hung: a
        // GeometryReader wants to fill a container that is sizing itself to its
        // content, so the two waited on each other and SwiftUI recursed until
        // it locked up; a custom Layout broke the recursion but then ground
        // through hundreds of re-measurements of the album art and canvases.
        VStack(spacing: (top.isEmpty || bottom.isEmpty) ? 0 : 8) {
            if !top.isEmpty {
                row(top, spacing: 14)
                    .frame(maxHeight: .infinity)
            }
            if !bottom.isEmpty {
                row(bottom, spacing: 6)
                    .frame(height: 46)
            }
        }
        .padding(.top, 10)
    }

    /// Width available to a row inside the open notch.
    private static let rowWidth = openNotchSize.width - 44

    private func row(_ tiles: [HomeTile], spacing: CGFloat) -> some View {
        let total = max(tiles.reduce(0) { $0 + CGFloat($1.span) }, 1)
        let available = Self.rowWidth - spacing * CGFloat(max(tiles.count - 1, 0))
        return HStack(alignment: .top, spacing: spacing) {
            ForEach(tiles) { tile in
                HomeTileView(tile: tile)
                    .frame(width: max(available * CGFloat(tile.span) / total, 24))
            }
        }
        .frame(width: Self.rowWidth, alignment: .leading)
    }
}

/// One tile. Compact kinds get the strip's boxed chrome; large ones are drawn
/// bare, because a box around the album art would be a box inside a box.
struct HomeTileView: View {
    let tile: HomeTile

    var body: some View {
        switch tile.kind {
        case .nowPlaying:
            NowPlayingTile()
        case .weather:
            WeatherPane()
        case .calendar:
            CalendarPane()
        case .mirror:
            MirrorPane()
        case .agents:
            AgentSessionsTile()
        case .notes:
            NotesView()
        case .timer:
            TimerView()
        default:
            HomePanelChrome {
                HomeStripPanel(tile: tile)
            }
        }
    }
}

/// Album art and transport, or the weather when nothing is playing — the
/// behaviour the home tab had before it was configurable.
private struct NowPlayingTile: View {
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        if music.track.isEmpty, settings.showWeatherWhenIdle {
            WeatherPane()
        } else {
            HStack(alignment: .top, spacing: 14) {
                AlbumArtwork()
                PlayerControls()
                    .frame(minWidth: 150)
            }
        }
    }
}
