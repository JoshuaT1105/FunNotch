//
//  MediaRemoteAdapter.swift
//  FunNotch
//
//  System-wide now playing on macOS 15.4 and later.
//
//  macOS 15.4 stopped answering apps that ask the private MediaRemote
//  framework what is playing, which is why Now Playing only covered Music,
//  Spotify and browsers from then on. `/usr/bin/perl` is still entitled to ask,
//  so this runs the bundled helper from ungive/mediaremote-adapter through it:
//
//      /usr/bin/perl mediaremote-adapter.pl <framework> <test client> stream
//
//  The helper prints one JSON object per line whenever anything changes. One
//  long-lived process is shared by every NowPlayingController instance, since
//  MusicManager creates a fresh controller each time it re-picks a backend.
//  Commands (play, next, seek…) are short separate invocations.
//
//  If the helper ever stops working on a future macOS, `health` turns
//  `.broken` and MusicManager falls back to the scripted backends exactly as
//  it did before.
//

import AppKit
import Foundation

/// Main-thread only: every callback below is hopped onto the main queue.
final class MediaRemoteAdapter {
    static let shared = MediaRemoteAdapter()

    enum Health: Equatable {
        /// The helper files are not in the app bundle (a development build
        /// that skipped them, say).
        case missing
        /// Started, not yet confirmed either way.
        case starting
        case working
        /// The helper exited with an error or failed its self-check.
        case broken(String)
    }

    private(set) var health: Health = .starting
    /// The latest merged payload from the stream.
    private var state: [String: Any] = [:]
    private var process: Process?
    private var buffer = Data()
    private var listeners: [UUID: () -> Void] = [:]
    private var restarts = 0
    private var cachedArtwork: (key: String, image: NSImage)?
    private var selfCheckDone = false

    private init() {
        if !Self.filesPresent { health = .missing }
    }

    // MARK: - Bundle layout

