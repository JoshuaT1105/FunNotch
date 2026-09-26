//
//  StyleEditor.swift
//  FunNotch
//
//  The notch's colour, outline and size, and saved looks to switch between.
//  Changes land on the stage and on the real notch at the same moment.
//

import AppKit
import SwiftUI

struct StyleEditor: View {
    @StateObject private var preview = NotchViewModel.makePreview()
    @ObservedObject private var settings = Settings.shared
    @State private var showsOpen = true

    private let closedScale: CGFloat = 1.55
    private let openScale: CGFloat = 0.78

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                StageScreen(
                    height: openNotchSize.height * openScale + 34,
                    menuBarHeight: showsOpen ? 32 * openScale : preview.closedNotchSize.height * closedScale,
                    scale: showsOpen ? openScale : closedScale
                ) {
                    Group {
                        if showsOpen {
                            OpenNotchMock()
                                .scaleEffect(openScale, anchor: .top)
                                .frame(width: openNotchSize.width * openScale,
                                       height: openNotchSize.height * openScale, alignment: .top)
                        } else {
                            LiveClosedNotchPreview(model: preview, scale: closedScale)
                        }
                    }
                    .transition(.opacity)
                }

                Picker("", selection: $showsOpen.animation(.easeInOut(duration: 0.2))) {
                    Text("Closed").tag(false)
                    Text("Open").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(12)
            }
            .padding(.horizontal, 24)

