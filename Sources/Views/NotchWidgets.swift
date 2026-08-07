//
//  NotchWidgets.swift
//  FunNotch
//
//  The small readouts that can sit either side of the camera cutout while the
//  notch is collapsed — and, optionally, in the black banner an app leaves
//  behind when it goes fullscreen.
//
//  Each side reports the width it actually needs rather than declaring one up
//  front: "11:56 AM", "23:56" and "Wed 13 Sept 23:56" are all very different
//  sizes, and a hard-coded guess would clip in some locales.
//

import AppKit
import SwiftUI

/// Measured widths of the widget stacks currently on screen, keyed by side.
struct WidgetWidthKey: PreferenceKey {
    static let defaultValue: [NotchSide: CGFloat] = [:]

    static func reduce(value: inout [NotchSide: CGFloat], nextValue: () -> [NotchSide: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

enum NotchSide: Hashable {
    case leading
    case trailing
}

/// A whole side's worth of widgets, measured as one unit.
struct NotchWidgetStack: View {
    let widgets: [NotchWidget]
    let side: NotchSide

    /// Breathing room between the stack and the cutout, plus enough margin for
    /// the notch's rounded outer corner.
    private let inset: CGFloat = 12
    private let outerMargin: CGFloat = 14

    var body: some View {
        HStack(spacing: 12) {
            ForEach(widgets) { widget in
                NotchWidgetButton(widget: widget)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WidgetWidthKey.self,
                    value: [side: proxy.size.width + inset + outerMargin]
                )
            }
        )
        .padding(side == .leading ? .trailing : .leading, inset)
        .frame(maxWidth: .infinity, alignment: side == .leading ? .trailing : .leading)
    }
}

/// Wraps a widget so clicking it goes somewhere useful instead of just opening
/// the notch.
private struct NotchWidgetButton: View {
    let widget: NotchWidget

    @EnvironmentObject private var viewModel: NotchViewModel
    @State private var isHovering = false

    var body: some View {
        Group {
            if widget.clickTarget != nil {
                Button(action: activate) { content }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
                    }
                    .scaleEffect(isHovering ? 1.06 : 1)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch widget {
        case .battery: BatteryWidget()
        case .clock: ClockWidget(showsDate: false)
        case .date: ClockWidget(showsDate: true)
        case .focusTimer: FocusTimerWidget()
        case .nextEvent: NextEventWidget()
        case .nowPlaying: NowPlayingWidget()
        case .cpu: StatWidget(kind: .cpu)
        case .memory: StatWidget(kind: .memory)
        case .disk: StatWidget(kind: .disk)
        case .weather: WeatherWidget()
        case .wifi: WiFiWidget()
        case .moonPhase: MoonWidget()
        }
    }

    private func activate() {
        guard let target = widget.clickTarget else { return }
        switch target {
        case let .settingsPane(identifier):
            if let url = URL(string: "x-apple.systempreferences:\(identifier)") {
                NSWorkspace.shared.open(url)
            }
        case let .app(bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .nextMeeting:
            guard let item = CalendarManager.shared.nextItem else { return }
            if item.meetingURL != nil {
                CalendarManager.shared.joinMeeting(item)
            } else {
                CalendarManager.shared.open(item: item)
            }
        case .playingApp:
            MusicManager.shared.openPlayingApp()
        case .focusTab:
            viewModel.currentTab = .focus
            viewModel.open()
        case .locationAccess:
            if WeatherManager.shared.isLocationAuthorized {
                if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                WeatherManager.shared.requestAccess()
            }
        }
    }
}

// MARK: - Individual widgets

private struct BatteryWidget: View {
    @ObservedObject private var battery = BatteryManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: battery.symbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(battery.indicatorColor)
            Text(battery.percentageText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .fixedSize()
    }
}

private struct ClockWidget: View {
    let showsDate: Bool

    var body: some View {
        // A minute-granularity timeline keeps this honest without a timer.
        TimelineView(.everyMinute) { context in
            Text(Self.formatter(showsDate: showsDate).string(from: context.date))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
        }
    }

    private static func formatter(showsDate: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        if showsDate {
            formatter.dateFormat = Locale.current.hasTwelveHourClock ? "E d MMM  h:mm a" : "E d MMM  HH:mm"
        } else {
            formatter.dateFormat = Locale.current.hasTwelveHourClock ? "h:mm a" : "HH:mm"
        }
        return formatter
    }
}

private struct FocusTimerWidget: View {
    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: focus.isOnBreak ? "cup.and.saucer" : "cup.and.saucer.fill")
                .font(.system(size: 9, weight: .medium))
            Text(focus.isActive ? focus.compactRemainingText : "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(focus.isActive ? settings.accentColor : .white.opacity(0.4))
        .fixedSize()
    }
}

private struct NextEventWidget: View {
    @ObservedObject private var calendar = CalendarManager.shared

    var body: some View {
        Group {
            if let event = calendar.nextItem {
                HStack(spacing: 5) {
                    if event.meetingURL != nil {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(event.calendarColor)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(event.calendarColor)
                            .frame(width: 2.5, height: 14)
                    }
                    VStack(alignment: .leading, spacing: -1) {
                        Text(event.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(event.countdownText ?? event.timeText)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    // Long titles would otherwise push the notch across the
                    // whole screen, so the text gets a ceiling.
                    .frame(maxWidth: 118, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(calendar.hasEventAccess ? "No events" : "Calendar off")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize()
            }
        }
    }
}

private struct NowPlayingWidget: View {
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        Group {
            if music.track.isEmpty {
                Text("Nothing playing")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize()
            } else {
                HStack(spacing: 5) {
                    if let artwork = music.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 15, height: 15)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    VStack(alignment: .leading, spacing: -1) {
                        Text(music.track.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(music.track.artist)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: 122, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct StatWidget: View {
    enum Kind { case cpu, memory, disk }
    let kind: Kind

    @ObservedObject private var stats = SystemStatsManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .fixedSize()
        .onAppear { stats.addSubscriber() }
        .onDisappear { stats.removeSubscriber() }
    }

    private var symbol: String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        }
    }

    private var value: String {
        switch kind {
        case .cpu: return stats.cpuText
        case .memory: return stats.memoryText
        case .disk: return stats.diskFreeText
        }
    }

    private var tint: Color {
        let usage: Double
        switch kind {
        case .cpu: usage = stats.cpuUsage
        case .memory: usage = stats.memoryUsage
        case .disk: usage = stats.diskUsage
        }
        if usage > 0.9 { return .red }
        if usage > 0.75 { return .orange }
        return .white.opacity(0.7)
    }
}

private struct WeatherWidget: View {
    @ObservedObject private var weather = WeatherManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 10, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.85))
            Text(weather.temperatureText ?? "—")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
        }
        .fixedSize()
        .help(weather.lastError ?? weather.conditions?.placeName ?? "Weather")
        .onAppear { weather.addSubscriber() }
        .onDisappear { weather.removeSubscriber() }
    }
}

private struct WiFiWidget: View {
    @ObservedObject private var weather = WeatherManager.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(weather.wifiNetwork == nil ? 0.45 : 0.85))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(weather.wifiNetwork == nil ? 0.55 : 0.85))
                .lineLimit(1)
        }
        .fixedSize()
        .help(helpText)
        .onAppear { weather.addSubscriber() }
        .onDisappear { weather.removeSubscriber() }
    }

    private var symbol: String {
        if let network = weather.wifiNetwork, !network.isEmpty { return "wifi" }
        if !weather.isLocationAuthorized { return "wifi.exclamationmark" }
        return weather.isWiFiConnected ? "wifi" : "wifi.slash"
    }

    // "Offline" would be a lie when the real problem is that macOS will not
    // hand over the network name without location access.
    private var label: String {
        if let network = weather.wifiNetwork, !network.isEmpty { return network }
        if !weather.isLocationAuthorized { return "Allow location" }
        return weather.isWiFiConnected ? "Connected" : "Offline"
    }

    private var helpText: String {
        weather.isLocationAuthorized
            ? "Wi-Fi network"
            : "macOS only reveals the network name to apps with location access — click to grant it"
    }
}

private struct MoonWidget: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 4) {
                Image(systemName: MoonPhase.symbol(on: context.date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(Int(round(MoonPhase.fraction(on: context.date) * 100)))%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .fixedSize()
            .help(MoonPhase.name(on: context.date))
        }
    }
}
