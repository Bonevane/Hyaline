// Calendar events and reminders from EventKit.

import AppKit
import EventKit
import CoreLocation
import IOKit

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: NSColor
}

struct ReminderItem: Identifiable {
    let id: String
    let title: String
    let due: Date?
    let completed: Bool
}

/// Set by the gallery self-check, which runs outside the app bundle: nothing may
/// trigger a permission prompt there (it would name the wrong app).
enum GalleryMode { static var on = false }

final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()
    private let store = EKEventStore()
    @Published var eventsAccess = false
    @Published var remindersAccess = false
    @Published var asked = false
    @Published var events: [EventItem] = []
    @Published var reminders: [ReminderItem] = []

    private init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in self?.reload() }
    }

    /// Asks for access the first time a calendar or reminders widget appears.
    func start() {
        guard !asked, !GalleryMode.on else { return }
        asked = true
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { self.eventsAccess = granted; self.reload() }
        }
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async { self.remindersAccess = granted; self.reload() }
        }
    }

    func reload() {
        let cal = Calendar.current
        if eventsAccess {
            let from = cal.startOfDay(for: Date()), to = cal.date(byAdding: .day, value: 60, to: from)!
            let predicate = store.predicateForEvents(withStart: cal.date(byAdding: .day, value: -7, to: from)!, end: to, calendars: nil)
            events = store.events(matching: predicate).map {
                EventItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate,
                          allDay: $0.isAllDay, color: NSColor(cgColor: $0.calendar.cgColor) ?? .systemRed)
            }.sorted { $0.start < $1.start }
        }
        if remindersAccess {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: predicate) { found in
                let items = (found ?? []).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder",
                                 due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, completed: $0.isCompleted)
                }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
                DispatchQueue.main.async { self.reminders = items }
            }
        }
    }

    func toggle(_ id: String) {
        guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        r.isCompleted.toggle()
        try? store.save(r, commit: true)
        reload()
    }

    /// Events touching the given day, all-day first.
    func events(on day: Date) -> [EventItem] {
        let cal = Calendar.current, start = cal.startOfDay(for: day), end = cal.date(byAdding: .day, value: 1, to: start)!
        return events.filter { $0.start < end && $0.end > start }.sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }

    var upcoming: [EventItem] { events.filter { $0.end > Date() } }
}
