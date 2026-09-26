//
//  SettingsComponents.swift
//  FunNotch
//
//  The handful of pieces every settings page is built from: a page header, a
//  card, a row, and the coloured icons down the sidebar. Pages only say what
//  they contain; everything about how it looks lives here.
//

import AppKit
import SwiftUI

// MARK: - Colours

enum SettingsStyle {
    /// Behind the pages: a touch darker than the cards sitting on it.
    static let pageBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.125, alpha: 1)
            : NSColor(calibratedWhite: 0.955, alpha: 1)
    })

    static let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1, alpha: 0.055)
            : NSColor.white
    })

    static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1, alpha: 0.07)
            : NSColor(calibratedWhite: 0, alpha: 0.07)
    })

    /// The site's gradient, used wherever the app talks about its own look.
    static let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.14, green: 0.54, blue: 0.86),
            Color(red: 0.35, green: 0.44, blue: 0.83),
            Color(red: 0.64, green: 0.34, blue: 0.73),
            Color(red: 0.82, green: 0.44, blue: 0.53),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let gray = Color(red: 0.55, green: 0.56, blue: 0.6)
    static let purple = Color(red: 0.62, green: 0.36, blue: 0.95)
    static let pink = Color(red: 1.0, green: 0.28, blue: 0.43)
    static let blue = Color(red: 0.16, green: 0.5, blue: 1.0)
    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.92)
    static let red = Color(red: 1.0, green: 0.3, blue: 0.28)
    static let green = Color(red: 0.2, green: 0.74, blue: 0.4)
    static let orange = Color(red: 1.0, green: 0.58, blue: 0.1)
    static let teal = Color(red: 0.1, green: 0.68, blue: 0.75)
    static let yellow = Color(red: 0.98, green: 0.76, blue: 0.1)
}

// MARK: - Icons

/// A white glyph on a rounded square of colour, the way System Settings draws
/// its sidebar.
struct SettingsIcon: View {
    let symbol: String
    var tint: Color = SettingsStyle.gray
    var gradient: LinearGradient?
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(gradient ?? LinearGradient(
                colors: [tint.opacity(0.88), tint],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Page

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = SettingsStyle.gray
    var gradient: LinearGradient?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                SettingsIcon(symbol: symbol, tint: tint, gradient: gradient, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card

/// A rounded group of rows with hairlines between them.
struct SettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }
            DividedStack { content }
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(SettingsStyle.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(SettingsStyle.cardBorder, lineWidth: 0.5)
                )
            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

/// A vertical stack that draws a hairline between each of its children, so a
/// card never has to be told where its rows begin and end — rows that are
/// switched off simply take their divider with them.
struct DividedStack<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        _VariadicView.Tree(DividedStackRoot()) { content }
    }
}

private struct DividedStackRoot: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let lastID = children.last?.id
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != lastID {
                    Divider().padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: - Rows

/// Title and optional explanation on the left, a control on the right.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = SettingsStyle.gray
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 11) {
            if let symbol {
                SettingsIcon(symbol: symbol, tint: tint, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil, tint: Color = SettingsStyle.gray) {
        self.init(title: title, subtitle: subtitle, symbol: symbol, tint: tint) { EmptyView() }
    }
}

/// The row almost every setting is: a switch, and optionally a button that
/// shows the thing it controls in the notch right now.
struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = SettingsStyle.gray
    @Binding var isOn: Bool
    var preview: (() -> Void)?

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, symbol: symbol, tint: tint) {
            HStack(spacing: 10) {
                if let preview {
                    PreviewInNotchButton(action: preview)
                        .disabled(!isOn)
                }
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }
}

/// A menu of choices, sized to its content.
struct SettingsPicker<Value: Hashable, Options: View>: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = SettingsStyle.gray
    @Binding var selection: Value
    @ViewBuilder let options: Options

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, symbol: symbol, tint: tint) {
            Picker("", selection: $selection) { options }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
    }
}

/// A slider with its value written beside it.
struct SettingsSlider: View {
    let title: String
    var subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { value },
                        set: { newValue in
                            value = step.map { (newValue / $0).rounded() * $0 } ?? newValue
                        }
                    ),
                    in: range
                )
                .controlSize(.small)
                .frame(width: 170)
                Text(format(value))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 46, alignment: .trailing)
            }
        }
    }
}

/// A small round button that fires the real announcement in the notch, so a
/// setting can be seen before it is kept.
struct PreviewInNotchButton: View {
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(hovering && isEnabled ? Color.white : Color.secondary)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(hovering && isEnabled ? Color.accentColor : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Show it in the notch")
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A capsule that toggles, for picking several of a few things in one row.
struct ChipToggle: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? Color.accentColor : Color.primary.opacity(0.07))
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A status line inside a card: a coloured symbol and a sentence.
struct SettingsStatus: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Window chrome

/// A native blurred material behind SwiftUI content.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
