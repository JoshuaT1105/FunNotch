//
//  MediaController.swift
//  FunNotch
//
//  A backend that can report and drive "what is playing right now".
//

import AppKit
import Foundation

/// Everything the UI needs to know about the current track.
struct TrackInfo: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var artwork: NSImage?
    var duration: TimeInterval = 0
    var elapsed: TimeInterval = 0
    var isPlaying: Bool = false
    var isShuffled: Bool = false
    var repeatMode: RepeatMode = .off
    var bundleIdentifier: String?
    /// When `elapsed` was last measured, so playback can be interpolated.
    var timestamp: Date = .init()

    var isEmpty: Bool {
        title.isEmpty && artist.isEmpty
    }

    /// True when the backend actually told us how long the track is. Without
    /// it there is no honest scrubber to draw.
    var hasTiming: Bool { duration > 0 }

    /// Elapsed time projected forward to now while playing. With no known
    /// duration this stays put rather than counting up from nowhere — a
    /// browser tab read from its title has no position to report.
    var interpolatedElapsed: TimeInterval {
        guard isPlaying, hasTiming else { return elapsed }
        return min(elapsed + Date().timeIntervalSince(timestamp), duration)
    }

    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.duration == rhs.duration
            && lhs.isShuffled == rhs.isShuffled
            && lhs.repeatMode == rhs.repeatMode
            && lhs.artwork === rhs.artwork
    }
}

protocol MediaController: AnyObject {
    var type: MediaControllerType { get }
    /// Called whenever the backend has fresh information.
    var onUpdate: ((TrackInfo) -> Void)? { get set }
    /// True when this backend can currently provide anything at all.
    var isAvailable: Bool { get }

    func start()
    func stop()
    /// Forces a refresh outside the normal cadence.
    func refresh()

    func play()
    func pause()
    func togglePlayPause()
    func nextTrack()
    func previousTrack()
    func seek(to time: TimeInterval)
    func toggleShuffle()
    func cycleRepeat()
}

extension MediaController {
    func play() {}
    func pause() {}
    func toggleShuffle() {}
    func cycleRepeat() {}
}
