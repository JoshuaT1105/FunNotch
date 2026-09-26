//
//  CustomizeWindow.swift
//  FunNotch
//
//  How the notch looks, edited against a picture of it: the home screen's
//  layout, the widgets beside the camera, and its colour, outline and size.
//
//  Everything applies as you go — the real notch changes along with the
//  preview — so there is nothing to save and nothing to lose by closing.
//
//  Editing inside the notch itself is not workable: it is 200 points tall, it
//  closes when the pointer leaves, and the thing being edited is the thing you
//  would be dragging in. So it is done here, at a comfortable size, on a stage
//  drawn to look like the top of your screen.
//

import AppKit
import SwiftUI

enum CustomizeTab: String, CaseIterable, Identifiable {
    case home
    case closed
    case style

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home Screen"
        case .closed: return "Beside the Notch"
        case .style: return "Style"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "square.grid.2x2.fill"
        case .closed: return "rectangle.topthird.inset.filled"
        case .style: return "paintpalette.fill"
        }
    }
}

@MainActor
final class CustomizeNavigation: ObservableObject {
    static let shared = CustomizeNavigation()
    @Published var tab: CustomizeTab = .home
    private init() {}
}

@MainActor
final class CustomizeWindowController: NSObject, NSWindowDelegate {
    static let shared = CustomizeWindowController()

    private var window: NSWindow?

    func show(tab: CustomizeTab? = nil) {
        if let tab { CustomizeNavigation.shared.tab = tab }

        if let window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: CustomizeView { [weak self] in
            self?.window?.close()
        })
        // Only the minimum size comes from SwiftUI. Left to its default, the
        // window grows to fit the widget gallery's full height, which runs off
        // the bottom of a 13-inch screen.
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Customize"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The stage is all about a black notch, so the window is always dark.
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 1010, height: 720))
        window.contentMinSize = NSSize(width: 960, height: 680)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        let closing = window
        // Let go of the window so its preview stops following the managers.
        window = nil
        DispatchQueue.main.async {
            SettingsWindowController.refreshActivationPolicy(excluding: closing)
        }
    }
}

// MARK: - Root

struct CustomizeView: View {
    let onDone: () -> Void

    @ObservedObject private var navigation = CustomizeNavigation.shared

    var body: some View {
        VStack(spacing: 0) {
            CustomizeTopBar(tab: $navigation.tab, onDone: onDone)
            Group {
                switch navigation.tab {
                case .home: HomeLayoutEditor()
                case .closed: ClosedNotchEditor()
                case .style: StyleEditor()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.18), value: navigation.tab)
        // Declared outright. Worked out from the content, the minimum measures
        // every line of text at almost no width — a word per line — and comes
        // to more than a 13-inch screen is tall.
        .frame(minWidth: 960, minHeight: 640)
        .background(CustomizeBackdrop())
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }
}

private struct CustomizeTopBar: View {
    @Binding var tab: CustomizeTab
    let onDone: () -> Void

    @Namespace private var selection

    var body: some View {
        ZStack {
            HStack(spacing: 3) {
                ForEach(CustomizeTab.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { tab = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(tab == item ? Color.white : Color.white.opacity(0.55))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background {
                            if tab == item {
                                Capsule()
                                    .fill(Color.white.opacity(0.14))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "tab", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.trailing, 20)
        }
        .frame(height: 58)
        .padding(.top, 6)
    }
}

/// A dark, faintly coloured backdrop — a desk lamp's worth of light on the
/// site's gradient.
private struct CustomizeBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.058, blue: 0.075)
            RadialGradient(
                colors: [Color(red: 0.14, green: 0.4, blue: 0.86).opacity(0.28), .clear],
                center: .topLeading, startRadius: 20, endRadius: 620
            )
            RadialGradient(
                colors: [Color(red: 0.82, green: 0.44, blue: 0.53).opacity(0.2), .clear],
                center: .bottomTrailing, startRadius: 20, endRadius: 640
            )
        }
    }
}

// MARK: - Stage

/// The top of a screen: wallpaper, a menu bar, and the notch hanging from it.
struct StageScreen<Content: View>: View {
    var height: CGFloat
    var menuBarHeight: CGFloat = 32
    /// How much bigger than life the stage is drawn, so the menu bar's text
    /// matches the notch hanging from it.
    var scale: CGFloat = 1
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            StageWallpaper()
            MenuBarStrip(height: menuBarHeight, scale: scale)
            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

private struct StageWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.2, blue: 0.42),
                    Color(red: 0.3, green: 0.2, blue: 0.46),
                    Color(red: 0.55, green: 0.27, blue: 0.4),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.95, green: 0.55, blue: 0.45).opacity(0.35), .clear],
                center: UnitPoint(x: 0.8, y: 0.95), startRadius: 10, endRadius: 420
            )
            RadialGradient(
                colors: [Color(red: 0.3, green: 0.6, blue: 1).opacity(0.3), .clear],
                center: UnitPoint(x: 0.12, y: 0.1), startRadius: 10, endRadius: 380
            )
        }
    }
}

