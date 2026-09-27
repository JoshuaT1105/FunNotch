//
//  DinoGame.swift
//  FunNotch
//
//  Dino Run's rules and physics: an endless runner across a desert that goes
//  from morning to night and back as the score climbs.
//
//  Controls have to work in a panel that is usually not the key window, so
//  the mouse is the first-class input: press anywhere on the board to jump,
//  and hold for a higher one. Once the board has been clicked the panel takes
//  the keyboard too, and Space, ↑ and ↓ behave as they do in the original.
//  Nothing needs ducking to survive: a mid-height pterodactyl can also be
//  cleared by a held jump, so a mouse is never at a disadvantage.
//
//  What makes it feel good is mostly in the jump. Gravity is lighter while the
//  button is held and the dinosaur is still rising, letting go early cuts the
//  climb short, a press just before landing is remembered and fires on touch-
//  down, and pressing ↓ in the air drops like a stone.
//

import AppKit
import SwiftUI

@MainActor
final class DinoGame {
    static let shared = DinoGame()

    enum Phase: Equatable {
        /// Standing at the start line, waiting for the first press.
        case ready
        case running
        /// The moment of impact, played in slow motion before the card.
        case crashed
        case over
    }

    struct Stem {
        /// Offset from the obstacle's left edge.
        let dx: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Where the arms join, as a fraction of the height, if it has them.
        let leftArm: CGFloat?
        let rightArm: CGFloat?
        let flower: Bool
    }

    enum ObstacleKind: Equatable {
        case cactus
        case rock
        /// A pterodactyl, flying at one of three heights.
        case bird
        /// Rolls in faster than the ground and bounces as it comes.
        case tumbleweed
    }

    struct Obstacle {
        let kind: ObstacleKind
        /// Left edge, in board coordinates.
        var x: CGFloat
        let width: CGFloat
        let height: CGFloat
        /// Height of the bottom above the ground (birds), or of a bounce.
        var altitude: CGFloat
        var stems: [Stem] = []
        let seed: Int
        var age: Double = 0
        var bounce: CGFloat = 0
        var bounceVelocity: CGFloat = 0
        var spin: Double = 0
        var passed = false
        /// The least clearance the dinosaur had while overlapping it.
        var closest: CGFloat = .infinity
        var overlapped = false
    }

    enum PowerKind: CaseIterable {
        /// One free hit.
        case shield
        /// A second jump in the air.
        case wings
        /// Gems fly to you.
        case magnet
        /// Faster, glowing, and anything in the way is smashed.
        case turbo

        var tint: Color {
            switch self {
            case .shield: return Color(red: 0.36, green: 0.66, blue: 1)
            case .wings: return Color(red: 0.4, green: 0.92, blue: 0.75)
            case .magnet: return Color(red: 1, green: 0.44, blue: 0.72)
            case .turbo: return Color(red: 1, green: 0.8, blue: 0.2)
            }
        }

        var symbol: String {
            switch self {
            case .shield: return "shield.fill"
            case .wings: return "chevron.up.2"
            case .magnet: return "sparkles"
            case .turbo: return "star.fill"
            }
        }

        var name: String {
            switch self {
            case .shield: return "Shield"
            case .wings: return "Double jump"
            case .magnet: return "Gem magnet"
            case .turbo: return "Turbo!"
            }
        }

        /// Seconds it lasts; the shield lasts until it is used.
        var duration: Double {
            switch self {
            case .shield: return 0
            case .wings: return 12
            case .magnet: return 12
            case .turbo: return 5
            }
        }
    }

    struct Gem {
        var x: CGFloat
        /// Height above the ground.
        var altitude: CGFloat
        let seed: Int
    }

    struct Orb {
        var x: CGFloat
        let altitude: CGFloat
        let kind: PowerKind
        var age: Double = 0
    }

