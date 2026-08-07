//
//  ShelfView.swift
//  FunNotch
//
//  The file tray. Drop things here from anywhere, then drag them straight back
//  out into another app, AirDrop them, or preview them.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @ObservedObject private var shelf = ShelfManager.shared
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(spacing: 6) {
            if shelf.items.isEmpty {
                emptyState
            } else {
                toolbar
                itemGrid
                folderTargets
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(viewModel.isDropTargeted ? 0.9 : 0.4))
                .scaleEffect(viewModel.isDropTargeted ? 1.12 : 1)

            Text(viewModel.isDropTargeted ? "Drop to add" : "Drop files here")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))

            Text("They stay on the shelf until you drag them out")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
                .foregroundStyle(.white.opacity(viewModel.isDropTargeted ? 0.5 : 0.16))
        )
        .animation(.easeOut(duration: 0.2), value: viewModel.isDropTargeted)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Text("\(shelf.items.count) item\(shelf.items.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))

            Spacer()

            ShelfToolbarButton(systemName: "square.and.arrow.up", label: "Share") {
                ShareAnchor.share(urls: shelf.shareURLs)
            }
            ShelfToolbarButton(systemName: "dot.radiowaves.right", label: "AirDrop") {
                shelf.airDrop(shelf.shareURLs)
            }
            ShelfToolbarButton(systemName: "doc.on.doc", label: "Copy") {
                shelf.copyToPasteboard(shelf.shareURLs)
            }
            ShelfToolbarButton(systemName: "trash", label: "Clear") {
                if shelf.selection.isEmpty {
                    shelf.clear()
                } else {
                    shelf.removeSelected()
                }
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var folderTargets: some View {
        let targets = settings.shelfFolderTargets
        if !targets.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                ForEach(targets, id: \.self) { path in
                    FolderTargetChip(path: path)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2)
        }
    }

    private var itemGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.flexible())], spacing: 8) {
                ForEach(shelf.items) { item in
                    ShelfItemTile(item: item)
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ShelfToolbarButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.white.opacity(isHovering ? 1 : 0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(isHovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}

private struct ShelfItemTile: View {
    let item: ShelfItem

    @ObservedObject private var shelf = ShelfManager.shared
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    private var isSelected: Bool { shelf.selection.contains(item.id) }

    /// A sheet inside a borderless panel is awkward, so renaming uses a plain
    /// alert with a text field.
    private func promptRename() {
        let alert = NSAlert()
        alert.messageText = "Rename item"
        alert.informativeText = "The file itself is renamed, so the new name follows it when you drag it back out."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = (item.name as NSString).deletingPathExtension
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        shelf.rename(id: item.id, to: field.stringValue)
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))

                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(4)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 62, height: 62)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.white.opacity(isHovering ? 0.3 : 0.08),
                            lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button {
                        shelf.remove(id: item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                }
            }

            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.04 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
            // Keep the notch open while the pointer is over an item being dragged.
            viewModel.pinnedOpen = hovering
        }
        .onTapGesture(count: 2) { shelf.open(item) }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                if isSelected { shelf.selection.remove(item.id) } else { shelf.selection.insert(item.id) }
            } else {
                shelf.selection = isSelected ? [] : [item.id]
            }
        }
        .onDrag {
            viewModel.pinnedOpen = true
            defer {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    viewModel.pinnedOpen = false
                    shelf.handleDragCompleted(id: item.id)
                }
            }
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        } preview: {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail).resizable().frame(width: 64, height: 64)
            } else {
                Image(systemName: "doc").font(.system(size: 32))
            }
        }
        .contextMenu {
            Button("Open") { shelf.open(item) }
            Button("Rename…") { promptRename() }
            Button("Quick Look") { shelf.quickLook(item) }
            Button("Reveal in Finder") { shelf.reveal(item) }
            Divider()
            Button("Share…") { ShareAnchor.share(urls: [item.url]) }
            Button("AirDrop") { shelf.airDrop([item.url]) }
            Button("Copy") { shelf.copyToPasteboard([item.url]) }
            Divider()
            Button("Remove from Shelf") { shelf.remove(id: item.id) }
        }
        .help("\(item.name)\n\(formattedFileSize(item.size)) · \(item.typeDescription)")
    }
}

/// The share picker needs a real NSView to anchor to; the notch panel's content
/// view is the natural choice.
@MainActor
enum ShareAnchor {
    static func share(urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let view = NotchWindowManager.shared.controllers.first?.panel.contentView else {
            ShelfManager.shared.airDrop(urls)
            return
        }
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1),
                    of: view,
                    preferredEdge: .minY)
    }
}


/// One-click destination for whatever is selected on the shelf.
private struct FolderTargetChip: View {
    let path: String

    @ObservedObject private var shelf = ShelfManager.shared
    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        Button(action: send) {
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.7))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(isHovering ? 0.18 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .help("Send the selection to \(path)")
    }

    private func send() {
        let folder = URL(fileURLWithPath: path)
        // With nothing selected, filing everything is the useful reading.
        let ids = shelf.selection.isEmpty
            ? shelf.items.map(\.id)
            : Array(shelf.selection)
        for id in ids {
            shelf.send(id: id, toFolder: folder, keepingOriginal: !settings.autoRemoveShelfItems)
        }
    }
}
