//
//  ScriptedMediaController.swift
//  FunNotch
//
//  Apple Music and Spotify are both driven over Apple Events. They share the
//  same polling / notification shape, so the differences live in a small
//  description struct.
//

import AppKit
import Foundation

/// Per-app AppleScript vocabulary.
private struct ScriptDialect {
    let bundleIdentifier: String
    let applicationName: String
    /// Distributed notification posted when playback state changes.
    let notificationName: String
    /// Track duration comes back in milliseconds (Spotify) or seconds (Music).
    let durationInMilliseconds: Bool
    let stateScript: String
    let artworkScript: String
    let shuffleCommand: (Bool) -> String
    let repeatCommand: (RepeatMode) -> String
}

private let fieldSeparator = "|~|"

final class ScriptedMediaController: MediaController {
    let type: MediaControllerType
    var onUpdate: ((TrackInfo) -> Void)?

    private let dialect: ScriptDialect
    private var timer: Timer?
    private var current = TrackInfo()
    private var lastArtworkKey = ""
    private var isFetchingArtwork = false
    private var observer: NSObjectProtocol?

    init?(type: MediaControllerType) {
        guard let dialect = ScriptedMediaController.dialect(for: type) else { return nil }
        self.type = type
        self.dialect = dialect
    }

    var isAvailable: Bool {
        AppleScriptRunner.isRunning(dialect.bundleIdentifier)
    }

    func start() {
        stop()

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(dialect.notificationName),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        // The notification covers state changes; the timer keeps the scrubber
        // honest and notices apps launching or quitting.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
    }

    func refresh() {
        guard isAvailable else {
            if !current.isEmpty || current.isPlaying {
                current = TrackInfo()
                onUpdate?(current)
            }
            return
        }

        AppleScriptRunner.shared.runForString(dialect.stateScript) { [weak self] result in
            guard let self else { return }
            guard let result, !result.isEmpty else { return }
            self.apply(rawState: result)
        }
    }

    private func apply(rawState: String) {
        let parts = rawState.components(separatedBy: fieldSeparator)
        guard parts.count >= 8 else { return }

        var info = TrackInfo()
        info.title = parts[0]
        info.artist = parts[1]
        info.album = parts[2]
        info.duration = Double(parts[3]) ?? 0
        if dialect.durationInMilliseconds {
            info.duration /= 1000
        }
        info.elapsed = Double(parts[4]) ?? 0
        info.isPlaying = parts[5].lowercased().contains("playing")
        info.isShuffled = parts[6].lowercased().hasPrefix("true")
        info.repeatMode = Self.parseRepeat(parts[7])
        info.bundleIdentifier = dialect.bundleIdentifier
        info.timestamp = Date()
        info.artwork = current.artwork

        let key = "\(info.title)|\(info.artist)|\(info.album)"
        if key != lastArtworkKey {
            lastArtworkKey = key
            info.artwork = nil
            fetchArtwork(for: key)
        }

        current = info
        onUpdate?(info)
    }

    private static func parseRepeat(_ raw: String) -> RepeatMode {
        let value = raw.lowercased()
        if value.contains("one") { return .one }
        if value.contains("all") || value.contains("context") || value == "true" { return .all }
        return .off
    }

    private func fetchArtwork(for key: String) {
        guard !isFetchingArtwork else { return }
        isFetchingArtwork = true

        AppleScriptRunner.shared.run(dialect.artworkScript) { [weak self] descriptor, _ in
            guard let self else { return }
            self.isFetchingArtwork = false
            guard key == self.lastArtworkKey else { return }

            // Spotify hands back a URL, Music hands back raw image bytes.
            if let string = descriptor?.stringValue, string.hasPrefix("http") {
                self.downloadArtwork(from: string, key: key)
                return
            }
            if let data = descriptor?.data, data.count > 128, let image = NSImage(data: data) {
                self.current.artwork = image
                self.onUpdate?(self.current)
            }
        }
    }

