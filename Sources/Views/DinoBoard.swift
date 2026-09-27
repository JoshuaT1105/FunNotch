//
//  DinoBoard.swift
//  FunNotch
//
//  Dino Run, drawn: a desert in layers — mountains, mesas, dunes, then the
//  ground — each scrolling at its own speed, under a sky that runs from
//  morning through sunset into a starry night as the score climbs. Everything
//  is vector: the dinosaur is built from curves every frame, so it runs,
//  blinks, squashes on landing and stretches on take-off.
//

import SwiftUI

struct DinoBoard: View {
    let now: Date

    @MainActor private var game: DinoGame { DinoGame.shared }

    var body: some View {
        Canvas { context, size in
            game.advance(to: now, size: size)
            DinoPainter(game: game, size: size).draw(in: &context)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Colour

/// A colour as numbers, so the sky can be blended between times of day.
private struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func color(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b, opacity: opacity) }
}

/// The landscape's colours at one moment of the day.
private struct Palette {
    let top: RGB
    let horizon: RGB
    let far: RGB
    let mid: RGB
    let near: RGB
    let ground: RGB
    let groundDeep: RGB

    func mix(_ other: Palette, _ t: Double) -> Palette {
        Palette(
            top: top.mix(other.top, t), horizon: horizon.mix(other.horizon, t),
            far: far.mix(other.far, t), mid: mid.mix(other.mid, t), near: near.mix(other.near, t),
            ground: ground.mix(other.ground, t), groundDeep: groundDeep.mix(other.groundDeep, t)
        )
    }

    /// Keyframes round the day. The first and last are the same moment.
    static let day: [(at: Double, palette: Palette)] = [
        (0.00, Palette(top: RGB(0.42, 0.7, 0.95), horizon: RGB(1, 0.86, 0.7), far: RGB(0.63, 0.73, 0.87),
                       mid: RGB(0.86, 0.6, 0.5), near: RGB(0.94, 0.75, 0.52), ground: RGB(0.97, 0.84, 0.62),
                       groundDeep: RGB(0.87, 0.69, 0.46))),
        (0.16, Palette(top: RGB(0.3, 0.62, 0.97), horizon: RGB(0.75, 0.9, 1), far: RGB(0.6, 0.74, 0.9),
                       mid: RGB(0.87, 0.63, 0.5), near: RGB(0.96, 0.79, 0.54), ground: RGB(0.98, 0.87, 0.65),
                       groundDeep: RGB(0.89, 0.73, 0.49))),
        (0.36, Palette(top: RGB(0.34, 0.58, 0.93), horizon: RGB(0.98, 0.88, 0.72), far: RGB(0.66, 0.7, 0.85),
                       mid: RGB(0.88, 0.6, 0.47), near: RGB(0.95, 0.75, 0.5), ground: RGB(0.97, 0.84, 0.6),
                       groundDeep: RGB(0.87, 0.68, 0.44))),
        (0.49, Palette(top: RGB(0.34, 0.3, 0.62), horizon: RGB(1, 0.58, 0.4), far: RGB(0.56, 0.42, 0.62),
                       mid: RGB(0.73, 0.38, 0.42), near: RGB(0.86, 0.5, 0.4), ground: RGB(0.88, 0.62, 0.47),
                       groundDeep: RGB(0.72, 0.45, 0.36))),
        (0.58, Palette(top: RGB(0.11, 0.12, 0.32), horizon: RGB(0.52, 0.29, 0.48), far: RGB(0.28, 0.24, 0.42),
                       mid: RGB(0.33, 0.23, 0.37), near: RGB(0.41, 0.29, 0.39), ground: RGB(0.45, 0.36, 0.42),
                       groundDeep: RGB(0.33, 0.26, 0.33))),
        (0.68, Palette(top: RGB(0.03, 0.05, 0.14), horizon: RGB(0.12, 0.16, 0.33), far: RGB(0.12, 0.15, 0.29),
                       mid: RGB(0.14, 0.15, 0.27), near: RGB(0.18, 0.18, 0.29), ground: RGB(0.25, 0.24, 0.34),
                       groundDeep: RGB(0.17, 0.16, 0.25))),
        (0.87, Palette(top: RGB(0.03, 0.05, 0.14), horizon: RGB(0.13, 0.17, 0.35), far: RGB(0.12, 0.15, 0.29),
                       mid: RGB(0.14, 0.15, 0.27), near: RGB(0.18, 0.18, 0.29), ground: RGB(0.25, 0.24, 0.34),
                       groundDeep: RGB(0.17, 0.16, 0.25))),
        (0.95, Palette(top: RGB(0.24, 0.31, 0.62), horizon: RGB(0.98, 0.66, 0.6), far: RGB(0.43, 0.44, 0.63),
                       mid: RGB(0.6, 0.44, 0.5), near: RGB(0.73, 0.55, 0.5), ground: RGB(0.82, 0.67, 0.56),
                       groundDeep: RGB(0.67, 0.52, 0.44))),
        (1.00, Palette(top: RGB(0.42, 0.7, 0.95), horizon: RGB(1, 0.86, 0.7), far: RGB(0.63, 0.73, 0.87),
                       mid: RGB(0.86, 0.6, 0.5), near: RGB(0.94, 0.75, 0.52), ground: RGB(0.97, 0.84, 0.62),
                       groundDeep: RGB(0.87, 0.69, 0.46))),
    ]

    static func at(_ phase: Double) -> Palette {
        let keys = day
        for index in 1 ..< keys.count where phase <= keys[index].at {
            let a = keys[index - 1]
            let b = keys[index]
            let t = (phase - a.at) / max(b.at - a.at, 0.0001)
            return a.palette.mix(b.palette, t * t * (3 - 2 * t))
        }
        return keys[0].palette
    }
}

/// A repeatable pseudo-random number in 0..<1 for an integer, so scenery is
/// the same every time it scrolls past.
private func hash(_ n: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15
    x ^= x >> 31
    x = x &* 0xBF58_476D_1CE4_E5B9
    x ^= x >> 29
    return Double(x % 10_000) / 10_000
}

// MARK: - Painter

@MainActor
private struct DinoPainter {
    let game: DinoGame
    let size: CGSize

    private var groundY: CGFloat { game.groundY }
    private var width: CGFloat { size.width }

    func draw(in context: inout GraphicsContext) {
        let palette = Palette.at(game.dayPhase)
        let night = game.nightness

        if game.shake > 0.05 {
            context.translateBy(
                x: CGFloat(sin(game.clock * 91)) * game.shake,
                y: CGFloat(cos(game.clock * 73)) * game.shake * 0.6
            )
        }

        drawSky(&context, palette, night: night)
        drawClouds(&context, palette, night: night)
        drawFarRange(&context, palette)
        drawMesas(&context, palette)
        drawDunes(&context, palette)
        drawGround(&context, palette, night: night)
        drawSpeedLines(&context, night: night)

        // The cast, in a layer of their own so the night can tint them
        // without muddying the sky behind.
        context.drawLayer { layer in
            for obstacle in game.obstacles { drawObstacle(&layer, obstacle) }
            drawDino(&layer)
            drawParticles(&layer, dust: palette.ground)
            if night > 0.01 {
                layer.blendMode = .sourceAtop
                layer.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .color(Color(red: 0.05, green: 0.08, blue: 0.3).opacity(0.32 * night)))
            }
        }

