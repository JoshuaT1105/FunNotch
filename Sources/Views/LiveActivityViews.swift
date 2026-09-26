//
//  LiveActivityViews.swift
//  FunNotch
//
//  What the collapsed notch shows when it has something to say: volume and
//  brightness, power, a device connecting, a screenshot landing on the shelf,
//  a download, a focus session, an agent finishing — and the track-change peek.
//
//  Every announcement shares one layout, borrowed from the Dynamic Island: a
//  glyph in the left wing, a value in the right, and one line in a short chin
//  under the camera. It replaces a 34-point strip that hung below the notch
//  with two lines of text in it. The HUD now drops 14 points and everything
//  else 24, so the notch barely leaves the menu bar to tell you something.
//

import AppKit
import SwiftUI

/// How far an announcement spreads and drops.
enum LiveActivityMetrics {
    struct Style {
        /// Width of each wing beside the cutout.
        let wing: CGFloat
        let minimumWidth: CGFloat
        /// Height added below the cutout.
        let chin: CGFloat
    }

    static let hud = Style(wing: 64, minimumWidth: 312, chin: 14)
    static let banner = Style(wing: 82, minimumWidth: 364, chin: 24)

    static func style(for type: SneakContentType) -> Style {
        type == .hud ? hud : banner
    }

    /// Inset of wing content from the outer edges.
    static let edgeInset: CGFloat = 16
}

/// The measurements a banner is laid out against.
struct BannerGeometry {
    let width: CGFloat
    let cutoutWidth: CGFloat
    /// Height of the row beside the camera.
    let rowHeight: CGFloat
    let chin: CGFloat

    var wing: CGFloat { max((width - cutoutWidth) / 2, 0) }
}

/// Wings either side of the camera, and a chin below it.
struct BannerLayout<Leading: View, Trailing: View, Chin: View>: View {
    let geometry: BannerGeometry
    let leading: Leading
    let trailing: Trailing
    let chin: Chin

    init(
        geometry: BannerGeometry,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder chin: () -> Chin
    ) {
        self.geometry = geometry
        self.leading = leading()
        self.trailing = trailing()
        self.chin = chin()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .padding(.leading, LiveActivityMetrics.edgeInset)
                    .frame(width: geometry.wing, height: geometry.rowHeight, alignment: .leading)
                Color.clear
                    .frame(width: geometry.cutoutWidth, height: geometry.rowHeight)
                trailing
                    .padding(.trailing, LiveActivityMetrics.edgeInset)
                    .frame(width: geometry.wing, height: geometry.rowHeight, alignment: .trailing)
            }
            chin
                .frame(width: geometry.width, height: geometry.chin)
        }
    }
}

// MARK: - Entrances

/// The glyph pops in on a spring.
private struct WingPop: ViewModifier {
    let time: Double
    var delay: Double = 0

    func body(content: Content) -> some View {
        let pop = Motion.spring(time - delay, response: 0.42, damping: 0.52)
        content
            .scaleEffect(0.35 + 0.65 * pop)
            .opacity(Motion.clamp(pop * 1.6))
    }
}

/// The value slides out from the camera.
private struct WingSlide: ViewModifier {
    let time: Double
    var delay: Double = 0.12

    func body(content: Content) -> some View {
        let progress = Motion.easeOut(Motion.progress(time, delay: delay, duration: 0.4))
        content
            .offset(x: (1 - progress) * -14)
            .opacity(progress)
    }
}

/// One line of text rising into the chin.
private struct ChinLine: View {
    let time: Double
    let text: Text

    var body: some View {
        let progress = Motion.easeOut(Motion.progress(time, delay: 0.1, duration: 0.42))
        text
            .font(.system(size: 11))
            .foregroundColor(.white)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .offset(y: (1 - progress) * 8)
            .opacity(progress)
            .padding(.bottom, 5)
    }
}

/// "**Name** did something": the subject in white, the rest softer.
private func headline(_ subject: String, _ rest: String) -> Text {
    Text(subject).fontWeight(.semibold) + Text(rest).foregroundColor(.white.opacity(0.62))
}

// MARK: - Dispatcher

