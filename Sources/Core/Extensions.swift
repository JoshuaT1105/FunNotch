//
//  Extensions.swift
//  FunNotch
//
//  Small shared helpers: artwork colour sampling, time formatting, and a few
//  SwiftUI conveniences.
//

import AppKit
import SwiftUI

extension NSImage {
    /// Samples the artwork down to a tiny bitmap and picks a vibrant primary
    /// colour plus a muted companion, used to tint the player.
    func dominantColors() -> (primary: NSColor, secondary: NSColor) {
        let side = 12
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (.gray, .darkGray)
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (.gray, .darkGray)
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var best: (score: CGFloat, color: NSColor) = (-1, .gray)
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        var count: CGFloat = 0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[index]) / 255
            let g = CGFloat(pixels[index + 1]) / 255
            let b = CGFloat(pixels[index + 2]) / 255
            let alpha = CGFloat(pixels[index + 3]) / 255
            guard alpha > 0.3 else { continue }

            totalR += r; totalG += g; totalB += b; count += 1

            let maxComponent = max(r, g, b)
            let minComponent = min(r, g, b)
            let saturation = maxComponent == 0 ? 0 : (maxComponent - minComponent) / maxComponent
            // Prefer colourful mid-tones over near-black or blown-out pixels.
            let score = saturation * (1 - abs(maxComponent - 0.65))
            if score > best.score {
                best = (score, NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
            }
        }

        guard count > 0 else { return (.gray, .darkGray) }

        let average = NSColor(
            srgbRed: totalR / count,
            green: totalG / count,
            blue: totalB / count,
            alpha: 1
        )

        // Keep the primary readable against the notch's black background.
        let primary = best.color.adjusted(minimumBrightness: 0.42, minimumSaturation: 0.22)
        return (primary, average)
    }

    /// A square, aspect-filled copy at the requested size.
    func resized(to size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: CGRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        image.unlockFocus()
        return image
    }
}

extension NSColor {
    /// Raises brightness and saturation to a floor so tints stay visible.
    func adjusted(minimumBrightness: CGFloat, minimumSaturation: CGFloat) -> NSColor {
        guard let converted = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: max(saturation, minimumSaturation),
            brightness: max(brightness, minimumBrightness),
            alpha: alpha
        )
    }

    /// Loose equality, so a swatch still reads as selected after a colour has
    /// made a round trip through the colour picker.
    func isApproximately(_ other: NSColor, tolerance: CGFloat = 0.02) -> Bool {
        guard let lhs = usingColorSpace(.sRGB), let rhs = other.usingColorSpace(.sRGB) else {
            return false
        }
        return abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }

    var isLight: Bool {
        guard let converted = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * converted.redComponent
            + 0.587 * converted.greenComponent
            + 0.114 * converted.blueComponent
        return luminance > 0.6
    }
}

extension TimeInterval {
    /// `m:ss`, or `h:mm:ss` for long tracks.
    var playbackTimestamp: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self)
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension View {
    /// Applies a transform only when `condition` holds.
    @ViewBuilder
    func applyIf<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Hides the view without removing it from layout.
    @ViewBuilder
    func invisible(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
    }
}

extension Color {
    static let notchBackground = Color.black
}

extension SliderColorEnum {
    /// Resolves the choice against the colours available right now.
    func resolved(albumArt: Color, accent: Color) -> Color {
        switch self {
        case .white: return .white
        case .albumArt: return albumArt
        case .accent: return accent
        }
    }
}

/// Accent colours offered as one-click swatches in Settings.
enum AccentPreset: String, CaseIterable, Identifiable {
    case system = "System"
    case blue = "Blue"
    case indigo = "Indigo"
    case purple = "Purple"
    case pink = "Pink"
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case mint = "Mint"
    case teal = "Teal"
    case cyan = "Cyan"
    case brown = "Brown"
    case graphite = "Graphite"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .brown: return .brown
        case .graphite: return Color(white: 0.62)
        }
    }
}

/// Formats a byte count the way Finder does.
func formattedFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    return formatter.string(fromByteCount: bytes)
}

extension FileManager {
    /// The first standard directory of a kind, or the conventional path if the
    /// system offers none.
    ///
    /// `urls(for:in:)` is documented as possibly returning an empty array, and
    /// every caller here took `[0]` from it. Some of those run inside lazy or
    /// static initialisers — the shelf's storage, the blocked-page file — where
    /// an out-of-range crash would mean the app simply refuses to start, on a
    /// machine the developer cannot reproduce. A fallback costs nothing.
    func standardDirectory(
        _ directory: SearchPathDirectory,
        fallback: String
    ) -> URL {
        urls(for: directory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(fallback, isDirectory: true)
    }
}
