// Clock widgets: stacked, word, split flap, dial, day arc, world arcs and strip.

import SwiftUI
import AppKit

struct StackedClock: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let c = Calendar.current.dateComponents([.hour, .minute, .day], from: ctx.date)
            VStack(alignment: .leading, spacing: 0) {
                SmallCaps(text: "\(ctx.date.formatted(.dateTime.weekday(.abbreviated))) \(c.day ?? 0)")
                VStack(alignment: .leading, spacing: -12) {
                    Text(pad2(c.hour ?? 0))
                    Text(pad2(c.minute ?? 0))
                }
                .font(.system(size: 62, weight: .medium, design: .rounded)).monospacedDigit()
                .fixedSize().padding(.top, 2)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WordClock: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let c = Calendar.current.dateComponents([.hour, .minute], from: ctx.date)
            let h = c.hour ?? 0, m = c.minute ?? 0
            let m5 = Int((Double(m) / 5).rounded()) * 5 % 60
            let names = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
            let hour = names[((m >= 33 ? h + 1 : h) % 12)]
            let lead = [0: "", 5: "five past", 10: "ten past", 15: "quarter past", 20: "twenty past", 25: "twenty-five past",
                        30: "half past", 35: "twenty-five to", 40: "twenty to", 45: "quarter to", 50: "ten to", 55: "five to"][m5] ?? ""
            let part = h < 12 ? "in the morning" : h < 17 ? "in the afternoon" : h < 21 ? "in the evening" : "at night"
            VStack(alignment: .leading, spacing: 1) {
                Spacer(minLength: 0)
                Text("it's").foregroundStyle(faint)
                if !lead.isEmpty { Text(lead) }
                Text(m5 == 0 ? "\(hour) o'clock" : hour)
                Text(part).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(faint).padding(.top, 3)
            }
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FlipClock: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let c = Calendar.current.dateComponents([.hour, .minute, .day], from: ctx.date)
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                HStack(spacing: 6) { card(pad2(c.hour ?? 0)); card(pad2(c.minute ?? 0)) }
                HStack {
                    SmallCaps(text: ctx.date.formatted(.dateTime.weekday(.wide)))
                    Spacer()
                    SmallCaps(text: ctx.date.formatted(.dateTime.day().month(.abbreviated)))
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func card(_ t: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
            Text(t).font(.system(size: 50, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 4)
            Rectangle().fill(Color.black.opacity(0.45)).frame(height: 1.5)
        }.frame(height: 86)
    }
}

struct MinimalDial: View {
    @ObservedObject var appearance: Appearance
    @ObservedObject var power = PowerMode.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: power.onBattery ? 10 : 1)) { ctx in
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2), r = min(size.width, size.height) / 2 - 2
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi, long = i % 5 == 0, r0 = long ? r - 9 : r - 4
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + r0 * sin(a), y: c.y - r0 * cos(a)))
                    p.addLine(to: CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)))
                    gc.stroke(p, with: .color(.white.opacity(long ? 0.85 : 0.3)), style: StrokeStyle(lineWidth: long ? 2 : 1, lineCap: .round))
                }
                let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: ctx.date)
                let mins = Double(comps.minute ?? 0) + Double(comps.second ?? 0) / 60
                let ha = (Double((comps.hour ?? 0) % 12) + mins / 60) / 12 * 2 * .pi, ma = mins / 60 * 2 * .pi
                func hand(_ a: Double, _ len: Double, _ w: CGFloat) {
                    var p = Path(); p.move(to: c); p.addLine(to: CGPoint(x: c.x + len * sin(a), y: c.y - len * cos(a)))
                    gc.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
                hand(ha, r * 0.52, 4); hand(ma, r * 0.78, 2.5)
                gc.fill(Path(ellipseIn: CGRect(x: c.x - 4.5, y: c.y - 4.5, width: 9, height: 9)), with: .color(appearance.accent(.orange)))
            }
        }
    }
}

struct DayArcClock: View {
    @ObservedObject var appearance: Appearance
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let cal = Calendar.current, start = cal.startOfDay(for: ctx.date)
            let frac = ctx.date.timeIntervalSince(start) / 86_400
            let sun = SunTimes.times(on: ctx.date)
            Canvas { gc, size in
                let c = CGPoint(x: size.width / 2, y: size.height - 8), r = min(size.width / 2 - 20, size.height - 18)
                func pt(_ f: Double, _ rr: CGFloat) -> CGPoint { let a = Double.pi + f * .pi; return CGPoint(x: c.x + rr * cos(a), y: c.y + rr * sin(a)) }
                var track = Path(); track.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                gc.stroke(track, with: .color(.white.opacity(0.16)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                var done = Path(); done.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(180 + frac * 180), clockwise: false)
                gc.stroke(done, with: .color(.white), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                if let (rise, set) = sun {
                    for d in [rise, set] {
                        let f = d.timeIntervalSince(start) / 86_400
                        var t = Path(); t.move(to: pt(f, r)); t.addLine(to: pt(f, r - 9))
                        gc.stroke(t, with: .color(.white.opacity(0.6)), lineWidth: 1.5)
                    }
                }
                let n = pt(frac, r)
                gc.fill(Path(ellipseIn: CGRect(x: n.x - 6, y: n.y - 6, width: 12, height: 12)), with: .color(appearance.accent(.orange)))
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    Text(ctx.date.formatted(.dateTime.hour().minute())).font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                    if let (rise, set) = sun {
                        Text("\(rise.formatted(date: .omitted, time: .shortened)) – \(set.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                    }
                }.padding(.bottom, 10)
            }
        }
    }
}

struct WorldArcs: View {
    let zones: [(String, TimeZone)] = [("Here", .current), ("London", TimeZone(identifier: "Europe/London")!), ("New York", TimeZone(identifier: "America/New_York")!)]
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 0) {
                ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                    var cal = Calendar.current
                    let _ = (cal.timeZone = z.1)
                    let c = cal.dateComponents([.hour, .minute], from: ctx.date)
                    let frac = (Double(c.hour ?? 0) * 60 + Double(c.minute ?? 0)) / 1440
                    VStack(spacing: 6) {
                        ZStack {
                            Arc(from: 0, to: 1).stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            Arc(from: 0, to: frac).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }.frame(width: 62, height: 32)
                        Text("\(pad2(c.hour ?? 0)):\(pad2(c.minute ?? 0))").font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                        SmallCaps(text: z.0 + ((c.hour ?? 12) < 6 || (c.hour ?? 12) >= 19 ? " · night" : ""))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 0.5) } }
                }
            }.frame(maxHeight: .infinity)
        }
    }
}

/// Upper half-circle arc from fraction `from` to `to` (0 = left, 1 = right).
struct Arc: Shape {
    var from: Double, to: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.maxY), r = min(rect.width / 2, rect.height)
        p.addArc(center: c, radius: r, startAngle: .degrees(180 + from * 180), endAngle: .degrees(180 + to * 180), clockwise: false)
        return p
    }
}

struct ClockStrip: View {
    @ObservedObject var appearance: Appearance
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            HStack(spacing: 12) {
                Text(ctx.date.formatted(.dateTime.hour().minute())).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date.formatted(.dateTime.weekday(.wide)))
                    Text(ctx.date.formatted(.dateTime.day().month(.wide)))
                }.font(.system(size: 13)).foregroundStyle(secondary)
                Spacer()
            }.frame(maxHeight: .infinity)
        }
    }
}
