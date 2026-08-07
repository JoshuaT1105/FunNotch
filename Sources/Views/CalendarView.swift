//
//  CalendarView.swift
//  FunNotch
//
//  A week strip with the agenda for the selected day, shown next to the player.
//

import SwiftUI

struct CalendarPane: View {
    @ObservedObject private var manager = CalendarManager.shared
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            weekStrip

            // Examples stand in for the permission prompt too. Somebody who has
            // switched them on has said what they want the panel to look like,
            // and nagging for Calendar access underneath it helps nobody. Turn
            // the setting off and the prompt comes straight back.
            if manager.items.isEmpty, !manager.hasEventAccess {
                permissionPrompt
            } else if manager.items.isEmpty {
                emptyState
            } else {
                agenda
            }
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 2) {
            ForEach(weekDays, id: \.self) { day in
                DayCell(
                    date: day,
                    isSelected: Calendar.current.isDate(day, inSameDayAs: manager.selectedDate),
                    isToday: Calendar.current.isDateInToday(day)
                ) {
                    manager.select(date: day)
                }
            }
        }
    }

    private var weekDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: today) else { return [today] }
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    // MARK: - Agenda

    private var agenda: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(manager.items) { item in
                        AgendaRow(item: item)
                            .id(item.id)
                    }
                }
                .padding(.trailing, 2)
            }
            .onAppear {
                guard let next = manager.items.first(where: { ($0.start ?? .distantPast) >= Date() }) else { return }
                proxy.scrollTo(next.id, anchor: .top)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.35))
            Text("No events")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionPrompt: some View {
        VStack(spacing: 5) {
            Text("Calendar access needed")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            Button("Grant Access") { manager.requestAccess() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.15)))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(weekdaySymbol)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSelected ? .black.opacity(0.55) : .white.opacity(0.45))
                Text(dayNumber)
                    .font(.system(size: 11, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? .black : (isToday ? .red : .white))
            }
            .frame(width: 24, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var weekdaySymbol: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }
}

private struct AgendaRow: View {
    let item: AgendaItem

    @EnvironmentObject private var settings: Settings
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if item.isReminder {
                Button {
                    CalendarManager.shared.complete(reminderID: item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(item.calendarColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.calendarColor)
                    .frame(width: 3)
                    .padding(.vertical, 1)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 10, weight: item.isCurrent ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 0.9))
                        .strikethrough(item.isCompleted)
                        .lineLimit(settings.showFullEventTitles ? 3 : 1)

                    // Placeholders say so. A filled-in agenda is decoration, and
                    // decoration that cannot be told apart from a real meeting
                    // is a way to miss one.
                    if item.isSample {
                        Text("Sample")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2.5)
                                    .fill(.white.opacity(0.12))
                            )
                            .fixedSize()
                    }
                }

                Text(item.countdownText.map { "\(item.timeText) · \($0)" } ?? item.timeText)
                    .font(.system(size: 9))
                    .foregroundStyle(item.isCurrent ? item.calendarColor : .white.opacity(0.45))
            }

            Spacer(minLength: 0)

            if item.meetingURL != nil {
                Button {
                    CalendarManager.shared.joinMeeting(item)
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(settings.accentColor))
                }
                .buttonStyle(.plain)
                .help("Join the meeting")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(isHovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { CalendarManager.shared.open(item: item) }
    }
}
