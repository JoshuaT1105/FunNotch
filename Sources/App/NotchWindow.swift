//
//  NotchWindow.swift
//  FunNotch
//
//  A borderless, non-activating panel pinned over the hardware notch. It is
//  always sized to hold the fully expanded notch; the collapsed state simply
//  draws less, and everything outside the drawn area lets clicks fall through
//  to whatever is underneath.
//

import AppKit
import SwiftUI

/// What the content view reports back about an in-flight drag.
@MainActor
protocol NotchDragHandling: AnyObject {
    func dragDidEnter()
    func dragDidExit()
    func dragDidDrop(_ pasteboard: NSPasteboard) -> Bool
}

/// Content view that only accepts mouse events inside the notch's live area, so
/// the rest of the menu bar keeps working normally.
///
/// It is also the app's drag destination. Doing this in AppKit rather than with
/// SwiftUI's `.onDrop` matters: SwiftUI registers its destination lazily and
/// only for `public.data` / `public.item`, and it sits below this view's
/// hit-test gate, so drags never reached it reliably.
final class PassthroughContentView: NSView {
    /// Active area, in this view's (bottom-left origin) coordinate space.
    var activeRect: (() -> CGRect)?
    weak var dragHandler: (any NotchDragHandling)?

    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .URL,
        .string,
        .tiff,
        .png,
        .pdf,
        .rtf,
        .rtfd,
        .html,
        .fileContents,
        NSPasteboard.PasteboardType("public.item"),
        NSPasteboard.PasteboardType("public.data"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // Registering in `init` happens before the view has a window, which can
    // leave the window itself unknown to the drag server. Re-registering once
    // the view is installed is what actually makes drags arrive.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        unregisterDraggedTypes()
        registerForDraggedTypes(Self.acceptedTypes)
        DiagnosticLog.write(
            "drag",
            "registered on window level \(window?.level.rawValue ?? 0), types=\(registeredDraggedTypes.count)"
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        guard let rect = activeRect?(), rect.contains(local) else { return nil }
        // Returning self is fine: AppKit walks up from the hit view to find a
        // registered drag destination, and SwiftUI still gets mouse events
        // through the subview it returns from `super`.
        return super.hitTest(point) ?? self
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types?.map(\.rawValue) ?? []
        DiagnosticLog.write("drag", "entered, shelf=\(Settings.shared.shelfEnabled) types=\(types)")
        guard Settings.shared.shelfEnabled else { return [] }
        dragHandler?.dragDidEnter()
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        Settings.shared.shelfEnabled ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragHandler?.dragDidExit()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        Settings.shared.shelfEnabled
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let accepted = dragHandler?.dragDidDrop(sender.draggingPasteboard) ?? false
        DiagnosticLog.write("drag", "performDragOperation accepted=\(accepted)")
        return accepted
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dragHandler?.dragDidExit()
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // Borderless panels normally refuse first responder; the shelf needs it for
    // keyboard shortcuts like ⌘C and delete.
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class NotchWindowController {
    let viewModel: NotchViewModel
    let panel: NotchPanel
    private let container: PassthroughContentView

    init(screen: NSScreen, rootView: AnyView, viewModel: NotchViewModel) {
        self.viewModel = viewModel

        panel = NotchPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isRestorable = false
        panel.animationBehavior = .none
        // Above the menu bar (24), status items (25) and anything else that
        // lives up here, but well below screen-saver level. Interactive windows
        // at `.screenSaver` are unusual and are a poor drag destination;
        // `.popUpMenu` is the level menus and popovers use, and it reliably
        // receives drags. Floating over fullscreen comes from the collection
        // behaviour below, not from the level.
        panel.level = .popUpMenu
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]

        container = PassthroughContentView(frame: NSRect(origin: .zero, size: windowSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        container.activeRect = { [weak viewModel] in
            guard let viewModel else { return .zero }
            return NotchWindowController.liveRect(for: viewModel)
        }

        panel.contentView = container
        container.dragHandler = self
        applySharingPolicy()
        reposition(on: screen)
        panel.orderFrontRegardless()
    }

    /// Extra catch area offered while a drag is in flight, so the drop does not
    /// have to be aimed at a 32-point strip.
    static let dragCatchHeight: CGFloat = 130

    /// The region of the window that currently draws content, in window space.
    static func liveRect(for viewModel: NotchViewModel) -> CGRect {
        if viewModel.dragDetectorTargeting, viewModel.notchState == .closed {
            return CGRect(
                x: 0,
                y: windowSize.height - dragCatchHeight,
                width: windowSize.width,
                height: dragCatchHeight
            )
        }

        let size = viewModel.contentSize
        var rect = CGRect(
            x: (windowSize.width - size.width) / 2,
            y: windowSize.height - size.height,
            width: size.width,
            height: size.height
        )

        if viewModel.notchState == .closed, Settings.shared.extendHoverArea {
            // A forgiving lip below the notch so the pointer does not have to be
            // pixel-accurate to keep it open.
            rect = rect.insetBy(dx: -12, dy: 0)
            rect.origin.y -= 12
            rect.size.height += 12
        }

        return rect
    }

    func reposition(on screen: NSScreen) {
        let origin = NSPoint(
            x: screen.frame.midX - windowSize.width / 2,
            y: screen.frame.maxY - windowSize.height
        )
        panel.setFrame(NSRect(origin: origin, size: windowSize), display: true)
    }

    func applySharingPolicy() {
        panel.sharingType = Settings.shared.hideFromScreenRecording ? .none : .readOnly
    }

    /// Screen-space rectangle the pointer must be inside to count as hovering.
    var hoverRect: CGRect {
        var rect = Self.liveRect(for: viewModel)
        rect.origin.x += panel.frame.origin.x
        rect.origin.y += panel.frame.origin.y
        return rect
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }
}

extension NotchWindowController: NotchDragHandling {
    func dragDidEnter() {
        DiagnosticLog.write("drag", "notch accepted the drag, opening the shelf")
        // The mouse monitors go quiet during a drag session, so if polling has
        // not already noticed this drag, start it now — it owns clearing the
        // flag when the button comes back up.
        MouseTracker.shared.noteDragInProgress()

        viewModel.dragDetectorTargeting = true
        viewModel.isDropTargeted = true
        viewModel.pinnedOpen = true
        viewModel.open()
        if Settings.shared.openShelfByDefault {
            viewModel.currentTab = .shelf
        }
    }

    func dragDidExit() {
        viewModel.isDropTargeted = false
        viewModel.pinnedOpen = false
    }

    func dragDidDrop(_ pasteboard: NSPasteboard) -> Bool {
        let added = ShelfManager.shared.addContents(of: pasteboard)
        viewModel.isDropTargeted = false
        viewModel.pinnedOpen = false
        if added {
            viewModel.currentTab = .shelf
            viewModel.open()
        }
        return added
    }
}
