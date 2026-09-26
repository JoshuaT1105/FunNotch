//
//  ClosedNotchEditor.swift
//  FunNotch
//
//  The widgets either side of the camera while the notch is closed, edited
//  above a live, magnified copy of the real thing.
//

import SwiftUI

struct ClosedNotchEditor: View {
    @StateObject private var preview = NotchViewModel.makePreview()
    @ObservedObject private var settings = Settings.shared
    @State private var targetedSide: NotchSide?

    private let scale: CGFloat = 1.55

    var body: some View {
        VStack(spacing: 14) {
            StageScreen(
                height: preview.closedNotchSize.height * scale + 64,
                menuBarHeight: preview.closedNotchSize.height * scale,
                scale: scale
            ) {
                LiveClosedNotchPreview(model: preview, scale: scale)
            }
            .padding(.horizontal, 24)

            HStack(alignment: .top, spacing: 12) {
                sidePanel(.leading)
                sidePanel(.trailing)
            }
            .padding(.horizontal, 24)
            .disabled(!settings.idleWidgetsEnabled)
            .opacity(settings.idleWidgetsEnabled ? 1 : 0.45)

            HStack(alignment: .top, spacing: 12) {
                palette
                behaviour
                    .frame(width: 300)
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 18)
    }

    // MARK: Sides

    private func widgets(on side: NotchSide) -> [NotchWidget] {
        side == .leading ? settings.idleLeftWidgets : settings.idleRightWidgets
    }

    private func setWidgets(_ list: [NotchWidget], on side: NotchSide) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            if side == .leading {
                settings.idleLeftWidgets = list
            } else {
                settings.idleRightWidgets = list
            }
        }
    }

    private func sidePanel(_ side: NotchSide) -> some View {
        let list = widgets(on: side)
        let targeted = targetedSide == side
        return CustomizePanel(
            title: side == .leading ? "Left of the camera" : "Right of the camera",
            subtitle: side == .leading ? "The last one sits closest to the camera." : "The first one sits closest to the camera."
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list) { widget in
                        placedChip(widget, side: side)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    if list.isEmpty {
                        Text("Drop widgets here")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.vertical, 7)
                    }
                }
                .padding(2)
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: targeted ? [] : [4, 3]))
                    .foregroundStyle(targeted ? Color.accentColor : Color.white.opacity(0.14))
            )
            .dropDestination(for: String.self) { items, _ in
                targetedSide = nil
                return accept(items.first, on: side, before: nil)
            } isTargeted: { isTargeted in
                withAnimation(.easeOut(duration: 0.12)) {
                    targetedSide = isTargeted ? side : (targetedSide == side ? nil : targetedSide)
                }
            }
        }
    }

    private func placedChip(_ widget: NotchWidget, side: NotchSide) -> some View {
        HStack(spacing: 5) {
            Image(systemName: widget.symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(widget.tint)
            Text(widget.rawValue)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.white)
            Button {
                setWidgets(widgets(on: side).filter { $0 != widget }, on: side)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .padding(.vertical, 6)
        .background(Capsule().fill(widget.tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(widget.tint.opacity(0.35), lineWidth: 0.6))
        .draggable("placed:\(side == .leading ? "L" : "R"):\(widget.rawValue)") {
            chipPreview(widget)
        }
        .dropDestination(for: String.self) { items, _ in
            accept(items.first, on: side, before: widget)
        }
    }

    private func chipPreview(_ widget: NotchWidget) -> some View {
        HStack(spacing: 5) {
            Image(systemName: widget.symbol).foregroundStyle(widget.tint)
            Text(widget.rawValue).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.85)))
    }

    /// A drop carries `widget:Name` from the palette or `placed:L:Name` from a side.
    private func accept(_ raw: String?, on side: NotchSide, before target: NotchWidget?) -> Bool {
        guard let raw else { return false }
        let widget: NotchWidget
        var from: NotchSide?

        if raw.hasPrefix("widget:") {
            guard let found = NotchWidget(rawValue: String(raw.dropFirst(7))) else { return false }
            widget = found
        } else if raw.hasPrefix("placed:") {
            let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3, let found = NotchWidget(rawValue: parts[2]) else { return false }
            widget = found
            from = parts[1] == "L" ? .leading : .trailing
        } else {
            return false
        }
        guard widget != target else { return false }

        if let from, from != side {
            setWidgets(widgets(on: from).filter { $0 != widget }, on: from)
        }
        var list = widgets(on: side).filter { $0 != widget }
        if let target, let index = list.firstIndex(of: target) {
            list.insert(widget, at: index)
        } else {
            list.append(widget)
        }
        setWidgets(list, on: side)
        return true
    }

    // MARK: Palette

    private var palette: some View {
        CustomizePanel(title: "Widgets", subtitle: "Drag one to a side, or use its buttons.") {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 8)], spacing: 8) {
                    ForEach(NotchWidget.allCases) { widget in
                        paletteCard(widget)
                    }
                }
            }
            // Always at least a row of it, however short the window.
            .frame(minHeight: 110, maxHeight: .infinity)
        }
        .disabled(!settings.idleWidgetsEnabled)
        .opacity(settings.idleWidgetsEnabled ? 1 : 0.45)
    }

    private func paletteCard(_ widget: NotchWidget) -> some View {
        HStack(spacing: 8) {
            TintedGlyph(symbol: widget.symbol, tint: widget.tint, size: 24)
            Text(widget.rawValue)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
            sideButton(widget, side: .leading)
            sideButton(widget, side: .trailing)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .contentShape(Rectangle())
        .draggable("widget:" + widget.rawValue) {
            chipPreview(widget)
        }
    }

    private func sideButton(_ widget: NotchWidget, side: NotchSide) -> some View {
        let placed = widgets(on: side).contains(widget)
        return Button {
            if placed {
                setWidgets(widgets(on: side).filter { $0 != widget }, on: side)
            } else {
                _ = accept("widget:" + widget.rawValue, on: side, before: nil)
            }
        } label: {
            Text(side == .leading ? "L" : "R")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(placed ? Color.white : Color.white.opacity(0.55))
                .frame(width: 20, height: 20)
                .background(Circle().fill(placed ? widget.tint.opacity(0.7) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(placed
              ? "Remove from the \(side == .leading ? "left" : "right")"
              : "Add to the \(side == .leading ? "left" : "right")")
    }

    // MARK: Behaviour

    private var behaviour: some View {
        CustomizePanel(title: "What shows here") {
            VStack(alignment: .leading, spacing: 11) {
                Toggle("Widgets", isOn: $settings.idleWidgetsEnabled)
                Toggle("Working AI agents", isOn: $settings.agentActivityEnabled)
                Toggle("Focus countdown", isOn: $settings.focusShowInClosedNotch)
                Toggle("Music spectrum", isOn: $settings.useMusicVisualizer)

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 6) {
                    Text("While music plays")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Picker("", selection: $settings.closedMediaDisplay) {
                        Text("Music").tag(ClosedMediaDisplay.mediaOnly)
                        Text("Both").tag(ClosedMediaDisplay.mediaAndWidgets)
                        Text("Widgets").tag(ClosedMediaDisplay.widgetsOnly)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(!settings.idleWidgetsEnabled)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.system(size: 12))
        }
    }
}
