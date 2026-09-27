//
//  GameView.swift
//  FunNotch
//
//  The Game tab: two games behind a switcher — Notch Breakout and Dino Run —
//  each with its own header of lives, power-ups and score over the board.
//  The rules live in BreakoutGame and DinoGame, the drawing in BreakoutBoard
//  and DinoBoard; this is the frame round them and the input.
//
//  Input comes two ways. The mouse always works: the paddle follows the
//  pointer, and a press on the board jumps or launches. The keyboard works
//  once the board has been clicked, which makes the notch panel key without
//  activating the app — so Space, ↑ and ↓ reach the game and nothing else.
//  The keyboard is handed back to whatever had it when the game goes away.
//

import AppKit
import SwiftUI

enum GameChoice: String, CaseIterable, Identifiable {
    case breakout
    case dino

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakout: return "Breakout"
        case .dino: return "Dino Run"
        }
    }

    var symbol: String {
        switch self {
        case .breakout: return "square.grid.3x2.fill"
        case .dino: return "lizard.fill"
        }
    }
}

struct GameView: View {
    @EnvironmentObject private var settings: Settings
    @State private var isPressing = false

    private var choice: GameChoice {
        GameChoice(rawValue: settings.selectedGame) ?? .breakout
    }

    var body: some View {
        // Driven by the display link rather than a Timer: it runs at the screen
        // refresh rate and stops on its own when the notch closes.
        TimelineView(.animation) { timeline in
            VStack(spacing: 6) {
                header
                board(now: timeline.date)
            }
        }
        .padding(.top, 3)
        .onAppear(perform: appear)
        .onDisappear(perform: disappear)
        .onChange(of: settings.selectedGame) { _, _ in
            switchedGame()
        }
    }

    // MARK: Lifecycle

    private func appear() {
        GameSound.shared.start()
        BreakoutGame.shared.resumeAfterOpen()
        DinoGame.shared.resumeAfterOpen()
        if choice == .breakout { followPointer() }
        GameKeyboard.shared.install { event in
            GameKeyboard.route(event, to: GameChoice(rawValue: Settings.shared.selectedGame) ?? .breakout)
        }
        DiagnosticLog.write("game", "\(choice.rawValue) shown")
    }

    private func disappear() {
        MouseTracker.shared.removeMoveObserver("breakout")
        BreakoutGame.shared.pauseForClose()
        DinoGame.shared.pauseForClose()
        GameSound.shared.stop()
        GameKeyboard.shared.remove()
        DiagnosticLog.write("game", "hidden; breakout \(BreakoutGame.shared.score), dino \(DinoGame.shared.score)")
    }

    private func followPointer() {
        MouseTracker.shared.addMoveObserver("breakout") { point in
            BreakoutGame.shared.pointerMoved(to: point)
        }
    }

    /// Whichever game is put away is paused, so switching back finds it
    /// where it was left.
    private func switchedGame() {
        switch choice {
        case .breakout:
            DinoGame.shared.pauseForClose()
            BreakoutGame.shared.resumeAfterOpen()
            followPointer()
        case .dino:
            BreakoutGame.shared.pauseForClose()
            DinoGame.shared.resumeAfterOpen()
            MouseTracker.shared.removeMoveObserver("breakout")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            GamePicker(selection: choice) { picked in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    settings.selectedGame = picked.rawValue
                }
            }

            switch choice {
            case .breakout: BreakoutHUD()
            case .dino: DinoHUD()
            }

            Spacer(minLength: 0)

            switch choice {
            case .breakout:
                let game = BreakoutGame.shared
                ScoreReadout(score: game.score.formatted(), best: game.highScore.formatted(),
                             beaten: game.beatHighScore, glow: 0)
            case .dino:
                let game = DinoGame.shared
                ScoreReadout(score: String(format: "%05d", game.score), best: String(format: "%05d", game.bestScore),
                             beaten: game.beatHighScore, glow: game.milestoneGlow)
                if game.phase == .running || game.isPaused {
                    HeaderButton(symbol: game.isPaused ? "play.fill" : "pause.fill",
                                 help: game.isPaused ? "Carry on" : "Pause (P)") {
                        game.togglePause()
                    }
                }
            }

            HeaderButton(symbol: settings.gameSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         help: settings.gameSoundEnabled ? "Mute" : "Sound on",
                         dimmed: !settings.gameSoundEnabled) {
                settings.gameSoundEnabled.toggle()
                if settings.gameSoundEnabled { GameSound.shared.start() } else { GameSound.shared.stop() }
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 22)
    }

