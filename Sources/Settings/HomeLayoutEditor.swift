//
//  HomeLayoutEditor.swift
//  FunNotch
//
//  The home screen, laid out on a life-size open notch. Drag widgets in from
//  the gallery, drag them around to reorder or move rows, click one to resize
//  it, throw it on the bin to remove it. Every change is saved as it happens.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HomeLayoutEditor: View {
    /// Mirrors what is saved, so the view is not decoding preferences on every
    /// redraw. Writes go straight through to Settings.
    @State private var layouts: [LayoutCase: [HomeTile]] = [:]
    @State private var editing: LayoutCase = .standard
    @State private var selection: UUID?
    @State private var dropTargetRow: Int?
    @State private var overTrash = false
    @State private var slotNames: [String] = []
    @State private var slotName = ""
    @State private var showingSaveSlot = false

    @ObservedObject private var settings = Settings.shared

    /// Rows are drawn at the notch's real width, so the proportions on screen
    /// are the proportions you get.
    private let rowWidth: CGFloat = openNotchSize.width - 44

    private var tiles: [HomeTile] {
        get { layouts[editing] ?? [] }
        nonmutating set {
            layouts[editing] = newValue
            Settings.shared.setHomeTiles(newValue, for: editing)
        }
    }

    private var isInheriting: Bool {
        editing != .standard && layouts[editing] == nil
    }

    private var selectedTile: HomeTile? {
        guard let selection else { return nil }
        return tiles.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 14) {
            caseBar
                .padding(.horizontal, 24)

            StageScreen(height: openNotchSize.height + 22) {
                stageNotch
            }
            .padding(.horizontal, 24)

            inspector
                .padding(.horizontal, 24)

            gallery
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 18)
        .onAppear(perform: load)
    }

    // MARK: Situations

    private var caseBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(LayoutCase.allCases) { item in
                    caseButton(item)
                }
            }
            Spacer(minLength: 8)
            Text(editing.explanation)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 260, alignment: .trailing)
        }
    }

    private func caseButton(_ item: LayoutCase) -> some View {
        let selected = editing == item
        let hasOwn = item == .standard || layouts[item] != nil
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                editing = item
                selection = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(item.rawValue)
                    .font(.system(size: 11.5, weight: .medium))
                if !hasOwn {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(hasOwn ? 0.7 : 0.45))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(hasOwn ? item.explanation : "Uses the Default layout until you give it its own")
    }

    // MARK: Stage

    private var stageNotch: some View {
        ZStack(alignment: .top) {
            Color.black
            if settings.notchTintIntensity > 0 {
                settings.notchTintColor.opacity(settings.notchTintIntensity * 0.5)
            }
            VStack(spacing: 0) {
                NotchHeaderMock()
                    .frame(height: 32)
                if isInheriting {
                    inheritNotice
                } else {
                    VStack(spacing: 8) {
                        stageRow(0, height: 100)
                        stageRow(1, height: 46)
                    }
                    .padding(.top, 10)
                }
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
        .contentShape(Rectangle())
        .onTapGesture { selection = nil }
    }

    private var inheritNotice: some View {
        VStack(spacing: 9) {
            Image(systemName: editing.symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text("\(editing.rawValue) uses your Default layout")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Give it its own, and it takes over whenever this applies.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Button("Give It Its Own Layout") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    tiles = HomeLayout.starter(for: editing)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stageRow(_ row: Int, height: CGFloat) -> some View {
        let rowTiles = tiles.filter { $0.row == row }
        let spacing: CGFloat = row == 0 ? 14 : 6
        let total = max(rowTiles.reduce(0) { $0 + CGFloat($1.span) }, 1)
        let available = rowWidth - spacing * CGFloat(max(rowTiles.count - 1, 0))

        return HStack(spacing: spacing) {
            if rowTiles.isEmpty {
                emptyRowHint(row)
            } else {
                ForEach(rowTiles) { tile in
                    tileChip(tile, height: height)
                        .frame(width: max(available * CGFloat(tile.span) / total, 40))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
        }
        .frame(width: rowWidth, height: height, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(dropTargetRow == row ? 0.9 : 0), lineWidth: 1.5)
                .padding(-4)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: rowTiles.map(\.id))
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: rowTiles.map(\.span))
        .dropDestination(for: String.self) { items, _ in
            dropTargetRow = nil
            return handleDrop(items, into: row)
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) {
                dropTargetRow = targeted ? row : (dropTargetRow == row ? nil : dropTargetRow)
            }
        }
    }

    private func emptyRowHint(_ row: Int) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(.white.opacity(0.2))
            .overlay(
                Text(row == 0 ? "Drop a widget here" : "Drop compact widgets here")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A placed widget: its colour, its glyph and its name. Draggable to
    /// reorder, move rows or throw away; clicking it selects it.
    private func tileChip(_ tile: HomeTile, height: CGFloat) -> some View {
        let isSelected = selection == tile.id
        let tint = tile.kind.tint
        let large = height > 60

        return VStack(spacing: large ? 7 : 3) {
            Image(systemName: tile.kind.symbol)
                .font(.system(size: large ? 20 : 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(tile.appName ?? tile.kind.rawValue)
                .font(.system(size: large ? 11 : 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            if large {
                SpanDots(span: tile.span, tint: tint)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: large ? 12 : 9, style: .continuous)
                .fill(tint.opacity(isSelected ? 0.26 : 0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: large ? 12 : 9, style: .continuous)
                .strokeBorder(isSelected ? Color.white.opacity(0.95) : tint.opacity(0.32), lineWidth: isSelected ? 1.6 : 0.8)
        )
        .shadow(color: isSelected ? tint.opacity(0.5) : .clear, radius: 8)
        .scaleEffect(isSelected ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture { selection = isSelected ? nil : tile.id }
        .draggable(tile.id.uuidString) {
            dragPreview(kind: tile.kind, name: tile.appName)
        }
        .dropDestination(for: String.self) { items, _ in
            // Dropping one tile onto another puts it in that position, which is
            // how reordering works without an insertion caret to aim at.
            guard let raw = items.first else { return false }
            return reorder(raw, before: tile)
        }
        .help(tile.kind.blurb)
    }

    private func dragPreview(kind: HomeTileKind, name: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.tint)
            Text(name ?? kind.rawValue)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .overlay(Capsule().strokeBorder(kind.tint.opacity(0.6), lineWidth: 1))
    }

    // MARK: Inspector

    /// What can be done to the selected widget, or how the editor works.
    private var inspector: some View {
        HStack(spacing: 12) {
            if let tile = selectedTile {
                TintedGlyph(symbol: tile.kind.symbol, tint: tile.kind.tint, size: 24)
                Text(tile.appName ?? tile.kind.rawValue)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Divider().frame(height: 16)
                Text("Width")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 0) {
                    Button { resize(tile, by: -1) } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(tile.span <= tile.kind.minimumSpan)
                    Text("\(tile.span)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .frame(width: 22)
                    Button { resize(tile, by: 1) } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .disabled(tile.span >= 8)
                }
                .buttonStyle(.borderless)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                Button(tile.row == 0 ? "Move to Strip" : "Move to Main Row") {
                    move(tile, to: tile.row == 0 ? 1 : 0)
                }
                .controlSize(.small)
                if tile.kind == .openApp {
                    Button("Choose App…") { chooseApp(for: tile) }
                        .controlSize(.small)
                }
                Spacer(minLength: 8)
                Button(role: .destructive) {
                    remove(tile)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .controlSize(.small)
            } else {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(.white.opacity(0.4))
                Text("Drag widgets onto the notch. Click one to resize it, drag it to move it.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 8)
                slotMenu
                if editing != .standard, layouts[editing] != nil {
                    Button("Use Default Instead") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            layouts[editing] = nil
                            Settings.shared.clearHomeTiles(for: editing)
                            selection = nil
                        }
                    }
                    .controlSize(.small)
                }
                Button("Reset") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        tiles = editing == .standard ? HomeLayout.default : HomeLayout.starter(for: editing)
                        selection = nil
                    }
                }
                .controlSize(.small)
                trash
            }
        }
        .frame(height: 34)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: selection)
    }

    /// Somewhere to throw a widget you are done with.
    private var trash: some View {
        HStack(spacing: 4) {
            Image(systemName: overTrash ? "trash.fill" : "trash")
            Text("Drop to remove")
        }
        .font(.system(size: 11))
        .foregroundStyle(overTrash ? Color.red : Color.white.opacity(0.5))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(overTrash ? Color.red.opacity(0.18) : Color.white.opacity(0.05))
        )
        .overlay(
            Capsule()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .foregroundStyle(overTrash ? Color.red.opacity(0.7) : Color.white.opacity(0.2))
        )
        .dropDestination(for: String.self) { items, _ in
            overTrash = false
            guard let raw = items.first, let id = UUID(uuidString: raw),
                  let tile = tiles.first(where: { $0.id == id }) else { return false }
            remove(tile)
            return true
        } isTargeted: { overTrash = $0 }
    }

    private var slotMenu: some View {
        Menu {
            Button("Save This Layout As…") { showingSaveSlot = true }
            if !slotNames.isEmpty {
                Divider()
                ForEach(slotNames, id: \.self) { name in
                    Button(name) {
                        if let loaded = Settings.shared.layoutSlot(name) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                tiles = loaded
                                selection = nil
                            }
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
            Label("Saved Layouts", systemImage: "square.stack.3d.up")
                .font(.system(size: 11.5))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .popover(isPresented: $showingSaveSlot) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Name this layout")
                    .font(.subheadline.weight(.semibold))
                TextField("Desk setup", text: $slotName)
                    .frame(width: 200)
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

    // MARK: Gallery

    private var gallery: some View {
        CustomizePanel(
            title: "Widgets",
            subtitle: "Drag one onto the notch, or press + to add it."
        ) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 176), spacing: 8)], spacing: 8) {
                    ForEach(HomeTileKind.allCases) { kind in
                        galleryCard(kind)
                    }
                }
                .padding(.bottom, 2)
            }
            // Always at least a row of it, however short the window.
            .frame(minHeight: 110, maxHeight: .infinity)
        }
        .disabled(isInheriting)
        .opacity(isInheriting ? 0.5 : 1)
    }

    private func galleryCard(_ kind: HomeTileKind) -> some View {
        let placed = !kind.allowsDuplicates && tiles.contains { $0.kind == kind }
        return HStack(spacing: 9) {
            TintedGlyph(symbol: kind.symbol, tint: kind.tint, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(kind.blurb)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if placed {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                        add(kind, to: kind.naturalRow)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(kind.tint.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .help("Add to the \(kind.naturalRow == 0 ? "main row" : "strip")")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(placed ? 0.025 : 0.055))
        )
        .opacity(placed ? 0.55 : 1)
        .contentShape(Rectangle())
        .draggable("kind:" + kind.rawValue) {
            dragPreview(kind: kind, name: nil)
        }
    }

    // MARK: Actions

    private func load() {
        var found: [LayoutCase: [HomeTile]] = [:]
        for item in LayoutCase.allCases {
            if let tiles = Settings.shared.homeTiles(for: item) { found[item] = tiles }
        }
        layouts = found
        slotNames = Settings.shared.layoutSlotNames
    }

    private func commitSlot() {
        Settings.shared.saveLayoutSlot(slotName, tiles: tiles)
        slotNames = Settings.shared.layoutSlotNames
        slotName = ""
        showingSaveSlot = false
    }

    /// A drop carries either `kind:Name` from the gallery or a tile's UUID.
    private func handleDrop(_ items: [String], into row: Int) -> Bool {
        guard let raw = items.first else { return false }

        if raw.hasPrefix("kind:") {
            guard let kind = HomeTileKind(rawValue: String(raw.dropFirst(5))) else { return false }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { add(kind, to: row) }
            return true
        }

        guard let id = UUID(uuidString: raw),
              let index = tiles.firstIndex(where: { $0.id == id }) else { return false }
        // Moving between rows keeps the tile's size; moving within a row sends
        // it to the end, which is the only sensible target for a drop on empty
        // space.
        var updated = tiles
        var moved = updated.remove(at: index)
        moved.row = row
        updated.append(moved)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { tiles = updated }
        return true
    }

    private func reorder(_ raw: String, before target: HomeTile) -> Bool {
        if raw.hasPrefix("kind:") {
            guard let kind = HomeTileKind(rawValue: String(raw.dropFirst(5))) else { return false }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { add(kind, to: target.row) }
            return true
        }
        guard let id = UUID(uuidString: raw), id != target.id,
              let from = tiles.firstIndex(where: { $0.id == id }) else { return false }
        var updated = tiles
        var moved = updated.remove(at: from)
        moved.row = target.row
        if let to = updated.firstIndex(where: { $0.id == target.id }) {
            updated.insert(moved, at: to)
        } else {
            updated.append(moved)
        }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { tiles = updated }
        return true
    }

    private func add(_ kind: HomeTileKind, to row: Int) {
        guard kind.allowsDuplicates || !tiles.contains(where: { $0.kind == kind }) else { return }
        let tile = HomeTile(kind: kind, row: row)
        tiles = tiles + [tile]
        selection = tile.id
        if kind == .openApp { chooseApp(for: tile) }
    }

    private func remove(_ tile: HomeTile) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            tiles = tiles.filter { $0.id != tile.id }
            if selection == tile.id { selection = nil }
        }
    }

    private func move(_ tile: HomeTile, to row: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        var updated = tiles
        var moved = updated.remove(at: index)
        moved.row = row
        updated.append(moved)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { tiles = updated }
    }

    private func resize(_ tile: HomeTile, by delta: Int) {
        guard let index = tiles.firstIndex(where: { $0.id == tile.id }) else { return }
        var updated = tiles
        updated[index].span = min(max(updated[index].span + delta, tile.kind.minimumSpan), 8)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) { tiles = updated }
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
        var updated = tiles
        updated[index].appPath = url.path
        tiles = updated
    }
}

/// How much of its row a tile claims, as dots.
private struct SpanDots: View {
    let span: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< 8, id: \.self) { index in
                Circle()
                    .fill(index < span ? tint.opacity(0.9) : Color.white.opacity(0.12))
                    .frame(width: 3.5, height: 3.5)
            }
        }
    }
}

/// The open notch's header, drawn as shapes: tabs on the left, the camera in
/// the middle, the buttons on the right.
struct NotchHeaderMock: View {
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                mockTab("house.fill", selected: true)
                mockTab("tray.fill")
                mockTab("doc.on.clipboard.fill")
                mockTab("cup.and.saucer.fill")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: 200)

            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 34, height: 12)
                Image(systemName: "square.grid.2x2")
                Image(systemName: "gearshape")
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func mockTab(_ symbol: String, selected: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0)))
    }
}