    private static var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
    }

    /// Where the helper actually runs from.
    ///
    /// A downloaded copy of the app carries the quarantine flag on every file
    /// inside it, and Gatekeeper then refuses to let `/usr/bin/perl` load the
    /// quarantined framework, even after the user has allowed the app itself.
    /// So the helper is copied out to Application Support once per build, and
    /// the copy, which the app wrote itself, has the flag removed. If that
    /// fails for any reason, the bundled files are used as they are.
    private static let directory: URL? = {
        guard let source = bundledDirectory else { return nil }
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return source }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let parent = support.appendingPathComponent("FunNotch", isDirectory: true)
        let target = parent.appendingPathComponent("MediaRemoteAdapter-\(build)", isDirectory: true)
        let binary = "MediaRemoteAdapter.framework/MediaRemoteAdapter"
        func size(_ url: URL) -> Int? {
            (try? fm.attributesOfItem(atPath: url.appendingPathComponent(binary).path)[.size]) as? Int
        }
        do {
            if size(target) == nil || size(target) != size(source) {
                try? fm.removeItem(at: target)
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target)
            }
            removeQuarantine(under: target)
            // Copies left behind by earlier builds.
            for old in (try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            where old.lastPathComponent.hasPrefix("MediaRemoteAdapter-") && old != target {
                try? fm.removeItem(at: old)
            }
            return target
        } catch {
            DiagnosticLog.write("media", "adapter copy failed, using the bundled files: \(error.localizedDescription)")
            return source
        }
    }()

    private static func removeQuarantine(under root: URL) {
        removexattr(root.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(atPath: root.path) else { return }
        for case let relative as String in items {
            removexattr(root.appendingPathComponent(relative).path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }
    private static var script: URL? { directory?.appendingPathComponent("mediaremote-adapter.pl") }
    private static var framework: URL? { directory?.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true) }
    private static var testClient: URL? { directory?.appendingPathComponent("MediaRemoteAdapterTestClient") }

    static var filesPresent: Bool {
        guard let script, let framework, let testClient else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: script.path)
            && fm.fileExists(atPath: framework.appendingPathComponent("MediaRemoteAdapter").path)
            && fm.isExecutableFile(atPath: testClient.path)
            && fm.isExecutableFile(atPath: "/usr/bin/perl")
    }

    /// Arguments that come before every command.
    private static var baseArguments: [String]? {
        guard let script, let framework, let testClient else { return nil }
        return [script.path, framework.path, testClient.path]
    }

    /// True while the helper is usable, or still might be.
    var isUsable: Bool {
        switch health {
        case .working, .starting: return Self.filesPresent
        case .missing, .broken: return false
        }
    }

    // MARK: - Listening

    /// Registers a callback for every change and makes sure the stream runs.
    func addListener(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID()
        listeners[id] = callback
        startIfNeeded()
        return id
    }

    func removeListener(_ id: UUID) {
        listeners[id] = nil
    }

    func startIfNeeded() {
        guard process == nil, Self.filesPresent, let base = Self.baseArguments else { return }
        if case .broken = health { return }
        Self.endOrphanedHelpers()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = base + ["stream", "--micros", "--debounce=100", "--allow-missing-title"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            DispatchQueue.main.async { self?.streamEnded(status: status, reason: reason) }
        }

        do {
            try process.run()
            self.process = process
            DiagnosticLog.write("media", "adapter stream started (pid \(process.processIdentifier))")
            scheduleSelfCheck()
        } catch {
            health = .broken("could not start /usr/bin/perl: \(error.localizedDescription)")
            DiagnosticLog.write("media", "adapter failed to start: \(error.localizedDescription)")
            notify()
        }
    }

    /// A helper whose app quit without stopping it (a crash, a force quit, a
    /// test run) is re-parented to launchd and would stream on unseen. End any
    /// such leftover of ours before starting a new one.
    private static var orphansChecked = false
    private static func endOrphanedHelpers() {
        guard !orphansChecked, let script = script?.path else { return }
        orphansChecked = true
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return }
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), fields[1] == "1",
                  fields[2].hasPrefix("/usr/bin/perl "), fields[2].contains(script)
            else { continue }
            kill(pid, SIGTERM)
            DiagnosticLog.write("media", "ended a leftover adapter stream (pid \(pid))")
        }
    }

    func stop() {
        guard let process else { return }
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        if process.isRunning { process.terminate() }
        self.process = nil
    }

    private func streamEnded(status: Int32, reason: Process.TerminationReason) {
        process = nil
        // A clean exit or our own SIGTERM: nothing is wrong.
        if reason == .uncaughtSignal || status == 0 { return }
        restarts += 1
        DiagnosticLog.write("media", "adapter stream exited with status \(status), restart \(restarts)")
        if restarts > 3 {
            health = .broken("the helper keeps exiting (status \(status))")
            state = [:]
            notify()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(restarts) * 2) { [weak self] in
            self?.startIfNeeded()
        }
    }

    /// Runs the helper's own check once per launch: it confirms that MediaRemote
    /// still answers, so a future macOS that closes this route is noticed.
    /// It is only needed while nothing has been reported; real data proves the
    /// route works on its own.
    private func scheduleSelfCheck() {
        guard !selfCheckDone else { return }
        selfCheckDone = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.health == .starting else { return }
            self.run(["test"]) { status in
                if status == 0 {
                    self.health = .working
                } else {
                    self.health = .broken("MediaRemote did not answer the helper's test (status \(status))")
                    self.stop()
                    self.state = [:]
                }
                DiagnosticLog.write("media", "adapter self-check: \(self.health)")
                self.notify()
            }
        }
    }

    // MARK: - Parsing

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex ..< newline]
            buffer.removeSubrange(buffer.startIndex ... newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            apply(payload, isDiff: object["diff"] as? Bool ?? false)
        }
    }

    private func apply(_ payload: [String: Any], isDiff: Bool) {
        if isDiff {
            for (key, value) in payload {
                if value is NSNull { state.removeValue(forKey: key) } else { state[key] = value }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }
        if !state.isEmpty, health != .working {
            health = .working
            restarts = 0
        }
        notify()
    }

    private func notify() {
        for callback in listeners.values { callback() }
    }

    // MARK: - Reading

    /// The current track, empty when nothing is playing.
    var track: TrackInfo {
        var info = TrackInfo()
        guard isUsable, !state.isEmpty else { return info }

        let bundle = state["bundleIdentifier"] as? String
        let parent = state["parentApplicationBundleIdentifier"] as? String
        info.bundleIdentifier = parent ?? bundle

        info.title = state["title"] as? String ?? ""
        info.artist = state["artist"] as? String ?? ""
        info.album = state["album"] as? String ?? ""
        // Some players (QuickTime, for one) report playback with no title.
        // Name the app rather than show nothing.
        if info.title.isEmpty, let identifier = info.bundleIdentifier {
            info.title = Self.appName(for: identifier) ?? ""
        }

        if let micros = Self.number(state["durationMicros"]) { info.duration = micros / 1_000_000 }
        if let micros = Self.number(state["elapsedTimeMicros"]) { info.elapsed = micros / 1_000_000 }
        if let epochMicros = Self.number(state["timestampEpochMicros"]) {
            info.timestamp = Date(timeIntervalSince1970: epochMicros / 1_000_000)
        } else {
            info.timestamp = Date()
        }
        if let playing = state["playing"] as? Bool {
            info.isPlaying = playing
        } else {
            info.isPlaying = (Self.number(state["playbackRate"]) ?? 0) > 0
        }
        if let shuffle = Self.number(state["shuffleMode"]) { info.isShuffled = shuffle > 1 }
        if let repeatMode = Self.number(state["repeatMode"]) {
            info.repeatMode = repeatMode == 2 ? .one : (repeatMode == 3 ? .all : .off)
        }
        info.artwork = artwork()
        return info
    }

    private func artwork() -> NSImage? {
        guard let encoded = state["artworkData"] as? String, !encoded.isEmpty else {
            cachedArtwork = nil
            return nil
        }
        // The same artwork arrives with every full payload; decode it once.
        let key = "\(encoded.count):\(encoded.prefix(64)):\(encoded.suffix(64))"
        if let cached = cachedArtwork, cached.key == key { return cached.image }
        guard let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else { return nil }
        cachedArtwork = (key, image)
        return image
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func appName(for bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Commands

    enum Command: Int {
        case play = 0, pause = 1, togglePlayPause = 2, nextTrack = 4, previousTrack = 5
        case toggleShuffle = 6, toggleRepeat = 7
    }

    func send(_ command: Command) {
        run(["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        run(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    /// Runs one short helper command off the main thread.
    private func run(_ arguments: [String], completion: ((Int32) -> Void)? = nil) {
        guard let base = Self.baseArguments, Self.filesPresent else {
            completion?(-1)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = base + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var status: Int32 = -1
            do {
                try process.run()
                process.waitUntilExit()
                status = process.terminationStatus
            } catch {
                status = -1
            }
            if let completion {
                DispatchQueue.main.async { completion(status) }
            }
        }
    }

    // MARK: - Diagnostics

    /// Runs one helper command and waits, for the self-test. Never call this
    /// from the main thread in normal use.
    static func runSynchronously(_ arguments: [String], timeout: TimeInterval = 10) -> (status: Int32, output: String) {
        guard let base = baseArguments, filesPresent else { return (-1, "helper not bundled") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = base + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return (-2, "timed out") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    var healthDescription: String {
        switch health {
        case .missing: return "helper not bundled"
        case .starting: return "starting"
        case .working: return "working"
        case .broken(let reason): return "not working: \(reason)"
        }
    }
}
