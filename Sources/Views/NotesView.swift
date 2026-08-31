//
//  NotesView.swift
//  FunNotch
//
//  The scratchpad. One text field per day, no formatting and no files.
//

import AppKit
import SwiftUI

struct NotesView: View {
    @ObservedObject private var notes = NotesManager.shared
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            ZStack(alignment: .topLeading) {
                // The panel never becomes the active app, so the placeholder is
                // drawn rather than relying on a real prompt.
                if notes.isEmpty {
                    Text(notes.isToday
                         ? "Jot something down. Saves to Desktop › notes."
                         : "Nothing written on this day.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.top, 2)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notes.text)
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
        .onAppear { installEditingShortcuts() }
        .onDisappear {
            removeEditingShortcuts()
            notes.saveNow()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            // Days are a menu rather than arrows: most of the time you want
            // today or yesterday, and a list gets you to either in one click.
            Menu {
                ForEach(notes.days, id: \.self) { day in
                    Button {
                        notes.openDay(day)
                    } label: {
                        if day == notes.day {
                            Label(notes.displayName(for: day), systemImage: "checkmark")
                        } else {
                            Text(notes.displayName(for: day))
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(notes.displayName(for: notes.day))
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            if !notes.isToday {
                Button("Today") { notes.openToday() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
            }

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
            .help("Show this note in Finder")
        }
    }

    @ViewBuilder
    private var status: some View {
        if let error = notes.saveError {
            Label("Desktop copy failed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(.orange)
                .help("\(error)\n\nA backup copy was still written inside the app.")
        } else if let at = notes.savedAt {
            Text("Saved \(at.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Editing shortcuts
    //
    // FunNotch has no menu bar, and macOS routes ⌘C, ⌘V and friends through the
    // main menu — so in the notch they did nothing at all. This catches them
    // while the notes tab is open and hands them to whatever is editing.

    private func installEditingShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }

            let selector: Selector?
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": selector = #selector(NSText.copy(_:))
            case "v": selector = #selector(NSText.paste(_:))
            case "x": selector = #selector(NSText.cut(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = event.modifierFlags.contains(.shift)
                ? Selector(("redo:"))
                : Selector(("undo:"))
            default:  selector = nil
            }

            guard let selector else { return event }
            // Consume the event only if something in the responder chain took
            // it, so an unhandled shortcut still behaves normally.
            return NSApp.sendAction(selector, to: nil, from: nil) ? nil : event
        }
    }

    private func removeEditingShortcuts() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