    // MARK: Board

    private func board(now: Date) -> some View {
        ZStack {
            switch choice {
            case .breakout: BreakoutBoard(now: now)
            case .dino: DinoBoard(now: now)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .background(
            // The paddle tracks the pointer in screen coordinates, so the board
            // has to say where on screen it actually is.
            ScreenFrameReader { frame in
                BreakoutGame.shared.boardScreenFrame = frame
            }
        )
        .overlay {
            GameOverlayCard(choice: choice)
        }
        .contentShape(Rectangle())
        // A press, not a click: the jump has to happen when the button goes
        // down, and a held press makes a higher one.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    isPressing = true
                    GameKeyboard.shared.takeFocus()
                    switch choice {
                    case .breakout: BreakoutGame.shared.primaryAction()
                    case .dino: DinoGame.shared.press()
                    }
                }
                .onEnded { _ in
                    isPressing = false
                    if choice == .dino { DinoGame.shared.release() }
                }
        )
    }
}

// MARK: - Keyboard

/// Keys for the games. Only ever active while the Game tab is on screen, and
/// only for events aimed at the notch panel itself.
@MainActor
final class GameKeyboard {
    static let shared = GameKeyboard()

    private var monitor: Any?
    private var handler: ((NSEvent) -> Bool)?
    /// Set once a click has made the panel key, so it is handed back after.
    private var tookFocus = false

    private init() {}

    func install(_ handler: @escaping (NSEvent) -> Bool) {
        self.handler = handler
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            MainActor.assumeIsolated {
                guard event.window is NotchPanel, let handler = GameKeyboard.shared.handler else { return event }
                return handler(event) ? nil : event
            }
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        handler = nil
        guard tookFocus else { return }
        tookFocus = false
        // After the notch has finished closing, so the panel is not hidden and
        // shown again in the middle of its animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            NotchPanel.relinquishKeyFocus()
        }
    }

    /// Makes the notch panel under the pointer the key window, so keys reach
    /// the game. It is a non-activating panel: the app you were in stays the
    /// active one.
    func takeFocus() {
        let point = NSEvent.mouseLocation
        guard let panel = NSApp.windows
            .compactMap({ $0 as? NotchPanel })
            .first(where: { $0.isVisible && $0.frame.contains(point) }),
            !panel.isKeyWindow
        else { return }
        panel.makeKey()
        tookFocus = true
    }

    /// Sends a key to the game. Returns true if the game used it.
    static func route(_ event: NSEvent, to choice: GameChoice) -> Bool {
        // Leave shortcuts alone.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let down = event.type == .keyDown
        switch choice {
        case .dino:
            let game = DinoGame.shared
            switch event.keyCode {
            case 49, 126, 13: // space, up, W
                if down {
                    if !event.isARepeat { game.press() }
                } else {
                    game.release()
                }
                return true
            case 125, 1: // down, S
                game.setDucking(down)
                return true
            case 35, 53: // P, escape
                if down, !event.isARepeat { game.togglePause() }
                return true
            case 36: // return
                if down, !event.isARepeat, game.phase != .running {
                    game.press()
                    game.release()
                }
                return true
            default:
                // Swallowed: with nothing to type into, any other key would
                // only make the panel beep.
                return true
            }
        case .breakout:
            let game = BreakoutGame.shared
            switch event.keyCode {
            case 49, 36: // space, return
                if down, !event.isARepeat { game.primaryAction() }
                return true
            case 35, 53: // P, escape
                if down, !event.isARepeat, game.phase == .running || game.isPaused { game.primaryAction() }
                return true
            default:
                return true
            }
        }
    }
}

