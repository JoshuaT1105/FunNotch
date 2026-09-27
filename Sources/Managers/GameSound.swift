//
//  GameSound.swift
//  FunNotch
//
//  Notch Breakout's sound: square and triangle blips and a noise rumble,
//  synthesised on the spot — the sound chip of the machines the game
//  imitates, with no audio files to ship.
//
//  The engine only runs while the game is on screen, so it never holds the
//  audio hardware awake in the background, and the whole thing is behind a
//  mute button in the game's header.
//

import AVFoundation
import Foundation

@MainActor
final class GameSound {
    static let shared = GameSound()

    enum Effect: Hashable {
        case launch
        case paddle
        /// A brick breaking; the pitch climbs a pentatonic scale with the combo.
        case brick(Int)
        /// A tough brick taking a hit without breaking.
        case crack
        case steel
        case coin
        case boom
        case combo
        case powerup
        case bad
        case laser
        case shield
        case lose
        case levelClear
        case gameOver
        case highScore
    }

    private enum Wave {
        case square
        case triangle
        /// White noise through a one-pole low-pass: a rumble, not a hiss.
        case rumble
    }

    /// One stretch of tone gliding from one pitch to another.
    private struct Note {
        let from: Double
        let to: Double
        let seconds: Double

        init(_ from: Double, _ to: Double? = nil, _ seconds: Double) {
            self.from = from
            self.to = to ?? from
            self.seconds = seconds
        }
    }

    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var cache: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    private init() {}

    var isEnabled: Bool { Settings.shared.gameSoundEnabled }

    // MARK: - Engine

    /// Starts the engine, if sound is on. Called when the game appears.
    func start() {
        guard isEnabled, engine == nil, let format else { return }
        let engine = AVAudioEngine()
        // A few voices, so a brick breaking does not cut off the paddle hit
        // that sent the ball there.
        for _ in 0 ..< 6 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        engine.mainMixerNode.outputVolume = 0.2
        do {
            try engine.start()
        } catch {
            voices.removeAll()
            DiagnosticLog.write("game", "sound unavailable: \(error.localizedDescription)")
            return
        }
        voices.forEach { $0.play() }
        self.engine = engine
    }

    /// Stops the engine and lets the audio hardware go.
    func stop() {
        voices.forEach { $0.stop() }
        engine?.stop()
        engine = nil
        voices.removeAll()
    }

    func play(_ effect: Effect) {
        guard isEnabled, let engine, engine.isRunning, !voices.isEmpty,
              let buffer = buffer(for: effect) else { return }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// Length of an effect in frames. For the self-test: it proves the
    /// synthesis works without having to start the audio engine.
    func frames(of effect: Effect) -> Int {
        Int(buffer(for: effect)?.frameLength ?? 0)
    }

    // MARK: - Synthesis

    private func buffer(for effect: Effect) -> AVAudioPCMBuffer? {
        if let cached = cache[effect] { return cached }
        let made: AVAudioPCMBuffer?
        switch effect {
        case .launch:
            made = synth([Note(392, 784, 0.07)], .square, gain: 0.35)
        case .paddle:
            made = synth([Note(330, 290, 0.055)], .square, gain: 0.45)
        case let .brick(combo):
            // C major pentatonic from C5, one step per brick in the combo:
            // a rally that keeps going plays a rising run.
            let steps = [0, 2, 4, 7, 9]
            let step = min(max(combo - 1, 0), 14)
            let semitones = Double(steps[step % 5] + 12 * (step / 5))
            let pitch = 523.25 * pow(2, semitones / 12)
            made = synth([Note(pitch, pitch * 0.98, 0.05)], .square, gain: 0.32)
        case .crack:
            made = synth([Note(720, 640, 0.045)], .triangle, gain: 0.6)
        case .steel:
            made = synth([Note(1480, 1400, 0.03), Note(2210, 2150, 0.035)], .triangle, gain: 0.45)
        case .coin:
            made = synth([Note(988, 988, 0.05), Note(1319, 1319, 0.12)], .square, gain: 0.3)
        case .boom:
            made = synth([Note(0, 0, 0.32)], .rumble, gain: 1.2)
        case .combo:
            made = synth([Note(784, 784, 0.04), Note(1047, 1047, 0.04), Note(1568, 1568, 0.08)], .square, gain: 0.28)
        case .powerup:
            made = synth([Note(523, 523, 0.045), Note(659, 659, 0.045), Note(784, 784, 0.045), Note(1047, 1047, 0.09)], .triangle, gain: 0.6)
        case .bad:
            made = synth([Note(400, 380, 0.07), Note(300, 280, 0.07), Note(220, 200, 0.12)], .square, gain: 0.35)
        case .laser:
            made = synth([Note(1500, 600, 0.06)], .square, gain: 0.16)
        case .shield:
            made = synth([Note(660, 1320, 0.12)], .triangle, gain: 0.55)
        case .lose:
            made = synth([Note(440, 110, 0.45)], .square, gain: 0.35)
        case .levelClear:
            made = synth([
                Note(523, 523, 0.07), Note(659, 659, 0.07), Note(784, 784, 0.07),
                Note(1047, 1047, 0.07), Note(1319, 1319, 0.22),
            ], .square, gain: 0.3)
        case .gameOver:
            made = synth([Note(392, 392, 0.14), Note(330, 330, 0.14), Note(262, 262, 0.14), Note(196, 180, 0.35)], .square, gain: 0.3)
        case .highScore:
            made = synth([
                Note(784, 784, 0.06), Note(988, 988, 0.06), Note(1175, 1175, 0.06), Note(1568, 1568, 0.06),
                Note(1175, 1175, 0.06), Note(1568, 1568, 0.2),
            ], .triangle, gain: 0.6)
        }
        cache[effect] = made
        return made
    }

    /// Renders notes into a buffer: a 3 ms attack and an exponential decay on
    /// each, so every blip starts clean and dies away instead of clicking off.
    private func synth(_ notes: [Note], _ wave: Wave, gain: Double) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let rate = format.sampleRate
        let total = notes.reduce(0) { $0 + Int($1.seconds * rate) }
        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)

        var phase = 0.0
        var filtered = 0.0
        var generator = SystemRandomNumberGenerator()
        var index = 0
        for note in notes {
            let count = Int(note.seconds * rate)
            for i in 0 ..< count {
                let progress = Double(i) / Double(count)
                let pitch = note.from + (note.to - note.from) * progress
                phase += pitch / rate
                let cycle = phase - phase.rounded(.down)
                let value: Double
                switch wave {
                case .square:
                    value = cycle < 0.5 ? 1 : -1
                case .triangle:
                    value = 4 * abs(cycle - 0.5) - 1
                case .rumble:
                    let noise = Double.random(in: -1 ... 1, using: &generator)
                    filtered += (noise - filtered) * 0.09
                    value = filtered * 3
                }
                let attack = min(Double(i) / (0.003 * rate), 1)
                let decay = exp(-progress * 3.4)
                samples[index] = Float(value * attack * decay * gain * 0.5)
                index += 1
            }
        }
        return buffer
    }
}
