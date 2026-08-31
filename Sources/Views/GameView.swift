//
//  GameView.swift
//  FunNotch
//
//  Notch Breakout.
//
//  The control scheme is the whole design. The notch is a non-activating panel,
//  so it never becomes the key window and `keyDown` is delivered to whatever app
//  is actually frontmost — which is never this one. Every keyboard-driven game
//  in here was therefore unplayable in practice. Pointer movement, on the other
//  hand, is already tracked globally to drive hover, so a paddle that follows
//  the cursor is the one scheme that genuinely works.
//
//  A wide, short board is also breakout's natural shape, and the game survives
//  the notch closing: the model is a singleton, so a run continues where it left
//  off the next time the tab is opened.
//

import AppKit
import SwiftUI

@MainActor
final class BreakoutGame {
    static let shared = BreakoutGame()

    enum Phase: Equatable {
        /// Ball rides the paddle, waiting for a launch.
        case serving
        case running
        case over
    }

    struct Ball {
        var position: CGPoint
        var velocity: CGVector
    }

    struct Brick {
        var frame: CGRect
        var hitPoints: Int
        var row: Int
    }

    /// No extra lives. Three is what you get, and the only way to keep a run
    /// going is to not drop the ball.
    enum PowerupKind: CaseIterable {
        case wide, multiball, slow

        var symbol: String {
            switch self {
            case .wide: return "↔"
            case .multiball: return "×2"
            case .slow: return "◷"
            }
        }

        var tint: Color {
            switch self {
            case .wide: return .cyan
            case .multiball: return .yellow
            case .slow: return .mint
            }
        }
    }

