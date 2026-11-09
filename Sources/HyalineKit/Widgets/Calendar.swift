// Calendar and reminders widgets.

import SwiftUI
import AppKit

func eventColor(_ e: EventItem, _ a: Appearance) -> Color { a.monochrome ? .white : Color(nsColor: e.color) }
func eventWhen(_ e: EventItem) -> String {
    let cal = Calendar.current
    let day = cal.isDateInToday(e.start) ? "Today" : cal.isDateInTomorrow(e.start) ? "Tomorrow" : e.start.formatted(.dateTime.weekday(.abbreviated).day())
    return e.allDay ? "\(day) · all day" : "\(day) · \(e.start.formatted(date: .omitted, time: .shortened))"
}

// MARK: - Calendar

struct WeekStrip: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var slim = false
    var body: some View {
        let cal = Calendar.current, today = Date()
        let start = cal.date(byAdding: .day, value: -(cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7, to: cal.startOfDay(for: today))!
        let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let weekEvents = days.flatMap { store.events(on: $0) }
        VStack(alignment: .leading, spacing: 8) {
            if !slim {
                HStack { WLabel(symbol: "calendar", text: today.formatted(.dateTime.month(.wide))); Spacer()
                    Text("\(Set(weekEvents.map(\.id)).count) this week").font(.system(size: 11.5)).foregroundStyle(secondary) }
            }
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { d in
                    let isToday = cal.isDateInToday(d), n = store.events(on: d).count
                    let weekend = cal.isDateInWeekend(d)
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11, weight: .semibold)).foregroundStyle(secondary)
                        Text("\(cal.component(.day, from: d))")
                            .font(.system(size: slim ? 14 : 16, weight: isToday ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isToday ? Color(white: 0.1) : weekend ? secondary : .white)
                            .frame(width: slim ? 26 : 30, height: slim ? 26 : 30)
                            .background(Circle().fill(isToday ? Color.white : .clear))
                        if !slim {
                            HStack(spacing: 3) { ForEach(0..<min(n, 3), id: \.self) { _ in Circle().fill(appearance.accent(.red)).frame(width: 4, height: 4) } }.frame(height: 5)
                        }
                    }.frame(maxWidth: .infinity)
                }
            }
            if !slim {
                Spacer(minLength: 0)
                Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.5)
                if let next = store.upcoming.first {
                    HStack { Text(next.title).lineLimit(1); Spacer(); Text(eventWhen(next)).foregroundStyle(secondary) }.font(.system(size: 13))
                } else {
                    Text(store.eventsAccess ? "Nothing coming up" : "Calendar access needed").font(.system(size: 13)).foregroundStyle(secondary)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { store.start() }
    }
}

struct NextUp: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var slim = false
    var body: some View {
        let upcoming = store.upcoming
        Group {
            if !store.eventsAccess && store.asked { NeedsAccess(what: "Calendar") }
            else if let e = upcoming.first {
                if slim {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(eventColor(e, appearance)).frame(width: 4).padding(.vertical, 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            Text(eventWhen(e) + (upcoming.count > 1 ? " · +\(upcoming.count - 1) more" : "")).font(.system(size: 12.5)).foregroundStyle(secondary)
                        }
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { WLabel(symbol: "calendar", text: "Next up"); Spacer(); Circle().fill(eventColor(e, appearance)).frame(width: 8, height: 8) }
                        Spacer(minLength: 0)
                        Text(e.title).font(.system(size: 19, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.7)
                        Text(eventWhen(e)).font(.system(size: 13)).foregroundStyle(secondary)
                        if upcoming.count > 1 {
                            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.5).padding(.top, 6)
                            Text("+ " + upcoming.dropFirst().prefix(2).map(\.title).joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack { Spacer(); Text("Nothing coming up").font(.system(size: 13)).foregroundStyle(secondary); Spacer() }.frame(maxWidth: .infinity)
            }
        }
        .onAppear { store.start() }
    }
}

struct MonthAgenda: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let cal = Calendar.current, now = Date()
        let first = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let count = cal.range(of: .day, in: .month, for: now)!.count
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        VStack(alignment: .leading, spacing: 6) {
            WLabel(symbol: "calendar", text: now.formatted(.dateTime.month(.wide).year()))
            // One ForEach with unique ids: separate ForEach blocks with overlapping ids
            // made SwiftUI drop the first days of the month.
            let cells: [(id: String, day: Int)] = (0..<7).map { ("h\($0)", -1 - $0) } + (0..<lead).map { ("l\($0)", 0) } + (1...count).map { ("d\($0)", $0) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(cells, id: \.id) { cell in
                    if cell.day < 0 {
                        Text(cal.veryShortStandaloneWeekdaySymbols[(-cell.day - 1 + cal.firstWeekday - 1) % 7]).font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary)
                    } else if cell.day == 0 {
                        Color.clear.frame(height: 20)
                    } else {
                        let date = cal.date(byAdding: .day, value: cell.day - 1, to: first)!
                        let isToday = cal.isDateInToday(date), has = !store.events(on: date).isEmpty
                        Text("\(cell.day)").font(.system(size: 11.5, weight: isToday ? .semibold : .regular))
                            .foregroundStyle(isToday ? Color(white: 0.1) : .white)
                            .frame(width: 22, height: 20)
                            .background(Capsule().fill(isToday ? Color.white : .clear))
                            .overlay(alignment: .bottom) { if has && !isToday { Circle().fill(appearance.accent(.red)).frame(width: 3, height: 3).offset(y: 1) } }
                    }
                }
            }
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 0.5)
            ForEach(store.upcoming.prefix(4)) { e in
                HStack(spacing: 8) {
                    Circle().fill(eventColor(e, appearance)).frame(width: 6, height: 6)
                    Text(e.title).lineLimit(1)
                    Spacer()
                    Text(eventWhen(e)).foregroundStyle(secondary).lineLimit(1)
                }.font(.system(size: 13))
            }
            Spacer(minLength: 0)
        }
        .onAppear { store.start() }
    }
}

