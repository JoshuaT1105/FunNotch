//
//  CalendarManager.swift
//  FunNotch
//
//  Calendar events and reminders for the day strip inside the open notch.
//

import AppKit
import Combine
import EventKit
import SwiftUI

/// One row in the notch's agenda, from either Calendar or Reminders.
struct AgendaItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case event
        case reminder(isCompleted: Bool)
    }

    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    let calendarColor: Color
    let calendarTitle: String
    let kind: Kind
    let location: String?
    /// URL used to open the item in Calendar or Reminders.
    let externalIdentifier: String?
    /// Video call link found in the event, if there is one.
    let meetingURL: URL?
    /// Placeholder rather than something from Calendar or Reminders. Kept out
    /// of anything that answers "what is next", so the notch never claims you
    /// have a meeting you do not have.
    var isSample = false

    var isReminder: Bool {
        if case .reminder = kind { return true }
        return false
    }

    var isCompleted: Bool {
        if case let .reminder(completed) = kind { return completed }
        return false
    }

    /// True when the event is happening right now.
    var isCurrent: Bool {
        guard let start, let end else { return false }
        let now = Date()
        return start <= now && now <= end
    }

    /// "in 5m" / "now" for something coming up soon, else nil.
    var countdownText: String? {
        guard let start else { return nil }
        if isCurrent { return "now" }
        let seconds = start.timeIntervalSinceNow
        guard seconds > 0, seconds < 6 * 3600 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "in under a minute" }
        if minutes < 60 { return "in \(minutes)m" }
        return "in \(minutes / 60)h \(minutes % 60)m"
    }

    var timeText: String {
        if isAllDay { return "All day" }
        guard let start else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = Locale.current.hasTwelveHourClock ? "h:mm a" : "HH:mm"
        return formatter.string(from: start)
    }
}

