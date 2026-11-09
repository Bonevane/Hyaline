// Temperature widgets: sensor rings, the slim strip and the thermometer.

import SwiftUI
import AppKit

/// Temperatures shown on a fixed 25–105° scale, so a bar or line means the same heat everywhere.
func heat(_ t: Double?) -> Double { min(max(((t ?? 25) - 25) / 80, 0), 1) }
func degrees(_ t: Double?) -> String { t.map { "\(Int($0.rounded()))°" } ?? "—" }
func rpm(_ v: Double) -> String { v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v.rounded()))" }
let heatColors: [Color] = [.teal, .green, .yellow, .orange, .red]

/// The heat colours in Default style; plain white (Clear) or the accent (Tinted) otherwise.
func heatStyle(_ appearance: Appearance) -> AnyShapeStyle {
    appearance.style == .full ? AnyShapeStyle(LinearGradient(colors: heatColors, startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(appearance.accent(.white))
}
func heatColor(_ t: Double?, _ appearance: Appearance) -> Color {
    guard appearance.style == .full else { return appearance.accent(.white) }
    let f = heat(t) * Double(heatColors.count - 1)
    return heatColors[min(Int(f.rounded()), heatColors.count - 1)]
}

/// A bar whose fill is cut from one full-width heat gradient, so its tip shows how hot.
struct HeatTrack: View {
    let fraction: Double
    let style: AnyShapeStyle
    var height: CGFloat = 5
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Rectangle().fill(style)
                    .mask(alignment: .leading) { Capsule().frame(width: max(height, geo.size.width * CGFloat(fraction))) }
                    .opacity(fraction > 0 ? 1 : 0)
            }
        }.frame(height: height)
    }
}

