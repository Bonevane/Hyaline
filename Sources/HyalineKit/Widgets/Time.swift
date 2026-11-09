// Time widgets: countdown, focus timer and sun path.

import SwiftUI
import AppKit

struct Countdown: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let cal = Calendar.current
            let next = cal.date(from: DateComponents(year: cal.component(.year, from: ctx.date) + 1, month: 1, day: 1))!
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: ctx.date), to: next).day ?? 0
            VStack(alignment: .leading, spacing: 0) {
                SmallCaps(text: "Until")
                Text("New Year").font(.system(size: 15, weight: .semibold)).padding(.top, 2)
                Spacer(minLength: 0)
                Text("\(days)").font(.system(size: 64, weight: .medium, design: .rounded)).monospacedDigit()
                Text("days · 1 Jan \(String(cal.component(.year, from: next)))").font(.system(size: 12)).foregroundStyle(secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FocusTimer: View {
    @AppStorage("focusEnd") private var endTime: Double = 0
    @AppStorage("focusDoneToday") private var done: Int = 0
    let length: Double = 25 * 60
    var body: some View {
        TimelineView(.periodic(from: .now, by: endTime > Date().timeIntervalSince1970 ? 1 : 60)) { ctx in
            let remaining = endTime > ctx.date.timeIntervalSince1970 ? endTime - ctx.date.timeIntervalSince1970 : 0
            let running = remaining > 0
            VStack(alignment: .leading, spacing: 0) {
                WLabel(symbol: "timer", text: "Focus")
                Spacer(minLength: 0)
                Text(String(format: "%02d:%02d", Int(running ? remaining : length) / 60, Int(running ? remaining : length) % 60))
                    .font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit()
                Track(value: running ? 1 - remaining / length : 0, height: 3).padding(.top, 8)
                HStack {
                    Text("\(done) done today").font(.system(size: 12)).foregroundStyle(secondary)
                    Spacer()
                    Button {
                        if running { endTime = 0 } else { endTime = Date().timeIntervalSince1970 + length }
                    } label: {
                        Image(systemName: running ? "stop.fill" : "play.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(white: 0.1)).frame(width: 30, height: 30).background(Circle().fill(Color.white))
                    }.buttonStyle(.plain)
                }.padding(.top, 10)
            }
        }
    }
}

/// The sun's height over the whole day as a smooth curve crossing a horizon line at
/// sunrise and sunset. Daylight part bright with a soft fill, night part dim, the
/// golden hour picked out before sunset, and the sun where it is now.
struct SunPath: View {
    @ObservedObject var appearance: Appearance
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            if let (rise, set) = SunTimes.times(on: ctx.date) {
                let start = Calendar.current.startOfDay(for: ctx.date)
                let day = 86_400.0
                let fRise = rise.timeIntervalSince(start) / day, fSet = set.timeIntervalSince(start) / day
                let golden = set.addingTimeInterval(-40 * 60)
                let fGolden = golden.timeIntervalSince(start) / day
                let fNow = ctx.date.timeIntervalSince(start) / day
                // Show sunrise to sunset with ~1.4 h either side, so the day is a wide hill.
                let margin = 0.06, lo = fRise - margin, hi = fSet + margin
                VStack(spacing: 6) {
                    HStack {
                        WLabel(symbol: "sun.horizon", text: "Sun")
                        Spacer()
                        Text(fNow < fSet && fNow > fRise ? "Sunset \(set.formatted(date: .omitted, time: .shortened))"
                                                         : "Sunrise \(rise.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(secondary)
                    }
                    Canvas { gc, size in
                        let horizonY = size.height * 0.7, amp = size.height * 0.62
                        // Elevation as a sine over daylight, continuing below the horizon at night.
                        func y(_ f: Double) -> CGFloat { horizonY - amp * CGFloat(sin(.pi * (f - fRise) / (fSet - fRise))) }
                        func x(_ f: Double) -> CGFloat { size.width * CGFloat((f - lo) / (hi - lo)) }
                        func curve(_ a: Double, _ b: Double) -> Path {
                            var p = Path(); let steps = 80
                            for i in 0...steps { let f = a + (b - a) * Double(i) / Double(steps)
                                let pt = CGPoint(x: x(f), y: y(f)); i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                            return p
                        }
                        // daylight fill under the curve
                        var fill = curve(fRise, fSet); fill.addLine(to: CGPoint(x: x(fSet), y: horizonY))
                        fill.addLine(to: CGPoint(x: x(fRise), y: horizonY)); fill.closeSubpath()
                        gc.fill(fill, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.02)]),
                                                            startPoint: CGPoint(x: 0, y: horizonY - amp), endPoint: CGPoint(x: 0, y: horizonY)))
                        // night parts dim, day bright, golden hour in the accent
                        gc.stroke(curve(lo, fRise), with: .color(.white.opacity(0.22)), lineWidth: 1.5)
                        gc.stroke(curve(fSet, hi), with: .color(.white.opacity(0.22)), lineWidth: 1.5)
                        gc.stroke(curve(fRise, fGolden), with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        gc.stroke(curve(fGolden, fSet), with: .color(appearance.accent(.orange)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        // horizon
                        var h = Path(); h.move(to: CGPoint(x: 0, y: horizonY)); h.addLine(to: CGPoint(x: size.width, y: horizonY))
                        gc.stroke(h, with: .color(.white.opacity(0.3)), lineWidth: 0.75)
                        // sun with a soft glow
                        let fSun = min(max(fNow, lo), hi)
                        let s = CGPoint(x: x(fSun), y: y(fSun)), up = fNow > fRise && fNow < fSet
                        gc.fill(Path(ellipseIn: CGRect(x: s.x - 14, y: s.y - 14, width: 28, height: 28)), with: .color(appearance.accent(.yellow).opacity(up ? 0.18 : 0.06)))
                        gc.fill(Path(ellipseIn: CGRect(x: s.x - 6.5, y: s.y - 6.5, width: 13, height: 13)), with: .color(up ? appearance.accent(.yellow) : .white.opacity(0.45)))
                        // times under the horizon at sunrise and sunset
                        for (f, d) in [(fRise, rise), (fSet, set)] {
                            gc.draw(Text(d.formatted(date: .omitted, time: .shortened)).font(.system(size: 11, weight: .medium)).foregroundColor(secondary),
                                    at: CGPoint(x: x(f), y: horizonY + 13))
                        }
                    }
                }
            } else {
                Text("No sunrise today").foregroundStyle(secondary)
            }
        }
    }
}
