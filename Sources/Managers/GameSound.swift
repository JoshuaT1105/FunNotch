//
//  GameSound.swift
//  FunNotch
//
//  The games' sound, synthesised on the spot so there are no audio files to
//  ship: marimba plucks for bricks, FM bells for coins and gems, filtered
//  noise for whooshes and thumps. Each effect is a few layers mixed into one
//  buffer the first time it is played, then cached.
//
//  The engine only runs while a game is on screen, so it never holds the
//  audio hardware awake in the background, and the whole thing is behind a
//  mute button in the game's header.
//

import AVFoundation
import Foundation

@MainActor
final class GameSound {
    static let shared = GameSound()

    enum Effect: Hashable {
        // Breakout
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

        // Dino Run
        case jump
        case doubleJump
        case land
        /// A gem, pitched up the scale by how many have been caught in a row.
        case gem(Int)
        case closeCall
        case milestone
        case shieldPop
        case crash
        case smash
        case turbo
    }

    private enum Wave {
        case sine
        case triangle
        /// A square with its corners rounded off: warm rather than buzzy.
        case soft
        /// White noise through a low-pass that can sweep.
        case noise
    }

    /// One voice in an effect: a tone, or noise, gliding from one pitch to
    /// another under its own envelope.
    private struct Layer {
        var wave: Wave
        var from: Double
        var to: Double
        /// Seconds into the effect this layer starts.
        var at: Double = 0
        var length: Double
        var gain: Double
        var attack: Double = 0.003
        /// How quickly it dies away over its length: higher is shorter.
        var decay: Double = 4
        /// Frequency modulation, for bells: the modulator's pitch as a multiple
        /// of the carrier's, and how deep it goes. The depth fades with the
        /// envelope, which is what makes a struck bell mellow as it rings.
        var fmRatio: Double = 0
        var fmIndex: Double = 0
        /// Low-pass cutoff for noise, sweeping from one to the other.
        var cutoff: Double = 4000
        var cutoffTo: Double?
        /// Pitch wobble: depth in Hz and rate.
        var vibrato: Double = 0
        var vibratoRate: Double = 7
    }

    private var engine: AVAudioEngine?
    private var voices: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var cache: [Effect: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)

    private init() {}

    var isEnabled: Bool { Settings.shared.gameSoundEnabled }

    // MARK: - Engine

