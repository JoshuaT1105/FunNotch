//
//  PixelWeatherView.swift
//  FunNotch
//
//  Retro pixel weather, drawn behind the temperature on the home tab.
//
//  Everything is snapped to a coarse grid and drawn as flat rectangles: no
//  gradients, no blur, no anti-aliased curves. That is the whole trick. Chunky
//  pixels read as deliberate; the same shapes drawn smoothly at this size just
//  look like a low-resolution mistake.
//
//  Particle positions come from a seeded generator rather than `random()`, so a
//  raindrop keeps its lane between frames instead of teleporting on every
//  redraw, and the scene looks identical on every Mac.
//

import SwiftUI

/// What the sky is doing, reduced to the handful of things worth animating.
enum WeatherScene {
    case clearDay
    case clearNight
    case cloudy
    case fog
    case drizzle
    case rain
    case storm
    case snow

    /// WMO weather code, as returned by the forecast API.
    static func from(code: Int, isDay: Bool) -> WeatherScene {
        switch code {
        case 0:                         return isDay ? .clearDay : .clearNight
        case 1, 2:                      return isDay ? .clearDay : .clearNight
        case 3:                         return .cloudy
        case 45, 48:                    return .fog
        case 51, 53, 55, 56, 57:        return .drizzle
        case 61, 63, 65, 66, 67:        return .rain
        case 71, 73, 75, 77, 85, 86:    return .snow
        case 80, 81, 82:                return .rain
        case 95, 96, 99:                return .storm
        default:                        return .cloudy
        }
    }

    var accent: Color {
        switch self {
        case .clearDay:   return Color(red: 1.00, green: 0.82, blue: 0.35)
        case .clearNight: return Color(red: 0.72, green: 0.80, blue: 1.00)
        case .cloudy:     return Color(red: 0.78, green: 0.82, blue: 0.88)
        case .fog:        return Color(red: 0.72, green: 0.76, blue: 0.80)
        case .drizzle:    return Color(red: 0.55, green: 0.78, blue: 0.98)
        case .rain:       return Color(red: 0.42, green: 0.70, blue: 1.00)
        case .storm:      return Color(red: 0.62, green: 0.66, blue: 1.00)
        case .snow:       return Color(red: 0.88, green: 0.94, blue: 1.00)
        }
    }

    var label: String {
        switch self {
        case .clearDay:   return "Clear"
        case .clearNight: return "Clear"
        case .cloudy:     return "Cloudy"
        case .fog:        return "Fog"
        case .drizzle:    return "Drizzle"
        case .rain:       return "Rain"
        case .storm:      return "Storm"
        case .snow:       return "Snow"
        }
    }
}

/// Deterministic noise. Same input, same output, on every machine and frame.
private func hash01(_ n: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n &* 0x27D4_EB2D))
    x ^= x >> 15
    x = x &* 0x2545_F491_4F6C_DD1D
    x ^= x >> 21
    return Double(x % 100_000) / 100_000
}

struct PixelWeatherView: View {
    let scene: WeatherScene

    /// Size of one "pixel". Everything lands on this grid.
    private let cell: CGFloat = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                draw(&ctx, size: size, t: t)
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    /// Snaps a rect to the pixel grid so nothing is ever drawn on a half pixel.
    private func snap(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 1, _ h: CGFloat = 1) -> CGRect {
        CGRect(
            x: (x / cell).rounded(.down) * cell,
            y: (y / cell).rounded(.down) * cell,
            width: w * cell,
            height: h * cell
        )
    }

    private func px(_ ctx: inout GraphicsContext, _ rect: CGRect, _ color: Color, _ opacity: Double = 1) {
        ctx.fill(Path(rect), with: .color(color.opacity(opacity)))
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        switch scene {
        case .clearDay:   drawSun(&ctx, size: size, t: t)
        case .clearNight: drawStars(&ctx, size: size, t: t)
        case .cloudy:     drawClouds(&ctx, size: size, t: t, density: 4)
        case .fog:        drawFog(&ctx, size: size, t: t)
        case .drizzle:    drawRain(&ctx, size: size, t: t, count: 14, speed: 34, length: 2, slant: 0.10)
        case .rain:       drawRain(&ctx, size: size, t: t, count: 30, speed: 74, length: 3, slant: 0.18)
        case .storm:      drawStorm(&ctx, size: size, t: t)
        case .snow:       drawSnow(&ctx, size: size, t: t)
        }
    }

    // MARK: - Scenes

