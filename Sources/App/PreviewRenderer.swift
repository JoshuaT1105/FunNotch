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
        // Entrances are drawn finished: the capture cannot wait for them.
        Motion.snapshotMode = true
        // And the weather is drawn at a known moment rather than whenever.
        PixelWeatherView.frozenTime = 1000.4

        let settings = Settings.shared
        let saved = (
            idle: settings.idleWidgetsEnabled,
            idleLeft: settings.idleLeftWidgets,
            idleRight: settings.idleRightWidgets,
            mediaDisplay: settings.closedMediaDisplay,
            game: settings.selectedGame,
            skin: settings.dinoSkin
        )
        restoreSettings = {
            settings.idleWidgetsEnabled = saved.idle
            settings.idleLeftWidgets = saved.idleLeft
            settings.idleRightWidgets = saved.idleRight
            settings.closedMediaDisplay = saved.mediaDisplay
            settings.selectedGame = saved.game
            settings.dinoSkin = saved.skin
        }

        // The render process has no location permission, so without this every
        // home-screen scene shows "Weather needs location access" instead of
        // the screen a real user sees. In-memory only; nothing touches disk.
        WeatherManager.shared.injectPreviewConditions(
            temperatureCelsius: 21, weatherCode: 0, isDay: true, placeName: "Cupertino"
        )

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
            ShelfManager.shared.injectPreviewItems([
                "Q3-notes.pdf", "mockup-v4.png", "budget.xlsx",
                "Screenshot 2026-09-20 at 09.41.02.png", "contract-draft.pdf",
                "logo-export.svg",
            ])
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
            FocusManager.shared.previewHistory = Self.sampleFocusHistory()
            FocusManager.shared.injectPreviewSession(minutes: 25, elapsedFraction: 0.35)
            FocusTabState.shared.mode = .focus
            viewModel.refreshPreviewFocusActivity()
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        scenes.append(("island-closed", { viewModel in
            viewModel.previewForceIsland = true
            viewModel.closedNotchSize = CGSize(
                width: Settings.shared.islandWidth,
                height: 32 + Settings.shared.islandTopGap
            )
        }))

        scenes.append(("island-open", { viewModel in
            viewModel.previewForceIsland = true
            viewModel.closedNotchSize = CGSize(
                width: Settings.shared.islandWidth,
                height: 32 + Settings.shared.islandTopGap
            )
            viewModel.previewOpen()
        }))

        scenes.append(("open-timer", { viewModel in
            FocusManager.shared.clearPreviewSession()
            viewModel.setPreviewFocusActivity(false)
            TimerManager.shared.previewRecent = [720, 2700, 90, 5400]
            TimerManager.shared.injectPreviewCountdown(duration: 600, remaining: 372)
            FocusTabState.shared.mode = .timer
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        scenes.append(("open-timer-idle", { viewModel in
            TimerManager.shared.resetCountdown()
            TimerManager.shared.draft = 1500
            FocusTabState.shared.mode = .timer
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        scenes.append(("open-timer-done", { viewModel in
            TimerManager.shared.injectPreviewCountdown(duration: 300, remaining: 0, finished: true)
            FocusTabState.shared.mode = .timer
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        scenes.append(("open-stopwatch", { viewModel in
            TimerManager.shared.resetCountdown()
            TimerManager.shared.injectPreviewStopwatch(elapsed: 134.32, laps: [31.2, 36.9, 28.4, 33.1])
            FocusTabState.shared.mode = .stopwatch
            viewModel.previewOpen()
            viewModel.currentTab = .focus
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
            Settings.shared.selectedGame = GameChoice.breakout.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            // An untouched board is a boring screenshot, and it would not show
            // whether collisions actually work.
            BreakoutGame.shared.playForPreview(seconds: 4.3)
        }))

        // Later in a run: explosives, lasers and a fireball on the Invader.
        scenes.append(("open-game-chaos", { viewModel in
            Settings.shared.selectedGame = GameChoice.breakout.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            BreakoutGame.shared.playForPreview(seconds: 1.6, level: 4, effects: [.laser, .fireball, .multiball])
        }))

        // Every kind of brick, untouched: steel, explosive, gold, mystery.
        scenes.append(("open-game-fortress", { viewModel in
            Settings.shared.selectedGame = GameChoice.breakout.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            BreakoutGame.shared.playForPreview(seconds: 0, level: 5)
        }))

        // Dino Run: the start line, then the same desert at four times of day.
        scenes.append(("open-dino-ready", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
        }))

        scenes.append(("open-dino-day", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            DinoGame.shared.playForPreview(seconds: 5.2, score: 120)
        }))

        scenes.append(("open-dino-sunset", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            DinoGame.shared.playForPreview(seconds: 3, score: 470, powers: [.wings, .magnet])
        }))

        scenes.append(("open-dino-night", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            DinoGame.shared.playForPreview(seconds: 4.4, score: 900, powers: [.shield])
        }))

        scenes.append(("open-dino-turbo", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            DinoGame.shared.playForPreview(seconds: 1.4, score: 1700, powers: [.turbo])
        }))

        scenes.append(("open-dino-over", { viewModel in
            Settings.shared.selectedGame = GameChoice.dino.rawValue
            viewModel.previewOpen()
            viewModel.currentTab = .game
            DinoGame.shared.playForPreview(seconds: 2.5, score: 40, crash: true)
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
            FocusManager.shared.previewHistory = Self.sampleFocusHistory()
            FocusTabState.shared.mode = .focus
            viewModel.setPreviewFocusActivity(false)
            viewModel.previewOpen()
            viewModel.currentTab = .focus
        }))

        // The home screen leads with the weather whenever media is idle, which
        // is what the site shows too — but the render process never has
        // location permission, so the forecast is injected. Nothing here
        // touches disk: `conditions` is in-memory only.
        // open-home already covers the default clear-day state. This one is
        // here to show the pixel scene changes with the forecast.
        scenes.append(("open-weather-rain", { viewModel in
            MusicManager.shared.clearPreviewTrack()
            viewModel.refreshPreviewMusicActivity()
            WeatherManager.shared.injectPreviewConditions(
                temperatureCelsius: 11, weatherCode: 63, isDay: true, placeName: "London"
            )
            viewModel.previewOpen()
            viewModel.currentTab = .home
        }))

        // MARK: Live activities

        scenes.append(("closed-hud-muted", { viewModel in
            MusicManager.shared.clearPreviewTrack()
            viewModel.setPreviewMusicActivity(false)
            HUDManager.shared.injectPreview(.volume, value: 0.4, muted: true)
            viewModel.expandingView = SneakPeek(
                show: true, type: .hud, value: 0, icon: HUDManager.Kind.volume.mutedSymbol
            )
        }))

        scenes.append(("closed-hud-backlight", { viewModel in
            viewModel.expandingView = SneakPeek(
                show: true, type: .hud, value: 0.7, icon: HUDManager.Kind.keyboardBacklight.symbol
            )
        }))

        scenes.append(("closed-agent-started", { viewModel in
            AgentSessionsManager.shared.injectPreview(.started, broadcast: false)
            viewModel.expandingView = SneakPeek(show: true, type: .agent)
        }))

        scenes.append(("closed-agent-finished", { viewModel in
            AgentSessionsManager.shared.injectPreview(.finished(194), broadcast: false)
            viewModel.expandingView = SneakPeek(show: true, type: .agent)
        }))

        scenes.append(("closed-agent-waiting", { viewModel in
            AgentSessionsManager.shared.injectPreview(.needsInput("permission prompt"), broadcast: false)
            viewModel.expandingView = SneakPeek(show: true, type: .agent)
        }))

        // Beside the clock and battery, a working agent is a small light.
        scenes.append(("closed-agent-light", { viewModel in
            let settings = Settings.shared
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock]
            settings.idleRightWidgets = [.battery]
            AgentSessionsManager.shared.injectPreviewSessions(Array(Self.sampleSessions().prefix(1)) + [Self.sampleSessions()[3]])
            viewModel.setPreviewAgentActivity(AgentActivity(active: 2, waiting: false))
        }))

        // With nothing else there, it takes both wings.
        scenes.append(("closed-agent-wings", { viewModel in
            Settings.shared.idleWidgetsEnabled = false
            AgentSessionsManager.shared.injectPreviewSessions([Self.sampleSessions()[0]])
            viewModel.setPreviewAgentActivity(AgentActivity(active: 1, waiting: false))
        }))

        scenes.append(("closed-focus-banner", { viewModel in
            AgentSessionsManager.shared.injectPreviewSessions([])
            viewModel.setPreviewAgentActivity(AgentActivity())
            FocusManager.shared.injectPreviewSession(minutes: 25, elapsedFraction: 0.02)
            viewModel.expandingView = SneakPeek(show: true, type: .focus, value: 0, icon: "cup.and.saucer.fill")
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
            FocusManager.shared.clearPreviewSession()
            TimerManager.shared.clearPreview()
            renderExtras(into: directory) {
                NSApp.terminate(nil)
            }
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

    // MARK: Tiles and windows

    /// Every weather scene as the pane shows it, with a filmstrip of its
    /// motion underneath, and the collapsed-notch icons. Drawn straight to
    /// images: the weather is a pure function of time, so no window is needed
    /// and no animation has to be waited for.
    private static func renderWeatherSheets(into directory: URL) {
        let variants: [(name: String, scene: WeatherScene, code: Int, night: Bool, celsius: Double)] = [
            ("clear-day", .clearDay, 0, false, 24),
            ("clear-night", .clearNight, 0, true, 14),
            ("cloudy-day", .cloudy, 3, false, 17),
            ("cloudy-night", .cloudy, 3, true, 11),
            ("fog", .fog, 45, false, 9),
            ("drizzle", .drizzle, 53, false, 12),
            ("rain", .rain, 63, false, 11),
            ("rain-night", .rain, 63, true, 9),
            ("storm", .storm, 95, true, 16),
            ("snow-day", .snow, 73, false, -2),
            ("snow-night", .snow, 73, true, -6),
        ]
        let size = CGSize(width: 420, height: 100)
        let saved = PixelWeatherView.frozenTime

        for variant in variants {
            var start = 1000.4
            var step = 0.25
            if variant.scene == .storm, let strike = PixelWeatherView.nextStrike(after: 1000) {
                start = strike - 0.08
                step = 0.08
            } else if variant.scene == .clearNight, let meteor = PixelWeatherView.nextMeteor(after: 1000) {
                start = meteor - 0.15
                step = 0.15
            }
            let times = (0 ..< 4).map { start + Double($0) * step }

            WeatherManager.shared.injectPreviewConditions(
                temperatureCelsius: variant.celsius, weatherCode: variant.code,
                isDay: !variant.night, placeName: "Cupertino"
            )
            PixelWeatherView.frozenTime = times[1]

            let sheet = VStack(alignment: .leading, spacing: 8) {
                WeatherPane()
                    .frame(width: size.width, height: size.height)
                ForEach(times, id: \.self) { time in
                    PixelWeatherView(scene: variant.scene, isNight: variant.night, time: time)
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(10)
            .background(Color.black)
            .environment(\.colorScheme, .dark)

            writeImage(sheet, scale: 2, to: directory.appendingPathComponent("weather-\(variant.name).png"))
        }

        // The collapsed-notch icons, eight times life size so each cell shows.
        let icons = HStack(spacing: 6) {
            ForEach([WeatherScene.clearDay, .clearNight, .cloudy, .fog, .drizzle, .rain, .storm, .snow], id: \.self) { scene in
                PixelWeatherIcon(scene: scene)
                    .padding(3)
                    .background(Color.black)
            }
        }
        .padding(4)
        .background(Color(white: 0.2))
        PixelWeatherView.frozenTime = 1000.1
        writeImage(icons, scale: 8, to: directory.appendingPathComponent("weather-icons.png"))

        PixelWeatherView.frozenTime = saved
        WeatherManager.shared.injectPreviewConditions(
            temperatureCelsius: 21, weatherCode: 0, isDay: true, placeName: "Cupertino"
        )
    }

    private static func writeImage(_ view: some View, scale: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return }
        try? data.write(to: url)
    }

    /// The Agents tile on its own, and every page of the two windows.
    private static func renderExtras(into directory: URL, completion: @escaping () -> Void) {
        renderWeatherSheets(into: directory)
        var jobs: [(name: String, size: CGSize, dark: Bool, make: () -> AnyView)] = []

        jobs.append(("tile-agents", CGSize(width: 300, height: 128), true, {
            AgentSessionsManager.shared.injectPreviewSessions(Self.sampleSessions())
            return AnyView(
                AgentSessionsTile()
                    .frame(width: 270, height: 100)
                    .padding(14)
                    .background(Color.black)
            )
        }))
        jobs.append(("tile-agents-compact", CGSize(width: 270, height: 74), true, {
            AnyView(
                HomePanelChrome { AgentSessionsTile(compact: true) }
                    .frame(width: 240, height: 46)
                    .padding(14)
                    .background(Color.black)
            )
        }))
        jobs.append(("tile-agents-empty", CGSize(width: 300, height: 128), true, {
            AgentSessionsManager.shared.injectPreviewSessions([])
            return AnyView(
                AgentSessionsTile()
                    .frame(width: 270, height: 100)
                    .padding(14)
                    .background(Color.black)
            )
        }))

        jobs.append(("tile-focus-medium", CGSize(width: 390, height: 190), true, {
            FocusManager.shared.previewHistory = Self.sampleFocusHistory()
            TimerManager.shared.injectPreviewCountdown(duration: 600, remaining: 372)
            FocusTabState.shared.mode = .timer
            return AnyView(
                FocusView(isTile: true)
                    .environmentObject(Settings.shared)
                    .frame(width: 352, height: 150)
                    .padding(19)
                    .background(Color.black)
            )
        }))
        jobs.append(("tile-focus-narrow", CGSize(width: 160, height: 190), true, {
            AnyView(
                FocusView(isTile: true)
                    .environmentObject(Settings.shared)
                    .frame(width: 118, height: 150)
                    .padding(19)
                    .background(Color.black)
            )
        }))

        for tab in SettingsTab.allCases {
            jobs.append(("settings-\(tab.rawValue)", CGSize(width: 820, height: 640), false, {
                if tab == .agents { AgentSessionsManager.shared.injectPreviewSessions(Self.sampleSessions()) }
                SettingsNavigation.shared.tab = tab
                return AnyView(SettingsView().environmentObject(Settings.shared))
            }))
        }
        for tab in CustomizeTab.allCases {
            jobs.append(("customize-\(tab.rawValue)", CGSize(width: 1010, height: 720), true, {
                CustomizeNavigation.shared.tab = tab
                return AnyView(CustomizeView(onDone: {}))
            }))
        }

        func next(_ index: Int) {
            guard index < jobs.count else {
                completion()
                return
            }
            let job = jobs[index]
            render(
                root: job.make(),
                size: job.size,
                appearance: NSAppearance(named: job.dark ? .darkAqua : .aqua),
                to: directory.appendingPathComponent("\(job.name).png")
            ) {
                next(index + 1)
            }
        }
        next(0)
    }

    /// An invented week of focus: a few good days, one off, a streak running
    /// into today.
    static func sampleFocusHistory() -> (seconds: [String: Int], sessions: [String: Int]) {
        let minutes = [95, 0, 50, 140, 75, 110, 40]
        var seconds: [String: Int] = [:]
        var sessions: [String: Int] = [:]
        let today = Calendar.current.startOfDay(for: Date())
        for (back, value) in minutes.reversed().enumerated() {
            guard let day = Calendar.current.date(byAdding: .day, value: -back, to: today) else { continue }
            let key = FocusManager.dayKey(day)
            seconds[key] = value * 60
            sessions[key] = value / 25
        }
        return (seconds, sessions)
    }

    /// Made-up sessions: one working, one waiting on a permission prompt, one
    /// that finished, and a second working one.
    static func sampleSessions() -> [AgentSessionsManager.Session] {
        let now = Date()
        func make(
            _ id: String, _ name: String, _ project: String,
            _ status: AgentSessionsManager.Status, since: TimeInterval, turn: TimeInterval?,
            last: TimeInterval? = nil, agent: AgentSessionsManager.Agent = .claude
        ) -> AgentSessionsManager.Session {
            AgentSessionsManager.Session(
                id: id, agent: agent, name: name, project: project, status: status,
                statusSince: now.addingTimeInterval(-since),
                turnStartedAt: turn.map { now.addingTimeInterval(-$0) },
                lastTurnDuration: last, startedAt: now.addingTimeInterval(-3600),
                pid: nil, host: .claudeApp
            )
        }
        return [
            make("a", "Notch animations", "FunNotch", .working, since: 134, turn: 134),
            make("b", "Release notes", "FunNotch", .waiting("permission prompt"), since: 12, turn: 75),
            make("c", "Fix the shelf drop", "FunNotch", .idle, since: 240, turn: 700, last: 460),
            make("d", "Website copy", "Website", .working, since: 42, turn: 42),
        ]
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

    private static func render(
        root: some View,
        size: CGSize = windowSize,
        appearance: NSAppearance? = nil,
        to url: URL,
        completion: @escaping () -> Void
    ) {
        let hosting = NSHostingView(rootView: AnyView(root))
        // As the real windows: SwiftUI sets the minimum, the window the size.
        hosting.sizingOptions = [.minSize]
        hosting.frame = CGRect(origin: .zero, size: size)

        // A real (offscreen) window makes SwiftUI lay out and draw for real.
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -8000, y: -8000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
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
