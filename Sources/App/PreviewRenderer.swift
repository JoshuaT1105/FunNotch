//
//  PreviewRenderer.swift
//  FunNotch
//
//  Development aid: `FunNotch --render-preview <directory>` renders each
//  notch state to a PNG and exits, so layout can be checked without screen
//  recording permission.
//

import AppKit
import SwiftUI

@MainActor
enum PreviewRenderer {
    /// Returns the output directory if the app was launched in preview mode.
    static func requestedDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-preview"),
              index + 1 < arguments.count
        else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Puts back any preference a scene changed. Preview mode runs in its own
    /// process but writes to the same defaults the real app reads.
    private static var restoreSettings: (() -> Void)?

    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let settings = Settings.shared
        let saved = (
            idle: settings.idleWidgetsEnabled,
            idleLeft: settings.idleLeftWidgets,
            idleRight: settings.idleRightWidgets,
            mediaDisplay: settings.closedMediaDisplay
        )
        restoreSettings = {
            settings.idleWidgetsEnabled = saved.idle
            settings.idleLeftWidgets = saved.idleLeft
            settings.idleRightWidgets = saved.idleRight
            settings.closedMediaDisplay = saved.mediaDisplay
        }

        let screen = NSScreen.main
        var scenes: [(name: String, configure: (NotchViewModel) -> Void)] = []

        scenes.append(("closed-idle", { _ in }))

        scenes.append(("closed-music", { viewModel in
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
        }))

        scenes.append(("closed-hud-battery", { viewModel in
            viewModel.expandingView = SneakPeek(show: true, type: .battery, value: 0.8, icon: "battery.100.bolt")
        }))

        // The renderer owns its own view model, so drive the strip directly
        // rather than through the manager's broadcast.
        scenes.append(("closed-hud-volume", { viewModel in
            HUDManager.shared.injectPreview(.volume, value: 0.62)
            viewModel.expandingView = SneakPeek(
                show: true, type: .hud, value: 0.62, icon: HUDManager.Kind.volume.symbol
            )
        }))

        scenes.append(("closed-hud-brightness", { viewModel in
            HUDManager.shared.injectPreview(.brightness, value: 0.38)
            viewModel.expandingView = SneakPeek(
                show: true, type: .hud, value: 0.38, icon: HUDManager.Kind.brightness.symbol
            )
        }))

        scenes.append(("closed-peek-music", { viewModel in
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
            viewModel.sneakPeek = SneakPeek(show: true, type: .music)
        }))

        scenes.append(("open-home", { viewModel in
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
            viewModel.previewOpen()
        }))

        scenes.append(("open-shelf", { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .shelf
        }))

        scenes.append(("closed-dropzone", { viewModel in
            viewModel.dragDetectorTargeting = true
        }))

        scenes.append(("closed-focus", { viewModel in
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
            FocusManager.shared.injectPreviewSession(minutes: 25, elapsedFraction: 0.35)
            viewModel.refreshPreviewFocusActivity()
        }))

        scenes.append(("open-focus", { viewModel in
            FocusManager.shared.injectPreviewSession(minutes: 25, elapsedFraction: 0.35)
            viewModel.refreshPreviewFocusActivity()
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        scenes.append(("open-timer", { viewModel in
            TimerManager.shared.start(seconds: 600)
            viewModel.previewOpen()
            viewModel.currentTab = .timer
        }))

        scenes.append(("open-stopwatch", { viewModel in
            TimerManager.shared.injectPreviewStopwatch(elapsed: 74.32, laps: [61.08, 32.55])
            viewModel.previewOpen()
            viewModel.currentTab = .timer
        }))

        scenes.append(("open-clipboard", { viewModel in
            ClipboardManager.shared.injectPreviewEntries([
                (.text("https://developer.apple.com/documentation/appkit/nspasteboard"), "Safari"),
                (.text("git rebase -i origin/main"), "Terminal"),
                (.files([URL(fileURLWithPath: "/Users/me/Desktop/Screenshot.png")]), "Finder"),
                (.text("Remember to pick up the dry cleaning before six"), "Notes"),
                (.text("swift build -c release"), "Terminal"),
            ])
            viewModel.previewOpen()
            viewModel.currentTab = .clipboard
        }))

        scenes.append(("closed-screenshot", { viewModel in
            FocusManager.shared.clearPreviewSession()
            viewModel.setPreviewFocusActivity(false)
            ScreenshotWatcher.shared.injectPreviewCatch("Screenshot 2026-08-01 at 10.24.11.png")
            viewModel.expandingView = SneakPeek(
                show: true, type: .screenshot, value: 1, icon: "camera.viewfinder"
            )
        }))

        scenes.append(("closed-bluetooth", { viewModel in
            FocusManager.shared.clearPreviewSession()
            viewModel.setPreviewFocusActivity(false)
            BluetoothMonitor.shared.injectPreviewChange(
                name: "AirPods Pro", connected: true, battery: 0.82
            )
            viewModel.expandingView = SneakPeek(
                show: true, type: .bluetooth, value: 0.82, icon: "airpods.pro"
            )
        }))

        scenes.append(("closed-widgets", { viewModel in
            let settings = Settings.shared
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock]
            settings.idleRightWidgets = [.battery]
            MusicManager.shared.injectPreviewTrack(TrackInfo())
            viewModel.setPreviewMusicActivity(false)
        }))

        scenes.append(("open-game", { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .game
            // An untouched board is a boring screenshot, and it would not show
            // whether collisions actually work.
            BreakoutGame.shared.playForPreview(seconds: 4.3)
        }))

        scenes.append(("closed-music-and-widgets", { viewModel in
            let settings = Settings.shared
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock]
            settings.idleRightWidgets = [.battery]
            settings.closedMediaDisplay = .mediaAndWidgets
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
        }))

        scenes.append(("closed-music-widgets-only", { viewModel in
            let settings = Settings.shared
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock]
            settings.idleRightWidgets = [.battery]
            settings.closedMediaDisplay = .widgetsOnly
            MusicManager.shared.injectPreviewTrack(Self.sampleTrack())
            viewModel.refreshPreviewMusicActivity()
        }))

