//
//  BreakoutBoard.swift
//  FunNotch
//
//  Notch Breakout, drawn. The rules live in BreakoutGame; this is the look:
//  glossy rounded bricks, a glowing ball with a comet tail, a lit capsule of a
//  paddle, and light that blooms where it overlaps — sparks, shockwaves and
//  lasers are drawn additively, so a busy moment glows rather than clutters.
//

import AppKit
import SwiftUI

struct BreakoutBoard: View {
    let now: Date

    @EnvironmentObject private var settings: Settings
    @MainActor private var game: BreakoutGame { BreakoutGame.shared }

    var body: some View {
        let accent = BreakoutShades(settings.accentColor)
        Canvas { context, size in
            game.advance(to: now, size: size)
            BreakoutPainter(game: game, size: size, accent: accent).draw(in: &context)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A colour with lighter and darker versions of itself, for gradients.
struct BreakoutShades {
    let base: Color
    let light: Color
    let dark: Color

    init(_ colour: Color) {
        let resolved = NSColor(colour).usingColorSpace(.sRGB) ?? .systemBlue
        base = colour
        light = Color(nsColor: resolved.blended(withFraction: 0.45, of: .white) ?? resolved)
        dark = Color(nsColor: resolved.blended(withFraction: 0.4, of: .black) ?? resolved)
    }

    init(hue: Double, saturation: Double = 0.7) {
        base = Color(hue: hue, saturation: saturation, brightness: 0.95)
        light = Color(hue: hue, saturation: saturation * 0.55, brightness: 1)
        dark = Color(hue: (hue + 0.02).truncatingRemainder(dividingBy: 1), saturation: min(saturation * 1.15, 1), brightness: 0.68)
    }
}

@MainActor
private struct BreakoutPainter {
    let game: BreakoutGame
    let size: CGSize
    let accent: BreakoutShades

    func draw(in context: inout GraphicsContext) {
        drawBackground(&context)

        var board = context
        if game.shake > 0.05 {
            board.translateBy(
                x: CGFloat(sin(game.clock * 97)) * game.shake,
                y: CGFloat(cos(game.clock * 83)) * game.shake * 0.7
            )
        }

        if game.shieldTimeLeft > 0 { drawShield(&board) }
        for brick in game.bricks { drawBrick(&board, brick) }
        drawAim(&board)
        drawParticles(&board)
        for powerup in game.powerups { drawPowerup(&board, powerup) }
        drawPaddle(&board)
        drawLasers(&board)
        for ball in game.balls { drawBall(&board, ball) }
        drawRings(&board)
        drawPopups(&board)

        if game.flash > 0.01 {
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 1, green: 0.85, blue: 0.7).opacity(0.22 * game.flash)))
        }
        drawBanner(&context)
    }

    // MARK: Background

