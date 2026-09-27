//
//  BreakoutGame.swift
//  FunNotch
//
//  Notch Breakout's rules and physics.
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
//  On top of the classic game: nine hand-drawn boards that come round harder,
//  steel, explosive, gold and mystery bricks, seven power-ups (one of them bad),
//  a combo multiplier for breaking bricks without touching the paddle, and
//  enough shake, sparks, shockwaves and sound that it feels like a game.
//

import AppKit
import SwiftUI

@MainActor
final class BreakoutGame {
    static let shared = BreakoutGame()

    enum Phase: Equatable {
        /// A new board's bricks are dropping into place.
        case intro
        /// Ball rides the paddle, waiting for a launch.
        case serving
        case running
        case over
    }

    enum BrickKind: Equatable {
        case normal
        /// Never breaks, and does not count towards clearing the board.
        case steel
        /// Takes its neighbours with it, and sets off other explosives.
        case explosive
        case gold
        /// Always drops a power-up.
        case mystery
    }

    struct Brick {
        var frame: CGRect
        var kind: BrickKind
        var hitPoints: Int
        let maxHitPoints: Int
        let row: Int
        let column: Int
        /// Seconds of white flash left after a hit.
        var flash: Double = 0
        /// Seconds until it lands, while a board is dropping in.
        var landing: Double = 0

        var isBreakable: Bool { kind != .steel }
        var hasLanded: Bool { landing <= 0 }
    }

    struct Ball {
        var position: CGPoint
        var velocity: CGVector
        /// Where it has just been, newest first, for the trail.
        var trail: [CGPoint] = []
    }

    enum PowerupKind: CaseIterable {
        case wide, multiball, slow, fireball, laser, shield, shrink

        var tint: Color {
            switch self {
            case .wide: return Color(red: 0.3, green: 0.85, blue: 1)
            case .multiball: return Color(red: 1, green: 0.85, blue: 0.25)
            case .slow: return Color(red: 0.45, green: 0.95, blue: 0.7)
            case .fireball: return Color(red: 1, green: 0.55, blue: 0.2)
            case .laser: return Color(red: 1, green: 0.35, blue: 0.55)
            case .shield: return Color(red: 0.45, green: 0.6, blue: 1)
            case .shrink: return Color(red: 0.95, green: 0.25, blue: 0.25)
            }
        }

        var name: String {
            switch self {
            case .wide: return "Wide"
            case .multiball: return "Multiball"
            case .slow: return "Slow-mo"
            case .fireball: return "Fireball"
            case .laser: return "Lasers"
            case .shield: return "Shield"
            case .shrink: return "Shrunk!"
            }
        }

        var symbol: String {
            switch self {
            case .wide: return "arrow.left.and.right"
            case .multiball: return "circle.grid.2x1.fill"
            case .slow: return "tortoise.fill"
            case .fireball: return "flame.fill"
            case .laser: return "bolt.fill"
            case .shield: return "shield.fill"
            case .shrink: return "arrow.right.and.line.vertical.and.arrow.left"
            }
        }

        /// How long it lasts, for the draining ring in the header.
        var duration: Double {
            switch self {
            case .wide: return 12
            case .shrink: return 9
            case .slow: return 9
            case .fireball: return 6
            case .laser: return 8
            case .shield: return 25
            case .multiball: return 0
            }
        }

        /// The one to dodge.
        var isBad: Bool { self == .shrink }
    }

    struct Powerup {
        var position: CGPoint
        let kind: PowerupKind
        var age: Double = 0
    }

