//
//  NotchViewModel.swift
//  FunNotch
//
//  One instance backs one notch window. It owns the open/closed state, the
//  measured geometry for its display, and the transient "sneak peek" and HUD
//  overlays that the collapsed notch shows.
//

import AppKit
import Combine
import SwiftUI

/// A transient message shown in the collapsed notch (track change, HUD, …).
struct SneakPeek: Equatable {
    var show: Bool = false
    var type: SneakContentType = .none
    var value: CGFloat = 0
    var icon: String = ""
}

@MainActor
final class NotchViewModel: ObservableObject {
    /// Identifier of the display this notch is pinned to.
    let screenIdentifier: String

    @Published private(set) var notchState: NotchState = .closed
    @Published var currentTab: NotchTab = .home

    /// Collapsed measurements for this display.
    @Published var closedNotchSize: CGSize = CGSize(width: 185, height: 32)

    /// True while the pointer is inside the notch's hover region.
    @Published var isHovering: Bool = false

    /// A drag is in flight somewhere on screen, so the notch offers a drop target.
    @Published var dragDetectorTargeting: Bool = false
    @Published var isDropTargeted: Bool = false

    /// Hidden because fullscreen media is playing on this display.
    @Published var hiddenForFullscreen: Bool = false

    @Published var sneakPeek = SneakPeek()
    @Published var expandingView = SneakPeek()

    /// Set while the notch should refuse to close (menus, popovers, drags).
    @Published var pinnedOpen: Bool = false

    private var hoverWorkItem: DispatchWorkItem?
    private var closeWorkItem: DispatchWorkItem?
    private var sneakPeekWorkItem: DispatchWorkItem?
    private var expandingViewWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private let settings = Settings.shared

    /// True when the collapsed notch should widen to show album art and the
    /// spectrum on either side of the hardware cutout.
    @Published private(set) var showsMusicActivity = false

    /// Mirrored from the focus manager so geometry can react to it.
    @Published private(set) var focusIsActive = false

    /// What the on-screen widgets reported they need, per side.
    @Published private(set) var measuredWidgetWidths: [NotchSide: CGFloat] = [:]