/// Whatever the notch is currently announcing.
struct LiveActivityBanner: View {
    let activity: SneakPeek
    let geometry: BannerGeometry

    var body: some View {
        Group {
            switch activity.type {
            case .hud:
                HUDBanner(activity: activity, geometry: geometry)
            case .battery:
                BatteryBanner(geometry: geometry)
            case .bluetooth:
                BluetoothBanner(activity: activity, geometry: geometry)
            case .screenshot:
                ScreenshotBanner(geometry: geometry)
            case .download:
                DownloadBanner(geometry: geometry)
            case .focus:
                FocusBanner(activity: activity, geometry: geometry)
            case .agent:
                AgentBanner(geometry: geometry)
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - HUD

/// Volume, brightness and keyboard backlight: the glyph reacts to every press,
/// the number rolls, and a glowing bar runs the width of the chin.
private struct HUDBanner: View {
    let activity: SneakPeek
    let geometry: BannerGeometry

    /// False for the first frame, so the bar grows out to the level instead of
    /// simply being there.
    @State private var appeared = Motion.snapshotMode

    private var kind: HUDManager.Kind {
        switch activity.icon {
        case HUDManager.Kind.brightness.symbol: return .brightness
        case HUDManager.Kind.keyboardBacklight.symbol: return .keyboardBacklight
        default: return .volume
        }
    }

    private var muted: Bool { activity.icon == HUDManager.Kind.volume.mutedSymbol }
    private var level: Double { Double(min(max(activity.value, 0), 1)) }

    var body: some View {
        BannerLayout(geometry: geometry) {
            HUDGlyph(kind: kind, level: level, muted: muted)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
        } trailing: {
            HUDReadout(level: level, muted: muted)
                .opacity(appeared ? 1 : 0)
                .offset(x: appeared ? 0 : -10)
        } chin: {
            HUDLevelBar(level: appeared ? level : 0, muted: muted, tint: tint)
                .padding(.horizontal, LiveActivityMetrics.edgeInset + 2)
                .padding(.bottom, 4)
        }
        .onAppear {
            guard !appeared else { return }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { appeared = true }
        }
    }

    private var tint: Color {
        switch kind {
        case .volume: return .white
        case .brightness: return Color(red: 1.0, green: 0.84, blue: 0.42)
        case .keyboardBacklight: return Color(red: 0.62, green: 0.84, blue: 1.0)
        }
    }
}

private struct HUDGlyph: View {
    let kind: HUDManager.Kind
    let level: Double
    let muted: Bool

    var body: some View {
        Group {
            switch kind {
            case .volume:
                Image(
                    systemName: muted || level < 0.005 ? "speaker.slash.fill" : "speaker.wave.3.fill",
                    variableValue: level
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, value: level)
                .foregroundStyle(.white)

            case .brightness:
                // The sun turns as it brightens, and swells a little.
                Image(systemName: level < 0.35 ? "sun.min.fill" : "sun.max.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(level * 150))
                    .scaleEffect(0.84 + 0.26 * level)
                    .foregroundStyle(Color(hue: 0.13, saturation: 0.12 + 0.5 * level, brightness: 1))
                    .shadow(color: Color.yellow.opacity(0.45 * level), radius: 2 + 4 * level)

            case .keyboardBacklight:
                Image(systemName: "keyboard.fill")
                    .foregroundStyle(.white.opacity(0.45 + 0.55 * level))
                    .shadow(color: Color(red: 0.62, green: 0.84, blue: 1).opacity(0.9 * level), radius: 1 + 5 * level)
                    .symbolEffect(.bounce.down, value: level)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 22, height: 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: level)
    }
}

private struct HUDReadout: View {
    let level: Double
    let muted: Bool

    private var percent: Int { Int((level * 100).rounded()) }

    var body: some View {
        Group {
            if muted {
                Text("Muted")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(percent)")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(percent)))
                    Text("%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.snappy(duration: 0.22), value: percent)
        .animation(.easeOut(duration: 0.18), value: muted)
    }
}

/// A capsule that fills to the level, with a bright head and a soft glow.
private struct HUDLevelBar: View {
    let level: Double
    let muted: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = level <= 0 ? 0 : max(width * level, 5)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.13))
                Capsule()
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.5), tint],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fill)
                    .shadow(color: tint.opacity(muted ? 0 : 0.6), radius: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.9), radius: 3)
                    .offset(x: max(fill - 6, 0))
                    .opacity(level > 0.02 && !muted ? 1 : 0)
            }
            .saturation(muted ? 0 : 1)
            .opacity(muted ? 0.4 : 1)
        }
        .frame(height: 4)
        .animation(.spring(response: 0.32, dampingFraction: 0.66), value: level)
        .animation(.easeOut(duration: 0.2), value: muted)
    }
}

