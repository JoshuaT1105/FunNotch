//
//  MouseTracker.swift
//  FunNotch
//
//  The notch panel never becomes the active app, so AppKit will not deliver
//  mouseEntered/mouseExited to it while another app has focus. Instead we watch
//  pointer movement globally and decide hover state ourselves.
//
//  Scroll events over the notch are also picked up here to drive the
//  swipe-to-open / swipe-to-close gestures.
//

import AppKit

@MainActor
final class MouseTracker {
    static let shared = MouseTracker()

    /// Called with the current pointer location, in global screen coordinates.
    var onMove: ((CGPoint) -> Void)?
    /// Called with (location, scrollDeltaY) for two-finger swipes.
    /// Location, vertical delta, horizontal delta. Vertical opens and closes
    /// the notch; horizontal is free for volume.
    var onScroll: ((CGPoint, CGFloat, CGFloat) -> Void)?
    /// Called with the click location for taps on the notch.
    var onClick: ((CGPoint) -> Void)?
    /// Called when a file drag starts or ends anywhere on screen.
    var onDragStateChange: ((Bool) -> Void)?

    /// Extra pointer observers. `onMove` belongs to the window manager; anything
    /// else that needs the global pointer — the notch game's paddle — registers
    /// here rather than fighting over that one slot.
    private var moveObservers: [String: (CGPoint) -> Void] = [:]

    private var monitors: [Any] = []
    private var isDragging = false
    /// Drag pasteboard generation at the last mouse-down. A real drag bumps it,
    /// which is how we tell a live drag from leftovers of an old one.
    private var pasteboardMarker = 0
    /// Runs only between mouse-down and mouse-up.
    private var dragPollTimer: Timer?

    private init() {}

    func start() {
        stop()

        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        addMonitors(matching: moveMask) { [weak self] event in
            self?.handleMove(event)
        }

        addMonitors(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            self.onScroll?(NSEvent.mouseLocation, event.scrollingDeltaY, event.scrollingDeltaX)
        }

        addMonitors(matching: [.leftMouseUp]) { [weak self] _ in
            self?.endDrag()
        }

        addMonitors(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            self.pasteboardMarker = NSPasteboard(name: .drag).changeCount
            self.startDragPolling()
            self.onClick?(NSEvent.mouseLocation)
        }
    }

    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        stopDragPolling()
    }

    // MARK: - Drag detection
    //
    // Once AppKit starts a drag session it runs its own event loop, and global
    // monitors stop seeing `leftMouseDragged` entirely. Polling the pressed
    // buttons and the drag pasteboard is the only way to notice a drag that is
    // already under way — and it needs no special permissions.

    private func startDragPolling() {
        guard dragPollTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragPollTimer = timer
    }

    private func stopDragPolling() {
        dragPollTimer?.invalidate()
        dragPollTimer = nil
    }

    private func pollDrag() {
        // Bit 0 is the left button.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endDrag()
            return
        }

        guard !isDragging, Settings.shared.expandedDragDetection else { return }

        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != pasteboardMarker,
              Self.pasteboardHasAcceptableContent(pasteboard)
        else { return }

        isDragging = true
        DiagnosticLog.write(
            "drag",
            "poll detected a drag, pasteboard types=\(pasteboard.types?.map(\.rawValue).prefix(4) ?? [])"
        )
        onDragStateChange?(true)
    }

    private func endDrag() {
        stopDragPolling()
        guard isDragging else { return }
        isDragging = false
        DiagnosticLog.write("drag", "drag ended")
        onDragStateChange?(false)
    }

    /// Called by the drop target when AppKit tells us a drag arrived that we
    /// had not noticed, so the flag still gets cleared on mouse-up.
    func noteDragInProgress() {
        guard !isDragging else { return }
        isDragging = true
        pasteboardMarker = -1
        startDragPolling()
    }

    private func addMonitors(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func addMoveObserver(_ key: String, _ body: @escaping (CGPoint) -> Void) {
        moveObservers[key] = body
    }

    func removeMoveObserver(_ key: String) {
        moveObservers.removeValue(forKey: key)
    }

    private func handleMove(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        onMove?(location)
        for observer in moveObservers.values {
            observer(location)
        }
    }

    static func pasteboardHasAcceptableContent(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let accepted: Set<NSPasteboard.PasteboardType> = [
            .fileURL, .URL, .string, .tiff, .png, .pdf, .rtf,
            NSPasteboard.PasteboardType("public.file-url"),
        ]
        return !accepted.isDisjoint(with: Set(types))
    }
}
