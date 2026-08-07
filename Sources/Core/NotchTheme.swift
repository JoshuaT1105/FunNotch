//
//  NotchTheme.swift
//  FunNotch
//
//  A named bundle of the colour settings, so a look can be saved and switched
//  back to later. Colours travel as hex strings rather than archived NSColors
//  so a theme stays readable and portable.
//

import AppKit
import SwiftUI

struct NotchTheme: Codable, Identifiable, Equatable {
    var name: String
    /// Nil means "follow the system accent colour".
    var accent: String?
    var notchTint: String
    var tintIntensity: Double
    var sliderColor: String
    var spectrumColor: String

    var id: String { name }

    var accentColor: Color {
        accent.map(Self.decode) ?? .accentColor
    }

    var tintColor: Color {
        Self.decode(notchTint)
    }

    // MARK: - Colour encoding

    static func encode(_ color: Color) -> String {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let red = Int(round(converted.redComponent * 255))
        let green = Int(round(converted.greenComponent * 255))
        let blue = Int(round(converted.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    static func decode(_ hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return .white }
        return Color(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    // MARK: - Built-ins

    static let builtIns: [NotchTheme] = [
        NotchTheme(
            name: "Default",
            accent: nil,
            notchTint: "#0A84FF",
            tintIntensity: 0,
            sliderColor: SliderColorEnum.white.rawValue,
            spectrumColor: SliderColorEnum.albumArt.rawValue
        ),
        NotchTheme(
            name: "Midnight",
            accent: "#5E5CE6",
            notchTint: "#1B1B3A",
            tintIntensity: 0.35,
            sliderColor: SliderColorEnum.accent.rawValue,
            spectrumColor: SliderColorEnum.accent.rawValue
        ),
        NotchTheme(
            name: "Sunset",
            accent: "#FF6B35",
            notchTint: "#3B1F2B",
            tintIntensity: 0.4,
            sliderColor: SliderColorEnum.albumArt.rawValue,
            spectrumColor: SliderColorEnum.albumArt.rawValue
        ),
        NotchTheme(
            name: "Forest",
            accent: "#30D158",
            notchTint: "#12261A",
            tintIntensity: 0.35,
            sliderColor: SliderColorEnum.accent.rawValue,
            spectrumColor: SliderColorEnum.accent.rawValue
        ),
        NotchTheme(
            name: "Mono",
            accent: "#9E9E9E",
            notchTint: "#000000",
            tintIntensity: 0,
            sliderColor: SliderColorEnum.white.rawValue,
            spectrumColor: SliderColorEnum.white.rawValue
        ),
        NotchTheme(
            name: "Bubblegum",
            accent: "#FF375F",
            notchTint: "#3A1030",
            tintIntensity: 0.45,
            sliderColor: SliderColorEnum.accent.rawValue,
            spectrumColor: SliderColorEnum.albumArt.rawValue
        ),
    ]
}