extension NotchPanel {
    /// Gives the keyboard back to the app that had it. A panel that has been
    /// made key keeps the keyboard until something else is clicked, so a
    /// sentence typed after closing the notch would otherwise vanish into it.
    /// Ordering it out and straight back in has the window server hand key
    /// status back to the active app's window.
    static func relinquishKeyFocus() {
        for controller in NotchWindowManager.shared.controllers where controller.panel.isKeyWindow {
            // Only once the notch has closed: if the game was put away for
            // another tab, that tab may want the keyboard itself.
            guard controller.viewModel.notchState == .closed else { continue }
            controller.panel.orderOut(nil)
            controller.panel.orderFrontRegardless()
            DiagnosticLog.write("game", "keyboard handed back")
        }
    }
}

// MARK: - Header pieces

private struct GamePicker: View {
    let selection: GameChoice
    let choose: (GameChoice) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 1) {
            ForEach(GameChoice.allCases) { game in
                let selected = game == selection
                Button {
                    choose(game)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: game.symbol)
                            .font(.system(size: 9, weight: .semibold))
                        Text(game.title)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selected ? .white : .white.opacity(0.5))
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                                .matchedGeometryEffect(id: "game", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(1.5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }
}

/// A power-up's icon inside a ring that drains as it runs out.
private struct EffectGauge: View {
    let symbol: String
    let tint: Color
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: 1.6)
            Circle()
                .trim(from: 0, to: max(min(fraction, 1), 0))
                .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 15, height: 15)
        .shadow(color: tint.opacity(0.5), radius: 2)
    }
}

private struct BreakoutHUD: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        let game = BreakoutGame.shared
        HStack(spacing: 7) {
            Text("Level \(game.level)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .help(game.boardName)

            HStack(spacing: 3) {
                ForEach(0 ..< max(game.lives, 0), id: \.self) { _ in
                    Circle()
                        .fill(RadialGradient(colors: [.white, settings.accentColor], center: .topLeading,
                                             startRadius: 0, endRadius: 6))
                        .frame(width: 6, height: 6)
                        .shadow(color: settings.accentColor.opacity(0.7), radius: 2)
                }
            }

            let running: [(BreakoutGame.PowerupKind, Double)] = [
                (.wide, game.wideTimeLeft), (.shrink, game.shrinkTimeLeft), (.slow, game.slowTimeLeft),
                (.fireball, game.fireTimeLeft), (.laser, game.laserTimeLeft), (.shield, game.shieldTimeLeft),
            ].filter { $0.1 > 0 }
            ForEach(Array(running.enumerated()), id: \.offset) { _, effect in
                EffectGauge(symbol: effect.0.symbol, tint: effect.0.tint, fraction: effect.1 / effect.0.duration)
            }

            if game.multiplier > 1, game.phase == .running {
                Text("×\(game.multiplier)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(BreakoutGame.comboColour(game.multiplier))
                    .shadow(color: BreakoutGame.comboColour(game.multiplier).opacity(0.7), radius: 3)
                    .scaleEffect(1 + 0.08 * sin(game.clock * 10))
            }
        }
    }
}

private struct DinoHUD: View {
    var body: some View {
        let game = DinoGame.shared
        HStack(spacing: 7) {
            if game.gemsThisRun > 0 || game.phase == .running {
                HStack(spacing: 3) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 0.7, green: 1, blue: 1),
                                                                 Color(red: 0.25, green: 0.6, blue: 1)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text("\(game.gemsThisRun)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            if game.hasShield {
                EffectGauge(symbol: DinoGame.PowerKind.shield.symbol, tint: DinoGame.PowerKind.shield.tint, fraction: 1)
            }
            if game.wingsLeft > 0 {
                EffectGauge(symbol: DinoGame.PowerKind.wings.symbol, tint: DinoGame.PowerKind.wings.tint,
                            fraction: game.wingsLeft / DinoGame.PowerKind.wings.duration)
            }
            if game.magnetLeft > 0 {
                EffectGauge(symbol: DinoGame.PowerKind.magnet.symbol, tint: DinoGame.PowerKind.magnet.tint,
                            fraction: game.magnetLeft / DinoGame.PowerKind.magnet.duration)
            }
            if game.turboLeft > 0 {
                EffectGauge(symbol: DinoGame.PowerKind.turbo.symbol, tint: DinoGame.PowerKind.turbo.tint,
                            fraction: game.turboLeft / DinoGame.PowerKind.turbo.duration)
            }
            if game.phase != .running {
                ColourButton()
            }
        }
    }
}

