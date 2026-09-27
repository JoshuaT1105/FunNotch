//
//  FilmRenderer.swift
//  FunNotch
//
//  Development aid: `FunNotch --render-film <directory>` renders the notch one
//  exact frame at a time for a video, and exits.
//
//  Every frame is the real ContentView, drawn by ImageRenderer with the film
//  clock (`Motion.filmTime` / `Motion.filmDate`) standing in for the wall
//  clock — so banners play their real entrances, spinners spin, the weather
//  drifts and the dinosaur runs, all at 60 frames a second whatever the
//  machine's speed. Each shot is a numbered PNG sequence of the whole notch
//  window on black, and `film.json` says where the notch sits in each shot so
//  a compositor can clip the video to its silhouette.
//
//  Nothing is saved: every preference a shot changes is put back, and all the
//  data on screen — calendar, sessions, files — is invented and in memory.
//

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum FilmRenderer {
    static func requestedDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-film"), index + 1 < arguments.count else {
            return nil
        }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Only the named shots, when `--shots a,b` is passed. For iterating.
    private static var requestedShots: Set<String>? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--shots"), index + 1 < arguments.count else { return nil }
        return Set(arguments[index + 1].split(separator: ",").map(String.init))
    }

    static let fps = 60.0
    static let scale: CGFloat = 4

    private struct Shot {
        let name: String
        let seconds: Double
        /// Called once, before the first frame.
        let prepare: (NotchViewModel) -> Void
        /// Called before every frame, with seconds into the shot.
        var pose: (NotchViewModel, Double) -> Void = { _, _ in }
        /// Called after every frame: anything that happened in it worth a
        /// sound, for the soundtrack to line up with.
        var observe: (() -> [String])?
    }

    // MARK: - Run

    static func run(into directory: URL) {
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)

        let settings = Settings.shared
        let saved = (
            idle: settings.idleWidgetsEnabled,
            left: settings.idleLeftWidgets,
            right: settings.idleRightWidgets,
            minutes: settings.focusDefaultMinutes,
            game: settings.selectedGame,
            mediaDisplay: settings.closedMediaDisplay,
            peekStyle: settings.sneakPeekStyle,
            slider: settings.sliderColor,
            spectrum: settings.spectrumColor,
            colouredSpectrum: settings.coloredSpectrogram
        )
        let spectrum = loadSpectrum()

        Motion.snapshotMode = false
        let base = filmBaseDate()
        let started = Date()

        // Invented, in-memory data for everything on screen.
        WeatherManager.shared.injectPreviewConditions(
            temperatureCelsius: 22, weatherCode: 0, isDay: true, placeName: "Cupertino"
        )
        MusicManager.shared.clearPreviewTrack()
        CalendarManager.shared.injectPreviewItems(sampleAgenda(on: base))
        AgentSessionsManager.shared.injectPreviewSessions([])
        FocusManager.shared.clearPreviewSession()
        FocusManager.shared.previewHistory = PreviewRenderer.sampleFocusHistory()

        var shotInfo: [String: Any] = [:]
        for shot in shots(base: base) {
            if let only = requestedShots, !only.contains(shot.name) { continue }
            let viewModel = NotchViewModel(screen: NSScreen.main)
            Motion.filmTime = 0
            Motion.filmDate = base
            shot.prepare(viewModel)

            let folder = directory.appendingPathComponent(shot.name, isDirectory: true)
            try? files.removeItem(at: folder)
            try? files.createDirectory(at: folder, withIntermediateDirectories: true)

            let frames = max(Int((shot.seconds * fps).rounded()), 1)
            var sizes: [CGSize] = []
            var events: [[Any]] = []
            for index in 0 ..< frames {
                let t = Double(index) / fps
                Motion.filmTime = t
                Motion.filmDate = base.addingTimeInterval(t)
                Motion.filmSpectrum = spectrum[shot.name].flatMap { index < $0.count ? $0[index] : $0.last }
                PixelWeatherView.frozenTime = 1000.4 + t
                shot.pose(viewModel, t)
                sizes.append(viewModel.contentSize)
                autoreleasepool {
                    if let image = render(viewModel) {
                        write(image, to: folder.appendingPathComponent(String(format: "f%04d.png", index)))
                    }
                }
                for event in shot.observe?() ?? [] {
                    events.append([event, (t * 1000).rounded() / 1000])
                }
            }

            let first = sizes.first ?? viewModel.contentSize
            shotInfo[shot.name] = [
                "frames": frames,
                "seconds": shot.seconds,
                "width": first.width,
                "height": first.height,
                "endWidth": sizes.last?.width ?? first.width,
                "endHeight": sizes.last?.height ?? first.height,
                "topRadius": viewModel.topCornerRadius,
                "bottomRadius": viewModel.bottomCornerRadius,
                "events": events,
            ]
            print("film: \(shot.name) — \(frames) frames, notch \(Int(first.width))×\(Int(first.height))")
        }

        // Where the dial and its Start button are, for the cursor to aim at.
        let closed = NotchViewModel(screen: NSScreen.main).closedNotchSize
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d  h:mm a"
        let manifest: [String: Any] = [
            "fps": fps,
            "scale": scale,
            "window": ["width": windowSize.width, "height": windowSize.height],
            "open": ["width": openNotchSize.width, "height": openNotchSize.height],
            "closed": ["width": closed.width, "height": closed.height],
            "menuBarTime": formatter.string(from: base),
            "shots": shotInfo,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent("film.json"))
        }

        exportSounds(into: directory.appendingPathComponent("sounds", isDirectory: true))

        // Put everything back.
        settings.idleWidgetsEnabled = saved.idle
        settings.idleLeftWidgets = saved.left
        settings.idleRightWidgets = saved.right
        settings.focusDefaultMinutes = saved.minutes
        settings.selectedGame = saved.game
        settings.closedMediaDisplay = saved.mediaDisplay
        settings.sneakPeekStyle = saved.peekStyle
        settings.sliderColor = saved.slider
        settings.spectrumColor = saved.spectrum
        settings.coloredSpectrogram = saved.colouredSpectrum
        FocusManager.shared.clearPreviewSession()
        FocusManager.shared.previewHistory = nil
        MusicManager.shared.clearPreviewTrack()
        HomeLayout.filmTiles = nil
        Motion.filmTime = nil
        Motion.filmDate = nil
        Motion.filmSpectrum = nil
        print(String(format: "film: done in %.1fs", Date().timeIntervalSince(started)))
        NSApp.terminate(nil)
    }

    // MARK: - Shots

    private static func shots(base: Date) -> [Shot] {
        let settings = Settings.shared
        var list: [Shot] = []

        func closedBase(_ viewModel: NotchViewModel) {
            settings.idleWidgetsEnabled = false
            viewModel.setPreviewAgentActivity(AgentActivity())
            viewModel.setPreviewMusicActivity(false)
            viewModel.setPreviewFocusActivity(false)
        }

        // The standard peek, and the player and bars tinted from the cover.
        func filmMediaSettings() {
            settings.sneakPeekStyle = .standard
            settings.sliderColor = .albumArt
            settings.spectrumColor = .albumArt
            settings.coloredSpectrogram = true
        }

        // Live activities, each from the moment it appears.
        list.append(Shot(name: "airpods", seconds: 1.3, prepare: { viewModel in
            closedBase(viewModel)
            BluetoothMonitor.shared.injectPreviewChange(name: "AirPods Pro", connected: true, battery: 0.82)
            viewModel.expandingView = SneakPeek(show: true, type: .bluetooth, value: 0.82, icon: "airpods.pro")
        }))

        list.append(Shot(name: "volume", seconds: 1.3, prepare: { viewModel in
            closedBase(viewModel)
        }, pose: { viewModel, t in
            let rise = Motion.easeOut(Motion.progress(t, delay: 0.12, duration: 0.6))
            let level = Float(0.36 + 0.38 * rise)
            HUDManager.shared.injectPreview(.volume, value: level)
            viewModel.expandingView = SneakPeek(
                show: true, type: .hud, value: CGFloat(level), icon: HUDManager.Kind.volume.symbol
            )
        }))

        list.append(Shot(name: "screenshot", seconds: 1.3, prepare: { viewModel in
            closedBase(viewModel)
            ScreenshotWatcher.shared.injectPreviewCatch("Screenshot 2026-09-27 at 9.41.12.png")
            viewModel.expandingView = SneakPeek(show: true, type: .screenshot, value: 1, icon: "camera.viewfinder")
        }))

        list.append(Shot(name: "claude", seconds: 1.4, prepare: { viewModel in
            closedBase(viewModel)
            AgentSessionsManager.shared.injectPreview(.finished(194), name: "Claude Code", broadcast: false)
            viewModel.expandingView = SneakPeek(show: true, type: .agent)
        }))

        // The soundtrack arriving as a track change: the cover turns in, the
        // bars play the music under the video, the title sits in the chin.
        list.append(Shot(name: "music-peek", seconds: 1.3, prepare: { viewModel in
            closedBase(viewModel)
            filmMediaSettings()
            MusicManager.shared.injectPreviewTrack(filmTrack(elapsed: musicHomeTrackTime, playing: true))
            viewModel.sneakPeek = SneakPeek(show: true, type: .music)
        }))

        // The home screen with that music playing: the player beside the
        // weather and today, two agents at work below. It is paused and played
        // again on the edit's beats, and the scrubber keeps the soundtrack's
        // own time.
        list.append(Shot(name: "music-home", seconds: 6.9, prepare: { viewModel in
            filmMediaSettings()
            viewModel.previewOpen()
            viewModel.currentTab = .home
            HomeLayout.filmTiles = [
                HomeTile(kind: .nowPlaying, row: 0, span: 6),
                HomeTile(kind: .weather, row: 0, span: 4),
                HomeTile(kind: .calendar, row: 0, span: 4),
                HomeTile(kind: .agents, row: 1, span: 6),
                HomeTile(kind: .quickActions, row: 1, span: 3),
                HomeTile(kind: .battery, row: 1, span: 2),
            ]
            AgentSessionsManager.shared.injectPreviewSessions(filmSessions())
            MusicManager.shared.injectPreviewTrack(filmTrack(elapsed: musicHomeTrackTime, playing: true))
            viewModel.setPreviewMusicActivity(true)
        }, pose: { _, t in
            let playing = t < musicPauseAt || t >= musicResumeAt
            let elapsed = t < musicPauseAt
                ? musicHomeTrackTime + t
                : (playing ? musicResumeTrackTime + (t - musicResumeAt) : musicHomeTrackTime + musicPauseAt)
            MusicManager.shared.injectPreviewPlayback(elapsed: elapsed, isPlaying: playing)
        }))

        // The shelf: the drop zone lighting up, then holding the file.
        list.append(Shot(name: "shelf-drop", seconds: 1.0, prepare: { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .shelf
            ShelfManager.shared.injectPreviewItems([String]())
            viewModel.isDropTargeted = true
        }))

        list.append(Shot(name: "shelf-held", seconds: 1.0, prepare: { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .shelf
            viewModel.isDropTargeted = false
            ShelfManager.shared.injectPreviewItems([(name: "Sunset.jpg", thumbnail: photoThumbnail())])
        }))

        // Focus: the dial wound round to 25, then Start.
        list.append(Shot(name: "focus", seconds: 3.4, prepare: { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .focus
            FocusTabState.shared.mode = .focus
            FocusManager.shared.clearPreviewSession()
            FocusManager.shared.previewHistory = PreviewRenderer.sampleFocusHistory()
            settings.focusDefaultMinutes = 5
        }, pose: { _, t in
            let minutes = focusDialMinutes(at: t)
            if settings.focusDefaultMinutes != minutes { settings.focusDefaultMinutes = minutes }
            if t >= focusStartsAt {
                FocusManager.shared.injectPreviewSession(
                    minutes: 25, elapsedFraction: (t - focusStartsAt) / 1500, blocked: 0,
                    now: base.addingTimeInterval(t)
                )
            }
        }))

        // Dino Run at sunset, with the jumps placed on the edit's beats.
        list.append(Shot(name: "dino", seconds: 4.5, prepare: { viewModel in
            viewModel.previewOpen()
            viewModel.currentTab = .game
            FocusManager.shared.clearPreviewSession()
            settings.selectedGame = GameChoice.dino.rawValue
            stageDinoRun(base: base)
        }, pose: { _, _ in
            DinoGame.shared.autopilot()
        }, observe: dinoEvents()))

        // Closed again, still playing: the cover and the clock on one side of
        // the camera, the bars and the weather on the other.
        list.append(Shot(name: "closed-media", seconds: 4.6, prepare: { viewModel in
            closedBase(viewModel)
            filmMediaSettings()
            settings.idleWidgetsEnabled = true
            settings.idleLeftWidgets = [.clock]
            settings.idleRightWidgets = [.weather]
            settings.closedMediaDisplay = .mediaAndWidgets
            MusicManager.shared.injectPreviewTrack(filmTrack(elapsed: musicHomeTrackTime, playing: true))
            viewModel.setPreviewMusicActivity(true)
            viewModel.expandingView = SneakPeek()
            measureWidgets(viewModel, besideMedia: true)
        }))

        return list
    }

    // MARK: - Choreography

    /// When Start is pressed in the focus shot. The video lines this up with
    /// a beat, so it is shared with the composition through film.json's
    /// timing and the same constants in the cursor path.
    static let focusStartsAt = 2.0

    /// The soundtrack's position when the home opens, and when it is paused
    /// and played again in that shot. The edit stops the music for the second
    /// between, and plays it again from the drop, 16.02s into the track.
    static let musicHomeTrackTime = 13.02
    static let musicPauseAt = 2.5
    static let musicResumeAt = 3.5
    static let musicResumeTrackTime = 16.02

    /// The dial is wound from 5 to 25 minutes between these times, easing in
    /// and out, and snaps to five-minute detents as the real one does.
    static let focusDragFrom = 0.30
    static let focusDragTo = 1.45

    static func focusDialAngle(at t: Double) -> Double {
        let p = Motion.easeInOut((t - focusDragFrom) / (focusDragTo - focusDragFrom))
        return 30 + 120 * p
    }

    static func focusDialMinutes(at t: Double) -> Int {
        min(max(Int((focusDialAngle(at: t) / 30).rounded()) * 5, 5), 25)
    }

    /// A run that jumps a cactus pair under an arc of gems at 1s, a low
    /// pterodactyl at 2s and a tall cactus at 3s — the beats the edit cuts on.
    private static func stageDinoRun(base: Date) {
        let game = DinoGame.shared
        let board = CGSize(width: openNotchSize.width - 44, height: 133)
        game.startForFilm(size: board, score: 556, date: base)

        // The autopilot jumps when an obstacle is `lead` points ahead.
        let speed: CGFloat = 385
        let lead = speed * 0.2 + 8
        func groundX(jumpingAt t: CGFloat) -> CGFloat { DinoGame.dinoX + lead + speed * t }

        let first = groundX(jumpingAt: 1.0)
        game.placeForTesting(.cactus, at: first, stems: 2)
        for index in 0 ..< 5 {
            let u = CGFloat(index) / 4
            let arc = 48 * (1 - (2 * u - 1) * (2 * u - 1))
            game.placeGemForTesting(x: first + 10 + (u - 0.5) * 92, altitude: 12 + arc)
        }
        // Birds fly a little faster than the ground scrolls, and are placed
        // where a ground obstacle would be, so aim by the ground's timing.
        game.placeForTesting(.bird, at: groundX(jumpingAt: 2.0), level: 0)
        game.placeForTesting(.cactus, at: groundX(jumpingAt: 3.0), tall: true)
    }

    /// Jumps, landings, gems and milestones as they happen in the dino shot.
    private static func dinoEvents() -> () -> [String] {
        var wasOnGround = true
        var gems = 0
        var glow = 0.0
        return {
            let game = DinoGame.shared
            var found: [String] = []
            if wasOnGround, !game.isOnGround { found.append("jump") }
            if !wasOnGround, game.isOnGround { found.append("land") }
            if game.gemsThisRun > gems { found.append("gem-\(min(game.gemRun - 1, 5))") }
            if game.milestoneGlow > glow + 0.5 { found.append("milestone") }
            wasOnGround = game.isOnGround
            gems = game.gemsThisRun
            glow = game.milestoneGlow
            return found
        }
    }

    /// In the app the widgets report their widths after the first layout and
    /// the notch widens to fit them. Offscreen that report never comes back,
    /// so take the widths from a first frame's pixels instead, the same way
    /// `NotchWidgetStack` measures itself: its content plus 26 points.
    private static func measureWidgets(_ viewModel: NotchViewModel, besideMedia: Bool = false) {
        guard let image = render(viewModel),
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return }
        let perRow = image.bytesPerRow
        let perPixel = image.bitsPerPixel / 8
        let rows = min(Int(30 * scale), image.height)
        var left = image.width
        var right = 0
        for y in 0 ..< rows {
            for x in 0 ..< image.width {
                let offset = y * perRow + x * perPixel
                let bright = max(bytes[offset], bytes[offset + 1], bytes[offset + 2])
                if bright > 40 {
                    left = min(left, x)
                    right = max(right, x)
                }
            }
        }
        guard left < right else { return }
        let closed = viewModel.closedNotchSize.width
        let cutoutLeft = (windowSize.width - closed) / 2
        let cutoutRight = cutoutLeft + closed
        let contentLeft = CGFloat(left) / scale
        let contentRight = CGFloat(right + 1) / scale
        // Beside the cover and the bars, those take the first stretch from the
        // camera, and the widgets only what is beyond it.
        let media = besideMedia ? NotchViewModel.musicActivityInset : 0
        viewModel.updateMeasuredWidgetWidths([
            .leading: cutoutLeft - contentLeft + 14 - media,
            .trailing: contentRight - cutoutRight + 14 - media,
        ])
    }

    // MARK: - Invented data

    /// Now, to the minute — or today at `FUNNOTCH_FILM_TIME` (HH:mm), so a
    /// shot re-rendered later still agrees with the rest. Everything on
    /// screen reads its time from this.
    private static func filmBaseDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        if let fixed = ProcessInfo.processInfo.environment["FUNNOTCH_FILM_TIME"] {
            let pieces = fixed.split(separator: ":").compactMap { Int($0) }
            if pieces.count == 2 {
                parts.hour = pieces[0]
                parts.minute = pieces[1]
            }
        }
        return calendar.date(from: parts) ?? now
    }

    private static func sampleAgenda(on day: Date) -> [AgendaItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let hour = calendar.component(.hour, from: day)
        func event(_ title: String, _ offsetHours: Int, _ minute: Int, minutes: Int, color: Color) -> AgendaItem {
            let begins = calendar.date(byAdding: DateComponents(hour: min(hour + offsetHours, 23), minute: minute), to: start)
            return AgendaItem(
                id: "film-\(title)", title: title, start: begins,
                end: begins.map { $0.addingTimeInterval(TimeInterval(minutes * 60)) },
                isAllDay: false, calendarColor: color, calendarTitle: "Work", kind: .event,
                location: nil, externalIdentifier: nil, meetingURL: nil
            )
        }
        // Two: the tile has room for two rows, and offscreen there is no
        // scroll view to hold a third.
        return [
            event("Design review", 1, 30, minutes: 45, color: .blue),
            event("Coffee with Sam", 3, 0, minutes: 30, color: .green),
        ]
    }

    /// Two Claude Code sessions hard at work.
    private static func filmSessions() -> [AgentSessionsManager.Session] {
        let now = Date()
        func make(_ id: String, _ name: String, since: TimeInterval) -> AgentSessionsManager.Session {
            AgentSessionsManager.Session(
                id: id, agent: .claude, name: name, project: "funnotch", status: .working,
                statusSince: now.addingTimeInterval(-since), turnStartedAt: now.addingTimeInterval(-since),
                lastTurnDuration: nil, startedAt: now.addingTimeInterval(-1800), pid: nil, host: .claudeApp
            )
        }
        return [make("film-a", "Landing page", since: 134), make("film-b", "Fix login bug", since: 41)]
    }

    /// The soundtrack, as the track the notch is playing. `FUNNOTCH_FILM_TRACK`
    /// names it — `title|artist|album|seconds` — so the notch credits the
    /// music actually under the video.
    private static func filmTrack(elapsed: TimeInterval, playing: Bool) -> TrackInfo {
        let parts = (ProcessInfo.processInfo.environment["FUNNOTCH_FILM_TRACK"] ?? "")
            .split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let named = parts.count == 4
        return TrackInfo(
            title: named ? parts[0] : "Sunset Drive",
            artist: named ? parts[1] : "FunNotch",
            album: named ? parts[2] : "Film",
            artwork: filmCover,
            duration: named ? Double(parts[3]) ?? 180 : 180,
            elapsed: elapsed,
            isPlaying: playing
        )
    }

    /// The cover from `FUNNOTCH_FILM_COVER`, loaded once.
    private static let filmCover: NSImage? = ProcessInfo.processInfo.environment["FUNNOTCH_FILM_COVER"]
        .flatMap { NSImage(contentsOfFile: $0) }

    /// Per-frame bar levels from `FUNNOTCH_FILM_SPECTRUM`, measured from the
    /// soundtrack: `{"shots": {"music-peek": [[b0, b1, b2, b3], …]}}`, one
    /// entry per frame of each shot that shows the bars.
    private static func loadSpectrum() -> [String: [[Double]]] {
        guard let path = ProcessInfo.processInfo.environment["FUNNOTCH_FILM_SPECTRUM"],
              let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let shots = object["shots"] as? [String: [[Double]]]
        else { return [:] }
        return shots
    }

    /// The site's own wallpaper, as a photo to drop on the shelf.
    private static func photoThumbnail() -> NSImage? {
        let candidates = [
            ProcessInfo.processInfo.environment["FUNNOTCH_FILM_PHOTO"],
            FileManager.default.currentDirectoryPath + "/Website/wallpaper.jpg",
        ].compactMap { $0 }
        for path in candidates {
            if let image = NSImage(contentsOfFile: path) { return image }
        }
        return nil
    }

    // MARK: - Output

    private static func render(_ viewModel: NotchViewModel) -> CGImage? {
        let root = ZStack(alignment: .top) {
            Color.black
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(Settings.shared)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        let renderer = ImageRenderer(content: root)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Dino Run's own synthesised sounds, for the video's soundtrack.
    private static func exportSounds(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var effects: [(String, GameSound.Effect)] = [
            ("jump", .jump), ("land", .land), ("milestone", .milestone), ("close-call", .closeCall),
        ]
        for step in 0 ..< 6 { effects.append(("gem-\(step)", .gem(step))) }
        for (name, effect) in effects {
            try? GameSound.shared.writeWAV(effect, to: folder.appendingPathComponent("\(name).wav"))
        }
    }
}
