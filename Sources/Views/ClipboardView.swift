//
//  ClipboardView.swift
//  FunNotch
//
//  Recent clipboard entries. Click one to put it back on the pasteboard.
//

import AppKit
import SwiftUI

struct ClipboardView: View {
    @ObservedObject private var clipboard = ClipboardManager.shared
    @EnvironmentObject private var settings: Settings

    @State private var justCopied: UUID?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 6) {
            if !settings.clipboardHistoryEnabled {
                disabledState
            } else if clipboard.entries.isEmpty {
                emptyState
            } else {
                toolbar
                entryList
            }
        }
        .padding(.top, 8)
    }

    private var disabledState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Clipboard history is off")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text("Turn it on in Settings → Clipboard")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
            Text("Nothing copied yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            Text("Whatever you copy shows up here")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var visibleEntries: [ClipboardEntry] {
        clipboard.filtered(by: query)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .frame(width: 150)

            Text("\(visibleEntries.count) item\(visibleEntries.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Button("Clear") { clipboard.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 2)
    }

    private var entryList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: [GridItem(.flexible())], spacing: 8) {
                ForEach(visibleEntries) { entry in
                    ClipboardTile(entry: entry, justCopied: justCopied == entry.id) {
                        clipboard.copyBack(entry)
                        withAnimation(.easeOut(duration: 0.15)) { justCopied = entry.id }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if justCopied == entry.id {
                                withAnimation(.easeOut(duration: 0.2)) { justCopied = nil }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 4)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ClipboardTile: View {
    let entry: ClipboardEntry
    let justCopied: Bool
    let action: () -> Void

    @ObservedObject private var clipboard = ClipboardManager.shared
    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: justCopied ? "checkmark" : (entry.isPinned ? "pin.fill" : entry.symbol))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(
                            justCopied || entry.isPinned
                                ? settings.accentColor
                                : .white.opacity(0.5)
                        )
                    if let source = entry.sourceApp {
                        Text(source)
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                content
            }
            .padding(7)
            .frame(width: 132, height: 96, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovering ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        justCopied || entry.isPinned
                            ? settings.accentColor.opacity(justCopied ? 1 : 0.5)
                            : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.03 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
        .contextMenu {
            Button("Copy") { clipboard.copyBack(entry) }
            Button(entry.isPinned ? "Unpin" : "Pin") { clipboard.togglePin(entry) }
            Button("Send to Shelf") { clipboard.sendToShelf(entry) }
            Divider()
            Button("Remove") { clipboard.remove(entry) }
        }
        .help(justCopied ? "Copied" : entry.preview)
    }

    @ViewBuilder
    private var content: some View {
        switch entry.payload {
        case let .image(image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 58)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        default:
            Text(entry.preview)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
