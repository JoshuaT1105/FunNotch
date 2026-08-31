//
//  OpenNotchView.swift
//  FunNotch
//
//  The expanded panel: a header that straddles the camera housing, then either
//  the home view (player, agenda, mirror) or the shelf.
//

import AppKit
import SwiftUI

struct OpenNotchView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(spacing: 0) {
            NotchHeader()
                .frame(height: max(viewModel.closedNotchSize.height, 30))

            Group {
                switch viewModel.currentTab {
                case .home:
                    NotchHomeView()
                case .shelf:
                    ShelfView()
                case .clipboard:
                    ClipboardView()
                case .focus:
                    FocusView()
                case .notes:
                    NotesView()
                case .timer:
                    TimerView()
                case .game:
                    // Belt and braces: the tab is already gone from the header
                    // during a session, but nothing should be able to land here
                    // and start a game anyway.
                    if FocusManager.shared.isActive {
                        GameBlockedDuringFocus()
                    } else {
                        GameView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        // Generous insets so nothing runs into the rounded corners.
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
        .animation(.notchContent, value: viewModel.currentTab)
    }
}

/// Stands in for the game while a focus session is running.
private struct GameBlockedDuringFocus: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @ObservedObject private var focus = FocusManager.shared

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.7))
            Text("Not while you're focusing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text("Notch Breakout comes back in \(focus.compactRemainingText).")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Button("Take me to the timer") {
                withAnimation(.notchContent) { viewModel.currentTab = .focus }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Header row. The middle is left empty so nothing ever hides behind the camera.
struct NotchHeader: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var focus = FocusManager.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(availableTabs) { tab in
                    TabChip(
                        tab: tab,
                        isSelected: viewModel.currentTab == tab,
                        // The header shares its row with the camera cutout, so
                        // labels only fit while there are few enough tabs.
                        showsLabel: settings.tileShowLabels
                            || (viewModel.currentTab == tab && availableTabs.count <= 4)
                    ) {
                        withAnimation(.notchContent) { viewModel.currentTab = tab }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Reserved space for the physical cutout.
            Color.clear.frame(width: viewModel.closedNotchSize.width)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                if settings.showBatteryIndicator {
                    BatteryPill()
                }

                if settings.settingsIconInNotch {
                    HoverButton(systemName: "gearshape", size: 13, padding: 5) {
                        SettingsWindowController.shared.show()
                        viewModel.close()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var availableTabs: [NotchTab] {
        NotchTab.allCases.filter { tab in
            switch tab {
            case .shelf: return settings.shelfEnabled
            case .clipboard: return settings.clipboardHistoryEnabled
            case .notes: return settings.showNotes
            case .timer: return settings.showTimer
            // A focus session is a promise not to get distracted, and a game in
            // the notch is the most distracting thing in here.
            case .game: return settings.showGame && !FocusManager.shared.isActive
            default: return true
            }
        }
    }
}

private struct TabChip: View {
    let tab: NotchTab
    let isSelected: Bool
    let showsLabel: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 11, weight: .medium))
                if showsLabel {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(isSelected ? 0.18 : (isHovering ? 0.1 : 0)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

// MARK: - Home

struct NotchHomeView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        VStack(spacing: 8) {
            main
            HomeStripView()
                .frame(height: 46)
        }
        .padding(.top, 10)
    }

    private var main: some View {
        HStack(alignment: .top, spacing: 14) {
            // With nothing playing, the artwork and transport are an empty
            // rectangle with a placeholder note in it. Weather is a better use
            // of the same space, and it goes away the moment music starts.
            if music.track.isEmpty, settings.showWeatherWhenIdle {
                WeatherPane()
                    .frame(minWidth: 232, maxWidth: .infinity)
                    .frame(height: 96)
            } else {
                AlbumArtwork()
                PlayerControls()
                    .frame(minWidth: 170)
            }

            if settings.showCalendar {
                CalendarPane()
                    .frame(width: 186)
            }

            if settings.showMirror {
                MirrorPane()
                    .frame(width: 96)
            }
        }
    }
}

private struct AlbumArtwork: View {
    @ObservedObject private var music = MusicManager.shared
    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    private let side = MusicPlayerImageSizes.size.opened.width

    var body: some View {
        Button {
            music.openPlayingApp()
        } label: {
            ZStack {
                if let artwork = music.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if isHovering {
                    Color.black.opacity(0.45)
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened))
            .overlay(
                RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .disabled(music.track.bundleIdentifier == nil)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { isHovering = hovering }
        }
        .overlay(alignment: .bottomTrailing) {
            if let icon = music.sourceAppIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(x: 5, y: 5)
                    .shadow(radius: 2)
            }
        }
    }
}

private struct PlayerControls: View {
    @ObservedObject private var music = MusicManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if music.track.isEmpty {
                emptyState
            } else {
                MarqueeText(text: music.track.title, font: .system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                MarqueeText(text: music.track.artist, font: .system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))

                if music.track.hasTiming {
                    scrubber
                } else {
                    noTimingHint
                }
                transport
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing playing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(hintText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private var hintText: String {
        if music.isNowPlayingDeprecated, settings.mediaController == .nowPlaying {
            return "macOS no longer exposes system-wide Now Playing. Pick Music or Spotify in Settings."
        }
        return "Start playing something in \(settings.mediaController.rawValue)."
    }

    /// Shown instead of the scrubber when the backend cannot report a
    /// position — a browser tab whose page we are not allowed to query. It
    /// stays on one line and leads somewhere, rather than being a paragraph of
    /// instructions sitting permanently under every track.
    @ViewBuilder
    private var noTimingHint: some View {
        if !settings.showPageAccessHint {
            // Switched off in settings: leave the space blank rather than
            // repeating something the user has already said they know about.
            Color.clear.frame(height: 20)
        } else if music.activeControllerType == .browser {
            Button {
                SettingsWindowController.shared.show(tab: .media)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text("Turn on page access for progress")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        } else {
            Text("No position reported")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.vertical, 6)
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            NotchSlider(
                value: Binding(
                    get: { music.displayedElapsed },
                    set: { music.displayedElapsed = $0 }
                ),
                range: 0 ... max(music.track.duration, 1),
                color: sliderColor,
                height: 4,
                isEnabled: music.track.duration > 0,
                onEditingChanged: { editing in
                    music.isScrubbing = editing
                    if !editing {
                        music.seek(to: music.displayedElapsed)
                    }
                }
            )
            .frame(height: 12)

            HStack {
                Text(music.displayedElapsed.playbackTimestamp)
                Spacer()
                Text(max(music.track.duration - music.displayedElapsed, 0).playbackTimestamp)
            }
            .font(.system(size: 9))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 2)
    }

    private var sliderColor: Color {
        settings.sliderColor.resolved(albumArt: music.artworkColor, accent: settings.accentColor)
    }

    private var transport: some View {
        HStack(spacing: 2) {
            if settings.showShuffleAndRepeat {
                HoverButton(
                    systemName: "shuffle",
                    size: 12,
                    padding: 5,
                    isActive: music.track.isShuffled,
                    tint: settings.accentColor
                ) { music.toggleShuffle() }
            }

            Spacer(minLength: 0)

            HoverButton(systemName: "backward.fill", size: 14, padding: 6) {
                music.previousTrack()
            }

            HoverButton(
                systemName: music.isPlaying ? "pause.fill" : "play.fill",
                size: 18,
                padding: 7
            ) { music.togglePlayPause() }

            HoverButton(systemName: "forward.fill", size: 14, padding: 6) {
                music.nextTrack()
            }

            Spacer(minLength: 0)

            if settings.showShuffleAndRepeat {
                HoverButton(
                    systemName: music.track.repeatMode.symbol,
                    size: 12,
                    padding: 5,
                    isActive: music.track.repeatMode != .off,
                    tint: settings.accentColor,
                    badge: music.track.repeatMode.badge
                ) { music.cycleRepeat() }
            }
        }
    }
}

// MARK: - Mirror

private struct MirrorPane: View {
    @ObservedObject private var webcam = WebcamManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        Group {
            if webcam.isRunning {
                CameraPreview(session: webcam.session)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    VStack(spacing: 5) {
                        Image(systemName: webcam.hasCamera ? "web.camera" : "video.slash")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(webcam.hasCamera ? "Mirror" : "No camera")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(mirrorShape)
        .overlay(mirrorShape.stroke(Color.white.opacity(0.1), lineWidth: 1))
        .onAppear { webcam.start() }
        .onDisappear { webcam.stop() }
    }

    private var mirrorShape: AnyShape {
        settings.mirrorShape == .circle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 12))
    }
}
