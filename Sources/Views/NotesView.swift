//
//  NotesView.swift
//  FunNotch
//
//  The scratchpad. One text field, no formatting, no files, no sync — the
//  cheapest version of the idea is the one people actually use.
//

import SwiftUI

struct NotesView: View {
    @ObservedObject private var notes = NotesManager.shared
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Notes")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))

                Spacer()

                status

                Button {
                    notes.revealInFinder()
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Show Notes.txt in Finder")
            }

            ZStack(alignment: .topLeading) {
                // The panel never becomes the key window, so the placeholder is
                // drawn rather than relying on a real prompt.
                if notes.isEmpty {
                    Text("Jot something down. It saves to Desktop › notes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.top, 2)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes.text)
                    .focused($editing)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        // A note half-typed when the notch closes is still a note.
        .onDisappear { notes.saveNow() }
    }

    @ViewBuilder
    private var status: some View {
        if let error = notes.saveError {
            Label("Not saving", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.orange)
                .help(error)
        } else if let at = notes.savedAt {
            Text("Saved \(at.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}
