//
//  PixelWeatherView.swift
//  FunNotch
//
//  Retro pixel weather, drawn behind the temperature on the home tab: a small
//  landscape with a cabin and a few pines, under whatever sky the forecast
//  says. Birds cross a clear day, stars twinkle and the odd one falls at
//  night, lightning forks down to the hills in a storm, the cabin's windows
//  light up when it is dark or wet, and its chimney smokes when it is cold.
//
//  Everything is snapped to a coarse grid and drawn as flat rectangles: no
//  gradients, no blur, no anti-aliased curves. Skies are banded the way old
//  consoles banded them, with a checkerboard where two bands meet. Chunky
//  pixels read as deliberate; the same shapes drawn smoothly at this size just
//  look like a low-resolution mistake.
//
//  Particle positions come from a seeded hash rather than `random()`, so a
//  raindrop keeps its lane between frames instead of teleporting, and a frame
//  is a pure function of time: the same moment draws the same picture on every
//  Mac, which is what lets the snapshot renderer check the motion frame by
//  frame.
//
//  A frame is a couple of thousand pixels. They are collected by colour and
//  filled as one path per colour, so it costs dozens of fills, not thousands.
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

struct PixelWeatherView: View {
    let scene: WeatherScene
    /// Darker skies, lit windows. Clear weather already knows; everything else
    /// is told.
    var isNight = false
    /// Draw this moment instead of following the clock.
    var time: Double?

    /// Set by the snapshot renderer, so every scene is drawn at a known moment.
    nonisolated(unsafe) static var frozenTime: Double?

    var body: some View {
        if let fixed = time ?? Self.frozenTime {
            canvas(at: fixed)
        } else {
            // Thirty frames a second: enough for rain to fall smoothly, and the
            // pane is only on screen while the notch is open.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                canvas(at: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(at t: Double) -> some View {
        Canvas { context, size in
            WeatherPainter(scene: scene, night: isNight, t: t, size: size).draw(into: &context)
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }

    /// The next moment a lightning bolt is at full brightness, for the
    /// snapshot renderer.
    static func nextStrike(after t: Double) -> Double? {
        var probe = t
        while probe < t + 120 {
            let painter = WeatherPainter(scene: .storm, night: true, t: probe, size: CGSize(width: 420, height: 100))
            if let strike = painter.strike, strike.hasBolt, strike.brightness > 0.9 { return probe }
            probe += 0.01
        }
        return nil
    }

    /// The next moment a shooting star is halfway across, for the snapshot
    /// renderer.
    static func nextMeteor(after t: Double) -> Double? {
        var probe = t
        while probe < t + 120 {
            let painter = WeatherPainter(scene: .clearNight, night: true, t: probe, size: CGSize(width: 420, height: 100))
            if let age = painter.meteorAge, age > 0.3, age < 0.4 { return probe }
            probe += 0.01
        }
        return nil
    }
}

// MARK: - Pixels

/// Deterministic noise. Same input, same output, on every machine and frame.
private func hash01(_ n: Int) -> Double {
    var x = UInt64(bitPattern: Int64(n &* 0x27D4_EB2D))
    x ^= x >> 15
    x = x &* 0x2545_F491_4F6C_DD1D
    x ^= x >> 21
    return Double(x % 100_000) / 100_000
}

/// Ordered dithering, the 4×4 Bayer matrix: whether a cell of a surface with
/// the given coverage is drawn.
private func dithered(_ gx: Int, _ gy: Int, _ coverage: Double) -> Bool {
    let matrix: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    let index = ((gy % 4 + 4) % 4) * 4 + (gx % 4 + 4) % 4
    return coverage > (matrix[index] + 0.5) / 16
}

private struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mix(_ other: RGB, _ amount: Double) -> RGB {
        let k = min(max(amount, 0), 1)
        return RGB(r + (other.r - r) * k, g + (other.g - g) * k, b + (other.b - b) * k)
    }

    func scaled(_ k: Double) -> RGB { RGB(r * k, g * k, b * k) }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)
}

/// Rectangles in grid cells, collected by colour and filled one path per
/// colour. Within a layer, draw order between colours is not kept, so each
/// layer holds things that do not overlap much; layers are flushed in order.
private struct PixelLayer {
    let cell: CGFloat
    private var order: [UInt64] = []
    private var paths: [UInt64: (RGB, Double, Path)] = [:]

    init(cell: CGFloat) {
        self.cell = cell
    }

    mutating func fill(_ gx: Int, _ gy: Int, _ width: Int = 1, _ height: Int = 1, _ colour: RGB, _ alpha: Double = 1) {
        guard width > 0, height > 0, alpha > 0.012 else { return }
        let a = min(alpha, 1)
        let key = Self.key(colour, a)
        let rect = CGRect(
            x: CGFloat(gx) * cell, y: CGFloat(gy) * cell,
            width: CGFloat(width) * cell, height: CGFloat(height) * cell
        )
        if paths[key] == nil {
            order.append(key)
            paths[key] = (colour, a, Path())
        }
        paths[key]?.2.addRect(rect)
    }

    mutating func flush(into context: inout GraphicsContext) {
        for key in order {
            guard let (colour, alpha, path) = paths[key] else { continue }
            context.fill(path, with: .color(Color(red: colour.r, green: colour.g, blue: colour.b).opacity(alpha)))
        }
        order.removeAll(keepingCapacity: true)
        paths.removeAll(keepingCapacity: true)
    }

    private static func key(_ c: RGB, _ a: Double) -> UInt64 {
        func q(_ v: Double) -> UInt64 { UInt64((min(max(v, 0), 1) * 255).rounded()) }
        return q(c.r) << 24 | q(c.g) << 16 | q(c.b) << 8 | q(a)
    }
}

// MARK: - Palettes

private struct Palette {
    var skyTop: RGB
    var skyHorizon: RGB
    /// Light around the sun or moon, when one is up.
    var glow: RGB?
    var cloudLight: RGB
    var cloudBody: RGB
    var cloudShade: RGB
    var farGround: RGB
    var nearGround: RGB
    /// The lit edge of the near ridge.
    var lip: RGB
    /// Trees and the cabin, which stay silhouettes in every weather.
    var foliage: RGB
    var snowy = false

    /// The same weather after dark.
    func night() -> Palette {
        var p = self
        p.skyTop = skyTop.scaled(0.3)
        p.skyHorizon = skyHorizon.scaled(0.4)
        p.glow = nil
        p.cloudLight = cloudLight.scaled(0.42)
        p.cloudBody = cloudBody.scaled(0.4)
        p.cloudShade = cloudShade.scaled(0.4)
        p.farGround = farGround.scaled(0.45)
        p.nearGround = nearGround.scaled(0.4)
        p.lip = lip.scaled(0.5)
        p.foliage = foliage.scaled(0.4)
        return p
    }