/// The last few minutes of a temperature on the fixed heat scale.
struct TempTrace: View {
    let values: [Double]
    let style: AnyShapeStyle
    /// Smallest range the trace spans, so a steady reading stays mid-height instead of jittering.
    var minSpan: Double = 12
    var body: some View {
        let lo0 = values.min() ?? 0, hi0 = values.max() ?? 1
        let mid = (lo0 + hi0) / 2, half = max(hi0 - lo0, minSpan) / 2 * 1.15
        let scale = { (v: Double) in (v - (mid - half)) / (2 * half) }
        GeometryReader { geo in
            let pts = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat(min(max(scale(v), 0), 1))))
            }
            ZStack {
                Path { p in
                    guard let first = pts.first, pts.count > 1 else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height)); pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height)); p.closeSubpath()
                }.fill(LinearGradient(colors: [Color.white.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = pts.first, pts.count > 1 else { return }
                    p.move(to: first); pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(style, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// Fan glyph that spins while the fans run, faster as they speed up.
struct FanGlyph: View {
    let share: Double
    var size: CGFloat = 13
    @ObservedObject var power = PowerMode.shared
    var body: some View {
        // Drawn at 24 fps on power and 8 fps on battery, rather than every display frame.
        TimelineView(.animation(minimumInterval: power.onBattery ? 1.0 / 8 : 1.0 / 24, paused: share <= 0)) { ctx in
            let turns = share > 0 ? ctx.date.timeIntervalSinceReferenceDate * (0.4 + share * 2) : 0
            Image(systemName: "fanblades.fill").font(.system(size: size, weight: .semibold))
                .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
        }
    }
}

/// Apple-style ring: grey track, fill from the top clockwise, symbol in the middle.
struct Ring: View {
    let fraction: Double
    let color: Color
    let symbol: AnyView
    var line: CGFloat = 5
    var symbolSize: CGFloat = 17
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: line)
            Circle().trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            symbol.font(.system(size: symbolSize, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
        }.padding(line / 2)
    }
}

/// Five rings: CPU, GPU, SSD and battery heat, and fan speed.
struct SensorsList: View {
    @ObservedObject var s = SensorStore.shared
    @ObservedObject var appearance: Appearance
    private var fanShare: Double {
        guard let top = s.fans.max(), top >= 1 else { return 0 }
        return zip(s.fans, s.fanMax + Array(repeating: 6000, count: s.fans.count)).map { $0 / max($1, 1) }.max() ?? 0
    }
    var body: some View {
        HStack(spacing: 0) {
            gauge("cpu", "CPU", s.cpu)
            gauge("cube.transparent", "GPU", s.gpu)
            gauge("internaldrive", "SSD", s.ssd)
            gauge("battery.75percent", "Battery", s.battery)
            let fan = s.fans.max() ?? 0
            cell(Ring(fraction: fanShare, color: appearance.accent(.cyan), symbol: AnyView(FanGlyph(share: fanShare, size: 17))),
                 fan < 1 ? "Off" : rpm(fan), "Fans")
        }.frame(maxWidth: .infinity, maxHeight: .infinity).onAppear { s.start() }
    }
    private func gauge(_ symbol: String, _ name: String, _ t: Double?) -> some View {
        cell(Ring(fraction: heat(t), color: heatColor(t, appearance), symbol: AnyView(Image(systemName: symbol))), degrees(t), name)
    }
    private func cell(_ ring: Ring, _ value: String, _ name: String) -> some View {
        VStack(spacing: 5) {
            ring.frame(width: 60, height: 60)
            Text(value).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
            Text(name).font(.system(size: 10.5, weight: .medium)).foregroundStyle(secondary).lineLimit(1)
        }.frame(maxWidth: .infinity)
    }
}

/// One slim-strip cell: a small ring, the value, and a label under it.
struct RingCell: View {
    let ring: Ring
    let value: String
    let label: String
    var size: CGFloat = 40
    var valueSize: CGFloat = 18
    var body: some View {
        HStack(spacing: 6) {
            ring.frame(width: size, height: size)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(size: valueSize, weight: .medium, design: .rounded)).monospacedDigit()
                Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(secondary)
            }.lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Slim: CPU, GPU and fans as small rings.
struct ThermalStrip: View {
    @ObservedObject var s = SensorStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        let fan = s.fans.max() ?? 0
        let share = fan < 1 ? 0 : zip(s.fans, s.fanMax + Array(repeating: 6000, count: s.fans.count)).map { $0 / max($1, 1) }.max() ?? 0
        HStack(spacing: 10) {
            RingCell(ring: Ring(fraction: heat(s.cpu), color: heatColor(s.cpu, appearance), symbol: AnyView(Image(systemName: "cpu")), line: 4, symbolSize: 14),
                     value: degrees(s.cpu), label: "CPU")
            RingCell(ring: Ring(fraction: heat(s.gpu), color: heatColor(s.gpu, appearance), symbol: AnyView(Image(systemName: "cube.transparent")), line: 4, symbolSize: 14),
                     value: degrees(s.gpu), label: "GPU")
            RingCell(ring: Ring(fraction: share, color: appearance.accent(.cyan), symbol: AnyView(FanGlyph(share: share, size: 14)), line: 4, symbolSize: 14),
                     value: fan < 1 ? "Off" : rpm(fan), label: fan < 1 ? "Fans" : "Fans · rpm")
        }.frame(maxHeight: .infinity).onAppear { s.start() }
    }
}

struct Thermometer: View {
    @ObservedObject var s = SensorStore.shared
    @ObservedObject var appearance: Appearance
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                WLabel(symbol: "thermometer.medium", text: "CPU temp")
                Spacer(minLength: 0)
                Text(s.cpu.map { "\(Int($0.rounded()))°" } ?? "—").font(.system(size: 48, weight: .medium, design: .rounded))
                Text("peak \(Int(s.peakCPU.rounded()))° since launch").font(.system(size: 12)).foregroundStyle(secondary)
            }
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Capsule().fill(appearance.monochrome ? AnyShapeStyle(Color.white)
                                                        : AnyShapeStyle(LinearGradient(colors: [.teal, .orange, .red], startPoint: .bottom, endPoint: .top)))
                        .frame(height: geo.size.height * CGFloat(min(max((s.cpu ?? 0) / 105, 0.04), 1)))
                }.background(Capsule().fill(Color.white.opacity(0.12)))
            }.frame(width: 12)
        }.onAppear { s.start() }
    }
}