// MARK: - Power

private struct BatteryBanner: View {
    let geometry: BannerGeometry

    @ObservedObject private var battery = BatteryManager.shared

    var body: some View {
        IntroTimeline(duration: 3.4) { time in
            BannerLayout(geometry: geometry) {
                BatteryGlyph(
                    level: Double(battery.level),
                    charging: battery.isPluggedIn,
                    color: battery.indicatorColor,
                    time: time
                )
                .modifier(WingPop(time: time))
            } trailing: {
                Text(battery.percentageText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(battery.isPluggedIn ? AgentPalette.done : .white)
                    .modifier(WingSlide(time: time))
            } chin: {
                ChinLine(time: time, text: headline(
                    battery.isPluggedIn ? (battery.isCharged ? "Fully charged" : "Charging") : "On battery",
                    battery.timeRemainingText.map { " · \($0)" } ?? ""
                ))
            }
        }
    }
}

/// A battery that fills to its charge, a bolt that lands on it when plugged
/// in, and a sheen that runs across while it charges.
private struct BatteryGlyph: View {
    let level: Double
    let charging: Bool
    let color: Color
    let time: Double

    var body: some View {
        let fill = Motion.easeOut(Motion.progress(time, delay: 0.12, duration: 0.7))
        let bolt = Motion.spring(time - 0.4, response: 0.4, damping: 0.45)
        let sheen = (time * 0.8).truncatingRemainder(dividingBy: 1)

        HStack(spacing: 1.2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.6, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
                    .frame(width: 25, height: 12.5)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(20.5 * level * fill, 1.5), height: 8.5)
                    .overlay(alignment: .leading) {
                        if charging {
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.55), .clear],
                                startPoint: .leading, endPoint: .trailing
                            )
                            .frame(width: 8)
                            .offset(x: -8 + sheen * 30)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .padding(.leading, 2.25)
            }
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 1.6, height: 4.5)
        }
        .overlay {
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1.2)
                    .scaleEffect(max(bolt, 0))
                    .offset(x: -1)
            }
        }
    }
}

// MARK: - Bluetooth

private struct BluetoothBanner: View {
    let activity: SneakPeek
    let geometry: BannerGeometry

    @ObservedObject private var bluetooth = BluetoothMonitor.shared

    private var connected: Bool { bluetooth.lastChange?.connected ?? true }

    var body: some View {
        IntroTimeline(duration: 1.8) { time in
            BannerLayout(geometry: geometry) {
                ZStack {
                    if connected {
                        ForEach(0 ..< 2, id: \.self) { ring in
                            let progress = Motion.progress(time, delay: 0.2 + Double(ring) * 0.35, duration: 0.95)
                            Circle()
                                .stroke(Color(red: 0.35, green: 0.68, blue: 1).opacity(0.7 * (1 - progress)), lineWidth: 1.2)
                                .frame(width: 14 + 20 * progress, height: 14 + 20 * progress)
                                .opacity(progress > 0 && progress < 1 ? 1 : 0)
                        }
                    }
                    Image(systemName: activity.icon.isEmpty ? "dot.radiowaves.left.and.right" : activity.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(connected ? 1 : 0.5))
                }
                .frame(width: 24, height: 24)
                .modifier(WingPop(time: time))
            } trailing: {
                Group {
                    if let battery = bluetooth.lastChange?.device.battery, battery > 0, connected {
                        Text("\(Int(battery * 100))%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: connected ? "checkmark" : "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(connected ? AgentPalette.done : .white.opacity(0.5))
                    }
                }
                .modifier(WingSlide(time: time))
            } chin: {
                ChinLine(time: time, text: headline(
                    bluetooth.lastChange?.device.name ?? "Bluetooth",
                    connected ? " connected" : " disconnected"
                ))
            }
        }
    }
}

// MARK: - Screenshot and downloads

private struct ScreenshotBanner: View {
    let geometry: BannerGeometry

    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var shelf = ShelfManager.shared