        // Things that give off light stay bright at night.
        for gem in game.gems { drawGem(&context, gem) }
        for orb in game.orbs { drawOrb(&context, orb) }
        drawGlows(&context)
        drawPopups(&context)
        drawBanner(&context)
    }

    // MARK: Sky

    private func drawSky(_ context: inout GraphicsContext, _ palette: Palette, night: Double) {
        let rect = CGRect(origin: .zero, size: size)
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [palette.top.color, palette.horizon.color]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: groundY)
        ))

        // Stars, fading in with the night.
        if night > 0.02 {
            for index in 0 ..< 46 {
                let x = hash(index * 3 + 1) * Double(width)
                let y = hash(index * 3 + 2) * Double(groundY - 30)
                let twinkle = 0.55 + 0.45 * sin(game.clock * (1.2 + hash(index) * 2.5) + Double(index))
                let big = index % 9 == 0
                let r: CGFloat = big ? 1.3 : 0.75
                let alpha = night * twinkle * (big ? 1 : 0.8)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
                if big {
                    var cross = Path()
                    cross.move(to: CGPoint(x: x - 3, y: y))
                    cross.addLine(to: CGPoint(x: x + 3, y: y))
                    cross.move(to: CGPoint(x: x, y: y - 3))
                    cross.addLine(to: CGPoint(x: x, y: y + 3))
                    context.stroke(cross, with: .color(.white.opacity(alpha * 0.45)), lineWidth: 0.5)
                }
            }
            drawShootingStar(&context, night: night)
        }

        drawSun(&context)
        drawMoon(&context, night: night)
    }

    /// Across the sky every twenty seconds or so, at night.
    private func drawShootingStar(_ context: inout GraphicsContext, night: Double) {
        let period = 7.0
        let cycle = floor(game.clock / period)
        let t = (game.clock - cycle * period) / 0.7
        guard night > 0.5, t < 1, hash(Int(cycle)) < 0.45 else { return }
        let startX = CGFloat(0.3 + hash(Int(cycle) + 7) * 0.6) * width
        let startY = CGFloat(8 + hash(Int(cycle) + 3) * 20)
        let head = CGPoint(x: startX - CGFloat(t) * 150, y: startY + CGFloat(t) * 45)
        let tail = CGPoint(x: head.x + 34, y: head.y - 10)
        var streak = Path()
        streak.move(to: tail)
        streak.addLine(to: head)
        let fade = sin(t * .pi)
        context.stroke(streak, with: .linearGradient(
            Gradient(colors: [.white.opacity(0), .white.opacity(0.9 * fade * night)]),
            startPoint: tail, endPoint: head
        ), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    /// Where on its arc something is that rises at `rise` and sets at `set`
    /// in day-phase terms, or nil while it is down.
    private func arc(rise: Double, set: Double) -> (point: CGPoint, height: Double)? {
        var p = game.dayPhase
        if p < rise - 0.5 { p += 1 }
        let t = (p - rise) / (set - rise)
        guard t > -0.02, t < 1.02 else { return nil }
        let lift = sin(max(min(t, 1), 0) * .pi)
        let x = width * CGFloat(0.06 + 0.88 * t)
        let y = groundY - 14 - CGFloat(lift) * (groundY - 30)
        return (CGPoint(x: x, y: y), lift)
    }

    private func drawSun(_ context: inout GraphicsContext) {
        guard let (centre, lift) = arc(rise: -0.06, set: 0.55) else { return }
        // White-gold overhead, deep orange on the horizon.
        let low = 1 - lift
        let core = RGB(1, 0.97, 0.82).mix(RGB(1, 0.62, 0.3), low)
        let glow = RGB(1, 0.9, 0.6).mix(RGB(1, 0.45, 0.25), low)
        let radius: CGFloat = 8 + CGFloat(low) * 3
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 60, y: centre.y - 60, width: 120, height: 120)),
                     with: .radialGradient(Gradient(colors: [glow.color(0.5), glow.color(0.12), glow.color(0)]),
                                           center: centre, startRadius: 0, endRadius: 60))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(core.color))
    }

    private func drawMoon(_ context: inout GraphicsContext, night: Double) {
        guard night > 0.05, let (centre, _) = arc(rise: 0.5, set: 1.02) else { return }
        let r: CGFloat = 7.5
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 36, y: centre.y - 36, width: 72, height: 72)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.75, green: 0.82, blue: 1).opacity(0.3 * night), .clear]),
                                           center: centre, startRadius: 0, endRadius: 36))
        context.drawLayer { layer in
            let disc = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
            layer.fill(disc, with: .color(Color(red: 0.97, green: 0.96, blue: 0.88).opacity(night)))
            // Craters, faintly.
            for (dx, dy, cr) in [(-2.2, -1.5, 1.6), (2.4, 2.1, 1.1), (1.2, -3.2, 0.8)] {
                layer.fill(Path(ellipseIn: CGRect(x: centre.x + dx - cr, y: centre.y + dy - cr, width: cr * 2, height: cr * 2)),
                           with: .color(Color(red: 0.8, green: 0.8, blue: 0.75).opacity(0.5 * night)))
            }
            // Bitten into a crescent.
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: CGRect(x: centre.x - r + 5, y: centre.y - r - 2.5, width: r * 2, height: r * 2)),
                       with: .color(.black))
        }
    }

    private func drawClouds(_ context: inout GraphicsContext, _ palette: Palette, night: Double) {
        let tint = RGB(1, 1, 1).mix(palette.horizon, 0.25).mix(RGB(0.32, 0.36, 0.55), night * 0.85)
        let span = Double(width) + 160
        for index in 0 ..< 5 {
            let speed = 0.05 + hash(index + 40) * 0.05
            let offset = hash(index + 20) * span - Double(game.distance) * speed - game.clock * 3
            var x = offset.truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            let cx = CGFloat(x) - 80
            let cy = CGFloat(12 + hash(index + 30) * 34)
            let scale = CGFloat(0.7 + hash(index + 50) * 0.6)
            let puffs: [(CGFloat, CGFloat, CGFloat)] = [(-12, 2, 7), (-3, -3, 9), (8, 0, 8), (16, 3, 5.5), (2, 4, 7)]
            var cloud = Path()
            for (dx, dy, r) in puffs {
                cloud.addEllipse(in: CGRect(x: cx + dx * scale - r * scale, y: cy + dy * scale - r * scale,
                                            width: r * 2 * scale, height: r * 2 * scale))
            }
            let alpha = (0.85 - night * 0.45) * (0.7 + hash(index + 60) * 0.3)
            context.fill(cloud, with: .linearGradient(
                Gradient(colors: [tint.color(alpha), tint.mix(palette.top, 0.3).color(alpha * 0.8)]),
                startPoint: CGPoint(x: cx, y: cy - 10 * scale), endPoint: CGPoint(x: cx, y: cy + 10 * scale)
            ))
        }
    }

    // MARK: Landscape

    /// A ridge line across the board: a y for each x.
    private func ridge(parallax: CGFloat, base: CGFloat, step: CGFloat = 5, height: (Double) -> Double) -> Path {
        let shift = Double(game.distance * parallax)
        var path = Path()
        path.move(to: CGPoint(x: -2, y: size.height))
        var x: CGFloat = -2
        while x <= width + step {
            let y = base - CGFloat(height(Double(x) + shift))
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: width + step, y: size.height))
        path.closeSubpath()
        return path
    }

    private func drawFarRange(_ context: inout GraphicsContext, _ palette: Palette) {
        let path = ridge(parallax: 0.05, base: groundY - 6) { x in
            22 + 11 * sin(x * 0.013 + 1) + 7 * sin(x * 0.031 + 2.3) + 3.5 * sin(x * 0.07)
        }
        context.fill(path, with: .linearGradient(
            Gradient(colors: [palette.far.mix(palette.horizon, 0.15).color, palette.far.mix(palette.horizon, 0.55).color]),
            startPoint: CGPoint(x: 0, y: groundY - 45), endPoint: CGPoint(x: 0, y: groundY)
        ))
    }

    /// Flat-topped buttes: a wave clipped off at the top gives the plateau,
    /// and steep sides where it rises.
    private func drawMesas(_ context: inout GraphicsContext, _ palette: Palette) {
        let path = ridge(parallax: 0.14, base: groundY - 2, step: 3) { x in
            let wave = sin(x * 0.019) + 0.4 * sin(x * 0.047 + 1.1) + 0.2 * sin(x * 0.11)
            let plateau = min(max((wave - 0.45) * 3.2, 0), 1)
            return 3 + 24 * plateau * (0.85 + 0.15 * sin(x * 0.29))
        }
        context.fill(path, with: .linearGradient(
            Gradient(colors: [palette.mid.color, palette.mid.mix(palette.near, 0.4).color]),
            startPoint: CGPoint(x: 0, y: groundY - 28), endPoint: CGPoint(x: 0, y: groundY)
        ))
    }

    private func drawDunes(_ context: inout GraphicsContext, _ palette: Palette) {
        let path = ridge(parallax: 0.35, base: groundY + 1) { x in
            6 + 4.5 * sin(x * 0.021 + 0.5) + 2.5 * sin(x * 0.055 + 2)
        }
        context.fill(path, with: .linearGradient(
            Gradient(colors: [palette.near.color, palette.near.mix(palette.ground, 0.5).color]),
            startPoint: CGPoint(x: 0, y: groundY - 12), endPoint: CGPoint(x: 0, y: groundY)
        ))

        // The odd cactus standing on the dunes, far off.
        let shift = game.distance * 0.35
        let spacing: CGFloat = 140
        let first = Int(floor(shift / spacing))
        for cell in first ... first + Int(width / spacing) + 1 {
            guard hash(cell + 900) < 0.45 else { continue }
            let worldX = CGFloat(cell) * spacing + CGFloat(hash(cell + 901)) * spacing * 0.8
            let x = worldX - shift
            let duneTop = 6 + 4.5 * sin(Double(worldX) * 0.021 + 0.5) + 2.5 * sin(Double(worldX) * 0.055 + 2)
            let baseY = groundY + 1 - CGFloat(duneTop) + 1
            let h = CGFloat(6 + hash(cell + 902) * 5)
            var cactus = Path()
            cactus.addRoundedRect(in: CGRect(x: x - 1.2, y: baseY - h, width: 2.4, height: h), cornerSize: CGSize(width: 1.2, height: 1.2))
            cactus.addRoundedRect(in: CGRect(x: x - 4, y: baseY - h * 0.75, width: 1.8, height: h * 0.4), cornerSize: CGSize(width: 0.9, height: 0.9))
            cactus.addRect(CGRect(x: x - 4, y: baseY - h * 0.4, width: 3.2, height: 1.3))
            context.fill(cactus, with: .color(palette.mid.mix(palette.near, 0.2).color(0.9)))
        }
    }

    private func drawGround(_ context: inout GraphicsContext, _ palette: Palette, night: Double) {
        let band = CGRect(x: -4, y: groundY, width: width + 8, height: size.height - groundY + 4)
        context.fill(Path(band), with: .linearGradient(
            Gradient(colors: [palette.ground.color, palette.groundDeep.color]),
            startPoint: CGPoint(x: 0, y: groundY), endPoint: CGPoint(x: 0, y: size.height)
        ))
        // A lit edge along the top, then a soft shadow line just under it.
        context.fill(Path(CGRect(x: -4, y: groundY, width: width + 8, height: 1.2)),
                     with: .color(.white.opacity(0.35 - night * 0.2)))
        context.fill(Path(CGRect(x: -4, y: groundY + 1.2, width: width + 8, height: 1.4)),
                     with: .color(palette.groundDeep.color(0.5)))

        // Pebbles, tufts and cracks, fixed to the ground as it scrolls.
        let cell: CGFloat = 16
        let first = Int(floor(game.distance / cell))
        let depth = size.height - groundY
        for index in first ... first + Int(width / cell) + 1 {
            let x = CGFloat(index) * cell - game.distance
            let roll = hash(index)
            let y = groundY + 4 + CGFloat(hash(index + 11)) * (depth - 7)
            if roll < 0.32 {
                let w = CGFloat(1.6 + hash(index + 3) * 2.4)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: w * 0.62)),
                             with: .color(palette.groundDeep.mix(RGB(0.3, 0.25, 0.2), 0.35).color(0.55)))
                context.fill(Path(ellipseIn: CGRect(x: x + w * 0.2, y: y, width: w * 0.5, height: w * 0.25)),
                             with: .color(.white.opacity(0.25)))
            } else if roll < 0.44 {
                var tuft = Path()
                let base = CGPoint(x: x + 4, y: groundY + 1.5)
                for blade in 0 ..< 3 {
                    let lean = CGFloat(blade - 1) * 1.6
                    tuft.move(to: base)
                    tuft.addQuadCurve(to: CGPoint(x: base.x + lean * 1.6, y: base.y - 3.5 - CGFloat(blade % 2)),
                                      control: CGPoint(x: base.x + lean * 0.3, y: base.y - 2))
                }
                context.stroke(tuft, with: .color(RGB(0.5, 0.62, 0.3).mix(palette.groundDeep, 0.3 + night * 0.4).color(0.9)),
                               style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            } else if roll < 0.52 {
                var crack = Path()
                crack.move(to: CGPoint(x: x, y: y))
                crack.addLine(to: CGPoint(x: x + 5, y: y + 1))
                crack.addLine(to: CGPoint(x: x + 8, y: y - 0.5))
                context.stroke(crack, with: .color(palette.groundDeep.mix(RGB(0.2, 0.15, 0.1), 0.3).color(0.5)),
                               lineWidth: 0.7)
            }
        }
    }

    /// At speed, streaks through the air.
    private func drawSpeedLines(_ context: inout GraphicsContext, night: Double) {
        let fast = game.turboLeft > 0 ? 1 : Double(min(max((game.speed - 450) / 190, 0), 1))
        guard fast > 0.02, game.phase == .running else { return }
        for index in 0 ..< 7 {
            let lane = CGFloat(10 + hash(index + 70) * Double(groundY - 30))
            let length = CGFloat(30 + hash(index + 71) * 50)
            let span = Double(width + length)
            var x = (hash(index + 72) * span - game.clock * Double(game.speed) * 1.6).truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            let start = CGPoint(x: CGFloat(x), y: lane)
            let end = CGPoint(x: CGFloat(x) + length, y: lane)
            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            context.stroke(line, with: .linearGradient(
                Gradient(colors: [.white.opacity(0.45 * fast), .white.opacity(0)]),
                startPoint: start, endPoint: end
            ), lineWidth: 0.8)
        }
    }

    // MARK: Obstacles

    private func drawObstacle(_ context: inout GraphicsContext, _ obstacle: DinoGame.Obstacle) {
        switch obstacle.kind {
        case .cactus: drawCactus(&context, obstacle)
        case .rock: drawRock(&context, obstacle)
        case .bird: drawBird(&context, obstacle)
        case .tumbleweed: drawTumbleweed(&context, obstacle)
        }
    }

    private func groundShadow(_ context: inout GraphicsContext, x: CGFloat, width: CGFloat, strength: Double) {
        context.fill(Path(ellipseIn: CGRect(x: x - width / 2, y: groundY - 1.5, width: width, height: 3.5)),
                     with: .color(.black.opacity(0.18 * strength)))
    }

    private func drawCactus(_ context: inout GraphicsContext, _ obstacle: DinoGame.Obstacle) {
        let light = Color(red: 0.4, green: 0.79, blue: 0.5)
        let dark = Color(red: 0.14, green: 0.47, blue: 0.3)
        for stem in obstacle.stems {
            let x = obstacle.x + stem.dx
            let w = stem.width
            let top = groundY - stem.height
            groundShadow(&context, x: x + w / 2, width: w + 8, strength: 1)

            var shape = Path()
            shape.addRoundedRect(in: CGRect(x: x, y: top, width: w, height: stem.height + 1),
                                 cornerSize: CGSize(width: w / 2, height: w / 2))
            let arm = w * 0.62
            if let join = stem.leftArm {
                let y = groundY - stem.height * join
                shape.addRoundedRect(in: CGRect(x: x - 5.5, y: y - arm / 2, width: 7, height: arm),
                                     cornerSize: CGSize(width: arm / 2, height: arm / 2))
                shape.addRoundedRect(in: CGRect(x: x - 5.5, y: y - 8.5, width: arm, height: 8.5 + arm / 2),
                                     cornerSize: CGSize(width: arm / 2, height: arm / 2))
            }
            if let join = stem.rightArm {
                let y = groundY - stem.height * join
                shape.addRoundedRect(in: CGRect(x: x + w - 1.5, y: y - arm / 2, width: 7, height: arm),
                                     cornerSize: CGSize(width: arm / 2, height: arm / 2))
                shape.addRoundedRect(in: CGRect(x: x + w + 5.5 - arm, y: y - 7, width: arm, height: 7 + arm / 2),
                                     cornerSize: CGSize(width: arm / 2, height: arm / 2))
            }
            // Lit from the left, like everything else out here.
            context.fill(shape, with: .linearGradient(
                Gradient(colors: [light, dark]),
                startPoint: CGPoint(x: x - 6, y: top), endPoint: CGPoint(x: x + w + 6, y: top)
            ))

            // Ribs down the stem.
            var ribs = Path()
            ribs.move(to: CGPoint(x: x + w * 0.35, y: top + 3))
            ribs.addLine(to: CGPoint(x: x + w * 0.35, y: groundY - 1))
            ribs.move(to: CGPoint(x: x + w * 0.68, y: top + 4))
            ribs.addLine(to: CGPoint(x: x + w * 0.68, y: groundY - 1))
            context.stroke(ribs, with: .color(Color(red: 0.7, green: 0.95, blue: 0.7).opacity(0.28)), lineWidth: 0.7)

            // Spines, as tiny ticks.
            for spine in 0 ..< Int(stem.height / 6) {
                let sy = top + 4 + CGFloat(spine) * 6
                let side = spine % 2 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: side ? x : x + w, y: sy))
                tick.addLine(to: CGPoint(x: side ? x - 1.6 : x + w + 1.6, y: sy - 0.8))
                context.stroke(tick, with: .color(.white.opacity(0.55)), lineWidth: 0.5)
            }

            if stem.flower {
                let centre = CGPoint(x: x + w / 2, y: top + 0.5)
                for petal in 0 ..< 5 {
                    let angle = Double(petal) / 5 * 2 * .pi
                    let p = CGPoint(x: centre.x + CGFloat(cos(angle)) * 1.6, y: centre.y + CGFloat(sin(angle)) * 1.3)
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4)),
                                 with: .color(Color(red: 1, green: 0.45, blue: 0.65)))
                }
                context.fill(Path(ellipseIn: CGRect(x: centre.x - 0.8, y: centre.y - 0.8, width: 1.6, height: 1.6)),
                             with: .color(Color(red: 1, green: 0.9, blue: 0.4)))
            }
        }
    }

    private func drawRock(_ context: inout GraphicsContext, _ obstacle: DinoGame.Obstacle) {
        let rect = CGRect(x: obstacle.x, y: groundY - obstacle.height, width: obstacle.width, height: obstacle.height + 1)
        groundShadow(&context, x: rect.midX, width: rect.width + 6, strength: 1.2)
        // A lumpy outline: points round an ellipse at seeded distances,
        // joined with curves.
        let count = 8
        var points: [CGPoint] = []
        for index in 0 ..< count {
            let angle = Double(index) / Double(count) * 2 * .pi + .pi
            let wobble = 0.82 + 0.18 * hash(obstacle.seed + index)
            let rx = rect.width / 2 * CGFloat(wobble)
            let ry = rect.height * CGFloat(wobble)
            var y = rect.maxY + CGFloat(sin(angle)) * ry
            y = min(y, rect.maxY)
            points.append(CGPoint(x: rect.midX + CGFloat(cos(angle)) * rx, y: y))
        }
        var blob = Path()
        let start = CGPoint(x: (points[0].x + points[count - 1].x) / 2, y: (points[0].y + points[count - 1].y) / 2)
        blob.move(to: start)
        for index in 0 ..< count {
            let current = points[index]
            let next = points[(index + 1) % count]
            blob.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        blob.closeSubpath()
        context.fill(blob, with: .linearGradient(
            Gradient(colors: [Color(red: 0.74, green: 0.68, blue: 0.62), Color(red: 0.45, green: 0.39, blue: 0.35)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
        ))
        context.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.22, y: rect.minY + 2,
                                            width: rect.width * 0.32, height: rect.height * 0.28)),
                     with: .color(.white.opacity(0.28)))
    }

    private func drawBird(_ context: inout GraphicsContext, _ obstacle: DinoGame.Obstacle) {
        let cx = obstacle.x + obstacle.width / 2
        let cy = groundY - obstacle.altitude
        let flap = sin(obstacle.age * 9 + Double(obstacle.seed % 7))
        // Its shadow on the ground, fainter the higher it flies.
        groundShadow(&context, x: cx, width: 20, strength: max(0.9 - Double(obstacle.altitude) / 70, 0.2))

        let body = Color(red: 0.62, green: 0.44, blue: 0.9)
        let deep = Color(red: 0.38, green: 0.24, blue: 0.66)
        let membrane = Color(red: 0.76, green: 0.6, blue: 1)

        func wing(offset: CGFloat, shade: Double) {
            var path = Path()
            let tip = CGPoint(x: cx + 3 + offset, y: cy - 2 + CGFloat(flap) * 13)
            path.move(to: CGPoint(x: cx - 5 + offset, y: cy - 1.5))
            path.addQuadCurve(to: tip, control: CGPoint(x: cx - 4 + offset, y: cy - 2 + CGFloat(flap) * 8))
            path.addQuadCurve(to: CGPoint(x: cx + 7 + offset, y: cy - 1.5), control: CGPoint(x: cx + 7 + offset, y: cy + CGFloat(flap) * 5))
            path.closeSubpath()
            context.fill(path, with: .color(membrane.opacity(shade)))
            var bone = Path()
            bone.move(to: CGPoint(x: cx - 5 + offset, y: cy - 1.5))
            bone.addQuadCurve(to: tip, control: CGPoint(x: cx - 4 + offset, y: cy - 2 + CGFloat(flap) * 8))
            context.stroke(bone, with: .color(deep.opacity(shade)), lineWidth: 1)
        }

        wing(offset: 3, shade: 0.55)

        // Tail, body, head, crest and beak.
        var tail = Path()
        tail.move(to: CGPoint(x: cx + 7, y: cy - 1))
        tail.addLine(to: CGPoint(x: cx + 15, y: cy - 3.5))
        tail.addLine(to: CGPoint(x: cx + 7, y: cy + 2))
        tail.closeSubpath()
        context.fill(tail, with: .color(deep))

        let bodyRect = CGRect(x: cx - 9, y: cy - 3.5, width: 18, height: 7)
        context.fill(Path(ellipseIn: bodyRect), with: .linearGradient(
            Gradient(colors: [body, deep]), startPoint: CGPoint(x: cx, y: bodyRect.minY), endPoint: CGPoint(x: cx, y: bodyRect.maxY)
        ))

        var crest = Path()
        crest.move(to: CGPoint(x: cx - 10, y: cy - 5.5))
        crest.addLine(to: CGPoint(x: cx - 2.5, y: cy - 9))
        crest.addLine(to: CGPoint(x: cx - 7, y: cy - 3.5))
        crest.closeSubpath()
        context.fill(crest, with: .color(deep))

        context.fill(Path(ellipseIn: CGRect(x: cx - 14, y: cy - 7, width: 8.5, height: 7.5)), with: .color(body))

        var beak = Path()
        beak.move(to: CGPoint(x: cx - 13, y: cy - 4.5))
        beak.addLine(to: CGPoint(x: cx - 22, y: cy - 2))
        beak.addLine(to: CGPoint(x: cx - 12.5, y: cy - 1))
        beak.closeSubpath()
        context.fill(beak, with: .color(Color(red: 1, green: 0.72, blue: 0.32)))

        context.fill(Path(ellipseIn: CGRect(x: cx - 11.8, y: cy - 5.6, width: 3, height: 3)), with: .color(.white))
        context.fill(Path(ellipseIn: CGRect(x: cx - 11.9, y: cy - 4.9, width: 1.6, height: 1.6)), with: .color(.black))

        wing(offset: 0, shade: 1)
    }

    private func drawTumbleweed(_ context: inout GraphicsContext, _ obstacle: DinoGame.Obstacle) {
        let r = obstacle.width / 2
        let centre = CGPoint(x: obstacle.x + r, y: groundY - obstacle.bounce - r)
        groundShadow(&context, x: centre.x, width: 16 - min(obstacle.bounce / 4, 8), strength: 1)
        let brown = Color(red: 0.72, green: 0.55, blue: 0.33)
        let pale = Color(red: 0.86, green: 0.72, blue: 0.5)
        for index in 0 ..< 7 {
            let start = obstacle.spin + Double(index) * 0.95
            let radius = r * CGFloat(0.45 + hash(obstacle.seed + index) * 0.55)
            var loop = Path()
            loop.addArc(center: centre, radius: radius, startAngle: .radians(start),
                        endAngle: .radians(start + 2.3), clockwise: false)
            context.stroke(loop, with: .color(index % 2 == 0 ? brown : pale), lineWidth: 1)
        }
        context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                       with: .color(brown.opacity(0.6)), lineWidth: 0.8)
    }

    // MARK: The dinosaur

    private func drawDino(_ context: inout GraphicsContext) {
        let skin = game.skin
        let feet = CGPoint(x: DinoGame.dinoX, y: groundY - game.height)
        let pose = game.pose

        // Its shadow first, shrinking as it rises.
        let lift = min(game.height / 70, 1)
        context.fill(Path(ellipseIn: CGRect(x: DinoGame.dinoX - 12 + lift * 4, y: groundY - 1.8,
                                            width: 24 - lift * 8, height: 3.6)),
                     with: .color(.black.opacity(0.2 * Double(1 - lift * 0.6))))

        // Blinking after the shield has saved it.
        if game.graceLeft > 0, Int(game.clock * 14) % 2 == 0 { return }

        if game.hasShield { drawShield(&context, around: feet) }

        var ctx = context
        ctx.translateBy(x: feet.x, y: feet.y)
        let s = CGFloat(game.squash)
        if s > 0 {
            ctx.scaleBy(x: 1 - 0.1 * s, y: 1 + 0.14 * s)
        } else if s < 0 {
            ctx.scaleBy(x: 1 - 0.16 * s, y: 1 + 0.2 * s)
        }
        if pose == .standing {
            ctx.scaleBy(x: 1, y: 1 + 0.018 * CGFloat(sin(game.clock * 2.4)))
        }
        if pose == .crashed {
            ctx.rotate(by: .radians(-0.22))
        }

        let shading: GraphicsContext.Shading
        if game.turboLeft > 0 {
            let hue = (game.clock * 0.9).truncatingRemainder(dividingBy: 1)
            shading = .linearGradient(
                Gradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 1),
                                  Color(hue: (hue + 0.25).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.9)]),
                startPoint: CGPoint(x: 0, y: -34), endPoint: CGPoint(x: 0, y: 0)
            )
        } else {
            shading = .linearGradient(Gradient(colors: [skin.top, skin.bottom]),
                                      startPoint: CGPoint(x: 0, y: -34), endPoint: CGPoint(x: 0, y: 0))
        }

        if pose == .ducking {
            drawDucking(&ctx, skin: skin, shading: shading)
        } else {
            drawUpright(&ctx, skin: skin, shading: shading, pose: pose)
        }
    }

    /// Standing, running, jumping and crashed: the same body, with the legs,
    /// eyes and mouth doing different things.
    private func drawUpright(_ ctx: inout GraphicsContext, skin: DinoGame.Skin, shading: GraphicsContext.Shading,
                             pose: DinoGame.Pose) {
        let stride = game.stride
        let running = pose == .running
        let sway = running ? CGFloat(sin(stride * 2)) * 1.3 : 0
        let bob = running ? -CGFloat(abs(sin(stride))) * 1.1 : 0

        // Legs, the far one darker, behind the body.
        func leg(hipX: CGFloat, angle: Double, lift: CGFloat, far: Bool) {
            let hip = CGPoint(x: hipX, y: -9 + bob)
            let foot = CGPoint(x: hipX + CGFloat(sin(angle)) * 6.5, y: min(-0.2 - lift, CGFloat(cos(angle)) * 9 - 9 + bob))
            var bone = Path()
            bone.move(to: hip)
            bone.addLine(to: foot)
            let colour = far ? skin.bottom.opacity(0.9) : skin.bottom
            ctx.stroke(bone, with: .color(colour), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
            var toes = Path()
            toes.move(to: foot)
            toes.addLine(to: CGPoint(x: foot.x + 3.2, y: foot.y))
            ctx.stroke(toes, with: .color(colour), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            if far {
                ctx.stroke(bone, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: 4.2, lineCap: .round))
            }
        }

        switch pose {
        case .running:
            let a = sin(stride)
            leg(hipX: -5, angle: a * 0.75, lift: CGFloat(max(0, cos(stride))) * 2.4, far: true)
            leg(hipX: 1, angle: -a * 0.75, lift: CGFloat(max(0, -cos(stride))) * 2.4, far: false)
        case .jumping:
            leg(hipX: -5, angle: 0.55, lift: 3, far: true)
            leg(hipX: 1, angle: -0.35, lift: 4, far: false)
        case .crashed:
            leg(hipX: -5, angle: 0.7, lift: 1, far: true)
            leg(hipX: 1, angle: -0.6, lift: 2, far: false)
        default:
            leg(hipX: -5, angle: 0.05, lift: 0, far: true)
            leg(hipX: 1, angle: -0.05, lift: 0, far: false)
        }

        // Tail.
        var tail = Path()
        tail.move(to: CGPoint(x: -6, y: -20 + bob))
        tail.addQuadCurve(to: CGPoint(x: -22, y: -23 + sway + bob), control: CGPoint(x: -15, y: -21 + bob))
        tail.addQuadCurve(to: CGPoint(x: -7, y: -10 + bob), control: CGPoint(x: -15, y: -15 + sway * 0.5 + bob))
        tail.closeSubpath()
        ctx.fill(tail, with: shading)

        // Spikes along the back.
        for (x, y, lean) in [(-1.5, -25.5, 0.2), (-6, -24.8, 0.35), (-10.5, -23.2, 0.5), (-15, -21.4, 0.65)] as [(CGFloat, CGFloat, CGFloat)] {
            var spike = Path()
            spike.move(to: CGPoint(x: x - 1.9, y: y + 1.6 + bob))
            spike.addLine(to: CGPoint(x: x - lean * 2.2, y: y - 2.6 + bob))
            spike.addLine(to: CGPoint(x: x + 1.9, y: y + 1.6 + bob))
            spike.closeSubpath()
            ctx.fill(spike, with: .color(skin.spikes))
        }

        // Body, neck and head.
        var shape = Path()
        shape.addEllipse(in: CGRect(x: -12, y: -25 + bob, width: 21, height: 18))
        shape.addRoundedRect(in: CGRect(x: 0, y: -26 + bob, width: 8, height: 9), cornerSize: CGSize(width: 3, height: 3))
        shape.addRoundedRect(in: CGRect(x: 0, y: -34 + bob, width: 18, height: 12.5), cornerSize: CGSize(width: 5.5, height: 5.5))
        ctx.fill(shape, with: shading)

        // Belly and a soft highlight on the crown.
        ctx.fill(Path(ellipseIn: CGRect(x: -5, y: -18.5 + bob, width: 12, height: 10)), with: .color(skin.belly.opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: 3, y: -33 + bob, width: 9, height: 3.4)), with: .color(.white.opacity(0.25)))

        // Arm.
        var arm = Path()
        arm.move(to: CGPoint(x: 6.5, y: -16 + bob))
        arm.addLine(to: CGPoint(x: 9.5, y: pose == .jumping ? -17.5 + bob : -12.5 + bob))
        ctx.stroke(arm, with: .color(skin.bottom), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // Cheek, nostril, mouth.
        ctx.fill(Path(ellipseIn: CGRect(x: 11, y: -26.6 + bob, width: 3.4, height: 2.2)),
                 with: .color(Color(red: 1, green: 0.5, blue: 0.58).opacity(0.45)))
        ctx.fill(Path(ellipseIn: CGRect(x: 15.4, y: -31 + bob, width: 1.3, height: 1)), with: .color(.black.opacity(0.45)))
        if pose == .crashed {
            ctx.fill(Path(ellipseIn: CGRect(x: 13, y: -25.4 + bob, width: 4, height: 3)), with: .color(Color(red: 0.35, green: 0.08, blue: 0.1)))
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 10.5, y: -24.6 + bob))
            mouth.addQuadCurve(to: CGPoint(x: 17, y: -25.6 + bob), control: CGPoint(x: 14, y: -23.6 + bob))
            ctx.stroke(mouth, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
        }

        drawEye(&ctx, at: CGPoint(x: 9.8, y: -29.6 + bob), crashed: pose == .crashed)

        if game.wingsLeft > 0 { drawLittleWings(&ctx, at: CGPoint(x: -6, y: -23 + bob)) }
    }

    private func drawDucking(_ ctx: inout GraphicsContext, skin: DinoGame.Skin, shading: GraphicsContext.Shading) {
        let stride = game.stride * 1.3
        let a = sin(stride)
        for (hipX, angle, far) in [(-6.0, a * 0.8, true), (2.0, -a * 0.8, false)] as [(CGFloat, Double, Bool)] {
            var bone = Path()
            bone.move(to: CGPoint(x: hipX, y: -5))
            bone.addLine(to: CGPoint(x: hipX + CGFloat(sin(angle)) * 4.5, y: -0.4))
            ctx.stroke(bone, with: .color(far ? skin.bottom.opacity(0.85) : skin.bottom),
                       style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        }

        var tail = Path()
        tail.move(to: CGPoint(x: -12, y: -12))
        tail.addQuadCurve(to: CGPoint(x: -25, y: -12.5 + CGFloat(sin(stride * 2))), control: CGPoint(x: -19, y: -13))
        tail.addQuadCurve(to: CGPoint(x: -12, y: -5), control: CGPoint(x: -18, y: -8))
        tail.closeSubpath()
        ctx.fill(tail, with: shading)

        for (x, y) in [(-8.0, -16.5), (-3.0, -17.2), (2.0, -17.2), (7.0, -16.6)] as [(CGFloat, CGFloat)] {
            var spike = Path()
            spike.move(to: CGPoint(x: x - 1.8, y: y + 1.5))
            spike.addLine(to: CGPoint(x: x - 1.2, y: y - 2.2))
            spike.addLine(to: CGPoint(x: x + 1.8, y: y + 1.5))
            spike.closeSubpath()
            ctx.fill(spike, with: .color(skin.spikes))
        }

        var shape = Path()
        shape.addEllipse(in: CGRect(x: -14, y: -17, width: 30, height: 13))
        shape.addRoundedRect(in: CGRect(x: 11, y: -17.5, width: 17, height: 11), cornerSize: CGSize(width: 5, height: 5))
        ctx.fill(shape, with: shading)
        ctx.fill(Path(ellipseIn: CGRect(x: -4, y: -11, width: 14, height: 6)), with: .color(skin.belly.opacity(0.8)))
        ctx.fill(Path(ellipseIn: CGRect(x: 22, y: -10.8, width: 3.2, height: 2)),
                 with: .color(Color(red: 1, green: 0.5, blue: 0.58).opacity(0.45)))
        drawEye(&ctx, at: CGPoint(x: 20.5, y: -13.6), crashed: false)
    }

    private func drawEye(_ ctx: inout GraphicsContext, at centre: CGPoint, crashed: Bool) {
        if crashed {
            var cross = Path()
            cross.move(to: CGPoint(x: centre.x - 1.8, y: centre.y - 1.8))
            cross.addLine(to: CGPoint(x: centre.x + 1.8, y: centre.y + 1.8))
            cross.move(to: CGPoint(x: centre.x + 1.8, y: centre.y - 1.8))
            cross.addLine(to: CGPoint(x: centre.x - 1.8, y: centre.y + 1.8))
            ctx.stroke(cross, with: .color(.black.opacity(0.8)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            return
        }
        // A blink every few seconds.
        let blinking = game.clock.truncatingRemainder(dividingBy: 3.4) > 3.27
        if blinking {
            var lid = Path()
            lid.move(to: CGPoint(x: centre.x - 2.2, y: centre.y + 0.2))
            lid.addQuadCurve(to: CGPoint(x: centre.x + 2.2, y: centre.y + 0.2), control: CGPoint(x: centre.x, y: centre.y + 1.4))
            ctx.stroke(lid, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
            return
        }
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 2.7, y: centre.y - 2.7, width: 5.4, height: 5.4)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x - 0.6, y: centre.y - 1.4, width: 2.8, height: 2.9)), with: .color(Color(white: 0.08)))
        ctx.fill(Path(ellipseIn: CGRect(x: centre.x + 0.2, y: centre.y - 1.2, width: 1, height: 1)), with: .color(.white))
    }

    private func drawLittleWings(_ ctx: inout GraphicsContext, at base: CGPoint) {
        let flap = game.isOnGround ? 0.2 : sin(game.clock * 22)
        let tint = DinoGame.PowerKind.wings.tint
        for (offset, alpha) in [(CGFloat(-2), 0.55), (CGFloat(0), 0.95)] {
            var wing = Path()
            wing.move(to: CGPoint(x: base.x + offset, y: base.y))
            wing.addQuadCurve(to: CGPoint(x: base.x - 9 + offset, y: base.y - 7 - CGFloat(flap) * 3),
                              control: CGPoint(x: base.x - 2 + offset, y: base.y - 8))
            wing.addQuadCurve(to: CGPoint(x: base.x + 2 + offset, y: base.y + 2),
                              control: CGPoint(x: base.x - 6 + offset, y: base.y - 1))
            wing.closeSubpath()
            ctx.fill(wing, with: .color(tint.opacity(alpha)))
        }
    }

    private func drawShield(_ context: inout GraphicsContext, around feet: CGPoint) {
        let tint = DinoGame.PowerKind.shield.tint
        let centre = CGPoint(x: feet.x + 2, y: feet.y - 16)
        let r: CGFloat = 22 + CGFloat(sin(game.clock * 5)) * 0.8
        let bubble = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        context.fill(bubble, with: .radialGradient(
            Gradient(colors: [tint.opacity(0.02), tint.opacity(0.16), tint.opacity(0.32)]),
            center: centre, startRadius: 0, endRadius: r
        ))
        context.stroke(bubble, with: .color(tint.opacity(0.75)), lineWidth: 1.1)
        var shine = Path()
        let start = game.clock * 1.6
        shine.addArc(center: centre, radius: r - 3, startAngle: .radians(start), endAngle: .radians(start + 0.9), clockwise: false)
        context.stroke(shine, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }

    // MARK: Pickups

    private func drawGem(_ context: inout GraphicsContext, _ gem: DinoGame.Gem) {
        let centre = CGPoint(x: gem.x, y: groundY - gem.altitude + CGFloat(sin(game.clock * 3 + Double(gem.seed % 10))) * 1.2)
        let turn = abs(cos(game.clock * 2.6 + Double(gem.seed % 17)))
        let w: CGFloat = 4.8 * CGFloat(0.3 + 0.7 * turn)
        let h: CGFloat = 6.4
        context.blendMode = .plusLighter
        context.fill(Path(ellipseIn: CGRect(x: centre.x - 11, y: centre.y - 11, width: 22, height: 22)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.4, green: 0.9, blue: 1).opacity(0.4), .clear]),
                                           center: centre, startRadius: 0, endRadius: 11))
        context.blendMode = .normal
        var diamond = Path()
        diamond.move(to: CGPoint(x: centre.x, y: centre.y - h))
        diamond.addLine(to: CGPoint(x: centre.x + w, y: centre.y - 1))
        diamond.addLine(to: CGPoint(x: centre.x, y: centre.y + h))
        diamond.addLine(to: CGPoint(x: centre.x - w, y: centre.y - 1))
        diamond.closeSubpath()
        context.fill(diamond, with: .linearGradient(
            Gradient(colors: [Color(red: 0.7, green: 1, blue: 1), Color(red: 0.22, green: 0.55, blue: 1)]),
            startPoint: CGPoint(x: centre.x - w, y: centre.y - h), endPoint: CGPoint(x: centre.x + w, y: centre.y + h)
        ))
        var facet = Path()
        facet.move(to: CGPoint(x: centre.x, y: centre.y - h))
        facet.addLine(to: CGPoint(x: centre.x - w, y: centre.y - 1))
        facet.addLine(to: CGPoint(x: centre.x, y: centre.y + 1))
        facet.closeSubpath()
        context.fill(facet, with: .color(.white.opacity(0.35)))
        context.stroke(diamond, with: .color(.white.opacity(0.6)), lineWidth: 0.5)
    }

    private func drawOrb(_ context: inout GraphicsContext, _ orb: DinoGame.Orb) {
        let centre = CGPoint(x: orb.x, y: groundY - orb.altitude + CGFloat(sin(orb.age * 3)) * 2.5)
        let tint = orb.kind.tint
        let pulse = 1 + 0.12 * sin(orb.age * 6)
        let halo = 17 * pulse
        context.blendMode = .plusLighter
        context.fill(Path(ellipseIn: CGRect(x: centre.x - halo, y: centre.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.5), tint.opacity(0)]),
                                           center: centre, startRadius: 0, endRadius: halo))
        context.blendMode = .normal
        let r: CGFloat = 8
        let disc = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [.white.opacity(0.95), tint, tint.opacity(0.85)]),
            center: CGPoint(x: centre.x - 2.5, y: centre.y - 3), startRadius: 0, endRadius: r * 1.3
        ))
        context.stroke(disc, with: .color(.white.opacity(0.8)), lineWidth: 0.8)
        var symbol = context.resolve(Image(systemName: orb.kind.symbol))
        symbol.shading = .color(.white)
        context.draw(symbol, in: CGRect(x: centre.x - 4.5, y: centre.y - 4.5, width: 9, height: 9))
    }

    // MARK: Effects

    private func drawParticles(_ context: inout GraphicsContext, dust: RGB) {
        for particle in game.particles {
            let t = particle.life / particle.maxLife
            switch particle.kind {
            case .dust:
                let r = particle.size * CGFloat(1.6 - t * 0.6)
                context.fill(Path(ellipseIn: CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)),
                             with: .color(dust.mix(RGB(1, 1, 1), 0.3).color(0.55 * t)))
            case .chip:
                var chip = context
                chip.translateBy(x: particle.position.x, y: particle.position.y)
                chip.rotate(by: .radians(particle.angle))
                chip.fill(Path(roundedRect: CGRect(x: -particle.size / 2, y: -particle.size / 3,
                                                   width: particle.size, height: particle.size * 0.66), cornerRadius: 0.8),
                          with: .color(particle.color.opacity(min(t * 2, 1))))
            case .confetti:
                var paper = context
                paper.translateBy(x: particle.position.x, y: particle.position.y)
                paper.rotate(by: .radians(particle.angle))
                paper.scaleBy(x: CGFloat(cos(particle.angle * 1.7)), y: 1)
                paper.fill(Path(CGRect(x: -particle.size / 2, y: -particle.size / 4, width: particle.size, height: particle.size / 2)),
                           with: .color(particle.color.opacity(min(t * 2, 1))))
            case .spark:
                break
            }
        }
    }

    private func drawGlows(_ context: inout GraphicsContext) {
        context.blendMode = .plusLighter
        for particle in game.particles where particle.kind == .spark {
            let t = particle.life / particle.maxLife
            let r = particle.size * CGFloat(0.5 + t * 0.8)
            context.fill(Path(ellipseIn: CGRect(x: particle.position.x - r * 2, y: particle.position.y - r * 2, width: r * 4, height: r * 4)),
                         with: .radialGradient(Gradient(colors: [particle.color.opacity(0.6 * t), particle.color.opacity(0)]),
                                               center: particle.position, startRadius: 0, endRadius: r * 2))
        }
        // The gold colour, and turbo, give the dinosaur a glow of its own.
        if game.turboLeft > 0 || game.skin.glows {
            let centre = CGPoint(x: DinoGame.dinoX + 2, y: groundY - game.height - 16)
            let tint = game.turboLeft > 0 ? DinoGame.PowerKind.turbo.tint : Color(red: 1, green: 0.85, blue: 0.4)
            let strength = game.turboLeft > 0 ? 0.45 : 0.18
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 34, y: centre.y - 34, width: 68, height: 68)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(strength), .clear]),
                                               center: centre, startRadius: 0, endRadius: 34))
        }
        if game.magnetLeft > 0 {
            let centre = CGPoint(x: DinoGame.dinoX + 2, y: groundY - game.height - 16)
            let phase = game.clock.truncatingRemainder(dividingBy: 0.9) / 0.9
            let r = CGFloat(14 + phase * 26)
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                           with: .color(DinoGame.PowerKind.magnet.tint.opacity(0.5 * (1 - phase))), lineWidth: 1.2)
        }
        context.blendMode = .normal
    }

    private func drawPopups(_ context: inout GraphicsContext) {
        for popup in game.popups {
            let age = popup.maxLife - popup.life
            let t = popup.life / popup.maxLife
            let scale = age < 0.12 ? 0.6 + age / 0.12 * 0.5 : 1.1 - min((age - 0.12) * 0.6, 0.1)
            var text = context
            text.translateBy(x: popup.position.x, y: popup.position.y)
            text.scaleBy(x: scale, y: scale)
            text.opacity = min(t * 2.2, 1)
            let label = Text(popup.text)
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundColor(popup.color)
            text.draw(Text(popup.text)
                .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                .foregroundColor(.black.opacity(0.35)), at: CGPoint(x: 0.6, y: 0.8))
            text.draw(label, at: .zero)
        }
    }

    private func drawBanner(_ context: inout GraphicsContext) {
        guard let banner = game.banner else { return }
        let text = context.resolve(Text(banner)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundColor(.white))
        let measured = text.measure(in: CGSize(width: 400, height: 40))
        let centre = CGPoint(x: width / 2, y: 30)
        let plate = CGRect(x: centre.x - measured.width / 2 - 14, y: centre.y - 11, width: measured.width + 28, height: 22)
        context.fill(Path(roundedRect: plate, cornerRadius: 11), with: .color(.black.opacity(0.38)))
        context.stroke(Path(roundedRect: plate, cornerRadius: 11), with: .color(.white.opacity(0.25)), lineWidth: 0.8)
        context.draw(text, at: centre)
    }
}
