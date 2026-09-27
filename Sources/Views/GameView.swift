//
//  GameView.swift
//  FunNotch
//
//  Notch Breakout, drawn. The rules live in BreakoutGame; this is the board,
//  the header above it, and the arcade look: everything on a two-point pixel
//  grid, scanlines over the top, and one monospaced font.
//

import AppKit
import SwiftUI

struct GameView: View {
    @EnvironmentObject private var settings: Settings

    private let game = BreakoutGame.shared

    var body: some View {
        // Driven by the display link rather than a Timer: it runs at the screen
        // refresh rate and stops on its own when the notch closes.
        TimelineView(.animation) { timeline in
            VStack(spacing: 5) {
                header
                board(now: timeline.date)
            }
        }
        .padding(.top, 4)
        .onAppear {
            game.resumeAfterOpen()
            GameSound.shared.start()
            MouseTracker.shared.addMoveObserver("breakout") { point in
                BreakoutGame.shared.pointerMoved(to: point)
            }
            DiagnosticLog.write("game", "board shown, paused=\(game.isPaused) level=\(game.level)")
        }
        .onDisappear {
            MouseTracker.shared.removeMoveObserver("breakout")
            game.pauseForClose()
            GameSound.shared.stop()
            DiagnosticLog.write("game", "board hidden at score \(game.score)")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            // Monospaced and upper case throughout: the arcade cabinets this
            // is imitating had one font, and a proportional rounded face beside
            // a pixel board looks like two different apps.
            Text("NOTCH BREAKOUT")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.9))

            Text("L\(game.level)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
                .help(game.boardName)

            // Square pips rather than hearts, for the same reason.
            HStack(spacing: 3) {
                ForEach(0 ..< max(game.lives, 0), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.pink.opacity(0.85))
                        .frame(width: 5, height: 5)
                }
            }

            effects

