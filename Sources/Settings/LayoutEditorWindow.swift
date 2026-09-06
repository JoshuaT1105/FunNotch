//
//  LayoutEditorWindow.swift
//  FunNotch
//
//  The home-screen editor, in its own window.
//
//  Editing inside the notch itself is not workable: it is 200 points tall, it
//  closes when the pointer leaves, and the thing being edited is the thing you
//  would be dragging in. So the layout is built at a comfortable size here and
//  the notch simply renders the result.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LayoutEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = LayoutEditorWindowController()

    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: LayoutEditorView { [weak self] in
            self?.window?.close()
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Customise Home Screen"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Editor

struct LayoutEditorView: View {
    let onClose: () -> Void

    /// Edited in a copy so Cancel means something. The notch keeps rendering
    /// the saved layout while this window is open.
    @State private var tiles: [HomeTile] = Settings.shared.homeTiles
    @State private var selection: UUID?
    @State private var dragging: HomeTileKind?

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            palette
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your notch")
                .font(.headline)
            Text("Drag a widget from below into a row. Click one to resize or remove it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                editorRow(0, label: "Main row", height: 118)
                editorRow(1, label: "Strip", height: 54)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08))
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorRow(_ row: Int, label: String, height: CGFloat) -> some View {
        let rowTiles = tiles.filter { $0.row == row }
        return VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.3))

            GeometryReader { geo in
                let spacing: CGFloat = 6
                let total = max(rowTiles.reduce(0) { $0 + CGFloat($1.span) }, 1)
                let available = geo.size.width - spacing * CGFloat(max(rowTiles.count - 1, 0))

                HStack(spacing: spacing) {
                    if rowTiles.isEmpty {
                        emptyRowHint
                    } else {
                        ForEach(rowTiles) { tile in
                            tileChip(tile)
                                .frame(width: max(available * CGFloat(tile.span) / total, 40))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let kind = HomeTileKind(rawValue: raw) else { return false }
                add(kind, to: row)
                return true
            }
        }
    }

    private var emptyRowHint: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.white.opacity(0.18))
            .overlay(
                Text("Drop a widget here")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
            )
            .frame(maxWidth: .infinity)
    }

    private func tileChip(_ tile: HomeTile) -> some View {
        let isSelected = selection == tile.id
        return VStack(spacing: 4) {
            Image(systemName: tile.kind.symbol)
                .font(.system(size: 13))
            Text(tile.appName ?? tile.kind.rawValue)
                .font(.system(size: 9.5))
                .lineLimit(1)
            if isSelected {
                controls(for: tile)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.28) : .white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = isSelected ? nil : tile.id }
    }

    private func controls(for tile: HomeTile) -> some View {
        HStack(spacing: 3) {
            Button {
                resize(tile, by: -1)
            } label: { Image(systemName: "minus") }
            .disabled(tile.span <= tile.kind.minimumSpan)

            Text("\(tile.span)")
                .font(.system(size: 9, design: .monospaced))
                .frame(minWidth: 12)

            Button {
                resize(tile, by: 1)
            } label: { Image(systemName: "plus") }
            .disabled(tile.span >= 8)

            Button {
                move(tile)
            } label: { Image(systemName: "arrow.up.arrow.down") }
            .help("Move to the other row")

            if tile.kind == .openApp {
                Button {
                    chooseApp(for: tile)
                } label: { Image(systemName: "folder") }
                .help("Choose the app")
            }

            Button(role: .destructive) {
                tiles.removeAll { $0.id == tile.id }
                selection = nil
            } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 9))
    }

    // MARK: Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
                ForEach(available) { kind in
                    paletteChip(kind)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paletteChip(_ kind: HomeTileKind) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(kind.rawValue)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .contentShape(Rectangle())
        .draggable(kind.rawValue) {
            Label(kind.rawValue, systemImage: kind.symbol)
                .padding(6)
                .background(.thinMaterial)
        }
        .onTapGesture(count: 2) { add(kind, to: kind.naturalRow) }
        .help("Drag onto a row, or double-click to add")
    }

    /// A kind already placed disappears from the palette, unless it is one that
    /// makes sense more than once.
    private var available: [HomeTileKind] {
        HomeTileKind.allCases.filter { kind in
            kind.allowsDuplicates || !tiles.contains { $0.kind == kind }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button("Reset to Default") {
                tiles = HomeLayout.default
                selection = nil
            }
            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                Settings.shared.homeTiles = tiles
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: Mutations

    private func add(_ kind: HomeTileKind, to row: Int) {
        guard kind.allowsDuplicates || !tiles.contains(where: { $0.kind == kind }) else { return }
        let tile = HomeTile(kind: kind, row: row)
        tiles.append(tile)
        selection = tile.id
        if kind == .openApp { chooseApp(for: tile) }
    }

    private func resize(_ tile: HomeTile, by delta: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        let next = tiles[index].span + delta
        tiles[index].span = min(max(next, tile.kind.minimumSpan), 8)
    }

    private func move(_ tile: HomeTile) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index].row = tiles[index].row == 0 ? 1 : 0
    }

    private func chooseApp(for tile: HomeTile) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url,
              let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index].appPath = url.path
    }
}