    var body: some View {
        IntroTimeline(duration: 1.4) { time in
            BannerLayout(geometry: geometry) {
                // A shutter flash, then the viewfinder.
                let flash = Motion.progress(time, duration: 0.45)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.85 * (1 - flash)))
                        .frame(width: 10 + 24 * flash, height: 10 + 24 * flash)
                        .blur(radius: 3)
                        .opacity(flash < 1 ? 1 : 0)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 24, height: 24)
                .modifier(WingPop(time: time, delay: 0.08))
            } trailing: {
                ShelfThumbnail(url: screenshots.lastCatch, shelf: shelf, time: time)
            } chin: {
                ChinLine(time: time, text: headline("Screenshot", " added to the shelf"))
            }
        }
    }
}

private struct DownloadBanner: View {
    let geometry: BannerGeometry

    @ObservedObject private var downloads = DownloadWatcher.shared
    @ObservedObject private var shelf = ShelfManager.shared

    var body: some View {
        IntroTimeline(duration: 1.4) { time in
            BannerLayout(geometry: geometry) {
                // The arrow drops into place and rings as it lands.
                let drop = Motion.spring(time, response: 0.45, damping: 0.5)
                let ring = Motion.progress(time, delay: 0.28, duration: 0.6)
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.35, green: 0.68, blue: 1).opacity(0.7 * (1 - ring)), lineWidth: 1.2)
                        .frame(width: 18 + 14 * ring, height: 18 + 14 * ring)
                        .opacity(ring > 0 && ring < 1 ? 1 : 0)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white, Color(red: 0.2, green: 0.55, blue: 1))
                        .offset(y: (1 - drop) * -12)
                }
                .frame(width: 24, height: 24)
                .opacity(Motion.clamp(drop * 2))
            } trailing: {
                ShelfThumbnail(url: downloads.lastDownload, shelf: shelf, time: time)
            } chin: {
                ChinLine(time: time, text: headline(
                    downloads.lastDownload?.lastPathComponent ?? "Download", " finished"
                ))
            }
        }
    }
}

/// The file's shelf thumbnail when the shelf has made one, its icon until then.
private struct ShelfThumbnail: View {
    let url: URL?
    @ObservedObject var shelf: ShelfManager
    let time: Double

    var body: some View {
        let drop = Motion.spring(time - 0.18, response: 0.5, damping: 0.55)
        Group {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 26, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                    )
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .rotationEffect(.degrees((1 - drop) * -14))
        .offset(y: (1 - drop) * -10)
        .opacity(Motion.clamp(drop * 2))
    }