    struct Powerup {
        var position: CGPoint
        var kind: PowerupKind
    }

    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var life: Double
        var color: Color
    }

    // MARK: - Board constants

    static let columns = 14
    private static let brickGap: CGFloat = 3
    private static let brickHeight: CGFloat = 10
    private static let brickTop: CGFloat = 4
    static let ballRadius: CGFloat = 3.5
    static let paddleHeight: CGFloat = 5

    // MARK: - State

    private(set) var phase: Phase = .serving
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var level = 1
    private(set) var highScore = Settings.shared.gameHighScore
    /// Set while the notch is closed, or by clicking the board.
    private(set) var isPaused = false

    private(set) var balls: [Ball] = []
    private(set) var bricks: [Brick] = []
    private(set) var powerups: [Powerup] = []
    private(set) var particles: [Particle] = []
    private(set) var paddleCenterX: CGFloat = 0
    private(set) var banner: String?

    private var bannerLife: Double = 0
    /// Seconds of widened paddle / slowed ball left on the clock.
    private var wideTimeLeft: Double = 0
    private var slowTimeLeft: Double = 0
    private var serveCountdown: Double = 1.6

    private(set) var boardSize: CGSize = .zero
    /// Where the board currently sits on screen, so the global pointer position
    /// can be mapped onto it.
    var boardScreenFrame: CGRect = .zero
    private var pointerX: CGFloat?
    private var lastUpdate: Date?

    private init() {}

    // MARK: - Derived geometry

    var paddleWidth: CGFloat {
        boardSize.width * (wideTimeLeft > 0 ? 0.24 : 0.13)
    }

    var paddleCenterY: CGFloat {
        boardSize.height - 7
    }

    /// Speed every ball is normalised to, so slow-motion and level ramps stay
    /// exact instead of drifting after each bounce.
    private var targetSpeed: CGFloat {
        let base = min(215 + 20 * CGFloat(level - 1), 400)
        return slowTimeLeft > 0 ? base * 0.66 : base
    }

    // MARK: - Input

    func pointerMoved(to screenPoint: CGPoint) {
        guard boardScreenFrame.width > 1 else { return }
        let fraction = (screenPoint.x - boardScreenFrame.minX) / boardScreenFrame.width
        pointerX = min(max(fraction, 0), 1) * boardSize.width
    }

    /// Click on the board: launch, resume, or start a fresh run.
    func primaryAction() {
        if isPaused {
            isPaused = false
            lastUpdate = nil
            return
        }
        switch phase {
        case .serving: launchBall()
        case .running: isPaused = true
        case .over: restart()
        }
    }

    func pauseForClose() {
        isPaused = true
        lastUpdate = nil
    }

    /// A run interrupted by the notch closing stays paused until it is clicked,
    /// rather than handing back a moving ball the moment the panel reappears.
    func resumeAfterOpen() {
        lastUpdate = nil
    }

    // MARK: - Lifecycle

    private func restart() {
        score = 0
        lives = 3
        level = 1
        wideTimeLeft = 0
        slowTimeLeft = 0
        powerups.removeAll()
        buildLevel()
    }

    private func buildLevel() {
        guard boardSize.width > 0 else { return }

        let rows = min(3 + level, 6)
        let width = boardSize.width
        let brickWidth = (width - Self.brickGap * CGFloat(Self.columns + 1)) / CGFloat(Self.columns)

        bricks = (0 ..< rows).flatMap { row in
            (0 ..< Self.columns).map { column in
                Brick(
                    frame: CGRect(
                        x: Self.brickGap + CGFloat(column) * (brickWidth + Self.brickGap),
                        y: Self.brickTop + CGFloat(row) * (Self.brickHeight + Self.brickGap),
                        width: brickWidth,
                        height: Self.brickHeight
                    ),
                    // The top row is the tough one, so digging upward pays off.
                    hitPoints: row == 0 && level > 1 ? 2 : 1,
                    row: row
                )
            }
        }

        phase = .serving
        serveCountdown = 1.6
        particles.removeAll()
        restBallOnPaddle()
    }

    /// Parks the ball on the paddle, so the very first frame already shows one.
    private func restBallOnPaddle() {
        balls = [
            Ball(
                position: CGPoint(x: paddleCenterX, y: paddleCenterY - Self.paddleHeight - Self.ballRadius),
                velocity: .zero
            ),
        ]
    }

    private func launchBall() {
        guard phase == .serving else { return }
        let angle = CGFloat.random(in: (-115 ... -65)) * .pi / 180
        balls = [
            Ball(
                position: CGPoint(x: paddleCenterX, y: paddleCenterY - Self.paddleHeight - Self.ballRadius),
                velocity: CGVector(dx: cos(angle) * targetSpeed, dy: sin(angle) * targetSpeed)
            ),
        ]
        phase = .running
    }

    // MARK: - Simulation

    func advance(to date: Date, size: CGSize) {
        adopt(size: size)

        let previous = lastUpdate ?? date
        lastUpdate = date
        guard !isPaused else { return }

        // A long gap (the notch was closed, the Mac slept) must not teleport the
        // ball through the whole board in one step.
        let delta = min(date.timeIntervalSince(previous), 1.0 / 30)
        guard delta > 0 else { return }

        stepTimers(by: delta)
        movePaddle()
        stepParticles(by: delta)
        stepPowerups(by: delta)

        switch phase {
        case .serving:
            let rest = CGPoint(x: paddleCenterX, y: paddleCenterY - Self.paddleHeight - Self.ballRadius)
            balls = [Ball(position: rest, velocity: .zero)]
            serveCountdown -= delta
            if serveCountdown <= 0 { launchBall() }
        case .running:
            stepBalls(by: delta)
        case .over:
            break
        }
    }

    /// Picks up the real canvas size, rescaling an in-flight game if the notch
    /// geometry changed underneath it.
    private func adopt(size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        guard size != boardSize else { return }

        if boardSize == .zero {
            boardSize = size
            paddleCenterX = size.width / 2
            buildLevel()
            return
        }

        let scaleX = size.width / boardSize.width
        let scaleY = size.height / boardSize.height
        boardSize = size
        paddleCenterX *= scaleX
        for index in bricks.indices {
            bricks[index].frame.origin.x *= scaleX
            bricks[index].frame.origin.y *= scaleY
            bricks[index].frame.size.width *= scaleX
            bricks[index].frame.size.height *= scaleY
        }
        for index in balls.indices {
            balls[index].position.x *= scaleX
            balls[index].position.y *= scaleY
        }
        powerups.removeAll()
        particles.removeAll()
    }

    private func stepTimers(by delta: Double) {
        wideTimeLeft = max(wideTimeLeft - delta, 0)
        slowTimeLeft = max(slowTimeLeft - delta, 0)
        if bannerLife > 0 {
            bannerLife -= delta
            if bannerLife <= 0 { banner = nil }
        }
    }

    private func movePaddle() {
        guard let pointerX else { return }
        let half = paddleWidth / 2
        // Following the pointer directly is what makes a mouse paddle feel
        // precise; the clamp keeps it on the board when the cursor runs past.
        paddleCenterX = min(max(pointerX, half), boardSize.width - half)
    }

    private func stepBalls(by delta: Double) {
        guard !balls.isEmpty else { return }

        // Substep so a fast ball cannot tunnel straight through a brick.
        let speed = targetSpeed
        let travel = speed * CGFloat(delta)
        let steps = max(Int(ceil(travel / Self.ballRadius)), 1)
        let stepDelta = CGFloat(delta) / CGFloat(steps)

        for _ in 0 ..< steps {
            for index in balls.indices.reversed() {
                normalise(&balls[index], to: speed)
                balls[index].position.x += balls[index].velocity.dx * stepDelta
                balls[index].position.y += balls[index].velocity.dy * stepDelta
                bounceOffWalls(&balls[index])
                bounceOffPaddle(&balls[index])
                hitBrick(&balls[index])

                if balls[index].position.y - Self.ballRadius > boardSize.height {
                    balls.remove(at: index)
                }
            }
            if balls.isEmpty { break }
        }

        if balls.isEmpty { loseLife() }
        if bricks.isEmpty { advanceLevel() }
    }

    private func normalise(_ ball: inout Ball, to speed: CGFloat) {
        let magnitude = sqrt(ball.velocity.dx * ball.velocity.dx + ball.velocity.dy * ball.velocity.dy)
        guard magnitude > 0.001 else { return }
        // A near-horizontal ball skims forever without clearing anything, so
        // the vertical component keeps a floor.
        var dy = ball.velocity.dy / magnitude
        let minimumVertical: CGFloat = 0.32
        if abs(dy) < minimumVertical {
            dy = dy < 0 ? -minimumVertical : minimumVertical
        }
        let dx = ball.velocity.dx / magnitude
        let renormalised = sqrt(dx * dx + dy * dy)
        ball.velocity = CGVector(dx: dx / renormalised * speed, dy: dy / renormalised * speed)
    }

    private func bounceOffWalls(_ ball: inout Ball) {
        if ball.position.x < Self.ballRadius {
            ball.position.x = Self.ballRadius
            ball.velocity.dx = abs(ball.velocity.dx)
        } else if ball.position.x > boardSize.width - Self.ballRadius {
            ball.position.x = boardSize.width - Self.ballRadius
            ball.velocity.dx = -abs(ball.velocity.dx)
        }
        if ball.position.y < Self.ballRadius {
            ball.position.y = Self.ballRadius
            ball.velocity.dy = abs(ball.velocity.dy)
        }
    }

    private func bounceOffPaddle(_ ball: inout Ball) {
        guard ball.velocity.dy > 0 else { return }
        let top = paddleCenterY - Self.paddleHeight / 2
        guard ball.position.y + Self.ballRadius >= top,
              ball.position.y < paddleCenterY + Self.paddleHeight
        else { return }

        let half = paddleWidth / 2
        let offset = (ball.position.x - paddleCenterX) / half
        guard abs(offset) <= 1.15 else { return }

        // Where it lands on the paddle sets the angle, which is what makes the
        // paddle a steering tool rather than a wall.
        let angle = -CGFloat.pi / 2 + min(max(offset, -1), 1) * (CGFloat.pi / 3)
        let speed = targetSpeed
        ball.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        ball.position.y = top - Self.ballRadius
    }

    private func hitBrick(_ ball: inout Ball) {
        let probe = CGRect(
            x: ball.position.x - Self.ballRadius,
            y: ball.position.y - Self.ballRadius,
            width: Self.ballRadius * 2,
            height: Self.ballRadius * 2
        )
        guard let index = bricks.firstIndex(where: { $0.frame.intersects(probe) }) else { return }

        let brick = bricks[index]
        let overlap = brick.frame.intersection(probe)
        // Bounce off whichever face was penetrated least — the shallow axis is
        // the one the ball actually arrived through.
        if overlap.width < overlap.height {
            ball.velocity.dx = ball.position.x < brick.frame.midX ? -abs(ball.velocity.dx) : abs(ball.velocity.dx)
        } else {
            ball.velocity.dy = ball.position.y < brick.frame.midY ? -abs(ball.velocity.dy) : abs(ball.velocity.dy)
        }

        if bricks[index].hitPoints > 1 {
            bricks[index].hitPoints -= 1
            score += 5
            spawnParticles(at: overlap.center, color: colour(forRow: brick.row), count: 4)
        } else {
            bricks.remove(at: index)
            score += 10 + (level - 1) * 2
            spawnParticles(at: brick.frame.center, color: colour(forRow: brick.row), count: 9)
            maybeDropPowerup(at: brick.frame.center)
        }
        recordHighScore()
    }

    /// Every brick drops something. It is bedlam, which is the point — the board
    /// is nine rows deep and a run only lasts a couple of minutes, so hoarding
    /// the powerups for a one-in-nine chance just meant most runs never saw one.
    private func maybeDropPowerup(at point: CGPoint) {
        guard let kind = PowerupKind.allCases.randomElement() else { return }
        powerups.append(Powerup(position: point, kind: kind))
    }

    private func stepPowerups(by delta: Double) {
        let paddleTop = paddleCenterY - Self.paddleHeight / 2
        let half = paddleWidth / 2

        for index in powerups.indices.reversed() {
            powerups[index].position.y += 116 * CGFloat(delta)
            let position = powerups[index].position

            if position.y > paddleTop - 5, position.y < paddleCenterY + 6,
               abs(position.x - paddleCenterX) <= half + 5 {
                collect(powerups[index].kind, at: position)
                powerups.remove(at: index)
            } else if position.y > boardSize.height {
                powerups.remove(at: index)
            }
        }
    }

    private func collect(_ kind: PowerupKind, at point: CGPoint) {
        spawnParticles(at: point, color: kind.tint, count: 10)
        switch kind {
        case .wide:
            wideTimeLeft = 12
            show("Wide paddle")
        case .slow:
            slowTimeLeft = 9
            show("Slow ball")
        case .multiball:
            splitBalls()
            show("×2 balls")
        }
    }

    /// Doubles the board rather than fanning one ball out: *every* ball in play
    /// gets a twin, so catching two in a row takes you 1 → 2 → 4.
    private func splitBalls() {
        guard phase == .running else { return }
        let speed = targetSpeed
        var extra: [Ball] = []
        for ball in balls {
            guard balls.count + extra.count < 16 else { break }
            let angle = atan2(ball.velocity.dy, ball.velocity.dx)
            extra.append(
                Ball(
                    position: ball.position,
                    velocity: CGVector(
                        dx: cos(angle + .pi / 8) * speed,
                        dy: sin(angle + .pi / 8) * speed
                    )
                )
            )
        }
        balls.append(contentsOf: extra)
    }

    private func loseLife() {
        lives -= 1
        wideTimeLeft = 0
        slowTimeLeft = 0
        powerups.removeAll()
        if lives <= 0 {
            phase = .over
            recordHighScore()
        } else {
            phase = .serving
            serveCountdown = 1.6
            show("\(lives) left")
        }
    }

    private func advanceLevel() {
        level += 1
        buildLevel()
        show("Level \(level)")
    }

    private func recordHighScore() {
        guard score > highScore else { return }
        highScore = score
        Settings.shared.gameHighScore = score
    }

    private func show(_ text: String) {
        banner = text
        bannerLife = 1.4
    }

    // MARK: - Particles

    private func spawnParticles(at point: CGPoint, color: Color, count: Int) {
        for _ in 0 ..< count {
            particles.append(
                Particle(
                    position: point,
                    velocity: CGVector(
                        dx: CGFloat.random(in: -70 ... 70),
                        dy: CGFloat.random(in: -80 ... 20)
                    ),
                    life: Double.random(in: 0.28 ... 0.55),
                    color: color
                )
            )
        }
    }

    private func stepParticles(by delta: Double) {
        for index in particles.indices.reversed() {
            particles[index].life -= delta
            if particles[index].life <= 0 {
                particles.remove(at: index)
                continue
            }
            particles[index].velocity.dy += 260 * CGFloat(delta)
            particles[index].position.x += particles[index].velocity.dx * CGFloat(delta)
            particles[index].position.y += particles[index].velocity.dy * CGFloat(delta)
        }
    }

    /// Plays the game against itself so `--render-preview` captures a board
    /// mid-rally rather than an untouched wall of bricks. The persisted high
    /// score is put back afterwards; a screenshot is not a run.
    func playForPreview(seconds: Double) {
        let savedHighScore = Settings.shared.gameHighScore
        let board = CGSize(width: 646, height: 128)
        var clock = Date()

        boardScreenFrame = CGRect(origin: .zero, size: board)
        advance(to: clock, size: board)
        for _ in 0 ..< Int(seconds * 60) {
            if let ball = balls.first {
                pointerMoved(to: CGPoint(x: ball.position.x, y: 0))
            }
            clock += 1.0 / 60
            advance(to: clock, size: board)
        }

        highScore = savedHighScore
        Settings.shared.gameHighScore = savedHighScore
    }

    // MARK: - Presentation

    func colour(forRow row: Int) -> Color {
        Color(hue: 0.58 - Double(row) * 0.085, saturation: 0.72, brightness: 0.97)
    }

    var overlayTitle: String? {
        if isPaused { return "Paused" }
        switch phase {
        case .over: return "Game over — \(score)"
        case .serving, .running: return nil
        }
    }

    var overlaySubtitle: String {
        if phase == .over, !isPaused { return "Click to play again" }
        return "Move the mouse to steer · click to resume"
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - View

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
            MouseTracker.shared.addMoveObserver("breakout") { point in
                BreakoutGame.shared.pointerMoved(to: point)
            }
            DiagnosticLog.write("game", "board shown, paused=\(game.isPaused) level=\(game.level)")
        }
        .onDisappear {
            MouseTracker.shared.removeMoveObserver("breakout")
            game.pauseForClose()
            DiagnosticLog.write("game", "board hidden at score \(game.score)")
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
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

            // Square pips rather than hearts, for the same reason.
            HStack(spacing: 3) {
                ForEach(0 ..< max(game.lives, 0), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.pink.opacity(0.85))
                        .frame(width: 5, height: 5)
                }
            }

            Spacer(minLength: 0)

            Text(String(format: "%06d", game.score))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text("HI \(String(format: "%06d", game.highScore))")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(settings.accentColor)
        }
        .padding(.horizontal, 2)
    }

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
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(game.overlaySubtitle)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.65)))
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

    private func fill(_ ctx: inout GraphicsContext, _ rect: CGRect, _ colour: Color, _ opacity: Double = 1) {
        ctx.fill(Path(snap(rect)), with: .color(colour.opacity(opacity)))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let p = Self.px

        for brick in game.bricks {
            let colour = game.colour(forRow: brick.row)
            let box = snap(brick.frame)
            // Flat body, a lit top edge and a shaded bottom edge. That two-tone
            // bevel is what makes a rectangle read as a block rather than a
            // coloured smear, and it costs two extra fills.
            fill(&context, box, colour, brick.hitPoints > 1 ? 1 : 0.85)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: box.width, height: p), .white, 0.30)
            fill(&context, CGRect(x: box.minX, y: box.maxY - p, width: box.width, height: p), .black, 0.30)

            if brick.hitPoints > 1 {
                // Armour is a pair of studs rather than an inset panel: legible
                // at this size, and unmistakably pixel art.
                let midY = box.midY - p / 2
                fill(&context, CGRect(x: box.minX + p * 2, y: midY, width: p, height: p), .white, 0.75)
                fill(&context, CGRect(x: box.maxX - p * 3, y: midY, width: p, height: p), .white, 0.75)
            }
        }

        for particle in game.particles {
            fill(&context,
                 CGRect(x: particle.position.x - p / 2, y: particle.position.y - p / 2, width: p, height: p),
                 particle.color, min(particle.life * 2.4, 1))
        }

        for powerup in game.powerups {
            let box = snap(CGRect(x: powerup.position.x - 6, y: powerup.position.y - 5, width: 12, height: 10))
            // A capsule at this size is mush. A square with a hard border and a
            // dark inset reads instantly as a pickup.
            fill(&context, box, powerup.kind.tint, 1)
            fill(&context, box.insetBy(dx: p, dy: p), .black, 0.55)
            context.draw(
                Text(powerup.kind.symbol)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(powerup.kind.tint),
                at: CGPoint(x: box.midX, y: box.midY)
            )
        }

        let paddleRect = snap(CGRect(
            x: game.paddleCenterX - game.paddleWidth / 2,
            y: game.paddleCenterY - BreakoutGame.paddleHeight / 2,
            width: game.paddleWidth,
            height: BreakoutGame.paddleHeight
        ))
        fill(&context, paddleRect, settings.accentColor, 1)
        fill(&context, CGRect(x: paddleRect.minX, y: paddleRect.minY, width: paddleRect.width, height: p), .white, 0.45)
        fill(&context, CGRect(x: paddleRect.maxX - p, y: paddleRect.minY, width: p, height: paddleRect.height), .black, 0.30)
        fill(&context, CGRect(x: paddleRect.minX, y: paddleRect.maxY - p, width: paddleRect.width, height: p), .black, 0.30)

        for ball in game.balls {
            // A square ball. An anti-aliased circle four pixels across is a
            // grey blob; a square is unambiguous and is what the machines this
            // is imitating actually drew.
            let r = BreakoutGame.ballRadius
            let box = snap(CGRect(x: ball.position.x - r, y: ball.position.y - r, width: r * 2, height: r * 2))
            fill(&context, box, .white, 1)
            fill(&context, CGRect(x: box.minX, y: box.minY, width: p, height: p), .white, 1)
            fill(&context, CGRect(x: box.maxX - p, y: box.maxY - p, width: p, height: p), .black, 0.35)
        }

        // Scanlines over the whole board. One dark row every third pixel, dim
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
            let plate = CGRect(x: centre.x - 58, y: centre.y - 9, width: 116, height: 18)
            fill(&context, plate, .black, 0.72)
            fill(&context, CGRect(x: plate.minX, y: plate.minY, width: plate.width, height: Self.px), .white, 0.22)
            fill(&context, CGRect(x: plate.minX, y: plate.maxY - Self.px, width: plate.width, height: Self.px), .white, 0.22)
            context.draw(
                Text(banner.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9)),
                at: centre
            )
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
