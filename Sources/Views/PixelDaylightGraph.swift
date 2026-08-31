//
//  PixelDaylightGraph.swift
//  FunNotch
//
//  The day's arc of light, drawn in the same chunky pixels as the weather.
//
//  The x axis is the whole 24 hours rather than sunrise-to-sunset, because the
//  useful thing to see at a glance is where you are in the day — how much light
//  is left, and how much of the strip is already behind you. Sunrise-to-sunset
//  alone hides that: at 9pm in June it would be pinned to one end with no sense
//  of the night either side.
//

import SwiftUI

struct PixelDaylightGraph: View {
    let sunrise: Date?
    let sunset: Date?
    /// Tint borrowed from the weather scene so the two panels agree.
    let accent: Color

    private let cell: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            Canvas { ctx, size in
                draw(&ctx, size: size, now: Date(), t: context.date.timeIntervalSinceReferenceDate)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    private func snap(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1) -> CGRect {
        CGRect(x: (x / cell).rounded(.down) * cell,
               y: (y / cell).rounded(.down) * cell,
               width: w * cell, height: h * cell)
    }

    private func px(_ ctx: inout GraphicsContext, _ r: CGRect, _ c: Color, _ o: Double = 1) {
        ctx.fill(Path(r), with: .color(c.opacity(o)))
    }

    /// Fraction of the way through the local day, 0 at midnight, 1 at the next.
    private func dayFraction(_ date: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        return date.timeIntervalSince(start) / 86_400
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date, t: TimeInterval) {
        let horizon = size.height * 0.72
        let riseF = sunrise.map(dayFraction)
        let setF = sunset.map(dayFraction)

        // Horizon: a dashed pixel rule, so it reads as a scale rather than a
        // solid divider.
        var x: CGFloat = 0
        while x < size.width {
            px(&ctx, snap(x, horizon, 1, 1), .white, 0.18)
            x += cell * 2
        }

        guard let riseF, let setF, setF > riseF else {
            // No sunrise or sunset today. Polar summer or winter, or the API
            // left them out; either way there is no arc to draw.
            let text = Text("No sunrise today").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            ctx.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        let nowF = dayFraction(now)
        let amplitude = horizon - cell * 2

        // The arc. One pixel per grid column, height from a half sine between
        // sunrise and sunset — close enough to the sun's real elevation curve
        // at this size, and it costs no astronomy.
        var col: CGFloat = 0
        while col < size.width {
            let f = Double(col / size.width)
            let isDay = f >= riseF && f <= setF
            if isDay {
                let progress = (f - riseF) / (setF - riseF)
                let elevation = sin(progress * .pi)
                let y = horizon - CGFloat(elevation) * amplitude
                // Dim ahead of now, bright behind it: the part of the day you
                // have already had is the part that is filled in.
                let past = f <= nowF
                px(&ctx, snap(col, y, 1, 1), accent, past ? 0.95 : 0.30)
                // A sparse column of fill under the arc for the elapsed part,
                // which gives the graph some body without a solid block.
                if past {
                    var fy = y + cell * 2
                    while fy < horizon {
                        px(&ctx, snap(col, fy, 1, 1), accent, 0.10)
                        fy += cell * 3
                    }
                }
            } else {
                // Night: a low scatter of pixels below the horizon.
                let seed = Int(col / cell)
                if seed % 3 == 0 {
                    let jitter = CGFloat((seed * 7) % 3) * cell
                    px(&ctx, snap(col, horizon + cell + jitter, 1, 1), .white, f <= nowF ? 0.22 : 0.10)
                }
            }
            col += cell
        }

        // Now marker: a full-height tick plus the sun or moon sitting on the
        // curve, pulsing so the eye finds it immediately.
        let nowX = CGFloat(nowF) * size.width
        var ty: CGFloat = 0
        while ty < size.height {
            px(&ctx, snap(nowX, ty, 1, 1), .white, 0.16)
            ty += cell * 2
        }

        let pulse = (sin(t * 2.2) + 1) / 2
        let isDaylight = nowF >= riseF && nowF <= setF
        let markerY: CGFloat
        if isDaylight {
            let progress = (nowF - riseF) / (setF - riseF)
            markerY = horizon - CGFloat(sin(progress * .pi)) * amplitude
        } else {
            markerY = horizon + cell * 2
        }
        // A 2x2 blob rather than a single pixel, so it outweighs the arc.
        px(&ctx, snap(nowX - cell, markerY - cell, 2, 2), isDaylight ? accent : .white,
           0.75 + pulse * 0.25)

        // Sunrise and sunset ticks, marked on the horizon.
        for f in [riseF, setF] {
            let mx = CGFloat(f) * size.width
            px(&ctx, snap(mx, horizon - cell, 1, 2), accent, 0.55)
        }
    }
}
