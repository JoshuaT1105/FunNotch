//
//  ActivityViews.swift
//  FunNotch
//
//  The strip that drops out from under the collapsed notch to announce
//  something: a power change, a screenshot landing on the shelf, a Bluetooth
//  device, a focus session, or a track change.
//

import SwiftUI

/// The announcement strip below the cutout.
struct ActivityStrip: View {
    let activity: SneakPeek

    @EnvironmentObject private var settings: Settings
    @ObservedObject private var battery = BatteryManager.shared

    var body: some View {
        HStack(spacing: 10) {
            // Battery always draws from live state so the glyph cannot drift
            // out of sync with the charge that is actually being reported.
            Image(systemName: activity.type == .battery ? battery.symbolName : symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(activity.type == .battery ? battery.indicatorColor : .white)
                .frame(width: 20)

            switch activity.type {
            case .battery:
                batteryDetail
            case .hud:
                hudDetail
            case .screenshot, .bluetooth, .download:
                ActivityCaption(activity: activity)
            default:
                progressBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var symbolName: String {
        activity.icon.isEmpty ? "circle" : activity.icon
    }

    /// A plain bar and a percentage, which is all the system panel is.
    private var hudDetail: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.22))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(proxy.size.width * activity.value, 2))
                }
            }
            .frame(height: 6)

            Text("\(Int((activity.value * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private var batteryDetail: some View {
        Group {
            VStack(alignment: .leading, spacing: 1) {
                Text(battery.isPluggedIn ? "Charging" : "On battery")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(battery.timeRemainingText ?? battery.percentageText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Text(battery.percentageText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.22))
            Capsule()
                .fill(settings.accentColor)
                .frame(width: max(6, 220 * activity.value))
        }
        .frame(height: 6)
    }
}

/// Title and subtitle for the activities that are an announcement rather than a
/// level: a screenshot landing on the shelf, or a Bluetooth device connecting.
private struct ActivityCaption: View {
    let activity: SneakPeek

    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var bluetooth = BluetoothMonitor.shared
    @ObservedObject private var downloads = DownloadWatcher.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        Spacer(minLength: 0)

        if activity.type == .bluetooth, let battery = bluetooth.lastChange?.device.battery, battery > 0 {
            Text("\(Int(battery * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    private var title: String {
        switch activity.type {
        case .screenshot:
            return "Added to shelf"
        case .download:
            return "Download finished"
        case .bluetooth:
            guard let change = bluetooth.lastChange else { return "Bluetooth" }
            return change.connected ? "Connected" : "Disconnected"
        default:
            return ""
        }
    }

    private var subtitle: String {
        switch activity.type {
        case .screenshot:
            return screenshots.lastCatch?.lastPathComponent ?? "Screenshot"
        case .download:
            return downloads.lastDownload?.lastPathComponent ?? "File"
        case .bluetooth:
            return bluetooth.lastChange?.device.name ?? ""
        default:
            return ""
        }
    }
}

/// Track-change peek in the standard style: art, title and artist under the notch.
struct StandardMusicPeek: View {
    @ObservedObject private var music = MusicManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        HStack(spacing: 9) {
            if let artwork = music.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "music.note").font(.system(size: 10)))
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(music.track.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(music.track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            MusicVisualizer(
                isPlaying: music.isPlaying,
                color: settings.coloredSpectrogram
                    ? settings.spectrumColor.resolved(albumArt: music.artworkColor, accent: settings.accentColor)
                    : .white
            )
            .frame(width: 16, height: 13)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