            if game.multiplier > 1, game.phase == .running {
                Text("×\(game.multiplier)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(BreakoutGame.comboColour(game.multiplier))
                    .scaleEffect(1 + 0.08 * sin(game.clock * 10))
            }

            Spacer(minLength: 0)

            Text(String(format: "%06d", game.score))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text("HI \(String(format: "%06d", game.highScore))")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(game.beatHighScore ? BreakoutGame.comboColour(2) : settings.accentColor)

            Button {
                settings.gameSoundEnabled.toggle()
                if settings.gameSoundEnabled { GameSound.shared.start() } else { GameSound.shared.stop() }
            } label: {
                Image(systemName: settings.gameSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(settings.gameSoundEnabled ? 0.7 : 0.4))
                    .frame(width: 16, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(settings.gameSoundEnabled ? "Mute" : "Sound on")
        }
        .padding(.horizontal, 2)
    }

    /// A small square for each power-up running, draining as it runs out.
    private var effects: some View {
        let running: [(BreakoutGame.PowerupKind, Double)] = [
            (.wide, game.wideTimeLeft / 12),
            (.shrink, game.shrinkTimeLeft / 9),
            (.slow, game.slowTimeLeft / 9),
            (.fireball, game.fireTimeLeft / 6),
            (.laser, game.laserTimeLeft / 8),
            (.shield, game.shieldTimeLeft / 25),
        ].filter { $0.1 > 0 }

        return HStack(spacing: 4) {
            ForEach(Array(running.enumerated()), id: \.offset) { _, effect in
                let (kind, left) = effect
                VStack(spacing: 1) {
                    PixelIcon(rows: GameView.icon(for: kind), colour: kind.tint)
                        .frame(width: 7, height: 5)
                    Rectangle()
                        .fill(kind.tint)
                        .frame(width: max(8 * left, 1), height: 1)
                        .frame(width: 8, alignment: .leading)
                }
            }
        }
    }

    // MARK: Board

    private func board(now: Date) -> some View {
        Canvas { context, size in
            game.advance(to: now, size: size)
            draw(in: &context, size: size)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
        .background(
            // The paddle tracks the pointer in screen coordinates, so the board
            // has to say where on screen it actually is.
            ScreenFrameReader { frame in
                BreakoutGame.shared.boardScreenFrame = frame
            }
        )
        .overlay {
            if let title = game.overlayTitle {
                overlay(title: title)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { game.primaryAction() }
    }

    private func overlay(title: String) -> some View {
        let celebrating = game.phase == .over && game.beatHighScore && !game.isPaused
        return VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(celebrating ? BreakoutGame.comboColour(2 + Int(game.clock * 6) % 4) : .white)
            Text(game.overlaySubtitle)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
            if game.phase == .over, !game.isPaused {
                Text("BEST LEVEL \(game.bestLevel) · HI \(game.highScore)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.78))
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 2))
        )
        .allowsHitTesting(false)
    }

    /// One "pixel" of the game's grid. Everything is snapped to it, so nothing
    /// ever lands on a half pixel and the whole board reads as one resolution
    /// rather than smooth shapes drawn small.
    private static let px: CGFloat = 2

    private func snap(_ rect: CGRect) -> CGRect {
        let p = Self.px
        let x = (rect.minX / p).rounded(.down) * p
        let y = (rect.minY / p).rounded(.down) * p
        return CGRect(
            x: x, y: y,
            width: max((rect.width / p).rounded() * p, p),
            height: max((rect.height / p).rounded() * p, p)
        )
    }

    private func fill(_ context: inout GraphicsContext, _ rect: CGRect, _ colour: Color, _ opacity: Double = 1) {
        context.fill(Path(snap(rect)), with: .color(colour.opacity(opacity)))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let p = Self.px

        // Shake the board, not the header: whole pixels only.
        if game.shake > 0.1 {
            let dx = (sin(game.clock * 97) * game.shake / p).rounded() * p
            let dy = (cos(game.clock * 83) * game.shake / p).rounded() * p
            context.translateBy(x: dx, y: dy)
        }

        drawStars(&context, size: size)
        if game.shieldTimeLeft > 0 { drawShield(&context, size: size) }
        for brick in game.bricks { drawBrick(&context, brick) }
        if game.phase == .serving || game.phase == .intro { drawAim(&context) }
        drawLasers(&context)

        for particle in game.particles {
            let s = max(particle.size, p)
            fill(&context,
                 CGRect(x: particle.position.x - s / 2, y: particle.position.y - s / 2, width: s, height: s),
                 particle.color, min(particle.life / particle.maxLife * 1.6, 1))
        }

        for powerup in game.powerups { drawPowerup(&context, powerup) }
        drawPaddle(&context)
        for ball in game.balls { drawBall(&context, ball) }

        for popup in game.popups {
            context.draw(
                Text(popup.text)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(popup.color.opacity(min(popup.life / popup.maxLife * 1.8, 1))),
                at: CGPoint(x: (popup.position.x / p).rounded() * p, y: (popup.position.y / p).rounded() * p)
            )
        }

        // Scanlines over the whole board. One dark row every other pixel, dim
        // enough to be felt rather than seen.
        var line: CGFloat = 0
        while line < size.height {
            context.fill(
                Path(CGRect(x: 0, y: line, width: size.width, height: 1)),
                with: .color(.black.opacity(0.09))
            )
            line += p * 2
        }

        if let banner = game.banner {
            let centre = CGPoint(x: size.width / 2, y: size.height * 0.62)
            let width = max(116, CGFloat(banner.count) * 6.4 + 28)
            let plate = CGRect(x: centre.x - width / 2, y: centre.y - 9, width: width, height: 18)
            fill(&context, plate, .black, 0.75)
            fill(&context, CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: p), .white, 0.22)
            fill(&context, CGRect(x: plate.minX, y: plate.maxY - p, width: plate.width, height: p), .white, 0.22)
            let tint: Color = banner.hasPrefix("COMBO") ? BreakoutGame.comboColour(game.multiplier)
                : banner.hasPrefix("NEW HIGH") ? BreakoutGame.comboColour(2 + Int(game.clock * 6) % 4)
                : .white.opacity(0.92)
            context.draw(
                Text(banner)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(tint),
                at: centre
            )
        }
    }

    // MARK: Pieces

    /// A slow fall of dim stars behind the bricks.
    private func drawStars(_ context: inout GraphicsContext, size: CGSize) {
        for index in 0 ..< 34 {
            let seed = Double(index)
            let x = (seed * 97.31).truncatingRemainder(dividingBy: 1) * size.width
            let speed = 3 + (seed * 13.7).truncatingRemainder(dividingBy: 1) * 6
            let y = ((seed * 57.1).truncatingRemainder(dividingBy: 1) * size.height + game.clock * speed)
                .truncatingRemainder(dividingBy: size.height)
            let twinkle = (sin(game.clock * (1 + (seed * 3.3).truncatingRemainder(dividingBy: 2)) + seed) + 1) / 2
            fill(&context, CGRect(x: x, y: y, width: Self.px, height: Self.px), .white, 0.06 + 0.16 * twinkle)
        }
    }

    private func drawBrick(_ context: inout GraphicsContext, _ brick: BreakoutGame.Brick) {
        let p = Self.px
        // Dropping in: hidden until its turn, then a short fall into place.
        guard brick.landing < BreakoutGame.dropDuration else { return }
        let fall = brick.landing / BreakoutGame.dropDuration
        var frame = brick.frame
        frame.origin.y -= BreakoutGame.dropHeight * CGFloat(fall * fall)
        let box = snap(frame)
        let settle = 1 - fall * 0.6
        let colour = game.colour(of: brick)

        switch brick.kind {
        case .steel:
            fill(&context, box, Color(white: 0.42), settle)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), Color(white: 0.85), 0.8 * settle)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), .black, 0.4 * settle)
            // Rivets.
            fill(&context, CGRect(x: box.minX + p * 2, y: box.midY - p / 2, width: p, height: p), Color(white: 0.8), settle)
            fill(&context, CGRect(x: box.maxX - p * 3, y: box.midY - p / 2, width: p, height: p), Color(white: 0.8), settle)
            // Now and then a glint slides along the metal.
            let glint = (game.clock * 0.35 + Double(brick.column) * 0.04).truncatingRemainder(dividingBy: 1.8)
            if glint < 1 {
                let x = box.minX + CGFloat(glint) * box.width
                fill(&context, CGRect(x: x, y: box.minY + p, width: p, height: box.height - p * 2), .white, 0.35 * settle)
            }