    static func of(_ scene: WeatherScene, night: Bool) -> Palette {
        switch scene {
        case .clearDay:
            return Palette(
                skyTop: RGB(0.05, 0.16, 0.38), skyHorizon: RGB(0.24, 0.48, 0.68),
                glow: RGB(1.0, 0.82, 0.45),
                cloudLight: RGB(1, 1, 1), cloudBody: RGB(0.86, 0.9, 0.96), cloudShade: RGB(0.62, 0.72, 0.84),
                farGround: RGB(0.1, 0.24, 0.33), nearGround: RGB(0.04, 0.11, 0.12),
                lip: RGB(0.26, 0.5, 0.32), foliage: RGB(0.03, 0.09, 0.09)
            )
        case .clearNight:
            return Palette(
                skyTop: RGB(0.01, 0.02, 0.07), skyHorizon: RGB(0.1, 0.08, 0.23),
                glow: RGB(0.62, 0.72, 1.0),
                cloudLight: RGB(0.34, 0.37, 0.52), cloudBody: RGB(0.22, 0.24, 0.36), cloudShade: RGB(0.14, 0.15, 0.24),
                farGround: RGB(0.05, 0.05, 0.13), nearGround: RGB(0.015, 0.015, 0.04),
                lip: RGB(0.13, 0.13, 0.28), foliage: RGB(0.01, 0.01, 0.03)
            )
        case .cloudy:
            let day = Palette(
                skyTop: RGB(0.13, 0.19, 0.28), skyHorizon: RGB(0.34, 0.41, 0.5),
                glow: RGB(1.0, 0.9, 0.7),
                cloudLight: RGB(0.93, 0.95, 0.99), cloudBody: RGB(0.73, 0.78, 0.86), cloudShade: RGB(0.52, 0.58, 0.68),
                farGround: RGB(0.16, 0.22, 0.28), nearGround: RGB(0.06, 0.09, 0.11),
                lip: RGB(0.28, 0.4, 0.34), foliage: RGB(0.04, 0.07, 0.08)
            )
            return night ? day.night() : day
        case .fog:
            let day = Palette(
                skyTop: RGB(0.24, 0.27, 0.31), skyHorizon: RGB(0.46, 0.49, 0.53),
                glow: RGB(1.0, 0.96, 0.85),
                cloudLight: RGB(0.8, 0.82, 0.86), cloudBody: RGB(0.7, 0.72, 0.76), cloudShade: RGB(0.6, 0.62, 0.66),
                farGround: RGB(0.3, 0.33, 0.37), nearGround: RGB(0.13, 0.15, 0.17),
                lip: RGB(0.36, 0.4, 0.42), foliage: RGB(0.11, 0.13, 0.15)
            )
            return night ? day.night() : day
        case .drizzle:
            let day = Palette(
                skyTop: RGB(0.12, 0.17, 0.25), skyHorizon: RGB(0.3, 0.37, 0.46),
                glow: nil,
                cloudLight: RGB(0.72, 0.76, 0.84), cloudBody: RGB(0.54, 0.59, 0.68), cloudShade: RGB(0.38, 0.42, 0.5),
                farGround: RGB(0.15, 0.2, 0.27), nearGround: RGB(0.05, 0.08, 0.1),
                lip: RGB(0.32, 0.42, 0.5), foliage: RGB(0.04, 0.06, 0.08)
            )
            return night ? day.night() : day
        case .rain:
            let day = Palette(
                skyTop: RGB(0.07, 0.1, 0.17), skyHorizon: RGB(0.19, 0.25, 0.34),
                glow: nil,
                cloudLight: RGB(0.46, 0.5, 0.6), cloudBody: RGB(0.31, 0.35, 0.44), cloudShade: RGB(0.19, 0.22, 0.29),
                farGround: RGB(0.1, 0.14, 0.2), nearGround: RGB(0.03, 0.05, 0.07),
                lip: RGB(0.3, 0.42, 0.56), foliage: RGB(0.02, 0.04, 0.05)
            )
            return night ? day.night() : day
        case .storm:
            // Dark whatever the hour; night only takes it a little further.
            let base = Palette(
                skyTop: RGB(0.03, 0.035, 0.07), skyHorizon: RGB(0.1, 0.11, 0.17),
                glow: nil,
                cloudLight: RGB(0.27, 0.29, 0.38), cloudBody: RGB(0.16, 0.17, 0.23), cloudShade: RGB(0.09, 0.09, 0.13),
                farGround: RGB(0.06, 0.07, 0.11), nearGround: RGB(0.015, 0.02, 0.035),
                lip: RGB(0.22, 0.27, 0.38), foliage: RGB(0.01, 0.015, 0.03)
            )
            guard night else { return base }
            var dark = base
            dark.skyTop = base.skyTop.scaled(0.7)
            dark.skyHorizon = base.skyHorizon.scaled(0.75)
            return dark
        case .snow:
            if night {
                return Palette(
                    skyTop: RGB(0.05, 0.06, 0.11), skyHorizon: RGB(0.16, 0.18, 0.27),
                    glow: nil,
                    cloudLight: RGB(0.38, 0.4, 0.5), cloudBody: RGB(0.26, 0.28, 0.36), cloudShade: RGB(0.17, 0.18, 0.24),
                    farGround: RGB(0.26, 0.29, 0.38), nearGround: RGB(0.5, 0.55, 0.66),
                    lip: RGB(0.74, 0.8, 0.92), foliage: RGB(0.02, 0.04, 0.06), snowy: true
                )
            }
            return Palette(
                skyTop: RGB(0.2, 0.26, 0.36), skyHorizon: RGB(0.46, 0.53, 0.62),
                glow: nil,
                cloudLight: RGB(0.96, 0.97, 1), cloudBody: RGB(0.8, 0.84, 0.92), cloudShade: RGB(0.62, 0.67, 0.78),
                farGround: RGB(0.54, 0.6, 0.7), nearGround: RGB(0.74, 0.8, 0.88),
                lip: RGB(0.93, 0.96, 1), foliage: RGB(0.08, 0.14, 0.16), snowy: true
            )
        }
    }
}

/// One band of clouds drifting at one speed.
private struct CloudBand {
    let count: Int
    let widths: ClosedRange<Int>
    let heights: ClosedRange<Int>
    /// Where the cloud tops sit, as fractions of the height. Negative is
    /// above the top edge: a ceiling of cloud.
    let rows: ClosedRange<Double>
    /// Cells per second.
    let speed: Double
    let alpha: Double
    let seed: Int

