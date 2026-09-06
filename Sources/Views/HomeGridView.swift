//
//  HomeGridView.swift
//  FunNotch
//
//  Renders the home tab from the user's tile layout.
//

import SwiftUI

struct HomeGridView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        let tiles = settings.homeTiles
        let top = HomeLayout.tiles(in: tiles, row: 0)
        let bottom = HomeLayout.tiles(in: tiles, row: 1)

        VStack(spacing: 8) {
            if !top.isEmpty {
                row(top, spacing: 14)
            }
            if !bottom.isEmpty {
                row(bottom, spacing: 6)
                    .frame(height: 46)
            }
        }
        .padding(.top, 10)
    }

    private func row(_ tiles: [HomeTile], spacing: CGFloat) -> some View {
        GeometryReader { geo in
            let total = tiles.reduce(0) { $0 + CGFloat($1.span) }
            let available = geo.size.width - spacing * CGFloat(max(tiles.count - 1, 0))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(tiles) { tile in
                    HomeTileView(tile: tile)
                        .frame(width: available * CGFloat(tile.span) / total)
                }
            }
        }
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