        case .explosive:
            let pulse = 0.78 + 0.22 * sin(game.clock * 7 + Double(brick.column))
            fill(&context, box, colour, pulse * settle)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), .white, 0.3 * settle)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), .black, 0.35 * settle)
            // A bomb in the middle with its fuse fizzing: stripes read as
            // decoration, a bomb reads as a bomb.
            let body = CGRect(x: box.midX - p * 2, y: box.midY - p, width: p * 4, height: p * 2)
            fill(&context, body, .black, 0.92 * settle)
            fill(&context, CGRect(x: body.minX + p, y: body.minY, width: p, height: p), .white, 0.35 * settle)
            let spark = Int(game.clock * 12 + Double(brick.column)) % 2 == 0
                ? Color(red: 1, green: 0.95, blue: 0.5) : Color(red: 1, green: 0.55, blue: 0.1)
            fill(&context, CGRect(x: body.maxX, y: body.minY - p, width: p, height: p), spark, settle)

        case .gold:
            fill(&context, box, colour, settle)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), Color(red: 1, green: 0.97, blue: 0.75), settle)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), Color(red: 0.6, green: 0.4, blue: 0), 0.8 * settle)
            // A shine that sweeps across, each brick a beat after the last.
            let sweep = (game.clock * 0.6 + Double(brick.column) * 0.07).truncatingRemainder(dividingBy: 1.4)
            if sweep < 1 {
                let x = box.minX + CGFloat(sweep) * (box.width + box.height) - box.height
                for step in 0 ..< Int(box.height / p) {
                    let sx = x + CGFloat(step) * p
                    guard sx >= box.minX, sx < box.maxX - p else { continue }
                    fill(&context, CGRect(x: sx, y: box.maxY - CGFloat(step + 1) * p, width: p * 2, height: p), .white, 0.55 * settle)
                }
            }

        case .mystery:
            let hue = 0.75 + 0.06 * sin(game.clock * 3 + Double(brick.column))
            fill(&context, box, Color(hue: hue, saturation: 0.62, brightness: 0.95), settle)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), .white, 0.35 * settle)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), .black, 0.3 * settle)
            context.draw(
                Text("?")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity((0.75 + 0.25 * sin(game.clock * 5)) * settle)),
                at: CGPoint(x: box.midX, y: box.midY)
            )

        case .normal:
            let tough = brick.maxHitPoints > 1
            // Flat body, a lit top edge and a shaded bottom edge. That two-tone
            // bevel is what makes a rectangle read as a block rather than a
            // coloured smear.
            fill(&context, box, colour, (tough ? 1 : 0.85) * settle)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), .white, 0.30 * settle)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), .black, (tough ? 0.45 : 0.30) * settle)
            if tough {
                // Armour is studs, one per hit left: legible at this size, and
                // unmistakably pixel art.
                let studs = min(brick.hitPoints, 4)
                let spacing = p * 3
                let start = box.midX - CGFloat(studs - 1) * spacing / 2 - p / 2
                for stud in 0 ..< studs {
                    fill(&context, CGRect(x: start + CGFloat(stud) * spacing, y: box.midY - p / 2, width: p, height: p), .white, 0.75 * settle)
                }
            }
            if brick.hitPoints < brick.maxHitPoints {
                // Cracks spread as it takes damage.
                let damage = brick.maxHitPoints - brick.hitPoints
                for step in 0 ..< min(damage * 3, 7) {
                    let cx = box.minX + p * CGFloat(3 + step * 2)
                    let cy = box.minY + p * (step % 2 == 0 ? 1 : 2)
                    guard cx < box.maxX - p else { break }
                    fill(&context, CGRect(x: cx, y: cy, width: p, height: p), .black, 0.55 * settle)
                }
            }
        }

        if brick.flash > 0 {
            fill(&context, box, .white, brick.flash / 0.1 * 0.7)
        }
    }

    /// Where the serve will go: a line of dots marching away from the ball.
    private func drawAim(_ context: inout GraphicsContext) {
        guard let ball = game.balls.first, game.phase == .serving else { return }
        let direction = CGVector(dx: cos(game.serveAngle), dy: sin(game.serveAngle))
        let march = CGFloat((game.clock * 24).truncatingRemainder(dividingBy: 9))
        for dot in 0 ..< 6 {
            let distance = 10 + CGFloat(dot) * 9 + march
            let point = CGPoint(x: ball.position.x + direction.dx * distance, y: ball.position.y + direction.dy * distance)
            fill(&context, CGRect(x: point.x - 1, y: point.y - 1, width: Self.px, height: Self.px),
                 .white, 0.55 * (1 - Double(dot) / 6))
        }
    }

    private func drawLasers(_ context: inout GraphicsContext) {
        let tint = BreakoutGame.PowerupKind.laser.tint
        for laser in game.lasers {
            let x = laser.position.x
            fill(&context, CGRect(x: x - 2, y: laser.position.y - 5, width: 4, height: 10), tint, 0.3)
            fill(&context, CGRect(x: x - 1, y: laser.position.y - 4, width: Self.px, height: 8), .white, 0.95)
        }
    }

    private func drawShield(_ context: inout GraphicsContext, size: CGSize) {
        let tint = BreakoutGame.PowerupKind.shield.tint
        let running = game.shieldTimeLeft
        // Blinks in its last three seconds, as a warning.
        guard running > 3 || Int(game.clock * 8) % 2 == 0 else { return }
        let pulse = 0.55 + 0.25 * sin(game.clock * 6)
        fill(&context, CGRect(x: 0, y: game.shieldY - 1, width: size.width, height: Self.px), tint, pulse)
        var x: CGFloat = CGFloat((game.clock * 40).truncatingRemainder(dividingBy: 24))
        while x < size.width {
            fill(&context, CGRect(x: x, y: game.shieldY - 1, width: Self.px * 2, height: Self.px), .white, 0.7)
            x += 24
        }
    }

    private func drawPowerup(_ context: inout GraphicsContext, _ powerup: BreakoutGame.Powerup) {
        let p = Self.px
        let box = snap(CGRect(x: powerup.position.x - 9, y: powerup.position.y - 5, width: 18, height: 10))
        // The bad one flashes, so it can be told apart before it is caught.
        let border = powerup.kind.isBad && Int(powerup.age * 8) % 2 == 0 ? Color.white : powerup.kind.tint
        fill(&context, box, border, 1)
        fill(&context, box.insetBy(dx: p, dy: p), .black, 0.7)
        let icon = GameView.icon(for: powerup.kind)
        let origin = CGPoint(x: (box.midX - 3.5).rounded(), y: (box.midY - 2.5).rounded())
        for (row, line) in icon.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                context.fill(
                    Path(CGRect(x: origin.x + CGFloat(column), y: origin.y + CGFloat(row), width: 1, height: 1)),
                    with: .color(powerup.kind.tint)
                )
            }
        }
    }

    private func drawPaddle(_ context: inout GraphicsContext) {
        let p = Self.px
        // A hit squashes the paddle for a moment.
        let squash = CGFloat(game.paddleSquash)
        let width = game.paddleWidth * (1 + 0.08 * squash)
        let height = BreakoutGame.paddleHeight * (1 - 0.3 * squash)
        let bottom = game.paddleCenterY + BreakoutGame.paddleHeight / 2
        let rect = snap(CGRect(x: game.paddleCenterX - width / 2, y: bottom - height, width: width, height: height))
        let colour = game.shrinkTimeLeft > 0 ? BreakoutGame.PowerupKind.shrink.tint : settings.accentColor

        fill(&context, rect, colour, 1)
        fill(&context, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: p), .white, 0.45)
        fill(&context, CGRect(x: rect.maxX - p, y: rect.minY, width: p, height: rect.height), .black, 0.30)
        fill(&context, CGRect(x: rect.minX, y: rect.maxY - p, width: rect.width, height: p), .black, 0.30)

        if game.laserTimeLeft > 0 {
            let tint = BreakoutGame.PowerupKind.laser.tint
            fill(&context, CGRect(x: rect.minX + p, y: rect.minY - p * 2, width: p * 2, height: p * 2), tint, 1)
            fill(&context, CGRect(x: rect.maxX - p * 3, y: rect.minY - p * 2, width: p * 2, height: p * 2), tint, 1)
        }
        if game.wideTimeLeft > 0 {
            let tint = BreakoutGame.PowerupKind.wide.tint
            fill(&context, CGRect(x: rect.minX, y: rect.minY, width: p, height: rect.height), tint, 0.9)
            fill(&context, CGRect(x: rect.maxX - p, y: rect.minY, width: p, height: rect.height), tint, 0.9)
        }
    }

    private func drawBall(_ context: inout GraphicsContext, _ ball: BreakoutGame.Ball) {
        let r = BreakoutGame.ballRadius
        let burning = game.fireTimeLeft > 0
        let trailColour: Color = burning ? Color(red: 1, green: 0.5, blue: 0.15) : .white
        // A fading trail of where it has just been.
        if game.phase == .running {
            for (index, point) in ball.trail.enumerated() where index > 0 {
                let fade = 1 - Double(index) / Double(ball.trail.count + 1)
                let size = r * 2 * CGFloat(0.4 + 0.6 * fade)
                fill(&context, CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                     trailColour, 0.28 * fade)
            }
        }
        // A square ball. An anti-aliased circle four pixels across is a grey
        // blob; a square is unambiguous and is what the machines this is
        // imitating actually drew.
        let box = snap(CGRect(x: ball.position.x - r, y: ball.position.y - r, width: r * 2, height: r * 2))
        fill(&context, box, burning ? Color(red: 1, green: 0.62, blue: 0.2) : .white, 1)
        fill(&context, CGRect(x: box.minX, y: box.minY, width: Self.px, height: Self.px),
             burning ? Color(red: 1, green: 0.95, blue: 0.6) : .white, 1)
        fill(&context, CGRect(x: box.maxX - Self.px, y: box.maxY - Self.px, width: Self.px, height: Self.px), .black, 0.35)
    }

    // MARK: Icons

    /// Seven-by-five pixel icons for the power-ups, drawn at one point per
    /// pixel inside their capsules and in the header.
    static func icon(for kind: BreakoutGame.PowerupKind) -> [String] {
        switch kind {
        case .wide:
            return [".......", ".#...#.", "#######", ".#...#.", "......."]
        case .multiball:
            return [".......", ".##.##.", ".##.##.", ".......", "......."]
        case .slow:
            return [".#####.", "..###..", "...#...", "..###..", ".#####."]
        case .fireball:
            return ["...#...", "..##...", "..###..", ".#####.", "..###.."]
        case .laser:
            return [".#...#.", ".#...#.", ".#...#.", ".......", ".#...#."]
        case .shield:
            return [".......", "#.....#", "#######", ".......", "......."]
        case .shrink:
            return [".......", "#.....#", ".#####.", "#.....#", "......."]
        }
    }
}

/// A tiny sprite from rows of `#` and `.`, one point per pixel.
private struct PixelIcon: View {
    let rows: [String]
    let colour: Color

    var body: some View {
        Canvas { context, _ in
            for (row, line) in rows.enumerated() {
                for (column, character) in line.enumerated() where character == "#" {
                    context.fill(
                        Path(CGRect(x: CGFloat(column), y: CGFloat(row), width: 1, height: 1)),
                        with: .color(colour)
                    )
                }
            }
        }
    }
}

/// Reports its own rectangle in screen coordinates. SwiftUI's hover callbacks
/// cannot be used for this: the notch panel is never the active app, so the
/// pointer has to come from the global tracker and be mapped in by hand.
private struct ScreenFrameReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context: Context) -> NSView {
        ReportingView(onChange: onChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ReportingView)?.onChange = onChange
    }

    private final class ReportingView: NSView {
        var onChange: (CGRect) -> Void

        init(onChange: @escaping (CGRect) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        private func report() {
            guard let window else { return }
            let screenFrame = window.convertToScreen(convert(bounds, to: nil))
            // Reporting straight out of `layout` would mutate state while the
            // window is still laying out.
            DispatchQueue.main.async { [onChange] in onChange(screenFrame) }
        }
    }
}