    enum ParticleKind {
        /// A point of light, drawn additively so a crowd of them blooms.
        case spark
        /// A tumbling chip of the brick that broke.
        case shard
        /// A soft puff that swells as it fades.
        case smoke
        /// Paper, flipping as it falls.
        case confetti
    }

    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var life: Double
        let maxLife: Double
        let color: Color
        var size: CGFloat = 2
        var gravity: CGFloat = 260
        var kind: ParticleKind = .spark
        var angle: Double = 0
        var spin: Double = 0
    }

    /// A ring of light spreading out from an explosion or a catch.
    struct Ring {
        let center: CGPoint
        let maxRadius: CGFloat
        var life: Double
        let maxLife: Double
        let color: Color

        var progress: Double { 1 - life / maxLife }
    }

    enum BannerTone {
        case plain
        case combo
        case record
    }

    struct Laser {
        var position: CGPoint
    }

    /// Score and power-up names that float up from where they happened.
    struct Popup {
        var position: CGPoint
        let text: String
        let color: Color
        var life: Double
        let maxLife: Double
    }

    private struct Blast {
        let row: Int
        let column: Int
        var fuse: Double
    }

    // MARK: - Board constants

    static let columns = 14
    private static let brickGap: CGFloat = 3
    private static let brickHeight: CGFloat = 10
    private static let brickTop: CGFloat = 4
    static let ballRadius: CGFloat = 3.5
    static let paddleHeight: CGFloat = 5
    /// How far a brick falls while the board drops in, and for how long.
    static let dropHeight: CGFloat = 26
    static let dropDuration: Double = 0.3

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
    private(set) var rings: [Ring] = []
    private(set) var lasers: [Laser] = []
    private(set) var popups: [Popup] = []
    private(set) var paddleCenterX: CGFloat = 0
    private(set) var banner: String?
    private(set) var bannerTone: BannerTone = .plain
    private(set) var bannerLife: Double = 0
    /// How long the current banner has been up, for its entrance.
    private(set) var bannerAge: Double = 0
    /// A white flash over the whole board, from an explosion. Decays on its own.
    private(set) var flash: Double = 0

    /// Bricks broken since a ball last touched the paddle.
    private(set) var combo = 0
    /// Screen shake, in points. Decays on its own.
    private(set) var shake: CGFloat = 0
    /// 1 the moment a ball hits the paddle, easing back to 0.
    private(set) var paddleSquash: Double = 0
    /// The direction the next serve goes, shown as a dotted line.
    private(set) var serveAngle: CGFloat = -.pi / 2
    /// Seconds of play, for anything that pulses or twinkles.
    private(set) var clock: Double = 0
    /// True once this run has beaten the best score there was when it began.
    private(set) var beatHighScore = false

    private(set) var wideTimeLeft: Double = 0
    private(set) var slowTimeLeft: Double = 0
    private(set) var fireTimeLeft: Double = 0
    private(set) var laserTimeLeft: Double = 0
    private(set) var shieldTimeLeft: Double = 0
    private(set) var shrinkTimeLeft: Double = 0

    private var laserCooldown: Double = 0
    private var serveCountdown: Double = 1.6
    private var introLeft: Double = 0
    /// Speed gained from paddle hits this life: a long rally gets quicker.
    private var rally: CGFloat = 0
    private var paddleVelocity: CGFloat = 0
    private var bestAtStart = Settings.shared.gameHighScore
    private var blasts: [Blast] = []

    private(set) var boardSize: CGSize = .zero
    /// Where the board currently sits on screen, so the global pointer position
    /// can be mapped onto it.
    var boardScreenFrame: CGRect = .zero
    private var pointerX: CGFloat?
    private var lastUpdate: Date?

    private let sound = GameSound.shared
    /// Set by the snapshot renderer, whose windows come and go and would
    /// otherwise pause the game as each one closes.
    private var isPreview = false

    private init() {}

    // MARK: - Derived

    var paddleWidth: CGFloat {
        let fraction: CGFloat
        if shrinkTimeLeft > 0 {
            fraction = 0.085
        } else if wideTimeLeft > 0 {
            fraction = 0.24
        } else {
            fraction = 0.13
        }
        return boardSize.width * fraction
    }

    var paddleCenterY: CGFloat {
        boardSize.height - 7
    }

    /// The line the shield sits on.
    var shieldY: CGFloat {
        boardSize.height - 2
    }

    /// Every four bricks broken without touching the paddle adds one to the
    /// multiplier, up to ×5.
    var multiplier: Int {
        min(1 + max(combo - 1, 0) / 4, 5)
    }

    var boardName: String {
        BreakoutLevels.board(for: level).name
    }

    var bestLevel: Int {
        max(Settings.shared.gameBestLevel, level)
    }

    /// How far through the pause before an automatic serve, 0 to 1.
    var serveProgress: Double {
        phase == .serving ? min(max(1 - serveCountdown / 1.6, 0), 1) : 0
    }

    /// Each board has its own colour, which the background takes on.
    var levelHue: Double {
        let hues = [0.6, 0.72, 0.52, 0.82, 0.08, 0.9, 0.45, 0.97, 0.14]
        return hues[(max(level, 1) - 1) % hues.count]
    }

    /// Speed every ball is normalised to, so slow motion and level ramps stay
    /// exact instead of drifting after each bounce.
    private var targetSpeed: CGFloat {
        let base = min(215 + 20 * CGFloat(level - 1), 400) * (1 + rally)
        return slowTimeLeft > 0 ? base * 0.66 : base
    }

    private var brickWidth: CGFloat {
        (boardSize.width - Self.brickGap * CGFloat(Self.columns + 1)) / CGFloat(Self.columns)
    }

    private func cellFrame(row: Int, column: Int) -> CGRect {
        CGRect(
            x: Self.brickGap + CGFloat(column) * (brickWidth + Self.brickGap),
            y: Self.brickTop + CGFloat(row) * (Self.brickHeight + Self.brickGap),
            width: brickWidth,
            height: Self.brickHeight
        )
    }

    // MARK: - Input

    func pointerMoved(to screenPoint: CGPoint) {
        guard boardScreenFrame.width > 1 else { return }
        let fraction = (screenPoint.x - boardScreenFrame.minX) / boardScreenFrame.width
        pointerX = min(max(fraction, 0), 1) * boardSize.width
    }

    /// Click on the board: launch, pause, resume, or start a fresh run.
    func primaryAction() {
        if isPaused {
            isPaused = false
            lastUpdate = nil
            return
        }
        switch phase {
        case .intro: finishIntro()
        case .serving: launchBall()
        case .running:
            isPaused = true
            persistHighScore()
        case .over: restart()
        }
    }

    func pauseForClose() {
        guard !isPreview else { return }
        isPaused = true
        lastUpdate = nil
        persistHighScore()
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
        combo = 0
        bestAtStart = highScore
        beatHighScore = false
        clearEffects()
        buildLevel()
    }

    private func clearEffects() {
        wideTimeLeft = 0
        slowTimeLeft = 0
        fireTimeLeft = 0
        laserTimeLeft = 0
        shieldTimeLeft = 0
        shrinkTimeLeft = 0
        rally = 0
        powerups.removeAll()
        lasers.removeAll()
        blasts.removeAll()
    }

    private func buildLevel() {
        guard boardSize.width > 0 else { return }
        let board = BreakoutLevels.board(for: level)
        layBricks(board.rows, toughening: BreakoutLevels.toughening(for: level), dropping: true)
        show("Level \(level) · \(board.name)", for: 2.2)
    }

    /// Turns a board's text into bricks. Dropping, they fall in row by row,
    /// spreading out from the middle, before the serve.
    private func layBricks(_ rows: [String], toughening: Int, dropping: Bool) {
        var laid: [Brick] = []
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where column < Self.columns {
                let kind: BrickKind
                var hits = 1
                switch character {
                case "1", "2", "3":
                    kind = .normal
                    hits = (Int(String(character)) ?? 1) + toughening
                case "#": kind = .steel
                case "X": kind = .explosive
                case "$": kind = .gold
                case "?": kind = .mystery
                default: continue
                }
                let landing = dropping
                    ? Self.dropDuration + Double(row) * 0.08 + abs(Double(column) - 6.5) * 0.03
                    : 0
                laid.append(Brick(
                    frame: cellFrame(row: row, column: column),
                    kind: kind, hitPoints: hits, maxHitPoints: hits,
                    row: row, column: column, landing: landing
                ))
            }
        }
        bricks = laid
        combo = 0
        particles.removeAll()
        rings.removeAll()
        popups.removeAll()
        clearEffects()
        restBallOnPaddle()
        if dropping {
            introLeft = (laid.map(\.landing).max() ?? 0) + 0.15
            phase = .intro
        } else {
            beginServe()
        }
    }

    /// An impatient click drops the whole board at once.
    private func finishIntro() {
        for index in bricks.indices { bricks[index].landing = 0 }
        introLeft = 0
        beginServe()
    }

    private func beginServe() {
        phase = .serving
        serveCountdown = 1.6
        // Up the board at an angle, never straight up: a vertical serve just
        // bounces between the paddle and the bottom row.
        let degrees = Bool.random() ? CGFloat.random(in: -118 ... -100) : CGFloat.random(in: -80 ... -62)
        serveAngle = degrees * .pi / 180
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
        balls = [
            Ball(
                position: CGPoint(x: paddleCenterX, y: paddleCenterY - Self.paddleHeight - Self.ballRadius),
                velocity: CGVector(dx: cos(serveAngle) * targetSpeed, dy: sin(serveAngle) * targetSpeed)
            ),
        ]
        phase = .running
        sound.play(.launch)
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
        clock += delta

        stepTimers(by: delta)
        movePaddle(by: delta)
        stepEffects(by: delta)
        stepPowerups(by: delta)

        switch phase {
        case .intro:
            restBallOnPaddle()
            introLeft -= delta
            if introLeft <= 0 { beginServe() }
        case .serving:
            restBallOnPaddle()
            serveCountdown -= delta
            if serveCountdown <= 0 { launchBall() }
        case .running:
            stepLasers(by: delta)
            stepBlasts(by: delta)
            stepBalls(by: delta)
            if phase == .running, !bricks.contains(where: \.isBreakable) {
                clearLevel()
            }
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
            bricks[index].frame = cellFrame(row: bricks[index].row, column: bricks[index].column)
        }
        for index in balls.indices {
            balls[index].position.x *= scaleX
            balls[index].position.y *= scaleY
            balls[index].trail.removeAll()
        }
        powerups.removeAll()
        particles.removeAll()
        rings.removeAll()
        lasers.removeAll()
        popups.removeAll()
    }

    private func stepTimers(by delta: Double) {
        wideTimeLeft = max(wideTimeLeft - delta, 0)
        slowTimeLeft = max(slowTimeLeft - delta, 0)
        fireTimeLeft = max(fireTimeLeft - delta, 0)
        laserTimeLeft = max(laserTimeLeft - delta, 0)
        shieldTimeLeft = max(shieldTimeLeft - delta, 0)
        shrinkTimeLeft = max(shrinkTimeLeft - delta, 0)
        if bannerLife > 0 {
            bannerLife -= delta
            bannerAge += delta
            if bannerLife <= 0 { banner = nil }
        }
    }

    private func movePaddle(by delta: Double) {
        guard let pointerX else { return }
        let half = paddleWidth / 2
        // Following the pointer directly is what makes a mouse paddle feel
        // precise; the clamp keeps it on the board when the cursor runs past.
        let target = min(max(pointerX, half), boardSize.width - half)
        let moved = (target - paddleCenterX) / CGFloat(delta)
        paddleVelocity = paddleVelocity * 0.5 + moved * 0.5
        paddleCenterX = target
    }

    private func stepEffects(by delta: Double) {
        shake = max(shake - CGFloat(delta) * 16, 0)
        paddleSquash = max(paddleSquash - delta / 0.2, 0)
        flash = max(flash - delta * 5, 0)

        for index in rings.indices.reversed() {
            rings[index].life -= delta
            if rings[index].life <= 0 { rings.remove(at: index) }
        }

        for index in bricks.indices {
            if bricks[index].flash > 0 { bricks[index].flash = max(bricks[index].flash - delta, 0) }
            if bricks[index].landing > 0 { bricks[index].landing = max(bricks[index].landing - delta, 0) }
        }

        for index in particles.indices.reversed() {
            particles[index].life -= delta
            if particles[index].life <= 0 {
                particles.remove(at: index)
                continue
            }
            particles[index].velocity.dy += particles[index].gravity * CGFloat(delta)
            if particles[index].kind == .smoke || particles[index].kind == .confetti {
                // Air resistance: smoke drifts to a stop, paper flutters.
                particles[index].velocity.dx *= CGFloat(pow(0.3, delta))
            }
            particles[index].position.x += particles[index].velocity.dx * CGFloat(delta)
            particles[index].position.y += particles[index].velocity.dy * CGFloat(delta)
            particles[index].angle += particles[index].spin * delta
        }

        for index in popups.indices.reversed() {
            popups[index].life -= delta
            if popups[index].life <= 0 {
                popups.remove(at: index)
                continue
            }
            popups[index].position.y -= 24 * CGFloat(delta)
        }

        // A fireball sheds embers as it goes.
        if fireTimeLeft > 0, phase == .running {
            for ball in balls where particles.count < 380 {
                particles.append(Particle(
                    position: ball.position,
                    velocity: CGVector(dx: CGFloat.random(in: -18 ... 18), dy: CGFloat.random(in: -30 ... 0)),
                    life: 0.32, maxLife: 0.32,
                    color: Bool.random() ? Color(red: 1, green: 0.6, blue: 0.15) : Color(red: 1, green: 0.85, blue: 0.3),
                    size: CGFloat.random(in: 1.5 ... 2.6),
                    gravity: -30
                ))
            }
        }
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

                // The shield saves one ball, once.
                if shieldTimeLeft > 0, balls[index].velocity.dy > 0,
                   balls[index].position.y + Self.ballRadius >= shieldY {
                    balls[index].velocity.dy = -abs(balls[index].velocity.dy)
                    balls[index].position.y = shieldY - Self.ballRadius
                    shieldTimeLeft = 0
                    burst(at: CGPoint(x: balls[index].position.x, y: shieldY), color: PowerupKind.shield.tint, count: 16)
                    ring(at: CGPoint(x: balls[index].position.x, y: shieldY), radius: 40, color: PowerupKind.shield.tint)
                    sound.play(.shield)
                }

                if balls[index].position.y - Self.ballRadius > boardSize.height {
                    balls.remove(at: index)
                }
            }
            if balls.isEmpty { break }
        }

        for index in balls.indices {
            balls[index].trail.insert(balls[index].position, at: 0)
            if balls[index].trail.count > 10 { balls[index].trail.removeLast() }
        }

        if balls.isEmpty { loseLife() }
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
        // paddle a steering tool rather than a wall — and the way the paddle is
        // moving at the time adds a little spin on top.
        let spin = min(max(paddleVelocity / 2400, -0.3), 0.3)
        let angle = -CGFloat.pi / 2 + min(max(offset, -1), 1) * (CGFloat.pi / 3) + spin
        rally = min(rally + 0.012, 0.2)
        let speed = targetSpeed
        ball.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        ball.position.y = top - Self.ballRadius
        combo = 0
        paddleSquash = 1
        sound.play(.paddle)
    }

    private func hitBrick(_ ball: inout Ball) {
        let probe = CGRect(
            x: ball.position.x - Self.ballRadius,
            y: ball.position.y - Self.ballRadius,
            width: Self.ballRadius * 2,
            height: Self.ballRadius * 2
        )
        guard let index = bricks.firstIndex(where: { $0.hasLanded && $0.frame.intersects(probe) }) else { return }

        let brick = bricks[index]
        let overlap = brick.frame.intersection(probe)
        // A fireball ploughs straight through anything that can break.
        let burning = fireTimeLeft > 0 && brick.isBreakable
        if !burning {
            // Bounce off whichever face was penetrated least — the shallow axis
            // is the one the ball actually arrived through.
            if overlap.width < overlap.height {
                ball.velocity.dx = ball.position.x < brick.frame.midX ? -abs(ball.velocity.dx) : abs(ball.velocity.dx)
            } else {
                ball.velocity.dy = ball.position.y < brick.frame.midY ? -abs(ball.velocity.dy) : abs(ball.velocity.dy)
            }
        }
        damage(at: index, by: burning ? brick.hitPoints : 1, from: overlap.center)
    }

    /// Takes hit points off a brick, and breaks it when they run out.
    private func damage(at index: Int, by amount: Int, from point: CGPoint) {
        guard bricks[index].isBreakable else {
            bricks[index].flash = 0.1
            burst(at: point, color: Color(white: 0.85), count: 3)
            sound.play(.steel)
            return
        }
        bricks[index].hitPoints -= amount
        if bricks[index].hitPoints > 0 {
            bricks[index].flash = 0.1
            addScore(5, at: point, floating: false)
            burst(at: point, color: colour(of: bricks[index]), count: 4)
            sound.play(.crack)
        } else {
            destroy(at: index)
        }
    }

    private func destroy(at index: Int) {
        let brick = bricks.remove(at: index)
        combo += 1

        let points: Int
        switch brick.kind {
        case .gold: points = 100
        case .explosive: points = 15
        default: points = 10 * brick.maxHitPoints
        }
        addScore(points + (level - 1) * 2, at: brick.frame.center, floating: true)
        burst(at: brick.frame.center, color: colour(of: brick), count: brick.kind == .gold ? 18 : 10)

        switch brick.kind {
        case .explosive:
            // A short fuse, so a chain ripples outward instead of going off
            // all at once.
            blasts.append(Blast(row: brick.row, column: brick.column, fuse: 0.07))
            sound.play(.brick(min(combo, 15)))
        case .mystery:
            dropPowerup(at: brick.frame.center, chance: 1)
            sound.play(.brick(min(combo, 15)))
        case .gold:
            sound.play(.coin)
            dropPowerup(at: brick.frame.center, chance: 0.4)
        case .normal, .steel:
            dropPowerup(at: brick.frame.center, chance: 0.16)
            sound.play(.brick(min(combo, 15)))
        }

        // Every fourth brick in a row raises the multiplier, up to its cap.
        if combo > 1, (combo - 1) % 4 == 0, (combo - 1) / 4 <= 4 {
            show("Combo ×\(multiplier)", for: 0.9, tone: .combo)
            sound.play(.combo)
        }
    }

    private func addScore(_ points: Int, at point: CGPoint, floating: Bool) {
        let total = points * multiplier
        score += total
        if floating {
            popups.append(Popup(
                position: point, text: "+\(total)",
                color: multiplier > 1 ? Self.comboColour(multiplier) : .white,
                life: 0.75, maxLife: 0.75
            ))
            if popups.count > 24 { popups.removeFirst() }
        }
        recordHighScore()
    }

    static func comboColour(_ multiplier: Int) -> Color {
        switch multiplier {
        case 2: return Color(red: 1, green: 0.9, blue: 0.3)
        case 3: return Color(red: 1, green: 0.6, blue: 0.2)
        case 4: return Color(red: 1, green: 0.35, blue: 0.45)
        default: return Color(red: 0.85, green: 0.45, blue: 1)
        }
    }

    // MARK: - Explosions

    private func stepBlasts(by delta: Double) {
        guard !blasts.isEmpty else { return }
        var due: [Blast] = []
        for index in blasts.indices.reversed() {
            blasts[index].fuse -= delta
            if blasts[index].fuse <= 0 { due.append(blasts.remove(at: index)) }
        }
        for blast in due { detonate(blast) }
    }

    private func detonate(_ blast: Blast) {
        let centre = cellFrame(row: blast.row, column: blast.column).center
        shake = max(shake, 3.5)
        flash = max(flash, 0.55)
        explosion(at: centre)
        sound.play(.boom)

        // Everything around it goes, except steel. Other explosives it
        // catches light their own fuses.
        let caught = bricks.indices.filter { index in
            let brick = bricks[index]
            return abs(brick.row - blast.row) <= 1 && abs(brick.column - blast.column) <= 1
                && brick.isBreakable && brick.hasLanded
        }
        for index in caught.sorted(by: >) {
            destroy(at: index)
        }
    }

    // MARK: - Power-ups

    private func dropPowerup(at point: CGPoint, chance: Double) {
        guard Double.random(in: 0 ..< 1) < chance, powerups.count < 6 else { return }
        // The helpful ones often, the bad one rarely.
        let pool: [PowerupKind] = [
            .wide, .wide, .multiball, .multiball, .slow,
            .fireball, .fireball, .laser, .laser, .shield, .shrink,
        ]
        powerups.append(Powerup(position: point, kind: pool.randomElement() ?? .wide))
    }

    private func stepPowerups(by delta: Double) {
        let paddleTop = paddleCenterY - Self.paddleHeight / 2
        let half = paddleWidth / 2

        for index in powerups.indices.reversed() {
            powerups[index].position.y += 96 * CGFloat(delta)
            powerups[index].age += delta
            let position = powerups[index].position

            if position.y > paddleTop - 5, position.y < paddleCenterY + 6,
               abs(position.x - paddleCenterX) <= half + 6 {
                collect(powerups[index].kind, at: position)
                powerups.remove(at: index)
            } else if position.y > boardSize.height + 8 {
                powerups.remove(at: index)
            }
        }
    }

    private func collect(_ kind: PowerupKind, at point: CGPoint) {
        burst(at: point, color: kind.tint, count: 14)
        ring(at: point, radius: 34, color: kind.tint)
        popups.append(Popup(
            position: CGPoint(x: point.x, y: point.y - 12), text: kind.name,
            color: kind.tint, life: 1, maxLife: 1
        ))
        switch kind {
        case .wide:
            wideTimeLeft = 12
            shrinkTimeLeft = 0
        case .shrink:
            shrinkTimeLeft = 9
            wideTimeLeft = 0
        case .slow:
            slowTimeLeft = 9
        case .multiball:
            splitBalls()
        case .fireball:
            fireTimeLeft = 6
        case .laser:
            laserTimeLeft = 8
            laserCooldown = 0
        case .shield:
            shieldTimeLeft = 25
        }
        sound.play(kind.isBad ? .bad : .powerup)
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
            extra.append(Ball(
                position: ball.position,
                velocity: CGVector(dx: cos(angle + .pi / 8) * speed, dy: sin(angle + .pi / 8) * speed)
            ))
        }
        balls.append(contentsOf: extra)
    }

    /// Two bolts at a time from the paddle's ends, while the lasers last.
    private func stepLasers(by delta: Double) {
        if laserTimeLeft > 0 {
            laserCooldown -= delta
            if laserCooldown <= 0 {
                laserCooldown = 0.32
                let y = paddleCenterY - Self.paddleHeight
                let reach = paddleWidth / 2 - 3
                lasers.append(Laser(position: CGPoint(x: paddleCenterX - reach, y: y)))
                lasers.append(Laser(position: CGPoint(x: paddleCenterX + reach, y: y)))
                sound.play(.laser)
            }
        }

        for index in lasers.indices.reversed() {
            lasers[index].position.y -= 430 * CGFloat(delta)
            let point = lasers[index].position
            if point.y < -8 {
                lasers.remove(at: index)
                continue
            }
            let probe = CGRect(x: point.x - 1, y: point.y - 4, width: 2, height: 8)
            if let hit = bricks.firstIndex(where: { $0.hasLanded && $0.frame.intersects(probe) }) {
                lasers.remove(at: index)
                damage(at: hit, by: 1, from: point)
            }
        }
    }

    // MARK: - Lives and levels

    private func loseLife() {
        lives -= 1
        combo = 0
        shake = max(shake, 5)
        clearEffects()
        sound.play(.lose)
        if lives <= 0 {
            phase = .over
            persistHighScore()
            if beatHighScore {
                confetti()
                sound.play(.highScore)
            } else {
                sound.play(.gameOver)
            }
        } else {
            beginServe()
            show(lives == 1 ? "Last ball" : "\(lives) balls left", for: 1.4)
        }
    }

    private func clearLevel() {
        let bonus = 250 + 100 * lives
        score += bonus
        recordHighScore()
        persistHighScore()
        sound.play(.levelClear)
        level += 1
        if level > Settings.shared.gameBestLevel { Settings.shared.gameBestLevel = level }
        buildLevel()
        popups.append(Popup(
            position: CGPoint(x: boardSize.width / 2, y: boardSize.height * 0.78),
            text: "Board clear +\(bonus)", color: Color(red: 0.5, green: 1, blue: 0.6),
            life: 1.6, maxLife: 1.6
        ))
    }

    private func recordHighScore() {
        // Only once there was a score to beat: the very first run beating 0 is
        // not news.
        if bestAtStart > 0, score > bestAtStart, !beatHighScore {
            beatHighScore = true
            show("New high score!", for: 1.6, tone: .record)
            sound.play(.highScore)
        }
        if score > highScore { highScore = score }
    }

    /// Written at the natural stopping points rather than on every brick, so a
    /// high-scoring rally is not a stream of preference writes.
    private func persistHighScore() {
        if highScore > Settings.shared.gameHighScore {
            Settings.shared.gameHighScore = highScore
        }
    }

    private func show(_ text: String, for seconds: Double, tone: BannerTone = .plain) {
        banner = text
        bannerTone = tone
        bannerLife = seconds
        bannerAge = 0
    }

    // MARK: - Particles

    /// Sparks, and chips of the brick itself tumbling away.
    private func burst(at point: CGPoint, color: Color, count: Int) {
        for index in 0 ..< count where particles.count < 420 {
            let life = Double.random(in: 0.3 ... 0.6)
            let isShard = index % 3 == 0
            particles.append(Particle(
                position: point,
                velocity: CGVector(dx: CGFloat.random(in: -85 ... 85), dy: CGFloat.random(in: -100 ... 15)),
                life: isShard ? life * 1.4 : life, maxLife: isShard ? life * 1.4 : life, color: color,
                size: isShard ? CGFloat.random(in: 2.4 ... 3.6) : CGFloat.random(in: 1.2 ... 2.2),
                gravity: isShard ? 380 : 220,
                kind: isShard ? .shard : .spark,
                angle: Double.random(in: 0 ... .pi),
                spin: Double.random(in: -14 ... 14)
            ))
        }
    }

    private func ring(at point: CGPoint, radius: CGFloat, color: Color, life: Double = 0.45) {
        rings.append(Ring(center: point, maxRadius: radius, life: life, maxLife: life, color: color))
        if rings.count > 12 { rings.removeFirst() }
    }

    /// A shockwave, fire, then smoke drifting up.
    private func explosion(at point: CGPoint) {
        ring(at: point, radius: 46, color: Color(red: 1, green: 0.7, blue: 0.3), life: 0.5)
        let fire = [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.5, blue: 0.15), Color(red: 0.95, green: 0.25, blue: 0.2)]
        for index in 0 ..< 22 where particles.count < 420 {
            let angle = Double(index) / 22 * 2 * .pi + Double.random(in: -0.2 ... 0.2)
            let speed = CGFloat.random(in: 60 ... 160)
            let life = Double.random(in: 0.3 ... 0.6)
            particles.append(Particle(
                position: point,
                velocity: CGVector(dx: CGFloat(cos(angle)) * speed, dy: CGFloat(sin(angle)) * speed),
                life: life, maxLife: life, color: fire.randomElement() ?? .orange,
                size: CGFloat.random(in: 1.6 ... 3.4), gravity: 120
            ))
        }
        for _ in 0 ..< 6 where particles.count < 420 {
            let life = Double.random(in: 0.6 ... 0.9)
            particles.append(Particle(
                position: point,
                velocity: CGVector(dx: CGFloat.random(in: -30 ... 30), dy: CGFloat.random(in: -45 ... -12)),
                life: life, maxLife: life, color: Color(white: 0.6), size: CGFloat.random(in: 5 ... 8),
                gravity: -20, kind: .smoke
            ))
        }
    }

    private func confetti() {
        let colours: [Color] = [.pink, .yellow, .cyan, .mint, .orange, .purple]
        for _ in 0 ..< 70 where particles.count < 420 {
            let life = Double.random(in: 1.2 ... 2.0)
            particles.append(Particle(
                position: CGPoint(x: CGFloat.random(in: 0 ... boardSize.width), y: -4),
                velocity: CGVector(dx: CGFloat.random(in: -40 ... 40), dy: CGFloat.random(in: 20 ... 90)),
                life: life, maxLife: life, color: colours.randomElement() ?? .pink,
                size: CGFloat.random(in: 2.5 ... 4), gravity: 60, kind: .confetti,
                angle: Double.random(in: 0 ... .pi), spin: Double.random(in: -9 ... 9)
            ))
        }
    }

    // MARK: - Presentation

    func colour(forRow row: Int) -> Color {
        Color(hue: 0.58 - Double(row) * 0.085, saturation: 0.72, brightness: 0.97)
    }

    func colour(of brick: Brick) -> Color {
        switch brick.kind {
        case .normal: return colour(forRow: brick.row)
        case .steel: return Color(white: 0.62)
        case .explosive: return Color(red: 0.95, green: 0.3, blue: 0.22)
        case .gold: return Color(red: 1, green: 0.8, blue: 0.25)
        case .mystery: return Color(red: 0.75, green: 0.4, blue: 1)
        }
    }

    var overlayTitle: String? {
        if isPaused { return "Paused" }
        switch phase {
        case .over: return beatHighScore ? "New high score!" : "Game over"
        case .intro, .serving, .running: return nil
        }
    }

    var overlaySubtitle: String {
        if phase == .over, !isPaused {
            return "\(score.formatted()) points · level \(level) · click to play again"
        }
        return "Move the pointer to steer · click to resume"
    }

    // MARK: - Preview and testing

    /// Plays the game against itself so `--render-preview` captures a board
    /// mid-rally rather than an untouched wall of bricks. The persisted high
    /// score is put back afterwards; a screenshot is not a run.
    func playForPreview(seconds: Double, level: Int = 1, effects: [PowerupKind] = []) {
        let savedHighScore = Settings.shared.gameHighScore
        let savedBestLevel = Settings.shared.gameBestLevel
        let board = CGSize(width: 646, height: 128)
        var clock = Date()
        isPreview = true
        isPaused = false

        boardScreenFrame = CGRect(origin: .zero, size: board)
        advance(to: clock, size: board)
        if level != self.level {
            self.level = level
            buildLevel()
        }
        finishIntro()
        launchBall()
        for effect in effects { collect(effect, at: CGPoint(x: paddleCenterX, y: paddleCenterY)) }
        for _ in 0 ..< Int(seconds * 60) {
            if let ball = balls.first {
                pointerMoved(to: CGPoint(x: ball.position.x, y: 0))
            }
            clock += 1.0 / 60
            advance(to: clock, size: board)
        }

        highScore = savedHighScore
        Settings.shared.gameHighScore = savedHighScore
        Settings.shared.gameBestLevel = savedBestLevel
    }

    /// Lays out a board at once, with no drop-in, for the self-test.
    func loadForTesting(_ rows: [String], size: CGSize) {
        adopt(size: size)
        phase = .running
        layBricks(rows, toughening: 0, dropping: false)
        phase = .running
        balls = []
    }

    /// Breaks the brick at a cell as if a ball had, for the self-test.
    func breakForTesting(row: Int, column: Int) {
        guard let index = bricks.firstIndex(where: { $0.row == row && $0.column == column }) else { return }
        damage(at: index, by: bricks[index].hitPoints, from: bricks[index].frame.center)
    }

    /// Lets fuses burn down without a ball in play, for the self-test.
    func settleForTesting(seconds: Double) {
        var remaining = seconds
        while remaining > 0 {
            stepBlasts(by: 1.0 / 60)
            remaining -= 1.0 / 60
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