            ScrollView {
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) {
                        themesPanel
                        colourPanel
                        playerPanel
                    }
                    VStack(spacing: 12) {
                        outlinePanel
                        sizePanel
                        islandPanel
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            .frame(minHeight: 160, maxHeight: .infinity)
        }
    }

    // MARK: Themes

    @State private var savingTheme = false
    @State private var themeName = ""

    private var themesPanel: some View {
        CustomizePanel(
            title: "Looks",
            subtitle: "A colour scheme in one click.",
            trailing: AnyView(
                Button("Save Current…") { savingTheme = true }
                    .controlSize(.small)
                    .popover(isPresented: $savingTheme) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name this look").font(.subheadline.weight(.semibold))
                            TextField("Midnight", text: $themeName)
                                .frame(width: 200)
                                .onSubmit(saveTheme)
                            HStack {
                                Spacer()
                                Button("Save", action: saveTheme)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(themeName.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(14)
                    }
            )
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(NotchTheme.builtIns + settings.savedThemes) { theme in
                    themeCard(theme)
                }
            }
        }
    }

    private func themeCard(_ theme: NotchTheme) -> some View {
        let active = settings.activeThemeName == theme.name
        let saved = settings.savedThemes.contains { $0.name == theme.name }
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { settings.apply(theme: theme) }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(
                            colors: [theme.tintColor.opacity(0.55), theme.accentColor.opacity(0.35)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                    NotchShape(topCornerRadius: 2, bottomCornerRadius: 6)
                        .fill(Color.black)
                        .overlay(
                            NotchShape(topCornerRadius: 2, bottomCornerRadius: 6)
                                .fill(theme.tintColor.opacity(theme.tintIntensity * 0.5))
                        )
                        .frame(width: 44, height: 13)
                }
                .frame(height: 38)
                Text(theme.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(active ? 1 : 0.7))
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(active ? 0.12 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(active ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if saved {
                Button("Delete", role: .destructive) {
                    settings.savedThemes.removeAll { $0.name == theme.name }
                }
            }
        }
    }

    private func saveTheme() {
        let name = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var themes = settings.savedThemes
        themes.removeAll { $0.name == name }
        themes.append(settings.currentTheme(named: name))
        settings.savedThemes = themes
        settings.activeThemeName = name
        themeName = ""
        savingTheme = false
    }

    // MARK: Colour

    private var colourPanel: some View {
        CustomizePanel(title: "Colour", subtitle: "A wash over the black.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    colourSwatch(nil)
                    ForEach([AccentPreset.blue, .indigo, .purple, .pink, .red, .orange, .yellow, .green, .teal]) { preset in
                        colourSwatch(preset.color)
                    }
                    ColorPanelSwatch(current: settings.notchTintColor) { colour in
                        settings.notchTintColor = colour
                        if settings.notchTintIntensity == 0 { settings.notchTintIntensity = 0.3 }
                    }
                }
                CustomizeSlider(
                    title: "Strength",
                    value: Binding(
                        get: { Double(settings.notchTintIntensity) },
                        set: { settings.notchTintIntensity = CGFloat($0) }
                    ),
                    range: 0 ... 1,
                    label: { "\(Int($0 * 100))%" }
                )
            }
        }
    }

    /// Nil is pure black.
    private func colourSwatch(_ colour: Color?) -> some View {
        let selected: Bool = {
            guard let colour else { return settings.notchTintIntensity == 0 }
            return settings.notchTintIntensity > 0
                && NSColor(settings.notchTintColor).isApproximately(NSColor(colour))
        }()
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if let colour {
                    settings.notchTintColor = colour
                    if settings.notchTintIntensity == 0 { settings.notchTintIntensity = 0.3 }
                } else {
                    settings.notchTintIntensity = 0
                }
            }
        } label: {
            Circle()
                .fill(colour ?? Color.black)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white, lineWidth: selected ? 2 : 0)
                        .padding(-3.5)
                )
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(colour == nil ? "Black" : "Tint")
    }

    // MARK: Outline

    private var outlinePanel: some View {
        CustomizePanel(
            title: "Outline",
            subtitle: "A hairline around the notch, drawn inside its edge.",
            trailing: AnyView(
                Toggle("", isOn: $settings.notchBorderEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            )
        ) {
            VStack(alignment: .leading, spacing: 11) {
                CustomizeSlider(
                    title: "Thickness",
                    value: Binding(
                        get: { Double(settings.notchBorderWidth) },
                        set: { settings.notchBorderWidth = CGFloat($0) }
                    ),
                    range: 0.5 ... 3,
                    step: 0.5,
                    label: { String(format: "%.1f pt", $0) }
                )
                CustomizeSlider(
                    title: "Strength",
                    value: Binding(
                        get: { Double(settings.notchBorderOpacity) },
                        set: { settings.notchBorderOpacity = CGFloat($0) }
                    ),
                    range: 0.05 ... 1,
                    label: { "\(Int($0 * 100))%" }
                )
                HStack {
                    Text("Colour")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Picker("", selection: $settings.notchBorderColorSource) {
                        Text("White").tag(BorderColorSource.white)
                        Text("Accent").tag(BorderColorSource.accent)
                        Text("Album art").tag(BorderColorSource.albumArt)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle("Outline the closed notch too", isOn: $settings.notchBorderWhenClosed)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
            }
            .disabled(!settings.notchBorderEnabled)
            .opacity(settings.notchBorderEnabled ? 1 : 0.45)
        }
    }

    // MARK: Size

    private var sizePanel: some View {
        CustomizePanel(title: "Size", subtitle: "How tall the closed notch sits.") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Height")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Picker("", selection: $settings.notchHeightMode) {
                        Text("Match the notch").tag(WindowHeightMode.matchRealNotchSize)
                        Text("Match the menu bar").tag(WindowHeightMode.matchMenuBar)
                        Text("Custom").tag(WindowHeightMode.custom)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if settings.notchHeightMode == .custom {
                    CustomizeSlider(
                        title: "Custom height",
                        value: Binding(
                            get: { Double(settings.notchHeight) },
                            set: { settings.notchHeight = CGFloat($0) }
                        ),
                        range: 20 ... 60,
                        step: 1,
                        label: { "\(Int($0)) pt" }
                    )
                }
                CustomizeSlider(
                    title: "Extra width",
                    value: Binding(
                        get: { Double(settings.notchWidthPadding) },
                        set: { settings.notchWidthPadding = CGFloat($0) }
                    ),
                    range: -10 ... 20,
                    step: 1,
                    label: { "\(Int($0)) pt" }
                )
            }
        }
    }

    // MARK: Other displays

    private var islandPanel: some View {
        CustomizePanel(title: "Displays without a notch", subtitle: "External monitors, and Macs without a cutout.") {
            VStack(alignment: .leading, spacing: 11) {
                Picker("", selection: $settings.nonNotchStyle) {
                    Text("Dynamic Island").tag(NonNotchStyle.island)
                    Text("Fake notch").tag(NonNotchStyle.notch)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if settings.nonNotchStyle == .island {
                    CustomizeSlider(
                        title: "Width",
                        value: Binding(
                            get: { Double(settings.islandWidth) },
                            set: { settings.islandWidth = CGFloat($0) }
                        ),
                        range: 100 ... 260,
                        step: 2,
                        label: { "\(Int($0)) pt" }
                    )
                    CustomizeSlider(
                        title: "Gap from the top",
                        value: Binding(
                            get: { Double(settings.islandTopGap) },
                            set: { settings.islandTopGap = CGFloat($0) }
                        ),
                        range: 0 ... 20,
                        step: 1,
                        label: { "\(Int($0)) pt" }
                    )
                }
            }
        }
    }

    // MARK: Player

    private var playerPanel: some View {
        CustomizePanel(title: "Player", subtitle: "Colours for the music controls.") {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Progress bar")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Picker("", selection: $settings.sliderColor) {
                        Text("White").tag(SliderColorEnum.white)
                        Text("Album art").tag(SliderColorEnum.albumArt)
                        Text("Accent").tag(SliderColorEnum.accent)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                HStack {
                    Toggle("Coloured spectrum", isOn: $settings.coloredSpectrogram)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11.5))
                    Spacer()
                    Picker("", selection: $settings.spectrumColor) {
                        Text("Album art").tag(SliderColorEnum.albumArt)
                        Text("Accent").tag(SliderColorEnum.accent)
                        Text("White").tag(SliderColorEnum.white)
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.coloredSpectrogram)
                }
                HStack {
                    Text("Camera mirror")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Picker("", selection: $settings.mirrorShape) {
                        Text("Rounded").tag(MirrorShapeEnum.rectangle)
                        Text("Circle").tag(MirrorShapeEnum.circle)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }
}

/// A rainbow swatch that opens the system colour panel, for any colour the
/// presets do not have. SwiftUI's ColorPicker draws the old square colour well,
/// which sits badly at the end of a row of round swatches.
struct ColorPanelSwatch: View {
    let current: Color
    let onChange: (Color) -> Void

    var body: some View {
        Button {
            ColorPanelBridge.shared.open(with: current, onChange: onChange)
        } label: {
            Circle()
                .fill(AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                    center: .center
                ))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                )
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help("Any colour")
    }
}

/// Routes the shared colour panel's changes to whichever swatch opened it.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var onChange: ((Color) -> Void)?

    func open(with colour: Color, onChange: @escaping (Color) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(colour)
        panel.setTarget(self)
        panel.setAction(#selector(colourChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colourChanged(_ sender: NSColorPanel) {
        onChange?(Color(nsColor: sender.color))
    }
}

/// A labelled slider with its value beside it, for the dark panels.
struct CustomizeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let label: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 104, alignment: .leading)
            // Snapped here rather than with Slider's own `step`, which draws a
            // tick for every step — a picket fence on a 160-step range.
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
            Text(label(value))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 44, alignment: .trailing)
        }
    }
}