    private func drawRain(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval,
                          count: Int, speed: Double, length: CGFloat, slant: Double) {
        for i in 0 ..< count {
            let lane = hash01(i * 7 + 1)
            let phase = hash01(i * 13 + 5)
            // Each drop falls at its own pace, so the sheet never pulses.
            let rate = speed * (0.75 + hash01(i * 3 + 2) * 0.5)
            let fall = (t * rate + phase * Double(size.height)).truncatingRemainder(dividingBy: Double(size.height + 12))
            let y = CGFloat(fall) - 12
            // Wind pushes the whole column sideways as it descends.
            let x = CGFloat(lane) * size.width + CGFloat(fall) * CGFloat(slant)
            let wrappedX = x.truncatingRemainder(dividingBy: size.width)
            px(&ctx, snap(wrappedX, y, 1, length), scene.accent, 0.30 + hash01(i) * 0.45)
        }
    }

    private func drawSnow(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        for i in 0 ..< 22 {
            let lane = hash01(i * 11 + 3)
            let phase = hash01(i * 17 + 9)
            let rate = 15 + hash01(i * 5) * 14
            let fall = (t * rate + phase * Double(size.height)).truncatingRemainder(dividingBy: Double(size.height + 8))
            let y = CGFloat(fall) - 8
            // A slow sideways drift, different per flake, reads as tumbling.
            let drift = sin(t * (0.5 + hash01(i * 23) * 0.8) + Double(i)) * 5
            let x = CGFloat(lane) * size.width + CGFloat(drift)
            px(&ctx, snap(x, y, 1, 1), scene.accent, 0.45 + hash01(i * 2) * 0.45)
        }
    }

    private func drawClouds(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval, density: Int) {
        for i in 0 ..< density {
            let speed = 5 + hash01(i * 31) * 6
            // Spread the band each cloud occupies rather than picking a random
            // height per cloud: three random values in a 96pt box clump often
            // enough to look like a mistake.
            let band = Double(size.height - 16) / Double(density)
            let baseY = 4 + band * Double(i) + hash01(i * 19) * band * 0.6
            let width = 8 + Int(hash01(i * 29) * 7)
            // Travel is one full width plus the cloud, so a cloud leaves the
            // right edge completely before reappearing on the left.
            let span = Double(size.width) + Double(CGFloat(width) * cell) + 20
            // Phase is spaced by index so they never start bunched together.
            let phase = (Double(i) / Double(density) + hash01(i * 41) * 0.3) * span
            let offset = (t * speed + phase).truncatingRemainder(dividingBy: span)
                - Double(CGFloat(width) * cell) - 10
            let x = CGFloat(offset)
            let y = CGFloat(baseY)
            let alpha = 0.16 + hash01(i * 7) * 0.16

            // A cloud is a fat bar with a shorter bar stacked on top.
            px(&ctx, snap(x, y + cell, CGFloat(width), 2), scene.accent, alpha)
            px(&ctx, snap(x + cell * 2, y, CGFloat(width) - 4, 1), scene.accent, alpha)
        }
    }

    private func drawFog(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        // Long horizontal bands sliding at different speeds. Fog is the one
        // condition where nothing falls, so the motion has to be lateral.
        for row in 0 ..< 5 {
            let speed = 4 + hash01(row * 37) * 7
            let y = 4 + CGFloat(row) * (size.height - 8) / 5
            let offset = (t * speed).truncatingRemainder(dividingBy: Double(size.width + 40)) - 20
            let width = 10 + Int(hash01(row * 13) * 10)
            px(&ctx, snap(CGFloat(offset), y, CGFloat(width), 1), scene.accent, 0.16)
            px(&ctx, snap(CGFloat(offset) - 40, y, CGFloat(width) / 2, 1), scene.accent, 0.10)
        }
    }