    enum ParticleKind {
        case dust
        case spark
        case chip
        case confetti
    }

    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var life: Double
        let maxLife: Double
        let color: Color
        var size: CGFloat
        var gravity: CGFloat
        var kind: ParticleKind
        var angle: Double = 0
        var spin: Double = 0
    }

    struct Popup {
        var position: CGPoint
        let text: String
        let color: Color
        var life: Double
        let maxLife: Double
    }

    /// The dinosaur's colours. Later ones are earned by beating a score.
    struct Skin {
        let name: String
        let unlockScore: Int
        let top: Color
        let bottom: Color
        let belly: Color
        let spikes: Color
        let glows: Bool
    }

    static let skins: [Skin] = [
        Skin(name: "Classic", unlockScore: 0,
             top: Color(red: 0.42, green: 0.86, blue: 0.45), bottom: Color(red: 0.16, green: 0.6, blue: 0.3),
             belly: Color(red: 0.82, green: 0.97, blue: 0.7), spikes: Color(red: 0.13, green: 0.5, blue: 0.26), glows: false),
        Skin(name: "Ocean", unlockScore: 500,
             top: Color(red: 0.4, green: 0.8, blue: 1), bottom: Color(red: 0.14, green: 0.46, blue: 0.86),
             belly: Color(red: 0.82, green: 0.94, blue: 1), spikes: Color(red: 0.1, green: 0.36, blue: 0.72), glows: false),
        Skin(name: "Sunset", unlockScore: 1000,
             top: Color(red: 1, green: 0.64, blue: 0.38), bottom: Color(red: 0.88, green: 0.3, blue: 0.26),
             belly: Color(red: 1, green: 0.9, blue: 0.76), spikes: Color(red: 0.72, green: 0.2, blue: 0.2), glows: false),
        Skin(name: "Grape", unlockScore: 2000,
             top: Color(red: 0.72, green: 0.58, blue: 1), bottom: Color(red: 0.42, green: 0.28, blue: 0.84),
             belly: Color(red: 0.92, green: 0.88, blue: 1), spikes: Color(red: 0.32, green: 0.2, blue: 0.66), glows: false),
        Skin(name: "Gold", unlockScore: 4000,
             top: Color(red: 1, green: 0.9, blue: 0.5), bottom: Color(red: 0.86, green: 0.6, blue: 0.1),
             belly: Color(red: 1, green: 0.97, blue: 0.84), spikes: Color(red: 0.7, green: 0.46, blue: 0.06), glows: true),
    ]

    // MARK: - Tuning

    /// Where the dinosaur's feet are, from the left edge.
    static let dinoX: CGFloat = 74
    /// The band of ground at the bottom of the board.
    static let groundDepth: CGFloat = 22
    static let jumpVelocity: CGFloat = 440
    static let gravity: CGFloat = 2500
    /// Gravity while the button is held on the way up: a floatier climb.
    static let holdGravity: CGFloat = 1350
    /// How long holding keeps gravity light.
    static let maxHold: Double = 0.22
    /// What letting go early leaves of the upward speed.
    static let jumpCut: CGFloat = 0.6
    /// Pressing down in the air.
    static let fastFall: CGFloat = 6200
    static let doubleJumpVelocity: CGFloat = 400
    static let startSpeed: CGFloat = 250
    static let topSpeed: CGFloat = 640
    /// Heights of a pterodactyl's middle above the ground: under the belly,
    /// head height, and high enough to run beneath.
    static let birdAltitudes: [CGFloat] = [14, 30, 50]

    // MARK: - State

    private(set) var phase: Phase = .ready
    private(set) var isPaused = false
    private(set) var boardSize: CGSize = .zero

    /// Height of the feet above the ground, and vertical speed (up is +).
    private(set) var height: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private(set) var isDucking = false
    private(set) var isHolding = false
    private var holdTime: Double = 0
    private var usedDoubleJump = false
    private var jumpBufferedUntil: Double = -1
    /// Squash on landing, stretch on take-off: -1 to 1, easing back to 0.
    private(set) var squash: Double = 0
    /// Runs the legs: advances with distance, not time.
    private(set) var stride: Double = 0

    private(set) var speed: CGFloat = startSpeed
    private(set) var distance: CGFloat = 0
    private(set) var runTime: Double = 0
    /// Seconds of play, for anything that pulses, blinks or twinkles.
    private(set) var clock: Double = 0
    private var exactScore: Double = 0
    private(set) var highScore = Settings.shared.dinoHighScore
    private(set) var beatHighScore = false
    private var bestAtStart = Settings.shared.dinoHighScore
    private(set) var gemsThisRun = 0
    private(set) var gemRun = 0
    private var gemRunTimer: Double = 0
    private(set) var closeCalls = 0

    private(set) var obstacles: [Obstacle] = []
    private(set) var gems: [Gem] = []
    private(set) var orbs: [Orb] = []
    private(set) var particles: [Particle] = []
    private(set) var popups: [Popup] = []

    private(set) var hasShield = false
    private(set) var wingsLeft: Double = 0
    private(set) var magnetLeft: Double = 0
    private(set) var turboLeft: Double = 0
    /// Brief invulnerability after the shield takes a hit.
    private(set) var graceLeft: Double = 0

    private(set) var shake: CGFloat = 0
    /// Lights up the score for a moment at every hundred.
    private(set) var milestoneGlow: Double = 0
    private(set) var crashTime: Double = 0
    private(set) var overAge: Double = 0
    /// Colour the game over card leads with, when a colour was unlocked.
    private(set) var unlockedSkin: Skin?
    private(set) var banner: String?
    private(set) var bannerLife: Double = 0
    /// What ended the last run, for the log and the self-test.
    private(set) var lastCrash = ""

    private var nextObstacleIn: CGFloat = 320
    private var nextOrbIn: CGFloat = 2600
    private var dustTimer: Double = 0
    private var lastUpdate: Date?
    private var seedCounter = 1
    private let sound = GameSound.shared
    private var isPreview = false

    private init() {}

    // MARK: - Derived

    var score: Int { Int(exactScore) }

    var groundY: CGFloat { boardSize.height - Self.groundDepth }

    var isOnGround: Bool { height <= 0.001 && velocity <= 0 }

    var skin: Skin {
        let index = Settings.shared.dinoSkin
        let skin = Self.skins[min(max(index, 0), Self.skins.count - 1)]
        return skin.unlockScore <= max(Settings.shared.dinoHighScore, highScore) ? skin : Self.skins[0]
    }

    var unlockedSkins: [Skin] {
        let best = max(Settings.shared.dinoHighScore, highScore)
        return Self.skins.filter { $0.unlockScore <= best }
    }

    var nextSkin: Skin? {
        let best = max(Settings.shared.dinoHighScore, highScore)
        return Self.skins.first { $0.unlockScore > best }
    }

    /// Where in the day the run has got to, 0 to 1: morning at 0, sunset
    /// around a half, night after that, dawn coming round again.
    var dayPhase: Double {
        (exactScore / 1400 + 0.08).truncatingRemainder(dividingBy: 1)
    }

    /// 0 in full day, 1 in full night.
    var nightness: Double {
        let p = dayPhase
        func ramp(_ a: Double, _ b: Double, _ x: Double) -> Double {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
        return ramp(0.46, 0.62, p) * (1 - ramp(0.86, 0.98, p))
    }

    var bestScore: Int { max(highScore, score) }

    /// How the dinosaur looks this frame.
    enum Pose { case standing, running, ducking, jumping, crashed }

    var pose: Pose {
        switch phase {
        case .ready: return .standing
        case .crashed, .over: return .crashed
        case .running:
            if !isOnGround { return .jumping }
            return isDucking ? .ducking : .running
        }
    }

    /// The dinosaur's hit boxes this frame, slightly inside its outline: a
    /// graze that looks like a miss should be one.
    var dinoBoxes: [CGRect] {
        let feet = groundY - height
        let x = Self.dinoX
        if pose == .ducking {
            return [CGRect(x: x - 12, y: feet - 15, width: 33, height: 13)]
        }
        return [
            CGRect(x: x - 10, y: feet - 21, width: 15, height: 14),
            CGRect(x: x + 2, y: feet - 30, width: 13, height: 9),
            CGRect(x: x - 5, y: feet - 8, width: 9, height: 8),
        ]
    }

    func boxes(of obstacle: Obstacle) -> [CGRect] {
        switch obstacle.kind {
        case .cactus:
            return obstacle.stems.map { stem in
                CGRect(x: obstacle.x + stem.dx + 1.5, y: groundY - stem.height + 2,
                       width: stem.width - 3, height: stem.height - 2)
            }
        case .rock:
            return [CGRect(x: obstacle.x + 2, y: groundY - obstacle.height + 2,
                           width: obstacle.width - 4, height: obstacle.height - 2)]
        case .bird:
            let centreY = groundY - obstacle.altitude
            return [CGRect(x: obstacle.x + 3, y: centreY - 4, width: obstacle.width - 8, height: 9)]
        case .tumbleweed:
            let r = obstacle.width / 2
            return [CGRect(x: obstacle.x + 2.5, y: groundY - obstacle.bounce - 2 * r + 2.5,
                           width: 2 * r - 5, height: 2 * r - 5)]
        }
    }

    // MARK: - Input

    /// The button, the space bar or ↑ going down.
    func press() {
        if isPaused {
            isPaused = false
            lastUpdate = nil
            return
        }
        isHolding = true
        switch phase {
        case .ready:
            start()
            jump()
        case .running:
            if isOnGround {
                jump()
            } else if wingsLeft > 0, !usedDoubleJump {
                doubleJump()
            } else {
                // Pressed a moment too early: jump the instant it lands.
                jumpBufferedUntil = clock + 0.13
            }
        case .crashed:
            break
        case .over:
            // A beat before a click can restart, so the press that was meant
            // as a jump does not skip straight past the score.
            if overAge > 0.45 {
                restart()
                jump()
            }
        }
    }

    func release() {
        isHolding = false
        if phase == .running, velocity > 0, holdTime < Self.maxHold {
            velocity *= Self.jumpCut
            holdTime = Self.maxHold
        }
    }

    func setDucking(_ ducking: Bool) {
        guard phase == .running || !ducking else { return }
        isDucking = ducking
    }

    func togglePause() {
        guard phase == .running || isPaused else { return }
        isPaused.toggle()
        lastUpdate = nil
        if isPaused { persistHighScore() }
    }

    func pauseForClose() {
        guard !isPreview else { return }
        isHolding = false
        isDucking = false
        if phase == .running { isPaused = true }
        lastUpdate = nil
        persistHighScore()
    }

    func resumeAfterOpen() {
        lastUpdate = nil
    }

    /// Cycles through the colours unlocked so far.
    func nextColour() {
        let unlocked = unlockedSkins
        guard unlocked.count > 1 else { return }
        let current = unlocked.firstIndex { $0.name == skin.name } ?? 0
        let next = unlocked[(current + 1) % unlocked.count]
        Settings.shared.dinoSkin = Self.skins.firstIndex { $0.name == next.name } ?? 0
    }

    // MARK: - Lifecycle

    private func start() {
        phase = .running
        bestAtStart = highScore
        beatHighScore = false
        unlockedSkin = nil
    }

    private func restart() {
        exactScore = 0
        distance = 0
        runTime = 0
        speed = Self.startSpeed
        height = 0
        velocity = 0
        squash = 0
        isDucking = false
        usedDoubleJump = false
        obstacles.removeAll()
        gems.removeAll()
        orbs.removeAll()
        particles.removeAll()
        popups.removeAll()
        hasShield = false
        wingsLeft = 0
        magnetLeft = 0
        turboLeft = 0
        graceLeft = 0
        gemsThisRun = 0
        gemRun = 0
        closeCalls = 0
        banner = nil
        nextObstacleIn = 320
        nextOrbIn = 2600
        start()
    }

    private func jump() {
        guard phase == .running else { return }
        velocity = Self.jumpVelocity
        height = max(height, 0.01)
        holdTime = 0
        usedDoubleJump = false
        jumpBufferedUntil = -1
        squash = 1
        puff(count: 4, spread: 30)
        sound.play(.jump)
    }

    private func doubleJump() {
        velocity = Self.doubleJumpVelocity
        holdTime = Self.maxHold
        usedDoubleJump = true
        squash = 0.8
        let feet = CGPoint(x: Self.dinoX, y: groundY - height)
        for index in 0 ..< 10 {
            let angle = Double(index) / 10 * .pi + .pi
            particles.append(Particle(
                position: feet,
                velocity: CGVector(dx: CGFloat(cos(angle)) * 60, dy: CGFloat(-sin(angle)) * 30 + 20),
                life: 0.4, maxLife: 0.4, color: PowerKind.wings.tint, size: 2, gravity: 0, kind: .spark
            ))
        }
        sound.play(.doubleJump)
    }

    // MARK: - Simulation

    func advance(to date: Date, size: CGSize) {
        adopt(size: size)
        let previous = lastUpdate ?? date
        lastUpdate = date
        guard !isPaused else { return }
        var delta = min(date.timeIntervalSince(previous), 1.0 / 30)
        guard delta > 0 else { return }

        // The crash plays out in slow motion.
        if phase == .crashed { delta *= 0.3 }

        // Fixed steps, so the jump is the same height at 60 Hz and 120 Hz.
        let step = 1.0 / 240
        var left = delta
        while left > 0.00001 {
            let dt = min(step, left)
            tick(dt)
            left -= dt
        }
    }

    private func adopt(size: CGSize) {
        guard size.width > 1, size.height > 1, size != boardSize else { return }
        let scale = boardSize.width > 0 ? size.width / boardSize.width : 1
        boardSize = size
        for index in obstacles.indices { obstacles[index].x *= scale }
        for index in gems.indices { gems[index].x *= scale }
        for index in orbs.indices { orbs[index].x *= scale }
        particles.removeAll()
    }

    private func tick(_ dt: Double) {
        clock += dt
        let fdt = CGFloat(dt)

        stepParticles(dt)
        squash *= pow(0.004, dt)
        shake = max(shake - fdt * 14, 0)
        milestoneGlow = max(milestoneGlow - dt * 1.4, 0)
        if bannerLife > 0 {
            bannerLife -= dt
            if bannerLife <= 0 { banner = nil }
        }

        switch phase {
        case .ready:
            return
        case .crashed:
            crashTime += dt
            stepDinoPhysics(dt)
            if crashTime > 0.32 { gameOver() }
            return
        case .over:
            overAge += dt
            stepDinoPhysics(dt)
            return
        case .running:
            break
        }

        runTime += dt
        wingsLeft = max(wingsLeft - dt, 0)
        magnetLeft = max(magnetLeft - dt, 0)
        graceLeft = max(graceLeft - dt, 0)
        if turboLeft > 0 {
            turboLeft = max(turboLeft - dt, 0)
            if turboLeft == 0 { popup("Turbo over", at: dinoCentre, color: PowerKind.turbo.tint) }
        }
        gemRunTimer -= dt
        if gemRunTimer <= 0 { gemRun = 0 }

        // Speed climbs quickly at first and levels off, so the first minute
        // is a warm-up and the fifth is a fight.
        let target = Self.startSpeed + (Self.topSpeed - Self.startSpeed) * CGFloat(1 - exp(-runTime / 110))
        speed = target * (turboLeft > 0 ? 1.55 : 1)
        let travel = speed * fdt
        distance += travel
        stride += Double(travel) / 9

        let before = score
        exactScore += Double(travel) / 22
        if score / 100 > before / 100 {
            milestoneGlow = 1
            sound.play(.milestone)
            if score % 1000 == 0 {
                show("\(score.formatted())!", for: 1.4)
            }
        }
        recordHighScore()

        stepDinoPhysics(dt)
        moveWorld(travel, dt: dt)
        spawn(travel)
        collide()
        collectGems()
        collectOrbs()

        // Dust from the feet while running.
        if isOnGround, !isDucking || Int(clock * 20) % 2 == 0 {
            dustTimer -= dt
            if dustTimer <= 0 {
                dustTimer = max(0.09 - Double(speed - Self.startSpeed) / 6000, 0.04)
                puff(count: 1, spread: 10)
            }
        }
        if turboLeft > 0, Int(clock * 60) % 2 == 0 {
            let hue = (clock * 1.5).truncatingRemainder(dividingBy: 1)
            particles.append(Particle(
                position: CGPoint(x: Self.dinoX - 12, y: groundY - height - CGFloat.random(in: 6 ... 22)),
                velocity: CGVector(dx: -speed * 0.6, dy: CGFloat.random(in: -10 ... 10)),
                life: 0.35, maxLife: 0.35, color: Color(hue: hue, saturation: 0.8, brightness: 1),
                size: 3, gravity: 0, kind: .spark
            ))
        }
    }

    private func stepDinoPhysics(_ dt: Double) {
        let fdt = CGFloat(dt)
        guard height > 0 || velocity > 0 else {
            height = 0
            velocity = 0
            return
        }
        let gravity: CGFloat
        if isDucking, phase == .running {
            gravity = Self.fastFall
        } else if velocity > 0, isHolding, holdTime < Self.maxHold {
            gravity = Self.holdGravity
            holdTime += dt
        } else {
            gravity = Self.gravity
        }
        velocity -= gravity * fdt
        height += velocity * fdt
        if height <= 0 {
            height = 0
            let impact = velocity
            velocity = 0
            land(impact: impact)
        }
    }

    private func land(impact: CGFloat) {
        guard phase == .running else { return }
        squash = -min(Double(-impact) / 700, 1)
        usedDoubleJump = false
        puff(count: 5, spread: 40)
        sound.play(.land)
        if clock <= jumpBufferedUntil {
            jump()
        }
    }

    private func moveWorld(_ travel: CGFloat, dt: Double) {
        let fdt = CGFloat(dt)
        for index in obstacles.indices.reversed() {
            var obstacle = obstacles[index]
            obstacle.age += dt
            switch obstacle.kind {
            case .tumbleweed:
                obstacle.x -= travel * 1.28
                obstacle.spin -= Double(travel * 1.28 / (obstacle.width / 2))
                obstacle.bounceVelocity -= 900 * fdt
                obstacle.bounce += obstacle.bounceVelocity * fdt
                if obstacle.bounce <= 0 {
                    obstacle.bounce = 0
                    obstacle.bounceVelocity = CGFloat.random(in: 150 ... 230)
                }
            case .bird:
                // A pterodactyl flies into the wind: a little faster than the
                // ground moves.
                obstacle.x -= travel * 1.08
            default:
                obstacle.x -= travel
            }
            obstacles[index] = obstacle
            if obstacle.x + obstacle.width < -40 { obstacles.remove(at: index) }
        }

        for index in gems.indices.reversed() {
            gems[index].x -= travel
            if magnetLeft > 0 {
                let target = CGPoint(x: Self.dinoX + 2, y: height + 16)
                let dx = target.x - gems[index].x
                let dy = target.y - gems[index].altitude
                if abs(dx) < 150 {
                    let pull = CGFloat(min(dt * 9, 1))
                    gems[index].x += dx * pull
                    gems[index].altitude += dy * pull
                }
            }
            if gems[index].x < -20 { gems.remove(at: index) }
        }

        for index in orbs.indices.reversed() {
            orbs[index].x -= travel
            orbs[index].age += dt
            if orbs[index].x < -20 { orbs.remove(at: index) }
        }

        for index in popups.indices.reversed() {
            popups[index].life -= dt
            popups[index].position.y -= 22 * fdt
            if popups[index].life <= 0 { popups.remove(at: index) }
        }
    }

    // MARK: - Spawning

    private func spawn(_ travel: CGFloat) {
        nextObstacleIn -= travel
        nextOrbIn -= travel
        guard boardSize.width > 0 else { return }

        if nextObstacleIn <= 0 {
            let spawnX = boardSize.width + 24
            let placed = placePattern(at: spawnX)
            // Room to land and react before the next one, growing with speed;
            // a little less as the run goes on, so it gets busier.
            let difficulty = min(runTime / 240, 1)
            let minimum = speed * 0.64 + 70 + placed
            let extra = CGFloat.random(in: 0 ... speed * CGFloat(0.95 - 0.35 * difficulty))
            nextObstacleIn = minimum + extra
        }

        if nextOrbIn <= 0 {
            // Only into clear air, well away from any obstacle; otherwise try
            // again a little further on.
            nextOrbIn = 120
            if obstacles.allSatisfy({ abs($0.x - boardSize.width) > 110 }) {
                nextOrbIn = CGFloat.random(in: 2600 ... 4200)
                let kinds: [PowerKind] = [.shield, .shield, .wings, .wings, .magnet, .magnet, .turbo]
                orbs.append(Orb(x: boardSize.width + 20, altitude: CGFloat.random(in: 28 ... 44),
                                kind: kinds.randomElement() ?? .shield))
            }
        }
    }

    /// Puts down one obstacle, or a small group, at `x`. Returns how much
    /// width it took up.
    private func placePattern(at x: CGFloat) -> CGFloat {
        let s = score
        var options: [(weight: Int, make: () -> Obstacle)] = [
            (6, { self.cactus(at: x, stems: 1, tall: false) }),
            (3, { self.cactus(at: x, stems: 1, tall: true) }),
            (2, { self.rock(at: x) }),
        ]
        if s > 120 {
            options.append((3, { self.cactus(at: x, stems: 2, tall: Bool.random()) }))
        }
        if s > 350 {
            options.append((2, { self.cactus(at: x, stems: 3, tall: false) }))
            options.append((3, { self.bird(at: x, level: Int.random(in: 0 ... 2)) }))
        }
        if s > 800 {
            options.append((2, { self.tumbleweed(at: x) }))
            options.append((2, { self.bird(at: x, level: 1) }))
        }
        let total = options.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0 ..< total)
        var made = options[0].make
        for option in options {
            if roll < option.weight {
                made = option.make
                break
            }
            roll -= option.weight
        }
        let obstacle = made()
        obstacles.append(obstacle)
        // Gems scroll with the ground, so they go over `x`: where anything
        // faster than the ground will be by the time it reaches the dinosaur.
        placeGems(near: x, width: obstacle.width, for: obstacle)
        return obstacle.width
    }

    /// An arc of gems over whatever has to be jumped, or a row to run through
    /// in the gap after it.
    private func placeGems(near x: CGFloat, width: CGFloat, for obstacle: Obstacle) {
        let groundThing = obstacle.kind != .bird || obstacle.altitude < 20
        if groundThing, obstacle.kind != .tumbleweed, Double.random(in: 0 ..< 1) < 0.33 {
            let apex = CGFloat(obstacle.kind == .cactus && obstacle.height > 28 ? 58 : 48)
            let count = 5
            for index in 0 ..< count {
                let t = CGFloat(index) / CGFloat(count - 1)
                let arc = apex * (1 - (2 * t - 1) * (2 * t - 1))
                gems.append(Gem(x: x + width / 2 + (t - 0.5) * 92, altitude: 12 + arc, seed: nextSeed()))
            }
        } else if Double.random(in: 0 ..< 1) < 0.22 {
            let start = x + width + speed * 0.5
            for index in 0 ..< 4 {
                gems.append(Gem(x: start + CGFloat(index) * 16, altitude: 12, seed: nextSeed()))
            }
        }
    }

    private func nextSeed() -> Int {
        seedCounter = seedCounter &* 1_103_515_245 &+ 12345
        return abs(seedCounter >> 8)
    }

    private func cactus(at x: CGFloat, stems count: Int, tall: Bool) -> Obstacle {
        var stems: [Stem] = []
        var cursor: CGFloat = 0
        for index in 0 ..< count {
            let isTall = tall && (index == 0 || Bool.random())
            let width: CGFloat = isTall ? 10 : 8
            let height: CGFloat = isTall ? CGFloat.random(in: 31 ... 36) : CGFloat.random(in: 18 ... 23)
            stems.append(Stem(
                dx: cursor, width: width, height: height,
                leftArm: Bool.random() || isTall ? CGFloat.random(in: 0.38 ... 0.55) : nil,
                rightArm: Bool.random() ? CGFloat.random(in: 0.5 ... 0.66) : nil,
                flower: Int.random(in: 0 ..< 5) == 0
            ))
            cursor += width + CGFloat.random(in: 3 ... 6)
        }
        let width = cursor - 3
        return Obstacle(kind: .cactus, x: x, width: width, height: stems.map(\.height).max() ?? 20,
                        altitude: 0, stems: stems, seed: nextSeed())
    }

    private func rock(at x: CGFloat) -> Obstacle {
        Obstacle(kind: .rock, x: x, width: CGFloat.random(in: 17 ... 22), height: CGFloat.random(in: 11 ... 14),
                 altitude: 0, seed: nextSeed())
    }

    /// Birds and tumbleweeds move faster than the ground, so they would catch
    /// up with whatever is in front of them and arrive together. Starting
    /// them further out by the same proportion makes them arrive exactly when
    /// something on the ground put down at `x` would.
    private static func arrivingWithGround(_ x: CGFloat, speed factor: CGFloat) -> CGFloat {
        dinoX + (x - dinoX) * factor
    }

    private func bird(at x: CGFloat, level: Int) -> Obstacle {
        Obstacle(kind: .bird, x: Self.arrivingWithGround(x, speed: 1.08), width: 30, height: 10,
                 altitude: Self.birdAltitudes[min(max(level, 0), 2)], seed: nextSeed())
    }

    private func tumbleweed(at x: CGFloat) -> Obstacle {
        Obstacle(kind: .tumbleweed, x: Self.arrivingWithGround(x, speed: 1.28), width: 17, height: 17,
                 altitude: 0, seed: nextSeed(), bounceVelocity: 200)
    }

    // MARK: - Collisions

    private var dinoCentre: CGPoint {
        CGPoint(x: Self.dinoX + 2, y: groundY - height - 16)
    }

    private func collide() {
        let mine = dinoBoxes
        let feet = groundY - height
        let dinoLeft = mine.map(\.minX).min() ?? 0
        for index in obstacles.indices {
            let theirs = boxes(of: obstacles[index])
            let right = theirs.map(\.maxX).max() ?? obstacles[index].x

            // Near misses: the smallest gap between any two boxes that were
            // side by side at the time.
            if !obstacles[index].passed {
                for box in mine {
                    for other in theirs where box.maxX > other.minX && box.minX < other.maxX {
                        let gap = max(other.minY - box.maxY, box.minY - other.maxY)
                        obstacles[index].overlapped = true
                        obstacles[index].closest = min(obstacles[index].closest, gap)
                    }
                }
            }
            if !obstacles[index].passed, right < dinoLeft {
                obstacles[index].passed = true
                if obstacles[index].overlapped, obstacles[index].closest < 4.5, turboLeft == 0 {
                    closeCalls += 1
                    exactScore += 15
                    popup("Close call +15", at: CGPoint(x: Self.dinoX + 10, y: feet - 40),
                          color: Color(red: 1, green: 0.85, blue: 0.4))
                    sound.play(.closeCall)
                }
            }

            guard !obstacles[index].passed,
                  mine.contains(where: { box in theirs.contains { $0.intersects(box) } })
            else { continue }

            if turboLeft > 0 || graceLeft > 0 {
                if turboLeft > 0 { smash(at: index) }
                continue
            }
            if hasShield {
                hasShield = false
                graceLeft = 1.1
                smash(at: index)
                sound.play(.shieldPop)
                popup("Shield saved you", at: CGPoint(x: Self.dinoX + 10, y: feet - 42), color: PowerKind.shield.tint)
                return
            }
            let obstacle = obstacles[index]
            lastCrash = "\(obstacle.kind) alt \(Int(obstacle.altitude)) h \(Int(obstacle.height)) at score \(score); "
                + "dino height \(Int(height)) \(isDucking ? "ducking" : "upright")"
            crash()
            return
        }
    }

    private func smash(at index: Int) {
        let obstacle = obstacles[index]
        obstacles[index].passed = true
        obstacles[index].x = -500
        let centre = CGPoint(x: obstacle.x + obstacle.width / 2,
                             y: groundY - obstacle.altitude - obstacle.height / 2)
        let colour: Color
        switch obstacle.kind {
        case .cactus: colour = Color(red: 0.3, green: 0.72, blue: 0.45)
        case .rock: colour = Color(white: 0.6)
        case .bird: colour = Color(red: 0.62, green: 0.45, blue: 0.9)
        case .tumbleweed: colour = Color(red: 0.72, green: 0.56, blue: 0.34)
        }
        for _ in 0 ..< 14 {
            particles.append(Particle(
                position: centre,
                velocity: CGVector(dx: CGFloat.random(in: 40 ... 220), dy: CGFloat.random(in: -200 ... -40)),
                life: 0.6, maxLife: 0.6, color: colour, size: CGFloat.random(in: 2 ... 4),
                gravity: 700, kind: .chip, angle: Double.random(in: 0 ... 3), spin: Double.random(in: -15 ... 15)
            ))
        }
        exactScore += 25
        popup("Smash +25", at: CGPoint(x: centre.x, y: centre.y - 14), color: PowerKind.turbo.tint)
        shake = max(shake, 2.5)
        sound.play(.smash)
    }

    private func crash() {
        phase = .crashed
        crashTime = 0
        isHolding = false
        isDucking = false
        shake = 6
        // A little hop backwards as it hits.
        velocity = 160
        height = max(height, 0.5)
        sound.play(.crash)
        for _ in 0 ..< 16 {
            particles.append(Particle(
                position: CGPoint(x: Self.dinoX + 10, y: groundY - height - 14),
                velocity: CGVector(dx: CGFloat.random(in: -120 ... 60), dy: CGFloat.random(in: -150 ... -20)),
                life: 0.7, maxLife: 0.7, color: Color(white: 1, opacity: 0.9), size: CGFloat.random(in: 1.5 ... 3),
                gravity: 500, kind: .spark
            ))
        }
    }

    private func gameOver() {
        phase = .over
        overAge = 0
        persistHighScore()
        if !isPreview {
            Settings.shared.dinoGemsTotal += gemsThisRun
        }
        // A colour earned by this run is worth saying so.
        unlockedSkin = Self.skins.last { $0.unlockScore > bestAtStart && $0.unlockScore <= score }
        if beatHighScore || unlockedSkin != nil {
            confetti()
            sound.play(.highScore)
        } else {
            sound.play(.gameOver)
        }
    }

    private func collectGems() {
        let reach = (dinoBoxes.reduce(CGRect.null) { $0.union($1) }).insetBy(dx: -3, dy: -3)
        for index in gems.indices.reversed() {
            let gem = gems[index]
            let box = CGRect(x: gem.x - 4, y: groundY - gem.altitude - 5, width: 8, height: 10)
            guard box.intersects(reach) else { continue }
            gems.remove(at: index)
            gemsThisRun += 1
            gemRun += 1
            gemRunTimer = 1.2
            let points = 5 * min(gemRun, 5)
            exactScore += Double(points)
            sound.play(.gem(min(gemRun - 1, 12)))
            for step in 0 ..< 6 {
                let angle = Double(step) / 6 * 2 * .pi
                particles.append(Particle(
                    position: CGPoint(x: gem.x, y: groundY - gem.altitude),
                    velocity: CGVector(dx: CGFloat(cos(angle)) * 55, dy: CGFloat(sin(angle)) * 55),
                    life: 0.35, maxLife: 0.35, color: Color(red: 0.55, green: 0.95, blue: 1), size: 2,
                    gravity: 0, kind: .spark
                ))
            }
            if gemRun >= 3 {
                popup("+\(points)", at: CGPoint(x: gem.x, y: groundY - gem.altitude - 10),
                      color: Color(red: 0.55, green: 0.95, blue: 1))
            }
        }
    }

    private func collectOrbs() {
        let reach = (dinoBoxes.reduce(CGRect.null) { $0.union($1) }).insetBy(dx: -4, dy: -4)
        for index in orbs.indices.reversed() {
            let orb = orbs[index]
            let box = CGRect(x: orb.x - 8, y: groundY - orb.altitude - 8, width: 16, height: 16)
            guard box.intersects(reach) else { continue }
            orbs.remove(at: index)
            switch orb.kind {
            case .shield: hasShield = true
            case .wings: wingsLeft = PowerKind.wings.duration
            case .magnet: magnetLeft = PowerKind.magnet.duration
            case .turbo:
                turboLeft = PowerKind.turbo.duration
                sound.play(.turbo)
            }
            if orb.kind != .turbo { sound.play(.powerup) }
            popup(orb.kind.name, at: CGPoint(x: orb.x, y: groundY - orb.altitude - 14), color: orb.kind.tint)
            for step in 0 ..< 12 {
                let angle = Double(step) / 12 * 2 * .pi
                particles.append(Particle(
                    position: CGPoint(x: orb.x, y: groundY - orb.altitude),
                    velocity: CGVector(dx: CGFloat(cos(angle)) * 80, dy: CGFloat(sin(angle)) * 80),
                    life: 0.45, maxLife: 0.45, color: orb.kind.tint, size: 2.4, gravity: 0, kind: .spark
                ))
            }
        }
    }

    // MARK: - Scores

    private func recordHighScore() {
        if bestAtStart > 0, score > bestAtStart, !beatHighScore {
            beatHighScore = true
            show("New best!", for: 1.6)
            sound.play(.highScore)
        }
        if score > highScore { highScore = score }
    }

    /// Written at the natural stopping points, not on every frame.
    private func persistHighScore() {
        guard !isPreview else { return }
        if highScore > Settings.shared.dinoHighScore {
            Settings.shared.dinoHighScore = highScore
        }
    }

    private func show(_ text: String, for seconds: Double) {
        banner = text
        bannerLife = seconds
    }

    private func popup(_ text: String, at point: CGPoint, color: Color) {
        popups.append(Popup(position: point, text: text, color: color, life: 0.9, maxLife: 0.9))
        if popups.count > 8 { popups.removeFirst() }
    }

    // MARK: - Particles

    private func stepParticles(_ dt: Double) {
        let fdt = CGFloat(dt)
        for index in particles.indices.reversed() {
            particles[index].life -= dt
            if particles[index].life <= 0 {
                particles.remove(at: index)
                continue
            }
            particles[index].velocity.dy += particles[index].gravity * fdt
            if particles[index].kind == .dust || particles[index].kind == .confetti {
                particles[index].velocity.dx *= CGFloat(pow(0.2, dt))
            }
            particles[index].position.x += particles[index].velocity.dx * fdt
            particles[index].position.y += particles[index].velocity.dy * fdt
            particles[index].angle += particles[index].spin * dt
        }
    }

    /// Dust kicked up by the feet.
    private func puff(count: Int, spread: CGFloat) {
        guard particles.count < 300 else { return }
        let feet = CGPoint(x: Self.dinoX - 4, y: groundY - 1)
        for _ in 0 ..< count {
            let life = Double.random(in: 0.35 ... 0.6)
            particles.append(Particle(
                position: CGPoint(x: feet.x + CGFloat.random(in: -4 ... 6), y: feet.y),
                velocity: CGVector(dx: -speed * 0.35 + CGFloat.random(in: -spread ... spread * 0.3),
                                   dy: CGFloat.random(in: -26 ... -6)),
                life: life, maxLife: life, color: .white, size: CGFloat.random(in: 2.5 ... 4.5),
                gravity: 40, kind: .dust
            ))
        }
    }

    private func confetti() {
        let colours: [Color] = [.pink, .yellow, .cyan, .mint, .orange, .purple]
        for _ in 0 ..< 60 where particles.count < 320 {
            let life = Double.random(in: 1.2 ... 2)
            particles.append(Particle(
                position: CGPoint(x: CGFloat.random(in: 0 ... boardSize.width), y: -4),
                velocity: CGVector(dx: CGFloat.random(in: -40 ... 40), dy: CGFloat.random(in: 20 ... 90)),
                life: life, maxLife: life, color: colours.randomElement() ?? .pink,
                size: CGFloat.random(in: 2.5 ... 4), gravity: 60, kind: .confetti,
                angle: Double.random(in: 0 ... .pi), spin: Double.random(in: -9 ... 9)
            ))
        }
    }

    // MARK: - Overlay text

    var overlayTitle: String? {
        if isPaused { return "Paused" }
        switch phase {
        case .ready: return "Dino Run"
        case .over:
            if let unlockedSkin { return "\(unlockedSkin.name) unlocked!" }
            return beatHighScore ? "New best!" : "Extinct!"
        case .running, .crashed: return nil
        }
    }

    var overlaySubtitle: String {
        if isPaused { return "Click or press Space to carry on" }
        switch phase {
        case .ready: return "Click or press Space to jump · hold for higher · ↓ to duck"
        case .over:
            var parts = ["\(score.formatted()) points"]
            if gemsThisRun > 0 { parts.append("\(gemsThisRun) gem\(gemsThisRun == 1 ? "" : "s")") }
            parts.append(overAge > 0.45 ? "click to run again" : " ")
            return parts.joined(separator: " · ")
        case .running, .crashed: return ""
        }
    }

    // MARK: - Preview and testing

    /// Runs the game against a perfect player so `--render-preview` captures a
    /// run in progress. Nothing is written to settings.
    func playForPreview(seconds: Double, score: Double? = nil, powers: [PowerKind] = [], crash: Bool = false) {
        isPreview = true
        isPaused = false
        let board = CGSize(width: 646, height: 132)
        var clock = Date()
        advance(to: clock, size: board)
        restart()
        if let score {
            exactScore = score
            runTime = score / 12
        }
        for power in powers {
            switch power {
            case .shield: hasShield = true
            case .wings: wingsLeft = power.duration
            case .magnet: magnetLeft = power.duration
            case .turbo: turboLeft = power.duration
            }
        }
        for _ in 0 ..< Int(seconds * 60) {
            autopilot()
            clock += 1.0 / 60
            advance(to: clock, size: board)
        }
        if crash {
            // Stop playing and let the next obstacle do it, then wait out
            // the slow motion so the card is up.
            for _ in 0 ..< 600 where phase == .running {
                if isHolding { release() }
                setDucking(false)
                clock += 1.0 / 60
                advance(to: clock, size: board)
            }
            for _ in 0 ..< 100 {
                clock += 1.0 / 60
                advance(to: clock, size: board)
            }
        }
        highScore = Settings.shared.dinoHighScore
    }

    /// Jumps whatever is coming, ducks the birds at head height, and runs
    /// under the high ones. Used by the preview and the self-test.
    func autopilot() {
        guard phase == .running else { return }
        let ahead = obstacles
            .filter { !$0.passed && $0.x + $0.width > Self.dinoX - 12 }
            .min { $0.x < $1.x }
        guard let next = ahead else {
            if isHolding { release() }
            setDucking(false)
            return
        }
        let gap = next.x - Self.dinoX
        let lead = speed * 0.2 + 8
        if next.kind == .bird {
            if next.altitude >= 45 {
                setDucking(false)
            } else if next.altitude >= 25 {
                setDucking(gap < lead + 30 && gap > -next.width)
            } else if gap < lead, isOnGround {
                press()
            }
        } else if gap < lead, gap > -next.width, isOnGround {
            setDucking(false)
            press()
        }
        if isHolding, holdTime > (next.height > 28 ? 0.2 : 0.09) { release() }
    }

    /// Puts the game into a fresh run at a given speed, for the self-test.
    func startForTesting(size: CGSize) {
        isPreview = true
        lastUpdate = nil
        advance(to: Date(), size: size)
        restart()
        obstacles.removeAll()
        nextObstacleIn = .greatestFiniteMagnitude
        nextOrbIn = .greatestFiniteMagnitude
    }

    /// Steps the simulation by whole frames, for the self-test.
    func stepForTesting(frames: Int) {
        for _ in 0 ..< frames {
            tick(1.0 / 60)
        }
    }

    func placeForTesting(_ kind: ObstacleKind, at x: CGFloat, level: Int = 0, tall: Bool = false) {
        switch kind {
        case .cactus: obstacles.append(cactus(at: x, stems: 1, tall: tall))
        case .rock: obstacles.append(rock(at: x))
        case .bird: obstacles.append(bird(at: x, level: level))
        case .tumbleweed: obstacles.append(tumbleweed(at: x))
        }
    }

    func releaseForTesting() {
        isPreview = false
        restart()
        phase = .ready
        highScore = Settings.shared.dinoHighScore
    }

    func grantForTesting(_ power: PowerKind) {
        switch power {
        case .shield: hasShield = true
        case .wings: wingsLeft = power.duration
        case .magnet: magnetLeft = power.duration
        case .turbo: turboLeft = power.duration
        }
    }

    func placeGemForTesting(x: CGFloat, altitude: CGFloat) {
        gems.append(Gem(x: x, altitude: altitude, seed: nextSeed()))
    }

    func setScoreForTesting(_ score: Double) {
        exactScore = score
    }

    func clearObstaclesForTesting() {
        obstacles.removeAll()
    }
}