        scenes.append(("closed-widgets-many", { viewModel in
            let settings = Settings.shared
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock, .weather]
            settings.idleRightWidgets = [.cpu, .memory, .battery]
            MusicManager.shared.injectPreviewTrack(TrackInfo())
            viewModel.setPreviewMusicActivity(false)
        }))

        scenes.append(("closed-download", { viewModel in
            viewModel.expandingView = SneakPeek(
                show: true, type: .download, value: 1, icon: "arrow.down.circle.fill"
            )
        }))

        scenes.append(("open-focus-idle", { viewModel in
            Settings.shared.idleWidgetsEnabled = false
            FocusManager.shared.clearPreviewSession()
            viewModel.setPreviewFocusActivity(false)
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        // Scenes are rendered one at a time: several of them configure shared
        // singletons, so running them concurrently would let the last one win.
        renderSequentially(scenes, index: 0, screen: screen, directory: directory)
    }

    private static func renderSequentially(
        _ scenes: [(name: String, configure: (NotchViewModel) -> Void)],
        index: Int,
        screen: NSScreen?,
        directory: URL
    ) {
        guard index < scenes.count else {
            restoreSettings?()
            NSApp.terminate(nil)
            return
        }

        let scene = scenes[index]
        let viewModel = NotchViewModel(screen: screen)
        scene.configure(viewModel)

        let root = ContentView()
            .environmentObject(viewModel)
            .environmentObject(Settings.shared)

        render(root: root, to: directory.appendingPathComponent("\(scene.name).png")) {
            renderSequentially(scenes, index: index + 1, screen: screen, directory: directory)
        }
    }

    private static func sampleTrack() -> TrackInfo {
        var track = TrackInfo()
        track.title = "Everything In Its Right Place"
        track.artist = "Radiohead"
        track.album = "Kid A"
        track.duration = 251
        track.elapsed = 84
        track.isPlaying = true
        track.isShuffled = true
        track.repeatMode = .all
        track.artwork = syntheticArtwork()
        return track
    }

    /// Stand-in album art so colour sampling and layout can be checked.
    private static func syntheticArtwork() -> NSImage {
        let size = CGSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        let gradient = NSGradient(colors: [
            NSColor(srgbRed: 0.98, green: 0.36, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.42, green: 0.12, blue: 0.55, alpha: 1),
        ])
        gradient?.draw(in: CGRect(origin: .zero, size: size), angle: 55)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: CGRect(x: 110, y: 110, width: 80, height: 80)).fill()
        image.unlockFocus()
        return image
    }

    private static func render(root: some View, to url: URL, completion: @escaping () -> Void) {
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = CGRect(origin: .zero, size: windowSize)

        // A real (offscreen) window makes SwiftUI lay out and draw for real.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0.16, alpha: 1)
        window.orderFront(nil)

        // Give SwiftUI a couple of run loop turns to settle animations.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            hosting.layoutSubtreeIfNeeded()
            guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                completion()
                return
            }
            hosting.cacheDisplay(in: hosting.bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
            }
            window.orderOut(nil)
            completion()
        }
    }
}

extension NotchViewModel {
    /// Opens without animation, for snapshots.
    func previewOpen() {
        setPreviewState(.open)
    }

    func refreshPreviewMusicActivity() {
        setPreviewMusicActivity(true)
    }

    func refreshPreviewFocusActivity() {
        setPreviewFocusActivity(FocusManager.shared.isActive)
    }
}