    private func downloadArtwork(from urlString: String, key: String) {
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard key == self.lastArtworkKey else { return }
                self.current.artwork = image
                self.onUpdate?(self.current)
            }
        }.resume()
    }

    // MARK: - Transport

    private func tell(_ command: String) {
        AppleScriptRunner.shared.execute("tell application \"\(dialect.applicationName)\" to \(command)")
    }

    func play() { tell("play") }
    func pause() { tell("pause") }
    func togglePlayPause() { tell("playpause") }
    func nextTrack() { tell("next track") }
    func previousTrack() { tell("previous track") }

    func seek(to time: TimeInterval) {
        tell("set player position to \(Int(time))")
        current.elapsed = time
        current.timestamp = Date()
        onUpdate?(current)
    }

    func toggleShuffle() {
        AppleScriptRunner.shared.execute(dialect.shuffleCommand(!current.isShuffled))
    }

    func cycleRepeat() {
        let next: RepeatMode
        switch current.repeatMode {
        case .off: next = .all
        case .all: next = .one
        case .one: next = .off
        }
        AppleScriptRunner.shared.execute(dialect.repeatCommand(next))
    }

    /// Whether the target app exists on this Mac. Scripts for a missing app
    /// cannot even be compiled, because its terminology is unavailable.
    static func isInstalled(_ type: MediaControllerType) -> Bool {
        guard let identifier = type.appBundleIdentifier else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil
    }

    /// Compiles the scripts without sending an Apple Event, so a syntax error
    /// surfaces immediately instead of looking like "nothing is playing".
    /// Returns nil for apps that are not installed.
    static func validateScripts() -> [(type: MediaControllerType, error: String?)] {
        var results: [(type: MediaControllerType, error: String?)] = []

        for type in MediaControllerType.allCases {
            guard let dialect = dialect(for: type), isInstalled(type) else { continue }

            var failure: String?
            for source in [dialect.stateScript, dialect.artworkScript] where failure == nil {
                guard let script = NSAppleScript(source: source) else {
                    failure = "could not create script"
                    continue
                }
                var errorInfo: NSDictionary?
                if !script.compileAndReturnError(&errorInfo) {
                    failure = errorInfo?[NSAppleScript.errorMessage] as? String ?? "unknown error"
                }
            }
            results.append((type, failure))
        }

        return results
    }

    // MARK: - Dialects

    private static func dialect(for type: MediaControllerType) -> ScriptDialect? {
        switch type {
        case .appleMusic:
            return ScriptDialect(
                bundleIdentifier: "com.apple.Music",
                applicationName: "Music",
                notificationName: "com.apple.Music.playerInfo",
                durationInMilliseconds: false,
                stateScript: """
                tell application "Music"
                    set out to ""
                    try
                        set t to current track
                        set sep to "\(fieldSeparator)"
                        set out to (name of t as string) & sep & (artist of t as string) & sep ¬
                            & (album of t as string) & sep & ((duration of t) as string) & sep ¬
                            & ((player position) as string) & sep & ((player state) as string) & sep ¬
                            & ((shuffle enabled) as string) & sep & ((song repeat) as string)
                    end try
                    return out
                end tell
                """,
                artworkScript: """
                tell application "Music"
                    try
                        return raw data of artwork 1 of current track
                    on error
                        return ""
                    end try
                end tell
                """,
                shuffleCommand: { enabled in
                    "tell application \"Music\" to set shuffle enabled to \(enabled)"
                },
                repeatCommand: { mode in
                    "tell application \"Music\" to set song repeat to \(mode.rawValue)"
                }
            )

        case .spotify:
            return ScriptDialect(
                bundleIdentifier: "com.spotify.client",
                applicationName: "Spotify",
                notificationName: "com.spotify.client.PlaybackStateChanged",
                durationInMilliseconds: true,
                stateScript: """
                tell application "Spotify"
                    set out to ""
                    try
                        set t to current track
                        set sep to "\(fieldSeparator)"
                        set out to (name of t as string) & sep & (artist of t as string) & sep ¬
                            & (album of t as string) & sep & ((duration of t) as string) & sep ¬
                            & ((player position) as string) & sep & ((player state) as string) & sep ¬
                            & ((shuffling) as string) & sep & ((repeating) as string)
                    end try
                    return out
                end tell
                """,
                artworkScript: """
                tell application "Spotify"
                    try
                        return artwork url of current track
                    on error
                        return ""
                    end try
                end tell
                """,
                shuffleCommand: { enabled in
                    "tell application \"Spotify\" to set shuffling to \(enabled)"
                },
                repeatCommand: { mode in
                    "tell application \"Spotify\" to set repeating to \(mode == .off ? "false" : "true")"
                }
            )

        case .nowPlaying, .browser:
            return nil
        }
    }
}
