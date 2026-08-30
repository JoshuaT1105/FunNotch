//
//  NotchWindowManager.swift
//  FunNotch
//
//  Creates and tears down notch panels as displays come and go, and routes
//  global pointer events to whichever notch the pointer is near.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowManager: ObservableObject {
    static let shared = NotchWindowManager()

    private(set) var controllers: [NotchWindowController] = []
    private var cancellables = Set<AnyCancellable>()
    private var gestureAccumulator: CGFloat = 0
    private var lastGestureReset = Date()

    private let settings = Settings.shared

    private init() {}

    /// All live view models, for broadcasting system-wide events.
    var viewModels: [NotchViewModel] {
        controllers.map(\.viewModel)
    }

    /// The notch on the display the pointer is currently on, else the first.
    var activeViewModel: NotchViewModel? {
        let mouse = NSEvent.mouseLocation
        if let match = controllers.first(where: { NSMouseInRect(mouse, $0.panel.screen?.frame ?? .zero, false) }) {
            return match.viewModel
        }
        return controllers.first?.viewModel
    }

    func start() {
        rebuild()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notchGeometryChanged)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openNotchRequested)
            .sink { [weak self] _ in self?.activeViewModel?.open() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .closeNotchRequested)
            .sink { [weak self] _ in self?.viewModels.forEach { $0.close() } }
            .store(in: &cancellables)

        let tracker = MouseTracker.shared
        tracker.onMove = { [weak self] point in self?.handlePointer(point) }
        tracker.onScroll = { [weak self] point, delta in self?.handleScroll(at: point, delta: delta) }
        tracker.onClick = { [weak self] point in self?.handleClick(at: point) }
        tracker.onDragStateChange = { [weak self] dragging in
            self?.viewModels.forEach { $0.dragDetectorTargeting = dragging }
        }
        tracker.start()
    }

    /// Recreates panels to match the current display configuration.
    func rebuild() {
        let targets: [NSScreen]
        if settings.showOnAllDisplays {
            targets = NSScreen.screens
        } else if let screen = preferredScreen() {
            targets = [screen]
        } else {
            targets = []
        }

        // Reuse panels whose display is unchanged so state survives a rebuild.
        var reused: [NotchWindowController] = []
        var stale = controllers

        for screen in targets {
            let identifier = screen.displayIdentifier
            if let index = stale.firstIndex(where: { $0.viewModel.screenIdentifier == identifier }) {
                let controller = stale.remove(at: index)
                controller.viewModel.refreshGeometry()
                controller.reposition(on: screen)
                controller.applySharingPolicy()
                reused.append(controller)
            } else {
                reused.append(makeController(for: screen))
            }
        }

        stale.forEach { $0.close() }
        controllers = reused
    }

    private func makeController(for screen: NSScreen) -> NotchWindowController {
        let viewModel = NotchViewModel(screen: screen)
        let root = AnyView(
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(settings)
        )
        return NotchWindowController(screen: screen, rootView: root, viewModel: viewModel)
    }

    // MARK: - Pointer routing

    private func handlePointer(_ point: CGPoint) {
        for controller in controllers {
            let inside = controller.hoverRect.contains(point)
            controller.viewModel.setHovering(inside)
        }

        // When "follow the pointer" is on and the notch lives on a single
        // display, move it to whichever display the pointer entered.
        guard settings.automaticallySwitchDisplay, !settings.showOnAllDisplays else { return }
        guard let current = controllers.first else { return }
        guard current.viewModel.notchState == .closed else { return }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
           screen.displayIdentifier != current.viewModel.screenIdentifier {
            rebuild()
        }
    }

    private func handleClick(at point: CGPoint) {
        guard let controller = controllers.first(where: { $0.hoverRect.contains(point) }) else { return }
        guard controller.viewModel.notchState == .closed else { return }
        // Tapping the collapsed notch opens it even when hover-to-open is off.
        if !settings.openNotchOnHover {
            controller.viewModel.open()
        }
    }

    private func handleScroll(at point: CGPoint, delta: CGFloat) {
        guard settings.enableGestures else { return }
        guard let controller = controllers.first(where: { $0.hoverRect.contains(point) }) else {
            gestureAccumulator = 0
            return
        }

        // Reset the accumulator between distinct swipes.
        if Date().timeIntervalSince(lastGestureReset) > 0.4 {
            gestureAccumulator = 0
        }
        lastGestureReset = Date()
        gestureAccumulator += delta

        let threshold = settings.gestureSensitivity / 10
        let viewModel = controller.viewModel

        if gestureAccumulator < -threshold, viewModel.notchState == .closed {
            gestureAccumulator = 0
            viewModel.open()
        } else if gestureAccumulator > threshold, viewModel.notchState == .open, settings.closeGestureEnabled {
            gestureAccumulator = 0
            viewModel.close()
        }
    }

    /// Applies a closure to every notch, used for system-wide activities.
    func broadcast(_ body: (NotchViewModel) -> Void) {
        viewModels.forEach(body)
    }
}