    static func bands(for scene: WeatherScene) -> (far: CloudBand?, near: CloudBand?) {
        switch scene {
        case .clearDay:
            return (nil, CloudBand(count: 2, widths: 12 ... 18, heights: 4 ... 6, rows: 0.04 ... 0.24, speed: 0.55, alpha: 0.92, seed: 10))
        case .clearNight:
            return (nil, CloudBand(count: 2, widths: 12 ... 16, heights: 4 ... 5, rows: 0.06 ... 0.28, speed: 0.45, alpha: 0.75, seed: 20))
        case .cloudy:
            return (
                CloudBand(count: 4, widths: 14 ... 22, heights: 4 ... 6, rows: 0.0 ... 0.3, speed: 0.3, alpha: 0.6, seed: 30),
                CloudBand(count: 3, widths: 16 ... 26, heights: 5 ... 8, rows: 0.14 ... 0.44, speed: 0.7, alpha: 0.96, seed: 40)
            )
        case .fog:
            return (nil, nil)
        case .drizzle:
            return (
                CloudBand(count: 4, widths: 16 ... 24, heights: 4 ... 6, rows: -0.08 ... 0.06, speed: 0.35, alpha: 0.75, seed: 50),
                CloudBand(count: 3, widths: 14 ... 20, heights: 4 ... 5, rows: 0.0 ... 0.14, speed: 0.6, alpha: 0.95, seed: 60)
            )
        case .rain:
            return (
                CloudBand(count: 5, widths: 16 ... 26, heights: 5 ... 7, rows: -0.1 ... 0.04, speed: 0.45, alpha: 0.8, seed: 70),
                CloudBand(count: 4, widths: 16 ... 24, heights: 5 ... 7, rows: -0.02 ... 0.12, speed: 0.9, alpha: 0.97, seed: 80)
            )
        case .storm:
            return (
                CloudBand(count: 6, widths: 18 ... 28, heights: 5 ... 8, rows: -0.12 ... 0.04, speed: 0.7, alpha: 0.85, seed: 90),
                CloudBand(count: 5, widths: 16 ... 26, heights: 5 ... 8, rows: -0.02 ... 0.14, speed: 1.3, alpha: 1, seed: 100)
            )
        case .snow:
            return (
                CloudBand(count: 4, widths: 16 ... 24, heights: 4 ... 6, rows: -0.08 ... 0.05, speed: 0.3, alpha: 0.8, seed: 110),
                CloudBand(count: 2, widths: 14 ... 20, heights: 4 ... 5, rows: 0.0 ... 0.1, speed: 0.5, alpha: 0.95, seed: 120)
            )
        }
    }
}

// MARK: - Painter

private struct WeatherPainter {
    let scene: WeatherScene
    let night: Bool
    let t: Double
    let cell: CGFloat = 3
    let width: CGFloat
    let height: CGFloat
    let cols: Int
    let rows: Int
    let palette: Palette

    init(scene: WeatherScene, night: Bool, t: Double, size: CGSize) {
        // Clear weather carries its own time of day.
        let isNight: Bool
        switch scene {
        case .clearDay: isNight = false
        case .clearNight: isNight = true
        default: isNight = night
        }
        self.scene = scene
        self.night = isNight
        self.t = t
        width = size.width
        height = size.height
        cols = max(Int((size.width / 3).rounded(.up)), 1)
        rows = max(Int((size.height / 3).rounded(.up)), 1)
        palette = Palette.of(scene, night: isNight)
    }

    // MARK: Layout

    /// The temperature and its labels take the left of the pane; nothing
    /// busy is placed under them.
    private let textZone = 46

    /// Where the sun or moon sits, clear of the text.
    private var sky: (x: Int, y: Int) { (cols - 26, Int(Double(rows) * 0.36)) }

    private var cabinX: Int { cols - 50 }
    private var showsScenery: Bool { cabinX - 13 > textZone && rows >= 24 }

    /// The near ridge's top row at a column. Kept low: it is a horizon for the
    /// weather to land on, not scenery that competes with the text.
    func nearTop(_ gx: Int) -> Int {
        let x = Double(gx) * Double(cell)
        let rise = 1.3 + 0.9 * sin(x * 0.05) + 0.8 * sin(x * 0.019 + 1.3)
        return rows - 2 - Int(rise.rounded())
    }

    func farTop(_ gx: Int) -> Int {
        let x = Double(gx) * Double(cell)
        let rise = 2.6 + 1.6 * sin(x * 0.028 + 2.1) + 1.1 * sin(x * 0.011 + 0.4)
        return rows - 3 - Int(rise.rounded())
    }

    /// A slow breeze with the occasional gust, in cells per second of sideways
    /// drift. Rain leans with it, snow drifts on it, smoke bends in it.
    private var wind: Double {
        let gustPhase = t.truncatingRemainder(dividingBy: 11) - 8
        let gust = exp(-gustPhase * gustPhase * 1.4)
        return 0.6 * sin(t * 0.21) + 2.4 * gust
    }

    /// How far the wind has carried things so far — the integral of `wind`, so
    /// a gust moves snow along rather than making it jump.
    private var windTravel: Double {
        let cycles = (t / 11).rounded(.down)
        let phase = t.truncatingRemainder(dividingBy: 11) - 8
        // The gust is a Gaussian; its integral is an error function.
        let gustSoFar = 2.4 * (Double.pi / 1.4).squareRoot() * 0.5 * (1 + erf(phase * 1.4.squareRoot()))
        let gustTotal = 2.4 * (Double.pi / 1.4).squareRoot()
        return -0.6 / 0.21 * cos(t * 0.21) + cycles * gustTotal + gustSoFar
    }

    private var windowsLit: Bool {
        night || [.storm, .rain, .drizzle, .snow, .fog].contains(scene)
    }

    private var chimneySmokes: Bool {
        [.clearNight, .cloudy, .fog, .snow, .drizzle].contains(scene)
    }

    // MARK: Frame

    func draw(into context: inout GraphicsContext) {
        var layer = PixelLayer(cell: cell)
        let strike = self.strike

        drawSky(&layer)
        if let glow = palette.glow { drawGlow(&layer, glow) }
        if scene == .clearNight {
            drawStars(&layer)
            drawMeteor(&layer)
        }
        layer.flush(into: &context)

        switch scene {
        case .clearDay: drawSun(&layer, strength: 1)
        case .clearNight: drawMoon(&layer)
        case .cloudy, .fog: if !night { drawSun(&layer, strength: scene == .fog ? 0.45 : 0.55) }
        default: break
        }
        layer.flush(into: &context)

        let bands = CloudBand.bands(for: scene)
        if let far = bands.far { drawClouds(&layer, far, strike: strike) }
        layer.flush(into: &context)
        if !night, scene == .clearDay || scene == .cloudy { drawBirds(&layer) }
        drawFarGround(&layer)
        switch scene {
        case .drizzle: drawRain(&layer, count: 16, speed: 16, length: 1, alpha: 0.32, lean: 0.1, seed: 1)
        case .rain: drawRain(&layer, count: 32, speed: 24, length: 2, alpha: 0.34, lean: 0.18, seed: 1)
        case .storm: drawRain(&layer, count: 40, speed: 30, length: 2, alpha: 0.36, lean: 0.34, seed: 1)
        case .snow: drawSnow(&layer, depth: 0)
        default: break
        }
        layer.flush(into: &context)

        if let near = bands.near { drawClouds(&layer, near, strike: strike) }
        layer.flush(into: &context)
        if let strike, strike.hasBolt { drawBolt(&layer, strike) }
        layer.flush(into: &context)

        drawNearGround(&layer)
        layer.flush(into: &context)
        if showsScenery {
            drawScenery(&layer)
            layer.flush(into: &context)
            if chimneySmokes { drawSmoke(&layer) }
        }
        layer.flush(into: &context)

        switch scene {
        case .drizzle: drawRain(&layer, count: 12, speed: 20, length: 2, alpha: 0.6, lean: 0.12, seed: 2, splashes: true)
        case .rain: drawRain(&layer, count: 30, speed: 32, length: 3, alpha: 0.72, lean: 0.24, seed: 2, splashes: true)
        case .storm: drawRain(&layer, count: 38, speed: 40, length: 4, alpha: 0.78, lean: 0.42, seed: 2, splashes: true)
        case .snow:
            drawSnow(&layer, depth: 1)
            drawSnow(&layer, depth: 2)
        case .fog: drawFog(&layer)
        default: break
        }
        layer.flush(into: &context)

        if let strike, strike.flash > 0.01 {
            context.fill(
                Path(CGRect(x: 0, y: 0, width: width, height: height)),
                with: .color(Color(red: 0.86, green: 0.88, blue: 1).opacity(strike.flash))
            )
        }
    }

