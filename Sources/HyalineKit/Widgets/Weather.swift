// Weather widgets.

import SwiftUI
import AppKit

func night(_ d: Date = Date()) -> Bool {
    guard let (rise, set) = SunTimes.times(on: d) else { return false }
    return d < rise || d > set
}

struct WeatherBig: View {
    @ObservedObject var store = WeatherStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let (symbol, name) = WeatherStore.describe(store.code, night: night())
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(store.place.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(secondary); Spacer()
                Image(systemName: symbol).symbolRenderingMode(appearance.monochrome ? .monochrome : .multicolor).font(.system(size: 16)) }
            Spacer(minLength: 0)
            Text(store.current.map { "\(Int($0.rounded()))°" } ?? "—").font(.system(size: 66, weight: .regular, design: .rounded))
            Text(name).font(.system(size: 13))
            if let today = store.days.first {
                Text("H \(Int(today.high.rounded()))° · L \(Int(today.low.rounded()))°").font(.system(size: 12)).foregroundStyle(secondary)
            }
        }
        .onAppear { store.start() }
    }
}

struct WeatherCurve: View {
    @ObservedObject var store = WeatherStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let hours = Array(store.hours.prefix(7))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(store.current.map { "\(Int($0.rounded()))°" } ?? "—").font(.system(size: 26, weight: .medium, design: .rounded))
                Text("\(WeatherStore.describe(store.code).1) · \(store.place)").font(.system(size: 12.5)).foregroundStyle(secondary).lineLimit(1)
                Spacer()
                if let t = store.days.first { Text("H\(Int(t.high.rounded())) L\(Int(t.low.rounded()))").font(.system(size: 12)).foregroundStyle(secondary) }
            }
            if hours.count > 1 {
                let lo = (hours.map(\.temp).min() ?? 0) - 1, hi = (hours.map(\.temp).max() ?? 1) + 1
                GeometryReader { geo in
                    let h = geo.size.height - 30
                    let pts = hours.enumerated().map { i, w in
                        CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(hours.count - 1), y: 14 + h * CGFloat(1 - (w.temp - lo) / (hi - lo)))
                    }
                    ZStack {
                        Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                            .stroke(appearance.accent(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        ForEach(Array(hours.enumerated()), id: \.offset) { i, w in
                            Circle().fill(Color.white).frame(width: 6, height: 6).position(pts[i])
                            Text("\(Int(w.temp.rounded()))°").font(.system(size: 10.5)).position(x: pts[i].x, y: pts[i].y - 11)
                            Text(w.id.formatted(.dateTime.hour())).font(.system(size: 10)).foregroundStyle(secondary)
                                .position(x: pts[i].x, y: geo.size.height - 4)
                        }
                    }
                }.padding(.horizontal, 8)
            } else { Spacer() }
        }
        .onAppear { store.start() }
    }
}

struct WeatherWeek: View {
    @ObservedObject var store = WeatherStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let lo = store.days.map(\.low).min() ?? 0, hi = store.days.map(\.high).max() ?? 1
        VStack(alignment: .leading, spacing: 0) {
            WLabel(symbol: "cloud.sun", text: "\(store.place) · 7 days").padding(.bottom, 6)
            ForEach(Array(store.days.enumerated()), id: \.element.id) { i, d in
                HStack(spacing: 10) {
                    Text(i == 0 ? "Today" : d.id.formatted(.dateTime.weekday(.abbreviated))).frame(width: 46, alignment: .leading)
                    Image(systemName: WeatherStore.describe(d.code).0).symbolRenderingMode(appearance.monochrome ? .monochrome : .multicolor).frame(width: 22)
                    Text("\(Int(d.low.rounded()))°").foregroundStyle(secondary).monospacedDigit().frame(width: 30, alignment: .trailing)
                    GeometryReader { geo in
                        let w = geo.size.width, span = max(hi - lo, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12))
                            Capsule().fill(appearance.monochrome ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient(colors: [.teal, .orange], startPoint: .leading, endPoint: .trailing)))
                                .frame(width: w * CGFloat((d.high - d.low) / span)).offset(x: w * CGFloat((d.low - lo) / span))
                        }
                    }.frame(height: 5)
                    Text("\(Int(d.high.rounded()))°").monospacedDigit().frame(width: 30, alignment: .leading)
                }
                .font(.system(size: 14))
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5) } }
            }
        }
        .onAppear { store.start() }
    }
}

struct WeatherStrip: View {
    @ObservedObject var store = WeatherStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let (symbol, name) = WeatherStore.describe(store.code, night: night())
        HStack(spacing: 12) {
            Image(systemName: symbol).symbolRenderingMode(appearance.monochrome ? .monochrome : .multicolor).font(.system(size: 20))
            Text(store.current.map { "\(Int($0.rounded()))°" } ?? "—").font(.system(size: 30, weight: .regular, design: .rounded))
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                if let t = store.days.first { Text("H\(Int(t.high.rounded())) L\(Int(t.low.rounded()))") }
            }.font(.system(size: 12.5)).foregroundStyle(secondary)
            Spacer()
            if let next = store.hours.dropFirst().first {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(next.id.formatted(.dateTime.hour())).foregroundStyle(secondary)
                    Text("\(Int(next.temp.rounded()))°" + (store.sunset.map { " · sunset \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
                }.font(.system(size: 12.5))
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { store.start() }
    }
}