    init(screen: NSScreen?) {
        screenIdentifier = screen?.displayIdentifier ?? ""
        closedNotchSize = measureClosedNotch(for: screen)

        NotificationCenter.default.publisher(for: .notchGeometryChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshGeometry() }
            .store(in: &cancellables)

        MusicManager.shared.$track
            .receive(on: RunLoop.main)
            .sink { [weak self] track in
                guard let self else { return }
                let shouldShow = !track.isEmpty
                guard shouldShow != self.showsMusicActivity else { return }
                withAnimation(.notchContent) { self.showsMusicActivity = shouldShow }
            }
            .store(in: &cancellables)

        FocusManager.shared.$isActive
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                guard let self, self.focusIsActive != active else { return }
                withAnimation(.notchContent) { self.focusIsActive = active }
                // Starting a session while the game is open would otherwise
                // leave it running behind a tab that no longer exists.
                if active, self.currentTab == .game {
                    withAnimation(.notchContent) { self.currentTab = .focus }
                }
            }
            .store(in: &cancellables)
    }

    var screen: NSScreen? {
        NSScreen.screen(withIdentifier: screenIdentifier) ?? NSScreen.main
    }

    func refreshGeometry() {
        closedNotchSize = measureClosedNotch(for: screen)
    }

    // MARK: - Open / close

    func open() {
        guard notchState == .closed else { return }
        cancelPendingClose()
        withAnimation(.notchOpen) {
            notchState = .open
        }
        if settings.openShelfByDefault, settings.shelfEnabled, dragDetectorTargeting {
            currentTab = .shelf
        }
        performHaptic()
    }

    func close() {
        guard notchState == .open else { return }
        guard !pinnedOpen else { return }
        withAnimation(.notchClose) {
            notchState = .closed
        }
        // Reset back to the default tab so the next open is predictable,
        // unless the user has asked for the last tab to be remembered.
        if !settings.rememberLastTab {
            currentTab = .home
        }
        sneakPeek.show = false
    }

    func toggle() {
        notchState == .open ? close() : open()
    }

    // MARK: - Hover driven behaviour

    /// Called by the mouse tracker whenever the pointer enters or leaves the
    /// notch's active region.
    func setHovering(_ hovering: Bool) {
        guard isHovering != hovering else { return }
        isHovering = hovering

        if hovering {
            cancelPendingClose()
            guard settings.openNotchOnHover, notchState == .closed else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.open()
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.minimumHoverDuration, execute: work)
        } else {
            hoverWorkItem?.cancel()
            hoverWorkItem = nil
            guard notchState == .open, !pinnedOpen else { return }
            // Small grace period so brushing past the edge does not slam it shut.
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isHovering else { return }
                self.close()
            }
            closeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }

    /// Sets state directly, bypassing animation. Used by the snapshot renderer.
    func setPreviewState(_ state: NotchState) {
        notchState = state
    }

    /// Forces the music live activity on, for snapshots.
    func setPreviewMusicActivity(_ visible: Bool) {
        showsMusicActivity = visible
    }

    /// Forces the focus live activity on, for snapshots.
    func setPreviewFocusActivity(_ active: Bool) {
        focusIsActive = active
    }

    private func cancelPendingClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    private func performHaptic() {
        guard settings.enableHaptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Transient overlays

    /// Shows the compact "now playing" peek shown on track changes.
    func showSneakPeek(type: SneakContentType, value: CGFloat = 0, icon: String = "", duration: Double? = nil) {
        sneakPeekWorkItem?.cancel()
        withAnimation(.smooth) {
            sneakPeek = SneakPeek(show: true, type: type, value: value, icon: icon)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) { self?.sneakPeek.show = false }
        }
        sneakPeekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (duration ?? settings.waitInterval), execute: work)
    }

    /// Shows the wider HUD strip used for volume / brightness / backlight.
    func showExpandingView(type: SneakContentType, value: CGFloat, icon: String, duration: Double = 2.0) {
        expandingViewWorkItem?.cancel()
        withAnimation(.smooth) {
            expandingView = SneakPeek(show: true, type: type, value: value, icon: icon)
        }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) { self?.expandingView.show = false }
        }
        expandingViewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // MARK: - Derived geometry

    /// Width added on each side of the cutout for the music live activity.
    static let musicActivityInset: CGFloat = MusicPlayerImageSizes.size.closed.width + 12
    /// Width the countdown needs beside the cutout.
    static let focusActivityInset: CGFloat = 46

    /// True when the announcement strip is showing below the cutout.
    var isShowingStandardHUD: Bool {
        expandingView.show && notchState == .closed
    }

    /// True when the notch is standing in as a drop target for a live drag.
    /// A drag is an active gesture, so it outranks any transient HUD.
    var isShowingDropZone: Bool {
        notchState == .closed && dragDetectorTargeting && settings.shelfEnabled
    }

    /// True when the collapsed notch is carrying the focus countdown.
    var showsFocusActivity: Bool {
        focusIsActive && settings.focusShowInClosedNotch
    }

    /// True when the peek strip below the cutout is showing a track change.
    var isShowingStandardMusicPeek: Bool {
        sneakPeek.show && sneakPeek.type == .music && settings.sneakPeekStyle == .standard
    }

    /// The widgets to show beside the cutout right now, if any.
    var activeWidgets: (leading: [NotchWidget], trailing: [NotchWidget]) {
        guard notchState == .closed, settings.idleWidgetsEnabled else { return ([], []) }
        return (settings.idleLeftWidgets, settings.idleRightWidgets)
    }

    /// Whether the artwork and spectrum take their places beside the cutout.
    /// Something can be playing without them being drawn — the user may have
    /// handed that space to the widgets instead.
    var showsClosedMediaActivity: Bool {
        showsMusicActivity && settings.closedMediaDisplay.showsMedia
    }

    /// Widgets only get the stage when nothing more urgent is using it — except
    /// for music, where the user decides who yields.
    var isShowingWidgets: Bool {
        guard notchState == .closed else { return false }
        guard !isShowingDropZone, !isShowingStandardHUD else { return false }
        guard !isShowingStandardMusicPeek else { return false }

        let widgets = activeWidgets
        guard !widgets.leading.isEmpty || !widgets.trailing.isEmpty else { return false }

        // A focus countdown still wins outright; it owns the right-hand side.
        guard !showsFocusActivity else { return false }
        guard showsMusicActivity else { return true }
        return settings.closedMediaDisplay.showsWidgets
    }

    /// Space taken beside the cutout by the live activities, left and right.
    var closedActivityInsets: (leading: CGFloat, trailing: CGFloat) {
        if isShowingDropZone { return (110, 110) }

        var leading: CGFloat = 0
        var trailing: CGFloat = 0

        if showsClosedMediaActivity, !isShowingStandardMusicPeek {
            leading = Self.musicActivityInset
            trailing = Self.musicActivityInset
        }

        if showsFocusActivity {
            // The countdown takes the right side; the left keeps the artwork,
            // or picks up the focus glyph when nothing is playing.
            trailing = Self.focusActivityInset
            leading = max(leading, Self.musicActivityInset)
        }

        if isShowingWidgets {
            let widgets = activeWidgets
            // Prefer what the widget actually measured; the declared width is
            // only a first guess for the very first layout pass. Added rather
            // than assigned, so widgets sharing the row with the artwork and
            // spectrum get their own space instead of overlapping them.
            leading += widgets.leading.isEmpty
                ? 0
                : (measuredWidgetWidths[.leading] ?? Self.estimatedWidth(of: widgets.leading))
            trailing += widgets.trailing.isEmpty
                ? 0
                : (measuredWidgetWidths[.trailing] ?? Self.estimatedWidth(of: widgets.trailing))
        }

        return (leading, trailing)
    }

    private static func estimatedWidth(of widgets: [NotchWidget]) -> CGFloat {
        widgets.reduce(0) { $0 + $1.estimatedWidth } + CGFloat(max(widgets.count - 1, 0)) * 12
    }

    /// Widths reported by the widgets currently on screen.
    func updateMeasuredWidgetWidths(_ widths: [NotchSide: CGFloat]) {
        let widgets = activeWidgets
        var filtered = widths
        if widgets.leading.isEmpty { filtered[.leading] = nil }
        if widgets.trailing.isEmpty { filtered[.trailing] = nil }

        guard filtered != measuredWidgetWidths else { return }
        withAnimation(.notchContent) { measuredWidgetWidths = filtered }
    }

    /// Content size for the current state, excluding shadow padding.
    var contentSize: CGSize {
        switch notchState {
        case .closed:
            var size = closedNotchSize

            if isShowingDropZone {
                size.height += 26
            } else if isShowingStandardHUD {
                size.width = max(size.width + 130, 300)
                size.height += 34
                return size
            } else if isShowingStandardMusicPeek {
                size.width = max(size.width + 60, 300)
                size.height += 34
                return size
            }

            let insets = closedActivityInsets
            size.width += insets.leading + insets.trailing
            return size

        case .open:
            return openNotchSize
        }
    }

    var topCornerRadius: CGFloat {
        guard settings.cornerRadiusScaling else { return cornerRadiusInsets.closed.top }
        return notchState == .open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    var bottomCornerRadius: CGFloat {
        guard settings.cornerRadiusScaling else { return cornerRadiusInsets.closed.bottom }
        return notchState == .open ? cornerRadiusInsets.opened.bottom : cornerRadiusInsets.closed.bottom
    }
}

extension Animation {
    /// Spring used when the notch expands — slightly bouncy, like the reference.
    static let notchOpen = Animation.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0.2)
    /// Slightly faster and flatter on the way back in.
    static let notchClose = Animation.spring(response: 0.32, dampingFraction: 0.85, blendDuration: 0.1)
    static let notchContent = Animation.spring(response: 0.35, dampingFraction: 0.8)
}