struct YearDots: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let cal = Calendar.current
            let year = cal.component(.year, from: ctx.date)
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1))!
            let total = cal.range(of: .day, in: .year, for: ctx.date)!.count
            let today = cal.ordinality(of: .day, in: .year, for: ctx.date)!
            let eventDays = Set(store.events.map { cal.ordinality(of: .day, in: .year, for: $0.start) ?? 0 })
            VStack(alignment: .leading, spacing: 10) {
                HStack { WLabel(symbol: "circle.grid.3x3", text: String(year)); Spacer()
                    Text("\(today) of \(total) · \(Int(Double(today) / Double(total) * 100))%").font(.system(size: 12)).foregroundStyle(secondary) }
                Canvas { gc, size in
                    // Pick the grid that fills the space: the largest cell where every day fits.
                    var cols = 20
                    while cols < 120 {
                        let cw = size.width / CGFloat(cols), rows = Int(ceil(Double(total) / Double(cols)))
                        if CGFloat(rows) * cw <= size.height { break }
                        cols += 1
                    }
                    let cw = size.width / CGFloat(cols), rows = Int(ceil(Double(total) / Double(cols)))
                    let rh = size.height / CGFloat(rows)
                    let dot = min(cw, rh) * 0.5
                    for i in 0..<total {
                        let c = CGPoint(x: cw * (CGFloat(i % cols) + 0.5), y: rh * (CGFloat(i / cols) + 0.5))
                        let day = i + 1
                        let color: Color = day == today ? appearance.accent(.orange) : day < today ? .white.opacity(0.85) : .white.opacity(0.18)
                        gc.fill(Path(ellipseIn: CGRect(x: c.x - dot / 2, y: c.y - dot / 2, width: dot, height: dot)), with: .color(color))
                        if eventDays.contains(day) && day != today {
                            gc.stroke(Path(ellipseIn: CGRect(x: c.x - dot * 0.85, y: c.y - dot * 0.85, width: dot * 1.7, height: dot * 1.7)), with: .color(.white.opacity(0.6)), lineWidth: 0.8)
                        }
                    }
                    _ = start
                }
            }
        }
        .onAppear { store.start() }
    }
}

struct DayTimeline: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let cal = Calendar.current
            let events = store.events(on: ctx.date)
            let allDay = events.filter(\.allDay), timed = events.filter { !$0.allDay }
            VStack(alignment: .leading, spacing: 4) {
                WLabel(symbol: "calendar", text: "\(ctx.date.formatted(.dateTime.weekday(.abbreviated))) \(cal.component(.day, from: ctx.date))")
                ForEach(allDay.prefix(2)) { e in
                    Text(e.title).font(.system(size: 11, weight: .medium)).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5).fill(eventColor(e, appearance).opacity(0.3)))
                }
                if events.isEmpty { Text("Nothing scheduled").font(.system(size: 12)).foregroundStyle(secondary) }
                GeometryReader { geo in
                    let startH = 8.0, endH = 22.0
                    let y = { (d: Date) -> CGFloat in
                        let h = Double(cal.component(.hour, from: d)) + Double(cal.component(.minute, from: d)) / 60
                        return geo.size.height * CGFloat((min(max(h, startH), endH) - startH) / (endH - startH))
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(stride(from: Int(startH), through: Int(endH), by: 2)), id: \.self) { h in
                            HStack(spacing: 4) {
                                Text(h == 12 ? "12p" : h > 12 ? "\(h - 12)p" : "\(h)a").font(.system(size: 10, weight: .semibold)).foregroundStyle(secondary).frame(width: 24, alignment: .leading)
                                Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5)
                            }.offset(y: geo.size.height * CGFloat((Double(h) - startH) / (endH - startH)) - 6)
                        }
                        ForEach(timed) { e in
                            Text(e.title).font(.system(size: 10.5, weight: .medium)).lineLimit(1).padding(.horizontal, 5)
                                .frame(width: geo.size.width - 28, height: max(y(e.end) - y(e.start), 16), alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 5).fill(eventColor(e, appearance).opacity(0.35)))
                                .offset(x: 28, y: y(e.start))
                        }
                        HStack(spacing: 0) {
                            Circle().fill(appearance.accent(.red)).frame(width: 7, height: 7)
                            Rectangle().fill(appearance.accent(.red)).frame(height: 1.5)
                        }.offset(x: 24, y: y(ctx.date) - 3.5)
                    }
                }.padding(.top, 6)
            }
        }
        .onAppear { store.start() }
    }
}

struct RemindersList: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { WLabel(symbol: "list.bullet", text: "Reminders"); Spacer()
                Text("\(store.reminders.count)").font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(appearance.accent(.orange)) }
            if !store.remindersAccess && store.asked { NeedsAccess(what: "Reminders") }
            ForEach(store.reminders.prefix(4)) { r in
                HStack(spacing: 10) {
                    Button { store.toggle(r.id) } label: {
                        Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.6).frame(width: 16, height: 16).contentShape(Circle())
                    }.buttonStyle(.plain)
                    Text(r.title).lineLimit(1)
                    Spacer()
                    if let due = r.due {
                        Text(Calendar.current.isDateInToday(due) ? "Today" : due.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.system(size: 11.5)).foregroundStyle(due < Date() ? appearance.accent(.red) : secondary)
                    }
                }.font(.system(size: 13.5)).padding(.vertical, 2)
            }
            Spacer(minLength: 0)
        }
        .onAppear { store.start() }
    }
}
