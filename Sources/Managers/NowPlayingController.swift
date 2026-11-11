//
//  NowPlayingController.swift
//  FunNotch
//
//  System-wide now playing via the private MediaRemote framework. This is the
//  only backend that sees every player: browsers, Podcasts, VLC, IINA and the
//  rest. Apple gated it behind a private entitlement in macOS 15.4; from then on
//  the same information comes through the bundled helper in
//  MediaRemoteAdapter.swift, and only if that fails does the app fall back to
//  the scripted controllers.
//

import AppKit
import Foundation

private typealias MRGetNowPlayingInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
private typealias MRGetIsPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
private typealias MRRegisterForNotifications = @convention(c) (DispatchQueue) -> Void
private typealias MRSendCommand = @convention(c) (Int, [String: Any]?) -> Bool
private typealias MRSetElapsedTime = @convention(c) (Double) -> Void

private enum MRCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

final class NowPlayingController: MediaController {
    let type: MediaControllerType = .nowPlaying
    var onUpdate: ((TrackInfo) -> Void)?

    /// MediaRemote stopped answering unentitled callers in macOS 15.4.
    static var isDeprecated: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion > 15 { return true }
        if version.majorVersion == 15, version.minorVersion >= 4 { return true }
        return false
    }

    private var handle: UnsafeMutableRawPointer?
    private var getNowPlayingInfo: MRGetNowPlayingInfo?
    private var getIsPlaying: MRGetIsPlaying?
    private var registerForNotifications: MRRegisterForNotifications?
    private var sendCommand: MRSendCommand?
    private var setElapsedTime: MRSetElapsedTime?

    private var current = TrackInfo()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// Set once MediaRemote has actually answered with something.
    private var everAnswered = false

    init() {
        loadFramework()
    }

    /// On macOS 15.4+ MediaRemote is read through the helper instead.
    private var usesAdapter: Bool { Self.isDeprecated }
    private var adapterListener: UUID?

    var isAvailable: Bool {
        if usesAdapter { return MediaRemoteAdapter.shared.isUsable }
        return getNowPlayingInfo != nil
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_LAZY) else { return }
        self.handle = handle

        func symbol<T>(_ name: String, as: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        getNowPlayingInfo = symbol("MRMediaRemoteGetNowPlayingInfo", as: MRGetNowPlayingInfo.self)
        getIsPlaying = symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: MRGetIsPlaying.self)
        registerForNotifications = symbol("MRMediaRemoteRegisterForNowPlayingNotifications", as: MRRegisterForNotifications.self)
        sendCommand = symbol("MRMediaRemoteSendCommand", as: MRSendCommand.self)
        setElapsedTime = symbol("MRMediaRemoteSetElapsedTime", as: MRSetElapsedTime.self)
    }

    func start() {
        stop()
        if usesAdapter {
            adapterListener = MediaRemoteAdapter.shared.addListener { [weak self] in
                self?.refresh()
            }
            refresh()
            return
        }
        registerForNotifications?(.main)

        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ] {
            let observer = NotificationCenter.default.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refresh()
            }
            observers.append(observer)
        }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        if let adapterListener {
            MediaRemoteAdapter.shared.removeListener(adapterListener)
            self.adapterListener = nil
        }
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func refresh() {
        if usesAdapter {
            let info = MediaRemoteAdapter.shared.track
            // Unchanged state arrives with every position tick; only pass on news.
            guard info != current || abs(info.elapsed - current.elapsed) > 1.5 else { return }
            current = info
            onUpdate?(info)
            return
        }
        guard let getNowPlayingInfo else { return }

        getNowPlayingInfo(.main) { [weak self] information in
            guard let self else { return }
            guard !information.isEmpty else { return }
            self.everAnswered = true

            var info = TrackInfo()
            info.title = information["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            info.artist = information["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            info.album = information["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
            info.duration = information["kMRMediaRemoteNowPlayingInfoDuration"] as? TimeInterval ?? 0
            info.elapsed = information["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? TimeInterval ?? 0
            let rate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            info.isPlaying = rate > 0
            info.timestamp = Date()

            if let data = information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                info.artwork = NSImage(data: data)
            } else {
                info.artwork = self.current.artwork
            }

            // Attribute the track to the frontmost audio app when we can.
            info.bundleIdentifier = information["kMRMediaRemoteNowPlayingInfoClientPropertiesData"] != nil
                ? self.current.bundleIdentifier
                : self.current.bundleIdentifier

            self.current = info
            self.onUpdate?(info)
        }
    }

    func togglePlayPause() { command(.togglePlayPause, .togglePlayPause) }
    func play() { command(.play, .play) }
    func pause() { command(.pause, .pause) }
    func nextTrack() { command(.nextTrack, .nextTrack) }
    func previousTrack() { command(.previousTrack, .previousTrack) }
    func toggleShuffle() { if usesAdapter { MediaRemoteAdapter.shared.send(.toggleShuffle) } }
    func cycleRepeat() { if usesAdapter { MediaRemoteAdapter.shared.send(.toggleRepeat) } }

    private func command(_ direct: MRCommand, _ viaAdapter: MediaRemoteAdapter.Command) {
        if usesAdapter {
            MediaRemoteAdapter.shared.send(viaAdapter)
        } else {
            _ = sendCommand?(direct.rawValue, nil)
        }
    }

    func seek(to time: TimeInterval) {
        if usesAdapter {
            MediaRemoteAdapter.shared.seek(to: time)
        } else {
            setElapsedTime?(time)
        }
        current.elapsed = time
        current.timestamp = Date()
        onUpdate?(current)
    }
}