/// A translucent menu bar with a few plausible items, so the notch has
/// something to sit in.
private struct MenuBarStrip: View {
    let height: CGFloat
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 18 * scale) {
            Image(systemName: "applelogo")
                .font(.system(size: 13 * scale, weight: .semibold))
            Text("Finder").fontWeight(.bold)
            Text("File")
            Text("Edit")
            Text("View")
            Spacer()
            // Magnified, the notch's own clock and battery sit right beside
            // these and say the same thing twice.
            if scale <= 1 {
                Image(systemName: "wifi")
                Image(systemName: "battery.75")
                Text(Date.now.formatted(date: .omitted, time: .shortened))
            }
        }
        .font(.system(size: 12.5 * scale))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 18 * scale)
        .frame(height: height)
        .background(Color.black.opacity(0.28))
    }
}

/// The real collapsed notch, drawn by the same view the notch uses, from a
/// view model of its own. It follows the managers, so music, the clock and
/// working agents all show up here as they do for real.
struct LiveClosedNotchPreview: View {
    @ObservedObject var model: NotchViewModel
    var scale: CGFloat = 1.55

    /// The notch never gets near the panel's full width, so only the middle
    /// is shown — otherwise the magnified preview would be wider than the window.
    static let visibleWidth: CGFloat = 580

    var body: some View {
        let visible = model.closedNotchSize.height + 4
        ContentView()
            .environmentObject(model)
            .environmentObject(Settings.shared)
            .frame(width: windowSize.width, height: visible, alignment: .top)
            .frame(width: Self.visibleWidth, height: visible, alignment: .top)
            .clipped()
            .allowsHitTesting(false)
            .scaleEffect(scale, anchor: .top)
            .frame(width: Self.visibleWidth * scale, height: visible * scale, alignment: .top)
    }
}

extension NotchViewModel {
    /// A view model for a preview, measured against the built-in display.
    static func makePreview() -> NotchViewModel {
        NotchViewModel(screen: NSScreen.screens.first(where: \.hasPhysicalNotch) ?? NSScreen.main)
    }
}

// MARK: - Shared pieces

/// A titled panel on the dark backdrop.
struct CustomizePanel<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
            }
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        )
    }
}

/// A round coloured badge with a glyph in it.
struct TintedGlyph: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Circle()
            .fill(tint.opacity(0.2))
            .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

extension HomeTileKind {
    /// Each widget's colour in the editor, so a layout reads at a glance.
    var tint: Color {
        switch self {
        case .nowPlaying, .mediaScrubber: return SettingsStyle.pink
        case .weather: return Color(red: 0.3, green: 0.72, blue: 1)
        case .calendar, .nextEvent: return SettingsStyle.red
        case .mirror: return Color(red: 0.62, green: 0.66, blue: 0.76)
        case .agents: return AgentPalette.claude
        case .notes: return SettingsStyle.yellow
        case .timer, .focusStreak: return SettingsStyle.orange
        case .quickActions: return Color(red: 1, green: 0.8, blue: 0.25)
        case .systemStats, .battery: return SettingsStyle.green
        case .devices, .recentShelf, .wifi: return SettingsStyle.blue
        case .clipboard: return SettingsStyle.purple
        case .openApp, .diskSpace: return Color(red: 0.62, green: 0.64, blue: 0.7)
        }
    }

    var blurb: String {
        switch self {
        case .nowPlaying: return "Artwork and controls"
        case .weather: return "A pixel-art forecast"
        case .calendar: return "This week, and what's next"
        case .mirror: return "A camera check before calls"
        case .agents: return "Claude Code sessions, live"
        case .notes: return "A quick scratchpad"
        case .timer: return "Countdowns and a stopwatch"
        case .quickActions: return "One-click shortcuts"
        case .systemStats: return "CPU and memory"
        case .battery: return "Charge and time left"
        case .devices: return "AirPods and other batteries"
        case .focusStreak: return "Days in a row"
        case .recentShelf: return "Latest files on the shelf"
        case .clipboard: return "The last thing you copied"
        case .wifi: return "Network and signal"
        case .openApp: return "Launch an app you pick"
        case .mediaScrubber: return "Scrub through the track"
        case .nextEvent: return "Your next event"
        case .diskSpace: return "Free space left"
        }
    }
}

extension NotchWidget {
    var tint: Color {
        switch self {
        case .battery, .cpu: return SettingsStyle.green
        case .clock: return Color(white: 0.85)
        case .date, .nextEvent: return SettingsStyle.red
        case .focusTimer: return SettingsStyle.indigo
        case .nowPlaying: return SettingsStyle.pink
        case .memory: return SettingsStyle.teal
        case .disk: return Color(red: 0.62, green: 0.64, blue: 0.7)
        case .weather: return Color(red: 0.3, green: 0.72, blue: 1)
        case .wifi, .shelfCount: return SettingsStyle.blue
        case .moonPhase: return SettingsStyle.yellow
        }
    }
}
