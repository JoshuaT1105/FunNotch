//
//  SettingsView.swift
//  FunNotch
//
//  The settings window: a sidebar of a few plain pages, each a short stack of
//  cards. How the notch *looks* — its layout, its widgets, its colour — lives
//  in the Customize window instead, where it can be seen while it changes.
//

import AppKit
import SwiftUI

/// Which page the settings window is showing, so other parts of the app can
/// send the user straight to the relevant one.
enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case activities
    case agents
    case media
    case shelf
    case focus
    case calendar
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .activities: return "Live Activities"
        case .agents: return "AI Agents"
        case .media: return "Media"
        case .shelf: return "Shelf & Clipboard"
        case .focus: return "Focus"
        case .calendar: return "Calendar"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .activities: return "sparkles"
        case .agents: return "sparkle"
        case .media: return "music.note"
        case .shelf: return "tray.full.fill"
        case .focus: return "cup.and.saucer.fill"
        case .calendar: return "calendar"
        case .about: return "info"
        }
    }

    var tint: Color {
        switch self {
        case .general: return SettingsStyle.gray
        case .activities: return SettingsStyle.purple
        case .agents: return AgentPalette.claude
        case .media: return SettingsStyle.pink
        case .shelf: return SettingsStyle.blue
        case .focus: return SettingsStyle.indigo
        case .calendar: return SettingsStyle.red
        case .about: return SettingsStyle.gray
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var tab: SettingsTab = .general
    private init() {}
}

struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $navigation.tab)
                .frame(width: 218)
                .background(VisualEffectBackground(material: .sidebar))

            Divider()

            ScrollView {
                page
                    .padding(.horizontal, 30)
                    .padding(.top, 34)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            // A fresh scroll position for every page.
            .id(navigation.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SettingsStyle.pageBackground)
        }
        .frame(minWidth: 780, minHeight: 560)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.tab {
        case .general: GeneralPage()
        case .activities: LiveActivitiesPage()
        case .agents: AgentsPage()
        case .media: MediaPage()
        case .shelf: ShelfClipboardPage()
        case .focus: FocusPage()
        case .calendar: CalendarPage()
        case .about: AboutPage()
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights, which sit over the sidebar.
            Color.clear.frame(height: 40)

            HStack(spacing: 10) {
                AppMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fun Notch")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Version \(version)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach([SettingsTab.general, .activities, .agents, .media, .shelf, .focus, .calendar]) { tab in
                    SidebarItem(tab: tab, isSelected: selection == tab) { selection = tab }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            VStack(spacing: 2) {
                CustomizeSidebarButton()
                SidebarItem(tab: .about, isSelected: selection == .about) { selection = .about }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
    }
}

private struct SidebarItem: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                SettingsIcon(symbol: tab.symbol, tint: tab.tint, size: 22)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Opens the Customize window rather than a page: the notch's look is edited
/// against a live preview, which a settings page has no room for.
private struct CustomizeSidebarButton: View {
    @State private var hovering = false

    var body: some View {
        Button {
            CustomizeWindowController.shared.show()
        } label: {
            HStack(spacing: 9) {
                SettingsIcon(symbol: "paintbrush.pointed.fill", gradient: SettingsStyle.brandGradient, size: 22)
                Text("Customize Notch")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Layout, widgets and colours, with a live preview")
    }
}

/// The app's mark: a notch hanging from the top of a gradient square.
struct AppMark: View {
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(SettingsStyle.brandGradient)
            .overlay(alignment: .top) {
                NotchShape(topCornerRadius: size * 0.05, bottomCornerRadius: size * 0.14)
                    .fill(Color.black)
                    .frame(width: size * 0.56, height: size * 0.22)
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}
