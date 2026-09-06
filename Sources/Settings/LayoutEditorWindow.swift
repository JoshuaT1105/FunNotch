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
    /// what is saved while this window is open.
    @State private var layouts: [LayoutCase: [HomeTile]] = [:]
    @State private var editing: LayoutCase = .standard
    @State private var selection: UUID?
    @State private var dropTargetRow: Int?
    @State private var overTrash = false
    @State private var slotNames: [String] = []
    @State private var slotName = ""
    @State private var showingSaveSlot = false

    /// The preview is drawn at the notch's real width so the proportions on
    /// screen are the proportions you get. It also means no measurement: a
    /// GeometryReader here would have to be told a width by a container that
    /// is sizing itself to its content.
    private let previewWidth: CGFloat = 646

    private var tiles: [HomeTile] {
        get { layouts[editing] ?? [] }
        nonmutating set { layouts[editing] = newValue }
    }

    private var isInheriting: Bool {
        editing != .standard && layouts[editing] == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            caseTabs
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stage
                    palette
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(minWidth: 780, minHeight: 600)
        .onAppear(perform: load)
    }

    // MARK: Cases

    private var caseTabs: some View {
        HStack(spacing: 6) {
            ForEach(LayoutCase.allCases) { item in
                caseTab(item)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func caseTab(_ item: LayoutCase) -> some View {
        let selected = editing == item
        let customised = item == .standard || layouts[item] != nil
        return Button {
            editing = item
            selection = nil
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.caption)
                Text(item.rawValue)
                    .font(.callout)
                if !customised {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .help(item.explanation)
    }

    // MARK: Stage

    private var stage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(editing == .standard ? "Your notch" : editing.rawValue)
                        .font(.headline)
                    Text(editing.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trash
            }

            if isInheriting {
                inheritNotice
            } else {
                notchPreview
            }
        }
    }

    private var inheritNotice: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Uses the Default layout")
                .font(.callout.weight(.medium))
            Text("Give this situation a notch of its own and it takes over whenever it applies.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Customise for this case") {
                layouts[editing] = HomeLayout.starter(for: editing)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var notchPreview: some View {
        VStack(spacing: 8) {
            stageRow(0, label: "Main row", height: 116)
            stageRow(1, label: "Strip", height: 54)
        }
        .padding(12)
        .frame(width: previewWidth + 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.09))
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func stageRow(_ row: Int, label: String, height: CGFloat) -> some View {
        let rowTiles = tiles.filter { $0.row == row }
        let spacing: CGFloat = 6
        let total = max(rowTiles.reduce(0) { $0 + CGFloat($1.span) }, 1)
        let available = previewWidth - spacing * CGFloat(max(rowTiles.count - 1, 0))

        return VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(dropTargetRow == row ? 0.8 : 0.3))

            HStack(spacing: spacing) {
                if rowTiles.isEmpty {
                    emptyRowHint
                } else {
                    ForEach(rowTiles) { tile in
                        tileChip(tile)
                            .frame(width: max(available * CGFloat(tile.span) / total, 44))
                    }
                }
            }
            .frame(width: previewWidth, height: height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(dropTargetRow == row ? Color.accentColor.opacity(0.12) : .clear)
            )
            .dropDestination(for: String.self) { items, _ in
                dropTargetRow = nil
                return handleDrop(items, into: row)
            } isTargeted: { targeted in
                dropTargetRow = targeted ? row : (dropTargetRow == row ? nil : dropTargetRow)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A placed tile. Draggable, so it can be reordered, thrown into the other
    /// row, or dropped on the bin.
    private func tileChip(_ tile: HomeTile) -> some View {
        let isSelected = selection == tile.id
        return VStack(spacing: 4) {
            Image(systemName: tile.kind.symbol)
                .font(.system(size: 13))
            Text(tile.appName ?? tile.kind.rawValue)
                .font(.system(size: 9.5))
                .lineLimit(1)
            if isSelected {
                spanControls(for: tile)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.30) : .white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = isSelected ? nil : tile.id }
        .draggable(tile.id.uuidString) {
            Label(tile.kind.rawValue, systemImage: tile.kind.symbol)
                .padding(6)
                .background(.thinMaterial)
        }
        .dropDestination(for: String.self) { items, _ in
            // Dropping one tile onto another puts it in that position, which is
            // how reordering works without an insertion caret to aim at.
            guard let raw = items.first else { return false }
            return reorder(raw, before: tile)
        }
    }

    private func spanControls(for tile: HomeTile) -> some View {
        HStack(spacing: 4) {
            Button { resize(tile, by: -1) } label: { Image(systemName: "minus") }
                .disabled(tile.span <= tile.kind.minimumSpan)
            Text("\(tile.span)")
                .font(.system(size: 9, design: .monospaced))
                .frame(minWidth: 10)
            Button { resize(tile, by: 1) } label: { Image(systemName: "plus") }
                .disabled(tile.span >= 8)
            if tile.kind == .openApp {
                Button { chooseApp(for: tile) } label: { Image(systemName: "folder") }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 9))
    }

    /// Somewhere to throw a tile you are done with.
    private var trash: some View {
        HStack(spacing: 5) {
            Image(systemName: overTrash ? "trash.fill" : "trash")
            Text("Drop to remove").font(.caption)
        }
        .foregroundStyle(overTrash ? Color.red : .secondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(overTrash ? Color.red.opacity(0.16) : Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(overTrash ? Color.red.opacity(0.6) : Color.secondary.opacity(0.3))
        )
        .dropDestination(for: String.self) { items, _ in
            overTrash = false
            guard let raw = items.first, let id = UUID(uuidString: raw) else { return false }
            tiles.removeAll { $0.id == id }
            if selection == id { selection = nil }
            return true
        } isTargeted: { overTrash = $0 }
    }

    // MARK: Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(HomeTileKind.allCases) { kind in
                    paletteChip(kind)
                }
            }
        }
    }

    private func paletteChip(_ kind: HomeTileKind) -> some View {
        let placed = !kind.allowsDuplicates && tiles.contains { $0.kind == kind }
        return HStack(spacing: 7) {
            Image(systemName: kind.symbol)
                .frame(width: 16)
                .foregroundStyle(placed ? .tertiary : .secondary)
            Text(kind.rawValue)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
            if placed {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(placed ? 0.06 : 0.14))
        )
        .opacity(placed ? 0.5 : 1)
        .contentShape(Rectangle())
        .draggable("kind:" + kind.rawValue) {
            Label(kind.rawValue, systemImage: kind.symbol)
                .padding(6)
                .background(.thinMaterial)
        }
        .onTapGesture(count: 2) { add(kind, to: kind.naturalRow) }
        .help(placed ? "Already in this layout" : "Drag onto a row, or double-click to add")
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            slotMenu

            if editing != .standard, layouts[editing] != nil {
                Button("Use Default Instead") {
                    layouts[editing] = nil
                    selection = nil
                }
            }

            Button("Reset") {
                layouts[editing] = editing == .standard
                    ? HomeLayout.default
                    : HomeLayout.starter(for: editing)
                selection = nil
            }

            Spacer()
            Button("Cancel") { onClose() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    private var slotMenu: some View {
        Menu {
            Button("Save this layout as…") { showingSaveSlot = true }
            if !slotNames.isEmpty {
                Divider()
                ForEach(slotNames, id: \.self) { name in
                    Button(name) {
                        if let loaded = Settings.shared.layoutSlot(name) {
                            layouts[editing] = loaded
                            selection = nil
                        }
                    }
                }
                Divider()
                Menu("Delete") {
                    ForEach(slotNames, id: \.self) { name in
                        Button(name) {
                            Settings.shared.deleteLayoutSlot(name)
                            slotNames = Settings.shared.layoutSlotNames
                        }
                    }
                }
            }
        } label: {
            Label("Saved layouts", systemImage: "square.stack.3d.up")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showingSaveSlot) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name this layout").font(.subheadline.weight(.semibold))
                TextField("Desk setup", text: $slotName)
                    .frame(width: 190)
                    .onSubmit(commitSlot)
                HStack {
                    Spacer()
                    Button("Save", action: commitSlot)
                        .buttonStyle(.borderedProminent)
                        .disabled(slotName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
        }
    }

    // MARK: Actions

    private func load() {
        var found: [LayoutCase: [HomeTile]] = [:]
        for item in LayoutCase.allCases {
            if let tiles = Settings.shared.homeTiles(for: item) { found[item] = tiles }
        }
        layouts = found
        // Read once here rather than on every redraw: reaching into
        // UserDefaults from a view body is a disk hit per frame.
        slotNames = Settings.shared.layoutSlotNames
    }

    private func save() {
        for item in LayoutCase.allCases {
            if let tiles = layouts[item] {
                Settings.shared.setHomeTiles(tiles, for: item)
            } else {
                Settings.shared.clearHomeTiles(for: item)
            }
        }
        onClose()
    }

    private func commitSlot() {
        Settings.shared.saveLayoutSlot(slotName, tiles: tiles)
        slotNames = Settings.shared.layoutSlotNames
        slotName = ""
        showingSaveSlot = false
    }

    /// A drop carries either `kind:Name` from the palette or a tile's UUID.
    private func handleDrop(_ items: [String], into row: Int) -> Bool {
        guard let raw = items.first else { return false }

        if raw.hasPrefix("kind:") {
            guard let kind = HomeTileKind(rawValue: String(raw.dropFirst(5))) else { return false }
            add(kind, to: row)
            return true
        }

        guard let id = UUID(uuidString: raw),
              let index = tiles.firstIndex(where: { $0.id == id }) else { return false }
        // Moving between rows keeps the tile's size; moving within a row sends
        // it to the end, which is the only sensible target for a drop on empty
        // space.
        var moved = tiles[index]
        moved.row = row
        tiles.remove(at: index)
        tiles.append(moved)
        return true
    }

    private func reorder(_ raw: String, before target: HomeTile) -> Bool {
        if raw.hasPrefix("kind:") {
            guard let kind = HomeTileKind(rawValue: String(raw.dropFirst(5))) else { return false }
            add(kind, to: target.row)
            return true
        }
        guard let id = UUID(uuidString: raw), id != target.id,
              let from = tiles.firstIndex(where: { $0.id == id }) else { return false }
        var moved = tiles[from]
        moved.row = target.row
        tiles.remove(at: from)
        guard let to = tiles.firstIndex(where: { $0.id == target.id }) else {
            tiles.append(moved)
            return true
        }
        tiles.insert(moved, at: to)
        return true
    }

    private func add(_ kind: HomeTileKind, to row: Int) {
        guard kind.allowsDuplicates || !tiles.contains(where: { $0.kind == kind }) else { return }
        let tile = HomeTile(kind: kind, row: row)
        tiles.append(tile)
        selection = tile.id
        if kind == .openApp { chooseApp(for: tile) }
    }

    private func resize(_ tile: HomeTile, by delta: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        tiles[index].span = min(max(tiles[index].span + delta, tile.kind.minimumSpan), 8)
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
