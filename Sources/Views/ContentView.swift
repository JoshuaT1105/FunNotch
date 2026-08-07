//
//  ContentView.swift
//  FunNotch
//
//  Root of a notch panel. Draws the notch silhouette and swaps between the
//  collapsed live-activity strip and the expanded panel.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        let size = viewModel.contentSize

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Color.black
                if settings.notchTintIntensity > 0 {
                    settings.notchTintColor.opacity(settings.notchTintIntensity * 0.5)
                }
                notchContent
            }
            .frame(width: size.width, height: size.height)
            .clipShape(
                NotchShape(
                    topCornerRadius: viewModel.topCornerRadius,
                    bottomCornerRadius: viewModel.bottomCornerRadius
                )
            )
            .overlay(border)
            .shadow(
                color: .black.opacity(settings.enableShadow && viewModel.notchState == .open ? 0.55 : 0),
                radius: 14,
                y: 6
            )
            // Drops are handled in AppKit by `PassthroughContentView`, which
            // sits above SwiftUI's hit-test gate and registers the exact types
            // Finder actually puts on the pasteboard.
            .onTapGesture {
                if viewModel.notchState == .closed {
                    viewModel.open()
                }
            }
            .opacity(viewModel.hiddenForFullscreen ? 0 : 1)
            .animation(.easeInOut(duration: 0.25), value: viewModel.hiddenForFullscreen)
        }
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .animation(.notchOpen, value: viewModel.notchState)
        .animation(.notchContent, value: size)
    }

    /// A hairline traced along the notch's own outline.
    ///
    /// `strokeBorder` rather than `stroke`: a centred stroke straddles the edge
    /// and the clip eats its outer half, which is what makes hand-rolled
    /// outlines look thin at the sides and thick nowhere in particular. This
    /// one sits wholly inside the silhouette and keeps the same width the whole
    /// way round.
    @ViewBuilder
    private var border: some View {
        if settings.notchBorderEnabled,
           viewModel.notchState == .open || settings.notchBorderWhenClosed {
            NotchOutline(
                topCornerRadius: viewModel.topCornerRadius,
                bottomCornerRadius: viewModel.bottomCornerRadius,
                inset: settings.notchBorderWidth / 2
            )
            .stroke(
                settings.resolvedBorderColor(albumArt: music.artworkColor)
                    .opacity(settings.notchBorderOpacity),
                lineWidth: settings.notchBorderWidth
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var notchContent: some View {
        switch viewModel.notchState {
        case .closed:
            ClosedNotchView()
                .transition(.opacity)
        case .open:
            OpenNotchView()
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
    }
}

// MARK: - Collapsed state

struct ClosedNotchView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leadingActivity
                    .frame(width: insets.leading, height: viewModel.closedNotchSize.height)

                // Dead space behind the physical camera housing.
                Color.clear
                    .frame(width: viewModel.closedNotchSize.width, height: viewModel.closedNotchSize.height)

                trailingActivity
                    .frame(width: insets.trailing, height: viewModel.closedNotchSize.height)
            }

            if viewModel.isShowingDropZone {
                DropZoneHint()
                    .frame(height: 26)
                    .transition(.opacity)
            } else if viewModel.isShowingStandardHUD {
                ActivityStrip(activity: viewModel.expandingView)
                    .frame(height: 34)
                    .transition(.opacity)
            } else if viewModel.isShowingStandardMusicPeek {
                StandardMusicPeek()
                    .frame(height: 34)
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(WidgetWidthKey.self) { widths in
            viewModel.updateMeasuredWidgetWidths(widths)
        }
    }

    private var insets: (leading: CGFloat, trailing: CGFloat) {
        if viewModel.isShowingDropZone {
            return viewModel.closedActivityInsets
        }
        if viewModel.isShowingStandardHUD || viewModel.isShowingStandardMusicPeek {
            let side = max((viewModel.contentSize.width - viewModel.closedNotchSize.width) / 2, 0)
            return (side, side)
        }
        return viewModel.closedActivityInsets
    }

    /// The strip below the notch already carries the artwork and spectrum, so
    /// the row beside the cutout stays empty while it is on screen.
    private var showsSideActivity: Bool {
        viewModel.showsClosedMediaActivity
            && !viewModel.isShowingStandardHUD
            && !viewModel.isShowingStandardMusicPeek
    }

    @ViewBuilder
    private var leadingActivity: some View {
        if viewModel.isShowingDropZone {
            DropZoneGlyph(systemName: "tray.and.arrow.down.fill")
        } else if showsSideActivity, viewModel.isShowingWidgets {
            // Sharing the row: the artwork keeps its place against the cutout
            // and the widgets flank it on the outside.
            HStack(spacing: 0) {
                NotchWidgetStack(widgets: viewModel.activeWidgets.leading, side: .leading)
                ClosedAlbumArt()
                    .frame(width: NotchViewModel.musicActivityInset)
            }
        } else if viewModel.isShowingWidgets {
            NotchWidgetStack(widgets: viewModel.activeWidgets.leading, side: .leading)
        } else if showsSideActivity {
            ClosedAlbumArt()
        } else if viewModel.showsFocusActivity {
            DropZoneGlyph(systemName: "cup.and.saucer.fill")
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingActivity: some View {
        if viewModel.isShowingDropZone {
            DropZoneGlyph(systemName: "plus.circle.fill")
        } else if viewModel.showsFocusActivity {
            ClosedFocusCountdown()
        } else if showsSideActivity, viewModel.isShowingWidgets {
            HStack(spacing: 0) {
                ClosedVisualizer()
                    .frame(width: NotchViewModel.musicActivityInset)
                NotchWidgetStack(widgets: viewModel.activeWidgets.trailing, side: .trailing)
            }
        } else if viewModel.isShowingWidgets {
            NotchWidgetStack(widgets: viewModel.activeWidgets.trailing, side: .trailing)
        } else if showsSideActivity {
            ClosedVisualizer()
        } else {
            EmptyView()
        }
    }
}

/// Countdown shown beside the cutout while a focus session runs.
private struct ClosedFocusCountdown: View {
    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        Text(focus.compactRemainingText)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(settings.accentColor)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Icon shown on either side of the cutout while a drag is in flight.
private struct DropZoneGlyph: View {
    let systemName: String

    @EnvironmentObject private var settings: Settings

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(settings.accentColor)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// The "let go and I'll keep it" label under the widened notch.
private struct DropZoneHint: View {
    @EnvironmentObject private var viewModel: NotchViewModel

    var body: some View {
        Text(viewModel.isDropTargeted ? "Release to add" : "Drop here to keep it")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(viewModel.isDropTargeted ? 1 : 0.6))
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
    }
}

/// Album art shown to the left of the cutout while something is playing.
private struct ClosedAlbumArt: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        Group {
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    )
            }
        }
        .frame(
            width: MusicPlayerImageSizes.size.closed.width,
            height: MusicPlayerImageSizes.size.closed.height
        )
        .clipShape(RoundedRectangle(cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed))
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// The spectrum bars shown to the right of the cutout.
private struct ClosedVisualizer: View {
    @EnvironmentObject private var settings: Settings
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        MusicVisualizer(
            isPlaying: music.isPlaying,
            color: settings.coloredSpectrogram
                ? settings.spectrumColor.resolved(albumArt: music.artworkColor, accent: settings.accentColor)
                : .white
        )
        .frame(width: 18, height: 14)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
