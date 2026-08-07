//
//  Components.swift
//  FunNotch
//
//  Reusable pieces: the spectrum visualizer, scrolling text, and the hover
//  buttons used throughout the notch.
//

import SwiftUI

/// Four bars that bounce while music plays and settle flat when it stops.
struct MusicVisualizer: View {
    let isPlaying: Bool
    let color: Color

    private let barCount = 4
    /// Per-bar phase and rate so the bars never move in lockstep.
    private let phases: [Double] = [0.0, 1.7, 0.6, 2.4]
    private let rates: [Double] = [3.1, 4.3, 2.6, 3.7]

    var body: some View {
        TimelineView(.animation(minimumInterval: isPlaying ? 1.0 / 30.0 : nil, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let spacing = proxy.size.width / CGFloat(barCount * 2 - 1)
                HStack(alignment: .center, spacing: spacing) {
                    ForEach(0 ..< barCount, id: \.self) { index in
                        Capsule()
                            .fill(color)
                            .frame(
                                width: spacing,
                                height: barHeight(index: index, time: time, maximum: proxy.size.height)
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }

    private func barHeight(index: Int, time: Double, maximum: CGFloat) -> CGFloat {
        guard isPlaying else { return max(maximum * 0.18, 2) }
        let wave = sin(time * rates[index] + phases[index])
        let secondary = sin(time * rates[index] * 0.53 + phases[index] * 1.7)
        let normalised = (wave * 0.6 + secondary * 0.4 + 1) / 2
        return max(maximum * (0.2 + 0.8 * normalised), 2)
    }
}

/// Text that scrolls horizontally when it does not fit, and sits still when it does.
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var speed: Double = 30
    var pause: Double = 1.6

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflows: Bool { textWidth > containerWidth + 1 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                if overflows {
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .offset(x: offset)
                } else {
                    label
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .onAppear {
                containerWidth = proxy.size.width
                restart()
            }
            .onChange(of: proxy.size.width) { _, newValue in
                containerWidth = newValue
                restart()
            }
        }
        .frame(height: lineHeight)
        .clipped()
        .onChange(of: text) { restart() }
        .onChange(of: textWidth) { restart() }
    }

    private var gap: CGFloat { 40 }
    private var lineHeight: CGFloat { 18 }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { textWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, newValue in textWidth = newValue }
                }
            )
    }

    private func restart() {
        offset = 0
        guard overflows else { return }
        let distance = textWidth + gap
        let duration = Double(distance) / speed
        withAnimation(.linear(duration: duration).delay(pause).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

/// Button that lights up on hover, used for every control in the notch.
struct HoverButton: View {
    let systemName: String
    var size: CGFloat = 16
    var padding: CGFloat = 7
    var isActive: Bool = false
    var tint: Color = .white
    /// Optional glyph drawn over the symbol, e.g. the "1" of repeat-one.
    var badge: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(isActive ? tint : .white)
                .overlay {
                    if let badge {
                        Text(badge)
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(isActive ? tint : .white)
                            .padding(.horizontal, 1)
                            .background(Color.black)
                    }
                }
                .frame(width: size + padding * 2, height: size + padding * 2)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovering ? 0.16 : 0))
                )
                .scaleEffect(isHovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

/// Slim, draggable progress bar used for the scrubber and HUD levels.
struct NotchSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0 ... 1
    var color: Color = .white
    var height: CGFloat = 5
    var isEnabled: Bool = true
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            let fraction = min(max((value - range.lowerBound) / span, 0), 1)
            let barHeight = (isHovering || isDragging) ? height + 3 : height

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                        }
                        let ratio = min(max(gesture.location.x / proxy.size.width, 0), 1)
                        value = range.lowerBound + ratio * span
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        isDragging = false
                        onEditingChanged?(false)
                    }
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)
        }
    }
}

/// Compact battery pill shown in the open notch's header.
struct BatteryPill: View {
    @ObservedObject private var battery = BatteryManager.shared
    @EnvironmentObject private var settings: Settings

    @State private var showsDetail = false

    var body: some View {
        HStack(spacing: 5) {
            if settings.showBatteryPercentage {
                Text(battery.percentageText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .frame(width: 24, height: 12)

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(battery.indicatorColor)
                    .frame(width: max(2, 20 * CGFloat(battery.level)), height: 8)
                    .padding(.leading, 2)

                if battery.isCharging || battery.isPluggedIn, settings.showPowerStatusIcons {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 12)
                }
            }
            .overlay(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 2, height: 5)
                    .offset(x: 3)
            }
        }
        .help(battery.timeRemainingText ?? battery.percentageText)
        .onHover { showsDetail = $0 }
    }
}
