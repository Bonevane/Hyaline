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

/// On while the showcase runs: widgets show made-up events and reminders instead
/// of yours, so screenshots can be shared.
enum SampleData { static var on = false }

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
        guard !asked, !GalleryMode.on, !SampleData.on else { return }
        asked = true
        // An answer that lands during the showcase is kept for afterwards, so it can't
        // replace the sample data's access.
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                if SampleData.on { self.saved?.eventsAccess = granted } else { self.eventsAccess = granted; self.reload() }
            }
        }
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async {
                if SampleData.on { self.saved?.remindersAccess = granted } else { self.remindersAccess = granted; self.reload() }
            }
        }
    }

    func reload() {
        guard !SampleData.on else { return }
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

    private var saved: (events: [EventItem], reminders: [ReminderItem], eventsAccess: Bool, remindersAccess: Bool)?

    /// Swaps in made-up events and reminders (for the showcase), or back to yours.
    func useSample(_ on: Bool) {
        if on {
            if saved == nil { saved = (events, reminders, eventsAccess, remindersAccess) }
            let cal = Calendar.current, today = cal.startOfDay(for: Date())
            func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
                cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
            }
            let blue = NSColor.systemBlue, orange = NSColor.systemOrange, green = NSColor.systemGreen, purple = NSColor.systemPurple, pink = NSColor.systemPink
            let plan: [(String, Date, Double, Bool, NSColor)] = [
                ("Standup", at(0, 9, 30), 0.25, false, blue), ("Design review", at(0, 11), 1, false, purple),
                ("Coffee with Sam", at(0, 15), 0.75, false, orange), ("Climbing", at(0, 18, 30), 1.5, false, green),
                ("Product launch", at(1, 0), 24, true, pink), ("Planning", at(1, 10), 1, false, blue),
                ("Dentist", at(2, 9), 1, false, orange), ("Team lunch", at(3, 12, 30), 1, false, green),
                ("Workshop", at(5, 14), 2, false, purple), ("Lisbon", at(8, 0), 72, true, pink),
                ("Quarterly review", at(13, 11), 1.5, false, blue), ("Birthday dinner", at(17, 19), 2, false, orange),
                ("Offsite", at(23, 0), 48, true, purple), ("Demo day", at(27, 16), 1, false, green),
            ]
            events = plan.enumerated().map { i, e in
                EventItem(id: "sample-\(i)", title: e.0, start: e.1, end: e.1.addingTimeInterval(e.2 * 3600), allDay: e.3, color: e.4)
            }
            reminders = [("Ship Hyaline 0.2", 0), ("Book flights to Lisbon", 1), ("Water the plants", nil), ("Call Mum", 2), ("Renew passport", 6)]
                .enumerated().map { i, r in
                    ReminderItem(id: "sample-r\(i)", title: r.0, due: r.1.map { at($0, 18) }, completed: false)
                }
            eventsAccess = true; remindersAccess = true
        } else if let s = saved {
            saved = nil
            events = s.events; reminders = s.reminders; eventsAccess = s.eventsAccess; remindersAccess = s.remindersAccess
            reload()
        }
    }

    func toggle(_ id: String) {
        guard !SampleData.on else { return }
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