    // MARK: Sky

    /// Bands of colour from zenith to horizon, meeting in a checkerboard.
    private func drawSky(_ layer: inout PixelLayer) {
        let bands = 6
        for gy in 0 ..< rows {
            let f = Double(gy) / Double(max(rows - 1, 1))
            let position = f * Double(bands - 1)
            let band = min(Int(position), bands - 1)
            let within = position - Double(band)
            let colour = palette.skyTop.mix(palette.skyHorizon, Double(band) / Double(bands - 1))
            layer.fill(0, gy, cols, 1, colour)
            guard band < bands - 1, within > 0.6 else { continue }
            let next = palette.skyTop.mix(palette.skyHorizon, Double(band + 1) / Double(bands - 1))
            // A quarter of the cells first, then half, as the next band nears.
            let coverage = within > 0.8 ? 0.5 : 0.25
            for gx in 0 ..< cols where dithered(gx, gy, coverage) {
                layer.fill(gx, gy, 1, 1, next)
            }
        }
    }

    /// Filled pixel disc, one rectangle per row.
    private func disc(_ layer: inout PixelLayer, _ cx: Int, _ cy: Int, _ radius: Double, _ colour: RGB, _ alpha: Double) {
        let reach = Int(radius.rounded(.up))
        for dy in -reach ... reach {
            let span = radius * radius - Double(dy * dy)
            guard span >= 0 else { continue }
            let half = Int((span.squareRoot() + 0.3).rounded(.down))
            layer.fill(cx - half, cy + dy, half * 2 + 1, 1, colour, alpha)
        }
    }

    /// Rings of light around the sun or moon, which is also what keeps the
    /// left of the pane — under the text — the darker side.
    private func drawGlow(_ layer: inout PixelLayer, _ glow: RGB) {
        let breathe = 0.88 + 0.12 * sin(t * 1.1)
        let strength: Double
        switch scene {
        case .clearDay: strength = 1
        case .clearNight: strength = 0.7
        default: strength = 0.45
        }
        for (radius, alpha) in [(19.0, 0.045), (13.0, 0.06), (8.5, 0.08)] {
            disc(&layer, sky.x, sky.y, radius, glow, alpha * breathe * strength)
        }
    }

    // MARK: Sun and moon

    private func drawSun(_ layer: inout PixelLayer, strength: Double) {
        let (cx, cy) = sky
        let rim = RGB(1.0, 0.72, 0.28)
        let core = RGB(1.0, 0.91, 0.52)

        // Rays as specks of light travelling outward — rotation stairsteps
        // horribly on a grid this coarse, emission does not.
        let directions = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
        for (k, direction) in directions.enumerated() {
            let diagonal = direction.0 != 0 && direction.1 != 0
            for speck in 0 ..< 2 {
                let p = (t * 0.55 + Double(k) * 0.137 + Double(speck) * 0.5).truncatingRemainder(dividingBy: 1)
                let reach = (6.0 + p * 6.5) * (diagonal ? 0.72 : 1)
                let x = cx + Int((Double(direction.0) * reach).rounded())
                let y = cy + Int((Double(direction.1) * reach).rounded())
                let alpha = (1 - p) * 0.9 * strength
                layer.fill(x, y, 1, 1, core, alpha)
                if !diagonal {
                    layer.fill(x - direction.0, y - direction.1, 1, 1, rim, alpha * 0.5)
                }
            }
        }

        disc(&layer, cx, cy, 4.3, rim, strength)
        disc(&layer, cx, cy, 3.2, core, strength)
        layer.fill(cx - 2, cy - 2, 2, 1, .white, 0.6 * strength)
    }

    /// A crescent, with the rest of the disc faintly there — earthshine — and
    /// a couple of craters on the lit side.
    private func drawMoon(_ layer: inout PixelLayer) {
        let (cx, cy) = sky
        let radius = 4.3
        let bite = (x: 1.9, y: -1.2, r: 3.7)
        for dy in -5 ... 5 {
            for dx in -5 ... 5 {
                let d = (Double(dx * dx + dy * dy)).squareRoot()
                guard d <= radius else { continue }
                let bx = Double(dx) - bite.x
                let by = Double(dy) - bite.y
                let inBite = (bx * bx + by * by).squareRoot()
                if inBite < bite.r {
                    layer.fill(cx + dx, cy + dy, 1, 1, RGB(0.5, 0.58, 0.82), 0.13)
                } else {
                    let terminator = inBite < bite.r + 1.1
                    layer.fill(cx + dx, cy + dy, 1, 1, terminator ? RGB(0.7, 0.75, 0.9) : RGB(0.94, 0.95, 1))
                }
            }
        }
        for (dx, dy) in [(-3, 1), (-2, 3), (-1, -1)] {
            let bx = Double(dx) - bite.x
            let by = Double(dy) - bite.y
            guard (bx * bx + by * by).squareRoot() >= bite.r + 1.1 else { continue }
            layer.fill(cx + dx, cy + dy, 1, 1, RGB(0.76, 0.8, 0.93))
        }
    }

    private func drawStars(_ layer: inout PixelLayer) {
        let (mx, my) = sky
        for i in 0 ..< 46 {
            let gx = Int(hash01(i * 43 + 1) * Double(cols))
            let gy = Int(hash01(i * 61 + 7) * Double(rows) * 0.66)
            let dx = gx - mx
            let dy = gy - my
            guard dx * dx + dy * dy > 64, gy < farTop(gx) - 2 else { continue }

            let base = 0.3 + hash01(i * 5) * 0.6
            let twinkle = (sin(t * (0.6 + hash01(i * 3) * 1.8) + Double(i) * 1.7) + 1) / 2
            let alpha = base * (0.35 + 0.65 * twinkle)
            let colour = hash01(i * 9) > 0.8 ? RGB(1, 0.9, 0.74) : RGB(0.86, 0.9, 1)
            layer.fill(gx, gy, 1, 1, colour, alpha)
            // The brightest few flare into a cross at the top of their twinkle.
            if hash01(i * 11) > 0.84, twinkle > 0.8 {
                let arm = alpha * (twinkle - 0.8) * 2.5
                layer.fill(gx - 1, gy, 1, 1, colour, arm)
                layer.fill(gx + 1, gy, 1, 1, colour, arm)
                layer.fill(gx, gy - 1, 1, 1, colour, arm)
                layer.fill(gx, gy + 1, 1, 1, colour, arm)
            }
        }
    }