/// The open notch as shapes — its silhouette, colour and outline, with the
/// home layout drawn as blocks. The real one is not used here: the camera
/// mirror switches the camera on the moment it appears.
struct OpenNotchMock: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        let tiles = settings.homeTiles
        ZStack(alignment: .top) {
            Color.black
            if settings.notchTintIntensity > 0 {
                settings.notchTintColor.opacity(settings.notchTintIntensity * 0.5)
            }
            VStack(spacing: 0) {
                NotchHeaderMock()
                    .frame(height: 32)
                VStack(spacing: 8) {
                    mockRow(tiles.filter { $0.row == 0 }, spacing: 14)
                        .frame(height: 100)
                    mockRow(tiles.filter { $0.row == 1 }, spacing: 6)
                        .frame(height: 46)
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .frame(width: openNotchSize.width, height: openNotchSize.height)
        .clipShape(NotchShape(
            topCornerRadius: cornerRadiusInsets.opened.top,
            bottomCornerRadius: cornerRadiusInsets.opened.bottom
        ))
        .overlay {
            if settings.notchBorderEnabled {
                NotchOutline(
                    topCornerRadius: cornerRadiusInsets.opened.top,
                    bottomCornerRadius: cornerRadiusInsets.opened.bottom,
                    inset: settings.notchBorderWidth / 2
                )
                .stroke(
                    settings.resolvedBorderColor(albumArt: music.artworkColor)
                        .opacity(settings.notchBorderOpacity),
                    lineWidth: settings.notchBorderWidth
                )
            }
        }
    }

    private func mockRow(_ row: [HomeTile], spacing: CGFloat) -> some View {
        let width = openNotchSize.width - 44
        let total = max(row.reduce(0) { $0 + CGFloat($1.span) }, 1)
        let available = width - spacing * CGFloat(max(row.count - 1, 0))
        return HStack(spacing: spacing) {
            ForEach(row) { tile in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Image(systemName: tile.kind.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(tile.kind.tint.opacity(0.85))
                    )
                    .frame(width: max(available * CGFloat(tile.span) / total, 30))
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