extension Locale {
    var hasTwelveHourClock: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: self) ?? ""
        return format.contains("a")
    }
}

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published private(set) var items: [AgendaItem] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var hasEventAccess = false
    @Published private(set) var hasReminderAccess = false
    @Published var selectedDate = Calendar.current.startOfDay(for: Date())

    private let store = EKEventStore()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Settings whose change means the agenda has to be built again. Anything
    /// that alters what belongs in the list has to be named here, or the panel
    /// keeps showing the old answer until the next minute tick.
    static let reloadTriggeringKeys: Set<String> = [
        "selectedCalendarIdentifiers",
        "hideAllDayEvents",
        "showReminders",
        "hideCompletedReminders",
        "showSampleAgenda",
    ]

    private init() {}

    func start() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .settingsChanged)
            .compactMap { $0.object as? String }
            .filter { Self.reloadTriggeringKeys.contains($0) }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)

        requestAccess()

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hasEventAccess = granted
                    self.calendars = self.store.calendars(for: .event)
                    self.reload()
                }
            }
        }

        store.requestFullAccessToReminders { [weak self] granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.hasReminderAccess = granted
                    self?.reload()
                }
            }
        }
    }

    /// The next thing coming up today, for the collapsed notch's widget.
    ///
    /// Sample rows are skipped deliberately. Filling an empty agenda is
    /// cosmetic and harmless; telling someone at a glance that they have a
    /// meeting in ten minutes when they do not is neither.
    var nextItem: AgendaItem? {
        Self.next(in: items, now: Date())
    }

    /// Split out from `nextItem` so the rule can be exercised directly rather
    /// than only through whatever happens to be in the real calendar today.
    static func next(in items: [AgendaItem], now: Date) -> AgendaItem? {
        items.first { item in
            guard !item.isSample, !item.isCompleted else { return false }
            guard let start = item.start else { return false }
            return item.isCurrent || start >= now
        }
    }

    func select(date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        reload()
    }

    func reload() {
        var collected: [AgendaItem] = []

        if hasEventAccess {
            collected.append(contentsOf: fetchEvents())
        }

        if hasReminderAccess, Settings.shared.showReminders {
            fetchReminders { [weak self] reminders in
                guard let self else { return }
                var merged = collected
                merged.append(contentsOf: reminders)
                self.items = Self.sorted(self.fillingIfEmpty(merged))
            }
        } else {
            items = Self.sorted(fillingIfEmpty(collected))
        }
    }

    /// Substitutes example rows for a day that has nothing on it.
    ///
    /// Only ever a substitution — a day with one real event keeps that one
    /// event and gains nothing, so a placeholder can never bury something real.
    private func fillingIfEmpty(_ items: [AgendaItem]) -> [AgendaItem] {
        Self.fillingIfEmpty(
            items,
            enabled: Settings.shared.showSampleAgenda,
            day: selectedDate,
            includeReminders: Settings.shared.showReminders
        )
    }

    static func fillingIfEmpty(
        _ items: [AgendaItem],
        enabled: Bool,
        day: Date,
        includeReminders: Bool
    ) -> [AgendaItem] {
        guard items.isEmpty, enabled else { return items }
        return sampleItems(for: day, includeReminders: includeReminders)
    }

    /// Hung off the given day, so moving through the week keeps the times
    /// sensible instead of showing yesterday's afternoon.
    static func sampleItems(for day: Date, includeReminders: Bool) -> [AgendaItem] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: day)

        func at(_ hour: Int, _ minute: Int) -> Date? {
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day)
        }

        func event(_ title: String, _ hour: Int, _ minute: Int, minutes: Int, color: Color) -> AgendaItem {
            let start = at(hour, minute)
            return AgendaItem(
                id: "sample-event-\(title)",
                title: title,
                start: start,
                end: start.map { $0.addingTimeInterval(TimeInterval(minutes * 60)) },
                isAllDay: false,
                calendarColor: color,
                calendarTitle: "Sample",
                kind: .event,
                location: nil,
                externalIdentifier: nil,
                meetingURL: nil,
                isSample: true
            )
        }

        func reminder(_ title: String, done: Bool) -> AgendaItem {
            AgendaItem(
                id: "sample-reminder-\(title)",
                title: title,
                start: nil,
                end: nil,
                isAllDay: false,
                calendarColor: .orange,
                calendarTitle: "Sample",
                kind: .reminder(isCompleted: done),
                location: nil,
                externalIdentifier: nil,
                meetingURL: nil,
                isSample: true
            )
        }

        var items = [
            event("Design review", 10, 30, minutes: 45, color: .blue),
            event("Call with Sam", 14, 15, minutes: 30, color: .green),
            event("Dentist", 16, 45, minutes: 60, color: .orange),
        ]

        if includeReminders {
            items.append(reminder("Renew the domain", done: false))
            items.append(reminder("Ship 1.0", done: true))
        }
        return items
    }

    private static func sorted(_ items: [AgendaItem]) -> [AgendaItem] {
        items.sorted { lhs, rhs in
            switch (lhs.start, rhs.start) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.title < rhs.title
            }
        }
    }

    private var activeCalendars: [EKCalendar]? {
        let selected = Settings.shared.selectedCalendarIdentifiers
        guard !selected.isEmpty else { return nil }
        let matching = store.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
        return matching.isEmpty ? nil : matching
    }

    private func fetchEvents() -> [AgendaItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: activeCalendars)
        let hideAllDay = Settings.shared.hideAllDayEvents

        return store.events(matching: predicate)
            .filter { !(hideAllDay && $0.isAllDay) }
            .map { event in
                AgendaItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarColor: Color(nsColor: NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue),
                    calendarTitle: event.calendar.title,
                    kind: .event,
                    location: event.location,
                    externalIdentifier: event.eventIdentifier,
                    meetingURL: MeetingLinkFinder.find(
                        in: [event.url?.absoluteString, event.location, event.notes]
                    )
                )
            }
    }

    private func fetchReminders(completion: @escaping ([AgendaItem]) -> Void) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDate)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            completion([])
            return
        }

        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: end,
            calendars: nil
        )

        store.fetchReminders(matching: predicate) { reminders in
            let hideCompleted = Settings.shared.hideCompletedReminders
            let mapped = (reminders ?? [])
                .filter { reminder in
                    if hideCompleted, reminder.isCompleted { return false }
                    guard let due = reminder.dueDateComponents?.date else { return false }
                    return due >= start && due < end
                }
                .map { reminder in
                    AgendaItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Reminder",
                        start: reminder.dueDateComponents?.date,
                        end: reminder.dueDateComponents?.date,
                        isAllDay: reminder.dueDateComponents?.hour == nil,
                        calendarColor: Color(nsColor: NSColor(cgColor: reminder.calendar.cgColor) ?? .systemOrange),
                        calendarTitle: reminder.calendar.title,
                        kind: .reminder(isCompleted: reminder.isCompleted),
                        location: nil,
                        externalIdentifier: reminder.calendarItemIdentifier,
                        meetingURL: nil
                    )
                }
            DispatchQueue.main.async { completion(mapped) }
        }
    }

    /// Marks a reminder done straight from the notch.
    func complete(reminderID: String) {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        reload()
    }

    /// Opens the event's video call. Falls back to opening the event itself.
    func joinMeeting(_ item: AgendaItem) {
        guard let url = item.meetingURL else {
            open(item: item)
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// The next thing today that has a call attached.
    var nextMeeting: AgendaItem? {
        let now = Date()
        return items.first { item in
            guard item.meetingURL != nil, let start = item.start else { return false }
            return item.isCurrent || start >= now
        }
    }

    func open(item: AgendaItem) {
        if item.isReminder {
            NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
        } else if let identifier = item.externalIdentifier,
                  let url = URL(string: "ical://ekevent/\(identifier)") {
            NSWorkspace.shared.open(url)
        }
    }
}


/// Digs a video call link out of whatever the organiser happened to fill in —
/// the URL field, the location, or somewhere in the notes.
enum MeetingLinkFinder {
    /// Hosts whose links are worth offering a one-click join for.
    private static let hosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "whereby.com",
        "meet.jit.si",
        "around.co",
        "gather.town",
        "chime.aws",
        "bluejeans.com",
    ]

    static func find(in candidates: [String?]) -> URL? {
        for candidate in candidates.compactMap({ $0 }) where !candidate.isEmpty {
            if let url = firstMeetingURL(in: candidate) { return url }
        }
        return nil
    }

    private static func firstMeetingURL(in text: String) -> URL? {
        // A plain zoommtg:// or msteams:// link is already a direct join.
        if let scheme = text.range(of: #"(zoommtg|msteams|zoomus)://\S+"#, options: .regularExpression) {
            return URL(string: String(text[scheme]))
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let url = match.url, let host = url.host?.lowercased() else { continue }
            if hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                return url
            }
        }
        return nil
    }
}