    /// Seconds into the current shooting star, if one is crossing.
    var meteorAge: Double? {
        let period = 6.5
        let slot = (t / period).rounded(.down)
        let n = Int(slot.truncatingRemainder(dividingBy: 1_000_000))
        guard hash01(n * 7 + 3) < 0.75 else { return nil }
        let start = slot * period + hash01(n * 11 + 5) * (period - 1)
        let age = t - start
        return age >= 0 && age < 0.75 ? age : nil
    }

    private func drawMeteor(_ layer: inout PixelLayer) {
        guard let age = meteorAge else { return }
        let n = Int((t / 6.5).rounded(.down).truncatingRemainder(dividingBy: 1_000_000))
        let startX = Double(cols) * (0.5 + 0.42 * hash01(n * 13))
        let startY = Double(rows) * (0.04 + 0.2 * hash01(n * 17))
        let velocity = (x: -34.0, y: 14.0)
        let fade = age < 0.1 ? age / 0.1 : (age > 0.55 ? max(0, (0.75 - age) / 0.2) : 1)
        let headX = startX + velocity.x * age
        let headY = startY + velocity.y * age
        let length = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        let step = (x: -velocity.x / length, y: -velocity.y / length)
        for i in 0 ..< 9 {
            let x = Int((headX + step.x * Double(i)).rounded(.down))
            let y = Int((headY + step.y * Double(i)).rounded(.down))
            let colour = i == 0 ? RGB.white : RGB(0.72, 0.8, 1)
            layer.fill(x, y, 1, 1, colour, fade * (1 - Double(i) / 9) * (i == 0 ? 1 : 0.8))
        }
    }

    // MARK: Clouds

    /// A cloud's outline: bumps of different sizes along a flat base, so each
    /// one is its own shape but the same shape every frame.
    private func cloudTops(width: Int, height: Int, seed: Int) -> [Int?] {
        // Few bumps, very different sizes: a big crown in the middle and small
        // lumps either side is what reads as cumulus. Many similar bumps merge
        // into a flat bar with a scalloped top.
        let bumpCount = width >= 10 ? max(3, min(4, width / 6)) : 2
        var bumps: [(x: Double, r: Double)] = []
        let centre = Double(bumpCount - 1) / 2
        for b in 0 ..< bumpCount {
            let spacing = Double(width) / Double(bumpCount)
            let x = (Double(b) + 0.5) * spacing + (hash01(seed * 31 + b) - 0.5) * 1.4
            let middle = 1 - abs(Double(b) - centre) / (centre + 0.5)
            let r = Double(height) * (0.48 + 0.52 * middle + 0.14 * hash01(seed * 37 + b))
            bumps.append((x, r))
        }
        return (0 ..< width).map { column in
            let x = Double(column) + 0.5
            var top: Double?
            for bump in bumps {
                let dx = x - bump.x
                guard abs(dx) < bump.r else { continue }
                let y = Double(height) - (bump.r * bump.r - dx * dx).squareRoot()
                top = min(top ?? .infinity, y)
            }
            return top.map { max(0, Int($0.rounded())) }
        }
    }

    private func drawClouds(_ layer: inout PixelLayer, _ band: CloudBand, strike: Strike?) {
        // Lightning lights clouds from below.
        let flash = strike?.brightness ?? 0
        let lit = RGB(0.82, 0.84, 1)
        let light = palette.cloudLight.mix(lit, flash * 0.35)
        let body = palette.cloudBody.mix(lit, flash * 0.45)
        let shade = palette.cloudShade.mix(lit, flash * 0.75)

        for i in 0 ..< band.count {
            let seed = band.seed * 100 + i
            let width = band.widths.lowerBound
                + Int(hash01(seed * 3) * Double(band.widths.upperBound - band.widths.lowerBound + 1))
            let height = band.heights.lowerBound
                + Int(hash01(seed * 5) * Double(band.heights.upperBound - band.heights.lowerBound + 1))
            // Spread through the band rather than wherever the hash lands, or
            // three clouds in a short pane clump often enough to look wrong.
            let slot = (Double(i) + 0.3 + hash01(seed * 7) * 0.4) / Double(band.count)
            let top = Int(((band.rows.lowerBound + (band.rows.upperBound - band.rows.lowerBound) * slot) * Double(rows)).rounded())
            let speed = band.speed * (0.8 + 0.4 * hash01(seed * 11))
            let span = Double(cols + width + 6)
            let phase = (Double(i) / Double(band.count) + hash01(seed * 13) * 0.25) * span
            let left = Int((t * speed + phase).truncatingRemainder(dividingBy: span).rounded(.down)) - width - 3

            let tops = cloudTops(width: width, height: height, seed: seed)
            for (column, columnTop) in tops.enumerated() {
                guard let columnTop else { continue }
                let x = left + column
                guard x >= -1, x <= cols else { continue }
                let y0 = top + columnTop
                let bottom = top + height - 1
                layer.fill(x, y0, 1, 1, light, band.alpha)
                let shadeRows = height >= 5 && bottom - y0 >= 3 ? 2 : 1
                if bottom - shadeRows >= y0 + 1 {
                    layer.fill(x, y0 + 1, 1, bottom - shadeRows - y0, body, band.alpha)
                }
                if bottom > y0 {
                    let from = max(y0 + 1, bottom - shadeRows + 1)
                    layer.fill(x, from, 1, bottom - from + 1, shade, band.alpha)
                }
            }
        }
    }

    // MARK: Life

    /// A few birds crossing a clear sky, wings up, wings down.
    private func drawBirds(_ layer: inout PixelLayer) {
        let colour = palette.foliage.mix(.black, 0.3)
        for bird in 0 ..< 3 {
            let period = 15.0 + Double(bird) * 5.5
            let p = (t + Double(bird) * 6.3).truncatingRemainder(dividingBy: period) / period
            guard p < 0.6 else { continue }
            let x = Int((Double(cols + 6) - p / 0.6 * Double(cols + 14)).rounded())
            let y = Int(Double(rows) * (0.16 + 0.1 * Double(bird)) + sin(t * 1.7 + Double(bird)) * 1.2)
            let wingsUp = Int(t * 5 + Double(bird) * 0.7) % 2 == 0
            // Two of them fly as a pair.
            let flock = bird == 1 ? [(0, 0), (4, -2)] : [(0, 0)]
            for (fx, fy) in flock {
                let bx = x + fx
                let by = y + fy
                if wingsUp {
                    layer.fill(bx - 1, by - 1, 1, 1, colour, 0.9)
                    layer.fill(bx + 1, by - 1, 1, 1, colour, 0.9)
                    layer.fill(bx, by, 1, 1, colour, 0.9)
                } else {
                    layer.fill(bx - 1, by, 1, 1, colour, 0.9)
                    layer.fill(bx + 1, by, 1, 1, colour, 0.9)
                    layer.fill(bx, by - 1, 1, 1, colour, 0.9)
                }
            }
        }
    }

