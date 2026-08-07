//
//  FocusView.swift
//  FunNotch
//
//  The Focus tab: pick a length, start the countdown, and distracting sites
//  stay out of the way until it runs out.
//

import SwiftUI

struct FocusView: View {
    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    private let presets = [15, 25, 45, 60]

    var body: some View {
        HStack(spacing: 18) {
            CountdownRing()
                .frame(width: 96, height: 96)

            if focus.isActive {
                activeControls
            } else {
                idleControls
            }

            BlocklistPanel()
                .frame(width: 176)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Idle

    private var idleControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Start a focus session")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Text(blockingSummary)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { minutes in
                    DurationChip(
                        label: "\(minutes)m",
                        isPrimary: minutes == settings.focusDefaultMinutes
                    ) {
                        focus.start(minutes: minutes)
                    }
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blockingSummary: String {
        guard settings.focusBlockWebsites else {
            return "Website blocking is off — this is just a timer."
        }
        let count = settings.focusBlocklist.count
        let browsers = FocusManager.supportedInstalledBrowsers
        guard !browsers.isEmpty else {
            return "\(count) sites on the blocklist, but no supported browser is installed."
        }
        return "Blocks \(count) site\(count == 1 ? "" : "s") in \(browsers.joined(separator: ", "))."
    }

    // MARK: - Active

    private var activeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focusing")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            if let host = focus.lastBlockedHost {
                Label("Blocked \(host)", systemImage: "hand.raised.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            } else {
                Text(endsAtText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 6) {
                DurationChip(label: "+5m", isPrimary: false) {
                    focus.extend(byMinutes: 5)
                }
                DurationChip(label: "Stop", isPrimary: true, isDestructive: true) {
                    focus.stop()
                }
            }
            .padding(.top, 2)

            if focus.blockedCount > 0 {
                Text("\(focus.blockedCount) redirect\(focus.blockedCount == 1 ? "" : "s") this session")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var endsAtText: String {
        guard let end = focus.endDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = Locale.current.hasTwelveHourClock ? "h:mm a" : "HH:mm"
        return "Ends at \(formatter.string(from: end))"
    }
}

/// What the session keeps out of the way, listed so it is never a surprise.
private struct BlocklistPanel: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var focus = FocusManager.shared

    /// How many sites fit in the panel before it starts summarising.
    private let visibleLimit = 5

    private var visibleSites: [String] {
        Array(settings.focusBlocklist.prefix(visibleLimit))
    }

    private var overflowCount: Int {
        max(settings.focusBlocklist.count - visibleLimit, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: settings.focusBlockWebsites ? "hand.raised.fill" : "hand.raised.slash")
                    .font(.system(size: 10))
                Text(settings.focusBlockWebsites ? "Blocking" : "Blocking off")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 0)
                if settings.focusBlockWebsites {
                    Text("\(settings.focusBlocklist.count)")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .foregroundStyle(.white.opacity(0.75))

            if settings.focusBlockWebsites, !settings.focusBlocklist.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleSites, id: \.self) { site in
                        Text(site)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }

                    if overflowCount > 0 {
                        Text("+\(overflowCount) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 6)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text(settings.focusBlockWebsites
                    ? "Nothing on the blocklist yet — add sites in Settings."
                    : "Turn blocking on in Settings to keep sites away.")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The countdown ring, which doubles as the idle "start" affordance.
private struct CountdownRing: View {
    @ObservedObject private var focus = FocusManager.shared
    @EnvironmentObject private var settings: Settings

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)

            Circle()
                .trim(from: 0, to: focus.isActive ? focus.progress : 0)
                .stroke(
                    settings.accentColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: focus.progress)

            if focus.isActive {
                VStack(spacing: 0) {
                    Text(focus.remainingText)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("left")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(isHovering ? 1 : 0.75))
                    Text("\(settings.focusDefaultMinutes)m")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .scaleEffect(isHovering ? 1.04 : 1)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture {
            if focus.isActive {
                focus.stop()
            } else {
                focus.start(minutes: settings.focusDefaultMinutes)
            }
        }
        .help(focus.isActive ? "Stop the focus session" : "Start a focus session")
    }
}

private struct DurationChip: View {
    let label: String
    var isPrimary: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void

    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(background))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    private var foreground: Color {
        if isDestructive { return .white }
        return isPrimary ? .black : .white.opacity(isHovering ? 1 : 0.8)
    }

    private var background: Color {
        if isDestructive {
            return Color.red.opacity(isHovering ? 0.85 : 0.7)
        }
        if isPrimary {
            return .white.opacity(isHovering ? 1 : 0.9)
        }
        return .white.opacity(isHovering ? 0.2 : 0.12)
    }
}