    private func drawBackground(_ context: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: size)
        let hue = game.levelHue
        context.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.17),
                Color(hue: hue, saturation: 0.6, brightness: 0.07),
            ]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
        ))

        // Slow washes of colour drifting behind the bricks.
        for index in 0 ..< 3 {
            let t = game.clock * (0.07 + Double(index) * 0.03) + Double(index) * 2.1
            let centre = CGPoint(
                x: size.width * CGFloat(0.5 + 0.42 * sin(t)),
                y: size.height * CGFloat(0.35 + 0.3 * cos(t * 1.3))
            )
            let radius = size.width * CGFloat(0.28 + 0.06 * Double(index))
            let tint = Color(hue: (hue + Double(index) * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 1)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [tint.opacity(0.13), tint.opacity(0)]),
                                               center: centre, startRadius: 0, endRadius: radius))
        }

        // Faint stars, drifting down.
        for index in 0 ..< 30 {
            let seed = Double(index)
            let x = (seed * 97.31).truncatingRemainder(dividingBy: 1) * size.width
            let speed = 3 + (seed * 13.7).truncatingRemainder(dividingBy: 1) * 5
            let y = ((seed * 57.1).truncatingRemainder(dividingBy: 1) * size.height + game.clock * speed)
                .truncatingRemainder(dividingBy: size.height)
            let twinkle = (sin(game.clock * (1 + (seed * 3.3).truncatingRemainder(dividingBy: 2)) + seed) + 1) / 2
            let r: CGFloat = index % 7 == 0 ? 0.9 : 0.55
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.1 + 0.3 * twinkle)))
        }

        // A soft vignette pulls the eye into the middle.
        context.fill(Path(rect), with: .radialGradient(
            Gradient(colors: [.clear, .black.opacity(0.35)]),
            center: CGPoint(x: size.width / 2, y: size.height * 0.45),
            startRadius: size.height * 0.6, endRadius: size.width * 0.62
        ))
    }

    // MARK: Bricks

    private func drawBrick(_ context: inout GraphicsContext, _ brick: BreakoutGame.Brick) {
        guard brick.landing < BreakoutGame.dropDuration else { return }
        // Dropping in: falls, eases to a stop, and fades up as it lands.
        let fall = brick.landing / BreakoutGame.dropDuration
        var frame = brick.frame
        frame.origin.y -= BreakoutGame.dropHeight * CGFloat(fall * fall)
        let alpha = 1 - fall * 0.8
        let radius = min(frame.height * 0.34, 3.5)
        let shape = Path(roundedRect: frame, cornerRadius: radius, style: .continuous)

        // Drop shadow.
        context.fill(Path(roundedRect: frame.offsetBy(dx: 0, dy: 1.6), cornerRadius: radius, style: .continuous),
                     with: .color(.black.opacity(0.35 * alpha)))

        switch brick.kind {
        case .normal:
            let hue = 0.58 - Double(brick.row) * 0.085
            let shades = BreakoutShades(hue: (hue + 1).truncatingRemainder(dividingBy: 1), saturation: 0.72)
            fillBody(&context, shape, frame, shades, alpha: alpha)
            if brick.maxHitPoints > 1 { drawArmour(&context, brick, frame, alpha: alpha) }
        case .steel:
            fillBody(&context, shape, frame, BreakoutShades(Color(white: 0.72)), alpha: alpha)
            drawSheen(&context, shape, frame, speed: 0.35, offset: Double(brick.column) * 0.04, strength: 0.5 * alpha)
            for x in [frame.minX + 4, frame.maxX - 4] {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.2, y: frame.midY - 1.2, width: 2.4, height: 2.4)),
                             with: .color(Color(white: 0.95).opacity(alpha)))
                context.fill(Path(ellipseIn: CGRect(x: x - 0.5, y: frame.midY - 0.3, width: 1.4, height: 1.4)),
                             with: .color(Color(white: 0.45).opacity(alpha)))
            }
        case .explosive:
            let pulse = 0.5 + 0.5 * sin(game.clock * 7 + Double(brick.column))
            fillBody(&context, shape, frame,
                     BreakoutShades(Color(red: 1, green: 0.36, blue: 0.22)), alpha: alpha)
            context.fill(shape, with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.4).opacity(0.55 * pulse * alpha), .clear]),
                center: CGPoint(x: frame.midX, y: frame.midY), startRadius: 0, endRadius: frame.width * 0.55
            ))
            drawBomb(&context, in: frame, alpha: alpha, column: brick.column)
        case .gold:
            fillBody(&context, shape, frame,
                     BreakoutShades(Color(red: 1, green: 0.78, blue: 0.22)), alpha: alpha)
            drawSheen(&context, shape, frame, speed: 0.6, offset: Double(brick.column) * 0.07, strength: 0.75 * alpha)
            let twinkle = sin(game.clock * 4 + Double(brick.column) * 1.7)
            if twinkle > 0.6 {
                drawSparkle(&context, at: CGPoint(x: frame.minX + frame.width * 0.3, y: frame.minY + 2.5),
                            size: 3.5 * CGFloat(twinkle), alpha: alpha)
            }
        case .mystery:
            let hue = (0.78 + 0.08 * sin(game.clock * 2 + Double(brick.column))).truncatingRemainder(dividingBy: 1)
            fillBody(&context, shape, frame, BreakoutShades(hue: hue, saturation: 0.6), alpha: alpha)
            let bob = CGFloat(sin(game.clock * 5 + Double(brick.column))) * 0.6
            var mark = context.resolve(Text("?").font(.system(size: 9, weight: .black, design: .rounded)))
            mark.shading = .color(.white.opacity(alpha))
            context.draw(mark, at: CGPoint(x: frame.midX, y: frame.midY + bob))
        }

        if brick.hitPoints < brick.maxHitPoints, brick.kind == .normal {
            drawCracks(&context, brick, frame, alpha: alpha)
        }

        if brick.flash > 0 {
            context.fill(shape, with: .color(.white.opacity(brick.flash / 0.1 * 0.75)))
        }
    }

    /// The glossy body every brick shares: a gradient, a shine across the
    /// top half, and a thin bright rim.
    private func fillBody(_ context: inout GraphicsContext, _ shape: Path, _ frame: CGRect,
                          _ shades: BreakoutShades, alpha: Double) {
        context.fill(shape, with: .linearGradient(
            Gradient(colors: [shades.light.opacity(alpha), shades.base.opacity(alpha), shades.dark.opacity(alpha)]),
            startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)
        ))
        let gloss = CGRect(x: frame.minX + 1.2, y: frame.minY + 1, width: frame.width - 2.4, height: frame.height * 0.42)
        context.fill(Path(roundedRect: gloss, cornerRadius: 2.2, style: .continuous), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.5 * alpha), .white.opacity(0.06 * alpha)]),
            startPoint: CGPoint(x: gloss.midX, y: gloss.minY), endPoint: CGPoint(x: gloss.midX, y: gloss.maxY)
        ))
        context.stroke(shape, with: .color(.white.opacity(0.22 * alpha)), lineWidth: 0.6)
    }

    /// A band of light sliding across metal every so often.
    private func drawSheen(_ context: inout GraphicsContext, _ shape: Path, _ frame: CGRect,
                           speed: Double, offset: Double, strength: Double) {
        let sweep = (game.clock * speed + offset).truncatingRemainder(dividingBy: 1.6)
        guard sweep < 1 else { return }
        let x = frame.minX - frame.height + CGFloat(sweep) * (frame.width + frame.height * 2)
        var band = Path()
        band.move(to: CGPoint(x: x, y: frame.maxY))
        band.addLine(to: CGPoint(x: x + frame.height, y: frame.minY))
        band.addLine(to: CGPoint(x: x + frame.height + 5, y: frame.minY))
        band.addLine(to: CGPoint(x: x + 5, y: frame.maxY))
        band.closeSubpath()
        var clipped = context
        clipped.clip(to: shape)
        clipped.fill(band, with: .color(.white.opacity(strength)))
    }

    /// Hit points still to go, as small studs.
    private func drawArmour(_ context: inout GraphicsContext, _ brick: BreakoutGame.Brick, _ frame: CGRect, alpha: Double) {
        let studs = min(brick.hitPoints, 4)
        let spacing: CGFloat = 5
        let start = frame.midX - CGFloat(studs - 1) * spacing / 2
        for stud in 0 ..< studs {
            let centre = CGPoint(x: start + CGFloat(stud) * spacing, y: frame.midY + 0.5)
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 1.5, y: centre.y - 1.5, width: 3, height: 3)),
                         with: .color(.black.opacity(0.25 * alpha)))
            context.fill(Path(ellipseIn: CGRect(x: centre.x - 1.2, y: centre.y - 1.6, width: 2.4, height: 2.4)),
                         with: .color(.white.opacity(0.85 * alpha)))
        }
    }

    /// Cracks that spread as a tough brick takes damage.
    private func drawCracks(_ context: inout GraphicsContext, _ brick: BreakoutGame.Brick, _ frame: CGRect, alpha: Double) {
        let damage = brick.maxHitPoints - brick.hitPoints
        var cracks = Path()
        for crack in 0 ..< min(damage * 2, 5) {
            let seed = Double(brick.row * 31 + brick.column * 7 + crack * 13)
            let startX = frame.minX + frame.width * CGFloat(0.15 + (seed * 0.137).truncatingRemainder(dividingBy: 0.7))
            var point = CGPoint(x: startX, y: crack % 2 == 0 ? frame.minY + 0.5 : frame.maxY - 0.5)
            cracks.move(to: point)
            for step in 1 ... 3 {
                let wiggle = CGFloat(sin(seed + Double(step) * 2.3)) * 2.4
                point = CGPoint(x: point.x + wiggle, y: point.y + (crack % 2 == 0 ? 1 : -1) * frame.height * 0.22)
                cracks.addLine(to: point)
            }
        }
        context.stroke(cracks, with: .color(.black.opacity(0.45 * alpha)), lineWidth: 0.8)
        context.stroke(cracks.offsetBy(dx: 0.6, dy: 0.6), with: .color(.white.opacity(0.18 * alpha)), lineWidth: 0.5)
    }

    private func drawBomb(_ context: inout GraphicsContext, in frame: CGRect, alpha: Double, column: Int) {
        let centre = CGPoint(x: frame.midX - 1, y: frame.midY + 0.5)
        let r: CGFloat = min(frame.height * 0.32, 3.4)
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(white: 0.1).opacity(alpha)))
        context.fill(Path(ellipseIn: CGRect(x: centre.x - r * 0.55, y: centre.y - r * 0.6, width: r * 0.6, height: r * 0.5)),
                     with: .color(.white.opacity(0.4 * alpha)))
        var fuse = Path()
        let top = CGPoint(x: centre.x + r * 0.6, y: centre.y - r * 0.7)
        let end = CGPoint(x: top.x + 2.4, y: top.y - 2)
        fuse.move(to: top)
        fuse.addQuadCurve(to: end, control: CGPoint(x: top.x + 1.8, y: top.y))
        context.stroke(fuse, with: .color(Color(white: 0.85).opacity(alpha)), lineWidth: 0.8)
        let flicker = 0.6 + 0.4 * sin(game.clock * 31 + Double(column) * 3)
        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)),
                  with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5).opacity(flicker * alpha), .clear]),
                                        center: end, startRadius: 0, endRadius: 3))
    }

    private func drawSparkle(_ context: inout GraphicsContext, at centre: CGPoint, size: CGFloat, alpha: Double) {
        var star = Path()
        star.move(to: CGPoint(x: centre.x, y: centre.y - size))
        star.addQuadCurve(to: CGPoint(x: centre.x + size, y: centre.y), control: centre)
        star.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y + size), control: centre)
        star.addQuadCurve(to: CGPoint(x: centre.x - size, y: centre.y), control: centre)
        star.addQuadCurve(to: CGPoint(x: centre.x, y: centre.y - size), control: centre)
        context.fill(star, with: .color(.white.opacity(0.95 * alpha)))
    }

    // MARK: Paddle and balls

    private func drawPaddle(_ context: inout GraphicsContext) {
        let squash = CGFloat(game.paddleSquash)
        let width = game.paddleWidth * (1 + 0.08 * squash)
        let height = (BreakoutGame.paddleHeight + 1.5) * (1 - 0.3 * squash)
        let bottom = game.paddleCenterY + BreakoutGame.paddleHeight / 2 + 0.5
        let rect = CGRect(x: game.paddleCenterX - width / 2, y: bottom - height, width: width, height: height)
        let shades = game.shrinkTimeLeft > 0
            ? BreakoutShades(BreakoutGame.PowerupKind.shrink.tint)
            : (game.wideTimeLeft > 0 ? BreakoutShades(BreakoutGame.PowerupKind.wide.tint) : accent)

        // A pool of its own light underneath.
        var glow = context
        glow.blendMode = .plusLighter
        glow.translateBy(x: rect.midX, y: rect.midY + 1)
        glow.scaleBy(x: 1, y: 0.28)
        let reach = width * 0.75
        glow.fill(Path(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)),
                  with: .radialGradient(Gradient(colors: [shades.base.opacity(0.45 + 0.3 * Double(squash)), shades.base.opacity(0)]),
                                        center: .zero, startRadius: 0, endRadius: reach))

        let capsule = Path(roundedRect: rect, cornerRadius: height / 2, style: .continuous)
        context.fill(capsule, with: .linearGradient(
            Gradient(colors: [shades.light, shades.base, shades.dark]),
            startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        ))
        context.fill(Path(roundedRect: CGRect(x: rect.minX + height / 2, y: rect.minY + 0.8,
                                              width: rect.width - height, height: height * 0.32),
                          cornerRadius: height * 0.16),
                     with: .color(.white.opacity(0.55)))

        if game.laserTimeLeft > 0 {
            let tint = BreakoutGame.PowerupKind.laser.tint
            for x in [rect.minX + 5, rect.maxX - 5] {
                let nub = CGRect(x: x - 1.8, y: rect.minY - 3, width: 3.6, height: 4)
                context.fill(Path(roundedRect: nub, cornerRadius: 1.2), with: .color(tint))
                glow = context
                glow.blendMode = .plusLighter
                glow.fill(Path(ellipseIn: nub.insetBy(dx: -4, dy: -4)),
                          with: .radialGradient(Gradient(colors: [tint.opacity(0.6), .clear]),
                                                center: CGPoint(x: nub.midX, y: nub.minY), startRadius: 0, endRadius: 6))
            }
        }
    }

    private func drawBall(_ context: inout GraphicsContext, _ ball: BreakoutGame.Ball) {
        let r = BreakoutGame.ballRadius
        let burning = game.fireTimeLeft > 0
        let core: Color = burning ? Color(red: 1, green: 0.75, blue: 0.3) : .white
        let halo: Color = burning ? Color(red: 1, green: 0.45, blue: 0.12) : accent.light

        var light = context
        light.blendMode = .plusLighter

        // A comet tail: circles along where it has been, shrinking and fading.
        if game.phase == .running, ball.trail.count > 1 {
            let points = ball.trail
            for index in 1 ..< points.count {
                let a = points[index - 1]
                let b = points[index]
                for step in 0 ..< 3 {
                    let t = CGFloat(step) / 3
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    let fade = 1 - (Double(index - 1) + Double(t)) / Double(points.count)
                    let size = r * CGFloat(0.35 + 0.65 * fade) * (burning ? 1.4 : 1)
                    light.fill(Path(ellipseIn: CGRect(x: p.x - size, y: p.y - size, width: size * 2, height: size * 2)),
                               with: .color(halo.opacity(0.22 * fade)))
                }
            }
        }

        let glowRadius = r * (burning ? 5.5 : 4)
        light.fill(Path(ellipseIn: CGRect(x: ball.position.x - glowRadius, y: ball.position.y - glowRadius,
                                          width: glowRadius * 2, height: glowRadius * 2)),
                   with: .radialGradient(Gradient(colors: [halo.opacity(burning ? 0.7 : 0.45), halo.opacity(0)]),
                                         center: ball.position, startRadius: 0, endRadius: glowRadius))

        let body = CGRect(x: ball.position.x - r, y: ball.position.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: body), with: .radialGradient(
            Gradient(colors: [.white, core]),
            center: CGPoint(x: body.midX - r * 0.35, y: body.midY - r * 0.35), startRadius: 0, endRadius: r * 1.6
        ))
    }

    /// Where the serve will go, and a ring round the ball that fills as the
    /// automatic serve comes due.
    private func drawAim(_ context: inout GraphicsContext) {
        guard game.phase == .serving, let ball = game.balls.first else { return }
        let direction = CGVector(dx: cos(game.serveAngle), dy: sin(game.serveAngle))
        let march = CGFloat((game.clock * 30).truncatingRemainder(dividingBy: 10))
        for dot in 0 ..< 7 {
            let distance = 10 + CGFloat(dot) * 10 + march
            let point = CGPoint(x: ball.position.x + direction.dx * distance, y: ball.position.y + direction.dy * distance)
            let fade = 1 - Double(distance) / 90
            let r: CGFloat = 1.1
            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(0.6 * max(fade, 0))))
        }
        var ring = Path()
        ring.addArc(center: ball.position, radius: BreakoutGame.ballRadius + 3.5, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * game.serveProgress), clockwise: false)
        context.stroke(ring, with: .color(accent.light.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func drawLasers(_ context: inout GraphicsContext) {
        let tint = BreakoutGame.PowerupKind.laser.tint
        var light = context
        light.blendMode = .plusLighter
        for laser in game.lasers {
            let bolt = CGRect(x: laser.position.x - 1, y: laser.position.y - 6, width: 2, height: 12)
            light.fill(Path(roundedRect: bolt.insetBy(dx: -2.5, dy: -2), cornerRadius: 3), with: .color(tint.opacity(0.35)))
            light.fill(Path(roundedRect: bolt, cornerRadius: 1), with: .linearGradient(
                Gradient(colors: [.white, tint]), startPoint: CGPoint(x: bolt.midX, y: bolt.minY),
                endPoint: CGPoint(x: bolt.midX, y: bolt.maxY)
            ))
        }
    }

    private func drawShield(_ context: inout GraphicsContext) {
        let tint = BreakoutGame.PowerupKind.shield.tint
        // Blinks in its last three seconds, as a warning.
        guard game.shieldTimeLeft > 3 || Int(game.clock * 8) % 2 == 0 else { return }
        let y = game.shieldY
        var light = context
        light.blendMode = .plusLighter
        light.fill(Path(CGRect(x: 0, y: y - 3, width: size.width, height: 6)), with: .linearGradient(
            Gradient(colors: [tint.opacity(0), tint.opacity(0.35), tint.opacity(0)]),
            startPoint: CGPoint(x: 0, y: y - 3), endPoint: CGPoint(x: 0, y: y + 3)
        ))
        light.fill(Path(CGRect(x: 0, y: y - 0.6, width: size.width, height: 1.2)), with: .color(tint.opacity(0.9)))
        let shimmer = CGFloat((game.clock * 0.6).truncatingRemainder(dividingBy: 1)) * (size.width + 120) - 60
        light.fill(Path(ellipseIn: CGRect(x: shimmer - 40, y: y - 2, width: 80, height: 4)), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.8), .clear]), center: CGPoint(x: shimmer, y: y), startRadius: 0, endRadius: 40
        ))
    }

    private func drawPowerup(_ context: inout GraphicsContext, _ powerup: BreakoutGame.Powerup) {
        let kind = powerup.kind
        let centre = powerup.position
        let flashing = kind.isBad && Int(powerup.age * 8) % 2 == 0
        let tint = flashing ? Color(red: 1, green: 0.3, blue: 0.3) : kind.tint

        var glow = context
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: CGRect(x: centre.x - 20, y: centre.y - 14, width: 40, height: 28)),
                  with: .radialGradient(Gradient(colors: [tint.opacity(0.45), .clear]),
                                        center: centre, startRadius: 0, endRadius: 18))

        var pill = context
        pill.translateBy(x: centre.x, y: centre.y)
        pill.rotate(by: .radians(sin(powerup.age * 4) * 0.12))
        let rect = CGRect(x: -12, y: -6.5, width: 24, height: 13)
        let shape = Path(roundedRect: rect, cornerRadius: 6.5, style: .continuous)
        let shades = BreakoutShades(tint)
        pill.fill(shape, with: .linearGradient(
            Gradient(colors: [shades.light, shades.base, shades.dark]),
            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)
        ))
        pill.stroke(shape, with: .color(.white.opacity(0.7)), lineWidth: 0.7)
        var symbol = pill.resolve(Image(systemName: kind.symbol))
        symbol.shading = .color(.white)
        pill.draw(symbol, in: CGRect(x: -4.5, y: -4.5, width: 9, height: 9))
    }

    // MARK: Effects

    private func drawParticles(_ context: inout GraphicsContext) {
        var light = context
        light.blendMode = .plusLighter
        for particle in game.particles {
            let t = particle.life / particle.maxLife
            switch particle.kind {
            case .spark:
                let r = max(particle.size * CGFloat(0.4 + 0.6 * t), 0.5)
                light.fill(Path(ellipseIn: CGRect(x: particle.position.x - r * 2, y: particle.position.y - r * 2,
                                                  width: r * 4, height: r * 4)),
                           with: .radialGradient(Gradient(colors: [particle.color.opacity(0.95 * t), particle.color.opacity(0)]),
                                                 center: particle.position, startRadius: 0, endRadius: r * 2))
            case .shard:
                var chip = context
                chip.translateBy(x: particle.position.x, y: particle.position.y)
                chip.rotate(by: .radians(particle.angle))
                let s = particle.size
                chip.fill(Path(roundedRect: CGRect(x: -s / 2, y: -s / 3, width: s, height: s * 0.66), cornerRadius: 0.8),
                          with: .color(particle.color.opacity(min(t * 1.8, 1))))
            case .smoke:
                let r = particle.size * CGFloat(1.8 - t)
                context.fill(Path(ellipseIn: CGRect(x: particle.position.x - r, y: particle.position.y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [particle.color.opacity(0.35 * t), particle.color.opacity(0)]),
                                                   center: particle.position, startRadius: 0, endRadius: r))
            case .confetti:
                var paper = context
                paper.translateBy(x: particle.position.x, y: particle.position.y)
                paper.rotate(by: .radians(particle.angle))
                paper.scaleBy(x: CGFloat(cos(particle.angle * 1.7)), y: 1)
                paper.fill(Path(CGRect(x: -particle.size / 2, y: -particle.size / 4, width: particle.size, height: particle.size / 2)),
                           with: .color(particle.color.opacity(min(t * 2, 1))))
            }
        }
    }

    private func drawRings(_ context: inout GraphicsContext) {
        var light = context
        light.blendMode = .plusLighter
        for ring in game.rings {
            let p = ring.progress
            let eased = 1 - (1 - p) * (1 - p)
            let r = ring.maxRadius * CGFloat(eased)
            light.stroke(Path(ellipseIn: CGRect(x: ring.center.x - r, y: ring.center.y - r, width: r * 2, height: r * 2)),
                         with: .color(ring.color.opacity(0.8 * (1 - p))), lineWidth: CGFloat(3 * (1 - p) + 0.5))
        }
    }

    private func drawPopups(_ context: inout GraphicsContext) {
        for popup in game.popups {
            let age = popup.maxLife - popup.life
            let t = popup.life / popup.maxLife
            let scale = age < 0.1 ? 0.6 + age / 0.1 * 0.55 : 1.15 - min((age - 0.1) * 0.8, 0.15)
            var text = context
            text.translateBy(x: popup.position.x, y: popup.position.y)
            text.scaleBy(x: scale, y: scale)
            text.opacity = min(t * 2, 1)
            text.draw(Text(popup.text)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.black.opacity(0.5)), at: CGPoint(x: 0.6, y: 0.9))
            text.draw(Text(popup.text)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(popup.color), at: .zero)
        }
    }

    private func drawBanner(_ context: inout GraphicsContext) {
        guard let banner = game.banner else { return }
        let tint: Color
        switch game.bannerTone {
        case .combo: tint = BreakoutGame.comboColour(game.multiplier)
        case .record: tint = BreakoutGame.comboColour(2 + Int(game.clock * 6) % 4)
        case .plain: tint = .white
        }
        let entrance = min(game.bannerAge / 0.18, 1)
        let scale = 0.85 + 0.15 * (1 - pow(1 - entrance, 3))
        let text = context.resolve(Text(banner)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundColor(tint))
        let measured = text.measure(in: CGSize(width: 400, height: 40))
        var plate = context
        plate.translateBy(x: size.width / 2, y: size.height * 0.62)
        plate.scaleBy(x: scale, y: scale)
        plate.opacity = min(entrance * 1.5, 1) * min(game.bannerLife / 0.2, 1)
        let rect = CGRect(x: -measured.width / 2 - 14, y: -11, width: measured.width + 28, height: 22)
        plate.fill(Path(roundedRect: rect, cornerRadius: 11), with: .color(.black.opacity(0.55)))
        plate.stroke(Path(roundedRect: rect, cornerRadius: 11), with: .color(tint.opacity(0.35)), lineWidth: 0.8)
        plate.draw(text, at: .zero)
    }
}