    // MARK: Ground

    private func drawFarGround(_ layer: inout PixelLayer) {
        for gx in 0 ..< cols {
            let top = farTop(gx)
            layer.fill(gx, top, 1, rows - top, palette.farGround)
        }
    }

    private func drawNearGround(_ layer: inout PixelLayer) {
        for gx in 0 ..< cols {
            let top = nearTop(gx)
            layer.fill(gx, top + 1, 1, rows - top - 1, palette.nearGround)
            layer.fill(gx, top, 1, 1, palette.lip)
        }
    }

    /// A cabin between the pines, standing on the highest ground under it.
    private func drawScenery(_ layer: inout PixelLayer) {
        let bx = cabinX
        drawPine(&layer, at: bx - 11, big: true)
        drawPine(&layer, at: bx + 9, big: false)
        if cols - 7 > bx + 14 { drawPine(&layer, at: cols - 7, big: true) }
        drawPine(&layer, at: bx - 17, big: false)
        drawCabin(&layer, at: bx)
    }

    private func drawPine(_ layer: inout PixelLayer, at x: Int, big: Bool) {
        let sprite = big
            ? ["...S...", "..S#S..", ".S###S.", "..S#S..", ".S###S.", "S#####S", "...#...", "...#..."]
            : ["..S..", ".S#S.", "S###S", ".S#S.", "S###S", "..#.."]
        let half = sprite[0].count / 2
        let base = (x - half ... x + half).map(nearTop).min() ?? nearTop(x)
        let snow = RGB(0.95, 0.97, 1)
        for (row, line) in sprite.enumerated() {
            let y = base - sprite.count + 1 + row
            for (column, character) in line.enumerated() where character != "." {
                let colour = character == "S" && palette.snowy ? snow : palette.foliage
                layer.fill(x - half + column, y, 1, 1, colour)
            }
        }
        // Fill any gap between the trunk and a dip in the ground.
        let ground = nearTop(x)
        if ground > base { layer.fill(x, base + 1, 1, ground - base, palette.foliage) }
    }

    private func drawCabin(_ layer: inout PixelLayer, at bx: Int) {
        let base = (bx - 5 ... bx + 5).map(nearTop).min() ?? nearTop(bx)
        let wall = palette.foliage.mix(.white, 0.13)
        let roof = palette.foliage.mix(.white, 0.05)
        let snow = RGB(0.95, 0.97, 1)

        // Foundation down to wherever the ground falls away.
        for gx in bx - 4 ... bx + 4 {
            let ground = nearTop(gx)
            if ground > base { layer.fill(gx, base + 1, 1, ground - base, wall) }
        }
        layer.fill(bx - 4, base - 3, 9, 4, wall)
        for r in 0 ..< 5 {
            let half = 5 - r
            layer.fill(bx - half, base - 4 - r, half * 2 + 1, 1, roof)
        }
        layer.fill(bx + 2, base - 9, 2, 3, wall)
        layer.fill(bx, base - 2, 1, 3, palette.foliage)

        if palette.snowy {
            for r in 0 ..< 5 {
                let half = 5 - r
                layer.fill(bx - half, base - 4 - r, 1, 1, snow)
                layer.fill(bx + half, base - 4 - r, 1, 1, snow)
            }
            layer.fill(bx - 1, base - 9, 2, 1, snow)
            layer.fill(bx + 2, base - 10, 2, 1, snow)
        }

        let lamp = RGB(1.0, 0.78, 0.38)
        let flicker = 0.84 + 0.16 * sin(t * 6.3 + sin(t * 2.2) * 2)
        for wx in [bx - 3, bx + 2] {
            if windowsLit {
                layer.fill(wx - 1, base - 3, 4, 3, lamp, 0.1 * flicker)
                layer.fill(wx, base - 2, 2, 1, lamp, flicker)
            } else {
                layer.fill(wx, base - 2, 2, 1, palette.foliage.mix(.white, 0.28))
            }
        }
    }

    /// Puffs that rise from the chimney, grow, lean with the wind and thin out.
    private func drawSmoke(_ layer: inout PixelLayer) {
        let bx = cabinX
        let base = (bx - 5 ... bx + 5).map(nearTop).min() ?? nearTop(bx)
        let colour = night ? RGB(0.5, 0.53, 0.62) : RGB(0.86, 0.88, 0.92)
        for puff in 0 ..< 6 {
            let age = (t / 3.6 + Double(puff) / 6).truncatingRemainder(dividingBy: 1)
            let rise = age * 11
            let lean = wind * age * 3.5 + sin(age * 6 + Double(puff)) * 0.8
            let x = bx + 2 + Int((0.5 + lean).rounded(.down))
            let y = base - 11 - Int(rise)
            let size = age < 0.35 ? 1 : 2
            let fadeIn = min(age / 0.12, 1)
            layer.fill(x, y, size, size, colour, 0.5 * (1 - age) * fadeIn)
        }
    }

    // MARK: Rain

    private func drawRain(
        _ layer: inout PixelLayer, count: Int, speed: Double, length: Int,
        alpha: Double, lean: Double, seed: Int, splashes: Bool = false
    ) {
        let colour = RGB(0.64, 0.8, 1)
        let slant = lean + wind * 0.05
        let cycle = Double(rows + length + 3)
        for i in 0 ..< count {
            let n = seed * 1000 + i
            let lane = hash01(n * 7 + 1)
            let rate = speed * (0.8 + 0.4 * hash01(n * 3 + 2))
            let fall = (t * rate + hash01(n * 13 + 5) * cycle).truncatingRemainder(dividingBy: cycle) - Double(length)
            let x0 = lane * Double(cols) + fall * slant
            let wrapped = (x0.truncatingRemainder(dividingBy: Double(cols)) + Double(cols))
                .truncatingRemainder(dividingBy: Double(cols))
            let head = Int(fall.rounded(.down))
            let gx = Int(wrapped)
            let ground = splashes ? nearTop(gx) : rows

            if head < ground {
                for k in 0 ..< length {
                    let y = head - k
                    let x = Int((wrapped - Double(k) * slant).rounded(.down))
                    let fade = 1 - Double(k) / Double(length + 1)
                    layer.fill(x, y, 1, 1, colour, alpha * (0.35 + 0.65 * hash01(n)) * fade + 0.1)
                }
            } else if splashes {
                // Landed: a crown of two droplets that jump and fall, and a
                // bright ring on the ground where it hit.
                let age = (fall - Double(ground)) / (rate * 0.16)
                guard age < 1 else { continue }
                let spread = age < 0.5 ? 1 : 2
                let lift = age < 0.5 ? 1 : 2
                let a = alpha * (1 - age)
                layer.fill(gx - spread, ground - lift, 1, 1, colour, a)
                layer.fill(gx + spread, ground - lift, 1, 1, colour, a)
                layer.fill(gx - 1, ground, 3, 1, RGB(0.8, 0.9, 1), a * 0.6)
            }
        }
    }

    // MARK: Snow