    /// Starts the engine, if sound is on. Called when a game appears.
    func start() {
        guard isEnabled, engine == nil, let format else { return }
        let engine = AVAudioEngine()
        // Several voices, so a brick breaking does not cut off the paddle hit
        // that sent the ball there.
        for _ in 0 ..< 8 {
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
            voices.append(voice)
        }
        engine.mainMixerNode.outputVolume = 0.32
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

    /// Writes an effect to a WAV file, for the film renderer's soundtrack.
    func writeWAV(_ effect: Effect, to url: URL) throws {
        guard let buffer = buffer(for: effect) else { return }
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }

    /// The loudest sample in an effect, for the self-test: nothing may clip.
    func peak(of effect: Effect) -> Float {
        guard let buffer = buffer(for: effect), let samples = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for index in 0 ..< Int(buffer.frameLength) { peak = max(peak, abs(samples[index])) }
        return peak
    }

    // MARK: - Recipes

    /// C major pentatonic from a root, one step per count: a rally or a run of
    /// gems plays a rising line.
    private static func pentatonic(_ root: Double, step: Int) -> Double {
        let steps = [0, 2, 4, 7, 9]
        let step = min(max(step, 0), 14)
        let semitones = Double(steps[step % 5] + 12 * (step / 5))
        return root * pow(2, semitones / 12)
    }

    private static func bell(_ pitch: Double, at: Double = 0, length: Double = 0.4, gain: Double = 0.4,
                             ratio: Double = 2, index: Double = 1.4) -> Layer {
        Layer(wave: .sine, from: pitch, to: pitch, at: at, length: length, gain: gain,
              attack: 0.002, decay: 5, fmRatio: ratio, fmIndex: index)
    }

    /// A struck wooden bar: the fundamental plus the bright fourth harmonic
    /// that dies away first.
    private static func marimba(_ pitch: Double, at: Double = 0, gain: Double = 0.55) -> [Layer] {
        [
            Layer(wave: .sine, from: pitch, to: pitch, at: at, length: 0.24, gain: gain, attack: 0.002, decay: 7),
            Layer(wave: .sine, from: pitch * 4, to: pitch * 4, at: at, length: 0.06, gain: gain * 0.22,
                  attack: 0.001, decay: 9),
            Layer(wave: .noise, from: 0, to: 0, at: at, length: 0.012, gain: gain * 0.25, attack: 0.001,
                  decay: 6, cutoff: 5000),
        ]
    }

    private func recipe(for effect: Effect) -> (layers: [Layer], echo: Double) {
        switch effect {
        // Breakout
        case .launch:
            return ([
                Layer(wave: .sine, from: 480, to: 980, length: 0.1, gain: 0.5, decay: 4),
                Layer(wave: .triangle, from: 960, to: 1960, length: 0.08, gain: 0.08, decay: 5),
            ], 0)
        case .paddle:
            return ([
                Layer(wave: .sine, from: 240, to: 150, length: 0.09, gain: 0.85, attack: 0.001, decay: 6),
                Layer(wave: .noise, from: 0, to: 0, length: 0.018, gain: 0.25, attack: 0.001, decay: 6, cutoff: 2600),
            ], 0)
        case let .brick(combo):
            return (Self.marimba(Self.pentatonic(523.25, step: combo - 1)), 0)
        case .crack:
            return ([
                Layer(wave: .triangle, from: 880, to: 660, length: 0.05, gain: 0.45, attack: 0.001, decay: 8),
                Layer(wave: .noise, from: 0, to: 0, length: 0.03, gain: 0.22, attack: 0.001, decay: 7, cutoff: 3200),
            ], 0)
        case .steel:
            return ([
                Self.bell(1480, length: 0.34, gain: 0.3, ratio: 3.5, index: 2.6),
                Self.bell(2210, length: 0.18, gain: 0.12, ratio: 1.4, index: 1.2),
            ], 0)
        case .coin:
            return ([
                Self.bell(1318.5, length: 0.12, gain: 0.34),
                Self.bell(1760, at: 0.075, length: 0.45, gain: 0.36),
            ], 0.11)
        case .boom:
            return ([
                Layer(wave: .sine, from: 120, to: 34, length: 0.55, gain: 0.95, attack: 0.002, decay: 3.4),
                Layer(wave: .noise, from: 0, to: 0, length: 0.5, gain: 0.8, attack: 0.002, decay: 4.5,
                      cutoff: 1400, cutoffTo: 280),
                Layer(wave: .noise, from: 0, to: 0, length: 0.05, gain: 0.3, attack: 0.001, decay: 5, cutoff: 6000),
            ], 0)
        case .combo:
            return ([
                Self.bell(783.99, length: 0.2, gain: 0.3),
                Self.bell(1046.5, at: 0.06, length: 0.2, gain: 0.3),
                Self.bell(1567.98, at: 0.12, length: 0.4, gain: 0.32),
            ], 0.12)
        case .powerup:
            return ([
                Self.bell(1046.5, length: 0.16, gain: 0.26, ratio: 1, index: 0.6),
                Self.bell(1318.5, at: 0.05, length: 0.16, gain: 0.26, ratio: 1, index: 0.6),
                Self.bell(1567.98, at: 0.1, length: 0.16, gain: 0.26, ratio: 1, index: 0.6),
                Self.bell(2093, at: 0.15, length: 0.42, gain: 0.3, ratio: 1, index: 0.8),
            ], 0.1)
        case .bad:
            return ([
                Layer(wave: .soft, from: 420, to: 180, length: 0.42, gain: 0.26, decay: 2.5, vibrato: 18, vibratoRate: 11),
                Layer(wave: .sine, from: 210, to: 90, length: 0.42, gain: 0.35, decay: 2.5),
            ], 0)
        case .laser:
            return ([
                Layer(wave: .sine, from: 1900, to: 420, length: 0.1, gain: 0.3, attack: 0.001, decay: 4),
                Layer(wave: .soft, from: 1900, to: 420, length: 0.07, gain: 0.05, attack: 0.001, decay: 5),
            ], 0)
        case .shield:
            return ([
                Layer(wave: .sine, from: 380, to: 1300, length: 0.28, gain: 0.35, attack: 0.01, decay: 3),
                Layer(wave: .noise, from: 0, to: 0, length: 0.28, gain: 0.2, attack: 0.04, decay: 3,
                      cutoff: 600, cutoffTo: 6000),
            ], 0)
        case .lose:
            return ([
                Layer(wave: .sine, from: 560, to: 120, length: 0.7, gain: 0.6, attack: 0.005, decay: 2.2,
                      vibrato: 10, vibratoRate: 6),
                Layer(wave: .triangle, from: 280, to: 60, length: 0.7, gain: 0.15, decay: 2.2),
            ], 0)
        case .levelClear:
            let notes = [1046.5, 1318.5, 1567.98, 2093, 2637]
            return (notes.enumerated().map { index, pitch in
                Self.bell(pitch, at: Double(index) * 0.07, length: index == notes.count - 1 ? 0.7 : 0.25,
                          gain: 0.28, ratio: 2, index: 1)
            }, 0.13)
        case .gameOver:
            let notes = [392.0, 329.63, 261.63, 196.0]
            return (notes.enumerated().flatMap { index, pitch in
                [
                    Layer(wave: .sine, from: pitch, to: pitch * (index == 3 ? 0.97 : 1), at: Double(index) * 0.17,
                          length: index == 3 ? 0.8 : 0.3, gain: 0.45, attack: 0.004, decay: 3),
                    Layer(wave: .triangle, from: pitch * 2, to: pitch * 2, at: Double(index) * 0.17,
                          length: 0.2, gain: 0.06, decay: 5),
                ]
            }, 0.15)
        case .highScore:
            let notes = [783.99, 987.77, 1174.66, 1567.98, 1174.66, 1567.98]
            return (notes.enumerated().map { index, pitch in
                Self.bell(pitch, at: Double(index) * 0.075, length: index == notes.count - 1 ? 0.8 : 0.22,
                          gain: 0.3, ratio: 2, index: 1.2)
            }, 0.13)

        // Dino Run
        case .jump:
            return ([
                Layer(wave: .sine, from: 300, to: 640, length: 0.13, gain: 0.42, attack: 0.002, decay: 4),
                Layer(wave: .triangle, from: 600, to: 1280, length: 0.09, gain: 0.07, decay: 5),
            ], 0)
        case .doubleJump:
            return ([
                Layer(wave: .sine, from: 460, to: 1020, length: 0.13, gain: 0.4, attack: 0.002, decay: 4),
                Self.bell(2093, at: 0.03, length: 0.2, gain: 0.12, ratio: 3, index: 0.8),
            ], 0.08)
        case .land:
            return ([
                Layer(wave: .sine, from: 150, to: 80, length: 0.07, gain: 0.35, attack: 0.001, decay: 7),
                Layer(wave: .noise, from: 0, to: 0, length: 0.05, gain: 0.14, attack: 0.001, decay: 6, cutoff: 1300),
            ], 0)
        case let .gem(run):
            return ([
                Self.bell(Self.pentatonic(1318.5, step: run), length: 0.3, gain: 0.3, ratio: 3, index: 0.9),
                Layer(wave: .sine, from: Self.pentatonic(2637, step: run), to: Self.pentatonic(2637, step: run),
                      length: 0.08, gain: 0.08, decay: 6),
            ], 0.09)
        case .closeCall:
            return ([
                Layer(wave: .noise, from: 0, to: 0, length: 0.32, gain: 0.5, attack: 0.07, decay: 3,
                      cutoff: 500, cutoffTo: 5200),
                Self.bell(1760, at: 0.06, length: 0.22, gain: 0.12, ratio: 2, index: 0.6),
            ], 0)
        case .milestone:
            return ([
                Self.bell(1760, length: 0.16, gain: 0.3),
                Self.bell(2637, at: 0.11, length: 0.5, gain: 0.32),
            ], 0.12)
        case .shieldPop:
            return ([
                Layer(wave: .noise, from: 0, to: 0, length: 0.14, gain: 0.35, attack: 0.001, decay: 4, cutoff: 7000),
                Self.bell(2400, length: 0.34, gain: 0.22, ratio: 1.41, index: 2.4),
                Self.bell(3100, at: 0.02, length: 0.24, gain: 0.12, ratio: 1.41, index: 2),
            ], 0.08)
        case .crash:
            return ([
                Layer(wave: .sine, from: 190, to: 40, length: 0.45, gain: 0.9, attack: 0.001, decay: 4),
                Layer(wave: .noise, from: 0, to: 0, length: 0.32, gain: 0.6, attack: 0.001, decay: 4.5,
                      cutoff: 2200, cutoffTo: 300),
            ], 0)
        case .smash:
            return ([
                Layer(wave: .noise, from: 0, to: 0, length: 0.2, gain: 0.55, attack: 0.001, decay: 4.5,
                      cutoff: 4200, cutoffTo: 600),
                Layer(wave: .sine, from: 320, to: 70, length: 0.22, gain: 0.55, attack: 0.001, decay: 5),
            ], 0)
        case .turbo:
            return ([
                Layer(wave: .sine, from: 300, to: 1200, length: 0.45, gain: 0.4, attack: 0.01, decay: 2),
                Layer(wave: .soft, from: 150, to: 600, length: 0.45, gain: 0.08, attack: 0.01, decay: 2,
                      vibrato: 20, vibratoRate: 14),
                Self.bell(2349, at: 0.3, length: 0.5, gain: 0.2),
            ], 0.12)
        }
    }

    // MARK: - Synthesis

    private func buffer(for effect: Effect) -> AVAudioPCMBuffer? {
        if let cached = cache[effect] { return cached }
        let (layers, echo) = recipe(for: effect)
        let made = render(layers, echo: echo)
        cache[effect] = made
        return made
    }

    /// Mixes the layers into one buffer. An echo, where asked for, repeats the
    /// whole thing a few times, quieter each time: a small room, which is most
    /// of the difference between a bell and a beep.
    private func render(_ layers: [Layer], echo: Double) -> AVAudioPCMBuffer? {
        guard let format, !layers.isEmpty else { return nil }
        let rate = format.sampleRate
        let dry = layers.map { $0.at + $0.length }.max() ?? 0
        let tail = echo > 0 ? echo * 4 : 0
        let total = Int((dry + tail) * rate) + 1
        guard total > 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)

        var mix = [Double](repeating: 0, count: total)
        var generator = SystemRandomNumberGenerator()

        for layer in layers {
            let start = Int(layer.at * rate)
            let count = Int(layer.length * rate)
            var phase = 0.0
            var modPhase = 0.0
            var filtered = 0.0
            for i in 0 ..< count where start + i < total {
                let t = Double(i) / rate
                let progress = Double(i) / Double(count)
                // Exponential glides sound like pitch; linear ones sound like
                // a siren.
                var pitch = layer.from > 0 && layer.to > 0
                    ? layer.from * pow(layer.to / layer.from, progress)
                    : layer.from + (layer.to - layer.from) * progress
                if layer.vibrato > 0 {
                    pitch += layer.vibrato * sin(2 * .pi * layer.vibratoRate * t)
                }

                let envelope = min(t / max(layer.attack, 0.0005), 1)
                    * exp(-layer.decay * progress)
                    * min(Double(count - i) / (0.004 * rate), 1)

                let value: Double
                switch layer.wave {
                case .sine, .triangle, .soft:
                    phase += pitch / rate
                    var modulation = 0.0
                    if layer.fmIndex > 0 {
                        modPhase += pitch * layer.fmRatio / rate
                        modulation = layer.fmIndex * envelope * sin(2 * .pi * modPhase)
                    }
                    let angle = 2 * .pi * phase + modulation
                    switch layer.wave {
                    case .sine: value = sin(angle)
                    case .triangle: value = 2 / .pi * asin(sin(angle))
                    default: value = tanh(2.6 * sin(angle)) / tanh(2.6)
                    }
                case .noise:
                    let cutoff = layer.cutoffTo.map { layer.cutoff * pow($0 / layer.cutoff, progress) } ?? layer.cutoff
                    let coefficient = 1 - exp(-2 * .pi * cutoff / rate)
                    filtered += (Double.random(in: -1 ... 1, using: &generator) - filtered) * coefficient
                    // Low-passing takes the level down; put some of it back.
                    value = filtered * min(2.4, 1 / max(coefficient, 0.05).squareRoot())
                }
                mix[start + i] += value * envelope * layer.gain
            }
        }

        if echo > 0 {
            let delay = Int(echo * rate)
            for index in delay ..< total {
                mix[index] += mix[index - delay] * 0.28
            }
        }

        // Soft-clip rather than let a big explosion wrap round into noise.
        for index in 0 ..< total {
            samples[index] = Float(tanh(mix[index] * 0.9))
        }
        return buffer
    }
}
