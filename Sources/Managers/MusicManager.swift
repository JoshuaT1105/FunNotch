//
//  MusicManager.swift
//  FunNotch
//
//  Owns whichever media backend is active, publishes the current track to the
//  UI, and fires the "sneak peek" when the song changes.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class MusicManager: ObservableObject {
    static let shared = MusicManager()

    @Published private(set) var track = TrackInfo()
    @Published private(set) var artwork: NSImage?
    /// Colours sampled from the artwork, used to tint the player.
    @Published private(set) var artworkColor: Color = .gray
    @Published private(set) var artworkSecondaryColor: Color = .gray
    /// Continuously updated playback position for the scrubber.
    @Published var displayedElapsed: TimeInterval = 0
    /// True while the user is dragging the scrubber, so updates do not fight them.
    @Published var isScrubbing = false

    private var controller: MediaController?
    private var fallbackControllers: [MediaController] = []
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastTrackKey = ""
    private var lastArtworkPointer: NSImage?
    /// When the active backend first went quiet, for the re-pick above.
    private var emptySince: Date?

    private let settings = Settings.shared

    private init() {}

    /// True when MediaRemote is unusable on this OS, so the UI can explain why.
    var isNowPlayingDeprecated: Bool { NowPlayingController.isDeprecated }

    var isPlaying: Bool { track.isPlaying }

    /// Icon of the app the music is coming from, for the live activity.
    var sourceAppIcon: NSImage? {
        guard let identifier = track.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func start() {
        NotificationCenter.default.publisher(for: .mediaControllerChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.activateController() }
            .store(in: &cancellables)

        // Apps launching or quitting can change which backend is usable.
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.activateController() }
            .store(in: &cancellables)

        activateController()

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func tick() {
        if !isScrubbing {
            let elapsed = track.interpolatedElapsed
            // Assigning an unchanged value still fires `objectWillChange`, and
            // that redraws and re-lays-out the whole notch. Five times a second
            // with nothing playing, this was the busiest thing the app did.
            if abs(elapsed - displayedElapsed) > 0.05 {
                displayedElapsed = elapsed
            }
        }

        // Whichever backend is live may simply have nothing to say — the user
        // switched from Music to a YouTube tab, say. Re-pick periodically so
        // that move is picked up without any intervention.
        guard track.isEmpty else {
            emptySince = nil
            return
        }
        let now = Date()
        guard let since = emptySince else {
            emptySince = now
            return
        }
        if now.timeIntervalSince(since) > 4 {
            emptySince = now
            activateController()
        }
    }

    // MARK: - Backend selection

    private func activateController() {
        let desired = settings.mediaController
        let candidate = makeController(for: desired)

        // If the chosen backend cannot see anything (app not running, or
        // MediaRemote locked down) fall through to one that can.
        let chosen: MediaController
        if candidate.isAvailable {
            chosen = candidate
        } else if let alternative = firstAvailableFallback(excluding: desired) {
            chosen = alternative
        } else {
            chosen = candidate
        }

        if let existing = controller, existing.type == chosen.type {
            existing.refresh()
            return
        }

        controller?.stop()
        controller = chosen
        chosen.onUpdate = { [weak self] info in
            MainActor.assumeIsolated { self?.handle(info) }
        }
        chosen.start()
    }

    private func makeController(for type: MediaControllerType) -> MediaController {
        switch type {
        case .nowPlaying:
            return NowPlayingController()
        case .appleMusic, .spotify:
            return ScriptedMediaController(type: type) ?? NowPlayingController()
        case .browser:
            return BrowserMediaController()
        }
    }

    private func firstAvailableFallback(excluding type: MediaControllerType) -> MediaController? {
        for candidate in MediaControllerType.allCases where candidate != type {
            let controller = makeController(for: candidate)
            if controller.isAvailable { return controller }
        }
        return nil
    }

    /// The backend actually in use, which can differ from the user's choice.
    var activeControllerType: MediaControllerType? { controller?.type }

    /// Forces an immediate re-read, used after a media key is pressed.
    func refreshNow() {
        controller?.refresh()
    }

    /// Installs a fixed track without touching any backend, for snapshots.
    func injectPreviewTrack(_ info: TrackInfo) {
        track = info
        displayedElapsed = info.elapsed
        artwork = info.artwork
        updateColors(from: info.artwork)
    }

    // MARK: - Incoming updates

    private func handle(_ info: TrackInfo) {
        let key = "\(info.title)|\(info.artist)|\(info.album)"
        let isNewTrack = !key.isEmpty && key != lastTrackKey && !info.title.isEmpty

        track = info
        if !isScrubbing {
            displayedElapsed = info.interpolatedElapsed
        }

        if info.artwork !== lastArtworkPointer {
            lastArtworkPointer = info.artwork
            artwork = info.artwork
            updateColors(from: info.artwork)
        }

        if isNewTrack {
            lastTrackKey = key
            announceTrackChange()
        } else if key.isEmpty {
            lastTrackKey = ""
        }
    }

    private func announceTrackChange() {
        guard settings.enableSneakPeek, track.isPlaying else { return }
        NotchWindowManager.shared.broadcast { viewModel in
            guard viewModel.notchState == .closed else { return }
            viewModel.showSneakPeek(type: .music)
        }
    }

    private func updateColors(from image: NSImage?) {
        guard let image else {
            artworkColor = .gray
            artworkSecondaryColor = .gray
            return
        }
        let colors = image.dominantColors()
        artworkColor = Color(nsColor: colors.primary)
        artworkSecondaryColor = Color(nsColor: colors.secondary)
    }

    // MARK: - Transport

    func togglePlayPause() {
        controller?.togglePlayPause()
        // Optimistically flip so the button feels instant.
        track.isPlaying.toggle()
        track.timestamp = Date()
        track.elapsed = displayedElapsed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.refresh()
        }
    }

    func nextTrack() {
        controller?.nextTrack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.refresh()
        }
    }

    func previousTrack() {
        controller?.previousTrack()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.refresh()
        }
    }

    func seek(to time: TimeInterval) {
        controller?.seek(to: time)
        displayedElapsed = time
    }

    func toggleShuffle() {
        controller?.toggleShuffle()
        track.isShuffled.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.refresh()
        }
    }

    func cycleRepeat() {
        controller?.cycleRepeat()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.controller?.refresh()
        }
    }

    /// Brings the playing app to the front, like clicking the artwork does.
    func openPlayingApp() {
        guard let identifier = track.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