    /// Three depths of flake: far ones small, slow and dim; near ones big,
    /// quick and swaying. All of them ride the same wind.
    private func drawSnow(_ layer: inout PixelLayer, depth: Int) {
        let presets: [(count: Int, speed: Double, sway: Double, alpha: Double, carry: Double)] = [
            (30, 2.4, 1.2, 0.45, 0.6),
            (20, 3.8, 2.0, 0.85, 1.0),
            (9, 5.6, 3.0, 0.95, 1.5),
        ]
        let (count, speed, sway, alpha, carry) = presets[depth]
        let colour = RGB(0.96, 0.97, 1)
        let cycle = Double(rows + 4)
        for i in 0 ..< count {
            let n = depth * 1000 + i + 500
            let rate = speed * (0.8 + 0.4 * hash01(n * 5))
            let fall = (t * rate + hash01(n * 17 + 9) * cycle).truncatingRemainder(dividingBy: cycle) - 2
            let drift = sin(t * (0.5 + hash01(n * 23) * 0.8) + Double(i)) * sway
            let raw = hash01(n * 11 + 3) * Double(cols) + drift + windTravel * carry
            let x = Int(((raw.truncatingRemainder(dividingBy: Double(cols)) + Double(cols))
                .truncatingRemainder(dividingBy: Double(cols))).rounded(.down))
            let y = Int(fall.rounded(.down))
            // Far flakes pass behind the near ridge; nearer ones settle on it.
            if depth > 0, y >= nearTop(x) { continue }
            if depth == 2, i < 5 {
                layer.fill(x, y, 1, 1, colour, alpha)
                layer.fill(x - 1, y, 1, 1, colour, alpha * 0.55)
                layer.fill(x + 1, y, 1, 1, colour, alpha * 0.55)
                layer.fill(x, y - 1, 1, 1, colour, alpha * 0.55)
                layer.fill(x, y + 1, 1, 1, colour, alpha * 0.55)
            } else if depth == 2 {
                layer.fill(x, y, 2, 1, colour, alpha)
            } else {
                layer.fill(x, y, 1, 1, colour, alpha)
            }
        }
    }

    // MARK: Fog

    /// Wisps of fog: long bands, tapered at both ends, drifting at different
    /// speeds and heights — thin up high, thick along the ground. Drawn in
    /// front of the cabin so it sits in the fog, and fainter over the text so
    /// the temperature stays readable.
    private func drawFog(_ layer: inout PixelLayer) {
        let colour = night ? RGB(0.46, 0.49, 0.56) : RGB(0.86, 0.88, 0.92)
        for wisp in 0 ..< 11 {
            let low = wisp >= 6
            let thickness = low ? 3 + Int(hash01(wisp * 5) * 2) : 2 + Int(hash01(wisp * 5) * 2)
            let length = Double(cols) * (0.35 + 0.35 * hash01(wisp * 7))
            let row = low
                ? rows - 3 - thickness - Int(hash01(wisp * 11) * 5)
                : Int(Double(rows) * (0.12 + 0.5 * hash01(wisp * 11)))
            let speed = (0.5 + hash01(wisp * 13) * 0.9) * (wisp % 2 == 0 ? 1 : -1)
            let span = Double(cols) + length
            let travel = (t * speed + hash01(wisp * 17) * span).truncatingRemainder(dividingBy: span)
            let left = (travel < 0 ? travel + span : travel) - length
            let alpha = (low ? 0.3 : 0.17) * (0.8 + 0.4 * hash01(wisp * 19))
            // A slow swell, so the fog thickens and thins as it passes.
            let swell = 0.75 + 0.25 * sin(t * 0.4 + Double(wisp) * 1.9)

            for r in 0 ..< thickness {
                // Rows away from the middle are shorter: a lens, not a slab.
                let offCentre = abs(Double(r) - Double(thickness - 1) / 2) / Double(thickness)
                let inset = length * (0.08 + 0.3 * offCentre) + Double(Int(hash01(wisp * 23 + r) * 3))
                let x0 = Int((left + inset).rounded())
                let x1 = Int((left + length - inset).rounded())
                guard x1 > x0 else { continue }
                segment(&layer, x0, x1, row + r, colour, alpha * swell)
            }
        }
    }

    /// A horizontal run of fog, fainter where it crosses the text.
    private func segment(_ layer: inout PixelLayer, _ x0: Int, _ x1: Int, _ y: Int, _ colour: RGB, _ alpha: Double) {
        let from = max(x0, 0)
        let to = min(x1, cols)
        guard to > from else { return }
        let split = min(max(textZone - 6, from), to)
        if split > from { layer.fill(from, y, split - from, 1, colour, alpha * 0.45) }
        if to > split { layer.fill(split, y, to - split, 1, colour, alpha) }
    }

    // MARK: Lightning

    struct Strike {
        /// Which strike this is; it seeds the bolt's shape.
        let index: Int
        /// Seconds since the strike began.
        let age: Double
        /// A forked bolt, or sheet lightning lighting up the clouds.
        let hasBolt: Bool

        /// Flicker: a faint leader, the main flash, a gap, a restrike, then
        /// an afterglow. Real strikes flicker; a single flash looks fake.
        var brightness: Double {
            switch age {
            case ..<0.05: return 0.35
            case ..<0.11: return 1
            case ..<0.16: return 0.15
            case ..<0.22: return 0.82
            default:
                let fade = max(0, 1 - (age - 0.22) / 0.62)
                return 0.45 * fade * fade
            }
        }

        var flash: Double { brightness * (hasBolt ? 0.3 : 0.14) }
    }

    /// The strike in progress, if any. Strikes land at irregular moments: each
    /// 2.8 s slot may hold one, at a point in it the hash decides.
    var strike: Strike? {
        guard scene == .storm else { return nil }
        let slotLength = 2.8
        let slot = (t / slotLength).rounded(.down)
        let n = Int(slot.truncatingRemainder(dividingBy: 1_000_000))
        let roll = hash01(n * 29 + 7)
        guard roll < 0.7 else { return nil }
        let start = slot * slotLength + hash01(n * 31 + 11) * 1.2
        let age = t - start
        guard age >= 0, age < 0.84 else { return nil }
        return Strike(index: n, age: age, hasBolt: roll < 0.46)
    }