    private var thumbnail: NSImage? {
        guard let url else { return nil }
        if let item = shelf.items.first(where: { $0.url == url }), let image = item.thumbnail {
            return image
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Focus

private struct FocusBanner: View {
    let activity: SneakPeek
    let geometry: BannerGeometry

    @ObservedObject private var focus = FocusManager.shared

    private var finished: Bool { activity.icon == "checkmark.circle.fill" }

    var body: some View {
        IntroTimeline(duration: 1.4) { time in
            BannerLayout(geometry: geometry) {
                Group {
                    if finished {
                        CheckmarkBurst(time: time, size: 17, tint: Color(red: 0.55, green: 0.5, blue: 1))
                    } else {
                        Image(systemName: activity.icon.isEmpty ? "cup.and.saucer.fill" : activity.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .modifier(WingPop(time: time))
                    }
                }
                .frame(width: 24, height: 24)
            } trailing: {
                Text(finished || !focus.isActive ? "Done" : focus.compactRemainingText)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .modifier(WingSlide(time: time))
            } chin: {
                ChinLine(time: time, text: chinText)
            }
        }
    }

    private var chinText: Text {
        if finished { return headline("Focus", " session complete") }
        if focus.isOnBreak { return headline("Break", " · stretch your legs") }
        return headline("Focus", " · \(focus.remainingText) to go")
    }
}

// MARK: - Agents

/// A Claude Code or Codex session starting, finishing or stopping to ask.
private struct AgentBanner: View {
    let geometry: BannerGeometry

    @ObservedObject private var agents = AgentSessionsManager.shared

    var body: some View {
        if let announcement = agents.announcement {
            IntroTimeline(duration: 2.2) { time in
                BannerLayout(geometry: geometry) {
                    leading(announcement, time: time)
                        .frame(width: 24, height: 24)
                } trailing: {
                    trailing(announcement)
                        .modifier(WingSlide(time: time, delay: 0.2))
                } chin: {
                    ChinLine(time: time, text: chin(announcement))
                }
            }
        }
    }

    @ViewBuilder
    private func leading(_ announcement: AgentSessionsManager.Announcement, time: Double) -> some View {
        switch announcement.event {
        case .started:
            ZStack {
                // A ring goes out as the spinner spins up.
                let ring = Motion.progress(time, delay: 0.1, duration: 0.7)
                Circle()
                    .stroke(announcement.session.agent.tint.opacity(0.7 * (1 - ring)), lineWidth: 1.3)
                    .frame(width: 12 + 20 * ring, height: 12 + 20 * ring)
                    .opacity(ring > 0 && ring < 1 ? 1 : 0)
                AgentWorkingGlyph(agent: announcement.session.agent, size: 15)
                    .modifier(WingPop(time: time))
            }
        case .finished:
            CheckmarkBurst(time: time, size: 18)
        case .needsInput:
            AgentWaitingGlyph(size: 15, time: time)
                .modifier(WingPop(time: time))
        }
    }

    @ViewBuilder
    private func trailing(_ announcement: AgentSessionsManager.Announcement) -> some View {
        switch announcement.event {
        case let .finished(duration):
            Text(AgentSessionsManager.duration(duration))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AgentPalette.done)
        case .started:
            Text(announcement.session.agent == .claude ? "Claude" : "Codex")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(announcement.session.agent.tint)
        case .needsInput:
            Text("Now")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AgentPalette.waiting)
        }
    }

    private func chin(_ announcement: AgentSessionsManager.Announcement) -> Text {
        let name = announcement.session.name
        switch announcement.event {
        case .started:
            return headline(name, " started working")
        case .finished:
            return headline(name, " finished")
        case let .needsInput(reason):
            let text = AgentSessionsManager.waitingText(reason)
            return headline(name, " · " + text.prefix(1).lowercased() + text.dropFirst())
        }
    }
}

// MARK: - Track change

/// The track-change peek: artwork turns in on the left, the spectrum plays on
/// the right, and the title sits in the chin.
struct MusicPeekBanner: View {
    let geometry: BannerGeometry

    @ObservedObject private var music = MusicManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        IntroTimeline(duration: 1.0) { time in
            BannerLayout(geometry: geometry) {
                let turn = Motion.spring(time, response: 0.5, damping: 0.62)
                artwork
                    .rotation3DEffect(.degrees((1 - turn) * 90), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .opacity(Motion.clamp(turn * 2))
            } trailing: {
                MusicVisualizer(
                    isPlaying: music.isPlaying,
                    color: settings.coloredSpectrogram
                        ? settings.spectrumColor.resolved(albumArt: music.artworkColor, accent: settings.accentColor)
                        : .white
                )
                .frame(width: 17, height: 13)
                .modifier(WingSlide(time: time))
            } chin: {
                ChinLine(time: time, text: headline(
                    music.track.title,
                    music.track.artist.isEmpty ? "" : " — \(music.track.artist)"
                ))
            }
        }
    }

    private var artwork: some View {
        Group {
            if let image = music.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.15))
                    .overlay(Image(systemName: "music.note").font(.system(size: 10)))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