    private func drawSun(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        // Sits where the weather icon used to, so the text has the left half
        // to itself. There was an SF Symbol sun here as well as this one, which
        // meant two suns in one small panel.
        let cx = size.width * 0.80
        let cy = size.height * 0.46

        // A blocky disc: rows of differing width, which is how a circle looks
        // when you only have whole pixels to spend. Wider than it is tall by a
        // row, because the grid is square but the eye is not.
        let widths: [CGFloat] = [4, 6, 8, 8, 8, 6, 4]
        for (row, w) in widths.enumerated() {
            let y = cy - cell * 3.5 + CGFloat(row) * cell
            px(&ctx, snap(cx - w * cell / 2, y, w, 1), scene.accent, 0.92)
        }
        // A dimmer ring just outside the disc reads as heat haze and stops the
        // edge looking cut out.
        for (row, w) in [CGFloat(2), 4, 6, 6, 6, 4, 2].enumerated() {
            let y = cy - cell * 4.5 + CGFloat(row) * cell
            px(&ctx, snap(cx - w * cell / 2 - cell, y, 1, 1), scene.accent, 0.22)
            px(&ctx, snap(cx + w * cell / 2, y, 1, 1), scene.accent, 0.22)
        }

        // Eight rays that breathe in and out. Rotation stairsteps horribly on a
        // grid this coarse, so they pulse instead — and the diagonals lag the
        // straight ones so the whole thing does not throb as one lump.
        let axes: [(Double, Double, Double)] = [
            (0, 1, 0), (.pi / 2, 0, 1), (.pi, -1, 0), (3 * .pi / 2, 0, -1),
            (.pi / 4, 0.7, 0.7), (3 * .pi / 4, -0.7, 0.7),
            (5 * .pi / 4, -0.7, -0.7), (7 * .pi / 4, 0.7, -0.7)
        ]
        for (index, axis) in axes.enumerated() {
            let diagonal = index >= 4
            let phase = diagonal ? 0.9 : 0.0
            let pulse = (sin(t * 1.9 + phase) + 1) / 2
            let inner = cell * 5.5
            let length = cell * (diagonal ? 1.5 : 2.5) * CGFloat(0.6 + pulse * 0.8)

            var travelled: CGFloat = 0
            while travelled < length {
                let d = inner + travelled
                let x = cx + CGFloat(axis.1) * d
                let y = cy + CGFloat(axis.2) * d
                px(&ctx, snap(x, y, 1, 1), scene.accent, 0.30 + pulse * 0.55)
                travelled += cell
            }
        }
    }

    private func drawStars(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        drawMoon(&ctx, size: size, t: t)
        for i in 0 ..< 18 {
            let x = hash01(i * 43 + 1) * Double(size.width)
            let y = hash01(i * 61 + 7) * Double(size.height)
            // Each star twinkles on its own clock.
            let twinkle = (sin(t * (0.8 + hash01(i * 3) * 1.6) + Double(i) * 1.7) + 1) / 2
            px(&ctx, snap(CGFloat(x), CGFloat(y), 1, 1), scene.accent, 0.20 + twinkle * 0.70)
        }
    }

    /// A crescent: the disc with a second disc punched out of it by drawing the
    /// background over the top, which is how you cut a shape when all you have
    /// is filled rectangles.
    private func drawMoon(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let cx = size.width * 0.80
        let cy = size.height * 0.46
        // Only the lit sliver is drawn. Punching the bite out with black looked
        // right on paper and wrong on screen: the panel is translucent, so
        // "black" is a visible dark blob rather than a hole.
        let widths: [CGFloat] = [4, 6, 8, 8, 8, 6, 4]
        let bites: [CGFloat] = [3, 5, 6, 6, 6, 5, 3]
        for (row, w) in widths.enumerated() {
            let y = cy - cell * 3.5 + CGFloat(row) * cell
            let discLeft = cx - w * cell / 2
            let biteLeft = cx - bites[row] * cell / 2 + cell * 2
            let lit = (biteLeft - discLeft) / cell
            guard lit >= 1 else { continue }
            px(&ctx, snap(discLeft, y, lit.rounded(.down), 1), scene.accent, 0.85)
        }
    }

    private func drawStorm(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        drawRain(&ctx, size: size, t: t, count: 26, speed: 96, length: 3, slant: 0.26)

        // Lightning on a repeating cycle, lit for a fraction of it. Two quick
        // flashes rather than one, because that is what lightning looks like.
        let cycle = t.truncatingRemainder(dividingBy: 4.2)
        let lit = cycle < 0.06 || (cycle > 0.14 && cycle < 0.19)
        guard lit else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.10)))

        // A zigzag bolt, stepped so it stays on the grid. The direction flips
        // every couple of steps off a step counter — keying it off `y` looked
        // right but always tested even, so the bolt came out a straight
        // diagonal line.
        let x = size.width * 0.62
        var y: CGFloat = 2
        var drift: CGFloat = 0
        var step = 0
        while y < size.height - 4 {
            px(&ctx, snap(x + drift, y, 1, 2), .white, 0.9)
            // A dimmer pixel beside it gives the bolt some body.
            px(&ctx, snap(x + drift + cell, y, 1, 2), .white, 0.35)
            y += cell * 2
            drift += (step / 2) % 2 == 0 ? cell : -cell
            step += 1
        }
    }
}