    /// A jagged path from the cloud base to the hills, with one fork.
    private func drawBolt(_ layer: inout PixelLayer, _ strike: Strike) {
        let brightness = strike.brightness
        guard brightness > 0.12 else { return }
        let halo = RGB(0.72, 0.78, 1)
        var x = Int(Double(cols) * (0.52 + 0.4 * hash01(strike.index * 3)))
        var y = Int(Double(rows) * 0.2)
        var path: [(Int, Int)] = []
        var step = 0
        while y < nearTop(x) {
            path.append((x, y))
            let roll = hash01(strike.index * 97 + step)
            x += roll < 0.38 ? -1 : (roll > 0.7 ? 1 : 0)
            y += 1
            step += 1
        }
        for (px, py) in path {
            layer.fill(px - 1, py, 1, 1, halo, brightness * 0.3)
            layer.fill(px + 1, py, 1, 1, halo, brightness * 0.3)
            layer.fill(px, py, 1, 1, .white, brightness)
        }

        // The fork leaves somewhere in the upper half and dies out.
        guard path.count > 6 else { return }
        let from = path[path.count / 3 + Int(hash01(strike.index * 5) * Double(path.count / 4))]
        let direction = hash01(strike.index * 7) < 0.5 ? -1 : 1
        var fx = from.0
        var fy = from.1
        for s in 0 ..< 4 + Int(hash01(strike.index * 9) * 5) {
            fx += hash01(strike.index * 131 + s) < 0.7 ? direction : 0
            fy += 1
            layer.fill(fx, fy, 1, 1, .white, brightness * 0.6)
        }

        // Sparks where it lands.
        if let end = path.last, brightness > 0.6 {
            for (dx, dy) in [(-2, -1), (2, -1), (-1, -2), (1, -2)] {
                layer.fill(end.0 + dx, end.1 + dy, 1, 1, RGB(1, 0.95, 0.75), brightness * 0.8)
            }
        }
    }
}

// MARK: - Beside the camera

/// The weather in the collapsed notch: a 16×12 sprite that moves a little —
/// the sun twinkles, rain falls, lightning flashes, fog slides.
struct PixelWeatherIcon: View {
    let scene: WeatherScene

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 8.0)) { context in
            Canvas { context2, size in
                let t = PixelWeatherView.frozenTime ?? context.date.timeIntervalSinceReferenceDate
                var layer = PixelLayer(cell: size.width / 16)
                MiniWeather(scene: scene, t: t).draw(&layer)
                layer.flush(into: &context2)
            }
        }
        .frame(width: 16, height: 12)
        .allowsHitTesting(false)
    }
}

private struct MiniWeather {
    let scene: WeatherScene
    let t: Double

    private static let cloud = [
        "....####....",
        "..########..",
        ".##########.",
        "############",
        ".##########.",
    ]

    func draw(_ layer: inout PixelLayer) {
        switch scene {
        case .clearDay: sun(&layer)
        case .clearNight: moon(&layer)
        case .cloudy:
            let drift = Int((sin(t * 0.9) * 1.2).rounded())
            sprite(&layer, Self.cloud, x: 3 + drift, y: 2, RGB(0.55, 0.6, 0.7))
            sprite(&layer, Self.cloud, x: 1 - drift, y: 5, RGB(0.9, 0.93, 0.98))
        case .fog:
            for (row, direction) in [(3, 1.0), (6, -1.0), (9, 1.0)] {
                let shift = Int((t * 3 * direction).rounded(.down))
                for x in 0 ..< 16 where ((x + shift) % 6 + 6) % 6 < 4 {
                    layer.fill(x, row, 1, 1, RGB(0.78, 0.8, 0.85), 0.9)
                }
            }
        case .drizzle:
            sprite(&layer, Self.cloud, x: 2, y: 0, RGB(0.72, 0.77, 0.86))
            drops(&layer, lanes: [5, 10], speed: 1.6, length: 1)
        case .rain:
            sprite(&layer, Self.cloud, x: 2, y: 0, RGB(0.62, 0.68, 0.78))
            drops(&layer, lanes: [4, 7, 10, 13], speed: 2.6, length: 2)
        case .storm:
            sprite(&layer, Self.cloud, x: 2, y: 0, RGB(0.45, 0.48, 0.58))
            drops(&layer, lanes: [4, 12], speed: 2.8, length: 2)
            if t.truncatingRemainder(dividingBy: 2.4) < 0.3 {
                for (x, y) in [(9, 5), (8, 6), (7, 7), (8, 7), (9, 7), (8, 8), (7, 9), (7, 10)] {
                    layer.fill(x, y, 1, 1, RGB(1, 0.9, 0.45))
                }
            }
        case .snow:
            sprite(&layer, Self.cloud, x: 2, y: 0, RGB(0.88, 0.91, 0.98))
            for (index, lane) in [4, 8, 12].enumerated() {
                let p = (t * 0.45 + Double(index) * 0.33).truncatingRemainder(dividingBy: 1)
                let x = lane + Int((sin(t * 2 + Double(index)) * 1).rounded())
                layer.fill(x, 6 + Int(p * 6), 1, 1, .white, p > 0.85 ? 0.5 : 1)
            }
        }
    }

    private func sprite(_ layer: inout PixelLayer, _ rows: [String], x: Int, y: Int, _ colour: RGB) {
        for (row, line) in rows.enumerated() {
            for (column, character) in line.enumerated() where character == "#" {
                layer.fill(x + column, y + row, 1, 1, colour)
            }
        }
    }

    private func drops(_ layer: inout PixelLayer, lanes: [Int], speed: Double, length: Int) {
        for (index, lane) in lanes.enumerated() {
            let p = (t * speed + Double(index) * 0.37).truncatingRemainder(dividingBy: 1)
            let head = 6 + Int(p * 6)
            for k in 0 ..< length where head - k >= 6 {
                layer.fill(lane, head - k, 1, 1, RGB(0.55, 0.76, 1), 1 - Double(k) * 0.4)
            }
        }
    }

    private func sun(_ layer: inout PixelLayer) {
        let core = RGB(1, 0.86, 0.42)
        for (dy, width) in [(-2, 3), (-1, 5), (0, 5), (1, 5), (2, 3)] {
            layer.fill(8 - width / 2, 6 + dy, width, 1, core)
        }
        // Straight and diagonal rays take turns, which reads as a twinkle.
        let straight = Int(t * 2.5) % 2 == 0
        let rays = straight
            ? [(8, 2), (8, 10), (4, 6), (12, 6)]
            : [(5, 3), (11, 3), (5, 9), (11, 9)]
        for (x, y) in rays { layer.fill(x, y, 1, 1, core, 0.95) }
        let faint = straight
            ? [(5, 3), (11, 3), (5, 9), (11, 9)]
            : [(8, 2), (8, 10), (4, 6), (12, 6)]
        for (x, y) in faint { layer.fill(x, y, 1, 1, core, 0.35) }
    }

    private func moon(_ layer: inout PixelLayer) {
        let lit = RGB(0.92, 0.94, 1)
        for dy in -4 ... 4 {
            for dx in -4 ... 4 {
                let d = Double(dx * dx + dy * dy).squareRoot()
                let bx = Double(dx) - 1.8
                let by = Double(dy) + 1.0
                guard d <= 4.2, (bx * bx + by * by).squareRoot() >= 3.4 else { continue }
                layer.fill(6 + dx, 6 + dy, 1, 1, lit)
            }
        }
        let twinkle = (sin(t * 3) + 1) / 2
        layer.fill(13, 2, 1, 1, lit, 0.5 + 0.5 * twinkle)
        if twinkle > 0.7 {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                layer.fill(13 + dx, 2 + dy, 1, 1, lit, (twinkle - 0.7) * 2)
            }
        }
        layer.fill(14, 8, 1, 1, lit, 0.3 + 0.5 * (1 - twinkle))
    }
}