/// The dinosaur's colour; click for the next one unlocked.
private struct ColourButton: View {
    @State private var isHovering = false

    var body: some View {
        let game = DinoGame.shared
        let skin = game.skin
        Button {
            game.nextColour()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: [skin.top, skin.bottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.6))
                Text(skin.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isHovering ? 0.9 : 0.55))
            }
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(Capsule().fill(Color.white.opacity(isHovering ? 0.12 : 0.05)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .help(colourHelp(game))
    }

    @MainActor private func colourHelp(_ game: DinoGame) -> String {
        var parts = ["Change colour"]
        if let next = game.nextSkin {
            parts.append("score \(next.unlockScore.formatted()) to unlock \(next.name)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ScoreReadout: View {
    let score: String
    let best: String
    let beaten: Bool
    /// Lights the score up for a moment, at a milestone.
    let glow: Double

    @EnvironmentObject private var settings: Settings

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(score)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(glow > 0.01
                                 ? Color(red: 1, green: 0.85 + 0.15 * (1 - glow), blue: 0.4 + 0.6 * (1 - glow))
                                 : .white)
                .scaleEffect(1 + 0.12 * glow, anchor: .trailing)
                .shadow(color: Color(red: 1, green: 0.8, blue: 0.3).opacity(glow * 0.8), radius: 4)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("BEST")
                    .font(.system(size: 7.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.35))
                Text(best)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(beaten ? Color(red: 1, green: 0.8, blue: 0.3) : settings.accentColor)
            }
        }
    }
}

private struct HeaderButton: View {
    let symbol: String
    let help: String
    var dimmed = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(dimmed ? 0.4 : (isHovering ? 0.95 : 0.7)))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .help(help)
    }
}

// MARK: - Overlay

/// Title, paused and game-over cards, over the middle of the board.
private struct GameOverlayCard: View {
    let choice: GameChoice

    @EnvironmentObject private var settings: Settings

    private struct Content {
        let title: String
        let subtitle: String
        let detail: String?
        let celebrate: Bool
    }

    var body: some View {
        Group {
            if let content {
                VStack(spacing: 3) {
                    Text(content.title)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(content.celebrate
                                         ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.35),
                                                                                 Color(red: 1, green: 0.45, blue: 0.55)],
                                                                        startPoint: .leading, endPoint: .trailing))
                                         : AnyShapeStyle(Color.white))
                    Text(content.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    if let detail = content.detail {
                        Text(detail)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 1)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: content?.title)
        .allowsHitTesting(false)
    }

    private var content: Content? {
        switch choice {
        case .breakout:
            let game = BreakoutGame.shared
            guard let title = game.overlayTitle else { return nil }
            let over = game.phase == .over && !game.isPaused
            return Content(
                title: title,
                subtitle: game.overlaySubtitle,
                detail: over ? "Best level \(game.bestLevel) · best score \(game.highScore.formatted())" : nil,
                celebrate: over && game.beatHighScore
            )
        case .dino:
            let game = DinoGame.shared
            guard let title = game.overlayTitle else { return nil }
            var detail: String?
            if !game.isPaused, game.phase == .ready || game.phase == .over {
                var parts: [String] = []
                if game.bestScore > 0 { parts.append("Best \(game.bestScore.formatted())") }
                if settings.dinoGemsTotal > 0 { parts.append("\(settings.dinoGemsTotal.formatted()) gems in all") }
                if let next = game.nextSkin { parts.append("\(next.name) colour at \(next.unlockScore.formatted())") }
                detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
            }
            let over = game.phase == .over && !game.isPaused
            return Content(
                title: title,
                subtitle: game.overlaySubtitle,
                detail: detail,
                celebrate: (over && (game.beatHighScore || game.unlockedSkin != nil)) || (game.phase == .ready && !game.isPaused)
            )
        }
    }
}

// MARK: - Screen frame

/// Reports its own rectangle in screen coordinates. SwiftUI's hover callbacks
/// cannot be used for this: the notch panel is never the active app, so the
/// pointer has to come from the global tracker and be mapped in by hand.
struct ScreenFrameReader: NSViewRepresentable {
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
