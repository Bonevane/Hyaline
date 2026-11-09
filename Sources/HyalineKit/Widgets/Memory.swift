// Memory widgets: pressure, breakdown and top apps.

import SwiftUI
import AppKit

struct MemoryLevel: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        let frac = sampler.memTotal > 0 ? sampler.memUsed / sampler.memTotal : 0
        let tint = extras.memPressure >= 4 ? Color.red : extras.memPressure >= 2 ? Color.yellow : Color.white
        ZStack(alignment: .bottom) {
            LiquidFill(fraction: frac, color: appearance.monochrome ? .white : tint)
            VStack(alignment: .leading, spacing: 2) {
                WLabel(symbol: "memorychip", text: "Memory")
                Spacer(minLength: 0)
                Text(String(format: "%.1f", sampler.memUsed / gb)).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    + Text(" GB").font(.system(size: 16)).foregroundColor(secondary)
                HStack(spacing: 6) {
                    Circle().fill(appearance.accent(extras.memPressure >= 4 ? .red : extras.memPressure >= 2 ? .yellow : .green)).frame(width: 7, height: 7)
                    Text("\(extras.memPressure >= 4 ? "Critical" : extras.memPressure >= 2 ? "Warning" : "Normal") · of \(Int(sampler.memTotal / gb)) GB")
                        .font(.system(size: 12)).foregroundStyle(secondary)
                }
            }
            .padding(Metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(-Metrics.padding)
    }
}

/// A level that fills the widget from the bottom with a gentle wave on top.
struct LiquidFill: View {
    let fraction: Double
    var color: Color = .white
    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height * CGFloat(min(max(fraction, 0), 1))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Wave().fill(color.opacity(0.16)).frame(height: 10)
                LinearGradient(colors: [color.opacity(0.16), color.opacity(0.07)], startPoint: .top, endPoint: .bottom).frame(height: h)
            }
        }
    }
}

struct Wave: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: r.maxY * 0.6))
        let q = r.width / 4
        for i in 0..<4 {
            let x0 = CGFloat(i) * q
            p.addQuadCurve(to: CGPoint(x: x0 + q, y: r.maxY * 0.6), control: CGPoint(x: x0 + q / 2, y: i % 2 == 0 ? 0 : r.maxY))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: 0, y: r.maxY)); p.closeSubpath()
        return p
    }
}

struct MemoryBar: View {
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var height: CGFloat = 14
    var body: some View {
        let parts: [(Double, Color)] = [(extras.memApp, appearance.accent(.blue)), (extras.memWired, .white.opacity(0.7)),
                                        (extras.memCompressed, .white.opacity(0.45)), (extras.memCached, .white.opacity(0.25)),
                                        (extras.memFree, .white.opacity(0.08))]
        let total = max(parts.map(\.0).reduce(0, +), 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.1).frame(width: max((geo.size.width - 8) * CGFloat(part.0 / total), 0))
                }
            }
        }
        .frame(height: height).clipShape(Capsule())
    }
}

struct MemoryBreakdown: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WLabel(symbol: "memorychip", text: "Memory")
                Spacer()
                Text(String(format: "%.1f", sampler.memUsed / gb)).font(.system(size: 22, weight: .medium, design: .rounded))
                    + Text(" of \(Int(sampler.memTotal / gb)) GB").font(.system(size: 13)).foregroundColor(secondary)
            }
            Spacer(minLength: 0)
            MemoryBar(extras: extras, appearance: appearance)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 4) {
                legend("App", extras.memApp, appearance.accent(.blue)); legend("Wired", extras.memWired, .white.opacity(0.7))
                legend("Compressed", extras.memCompressed, .white.opacity(0.45)); legend("Cached", extras.memCached, .white.opacity(0.25))
                legend("Free", extras.memFree, .white.opacity(0.12))
            }.font(.system(size: 12))
        }
    }
    private func legend(_ name: String, _ v: Double, _ c: Color) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 7, height: 7); Text(name).foregroundStyle(secondary); Text(String(format: "%.1f", v / gb)) }
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}

struct MemoryApps: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { WLabel(symbol: "memorychip", text: "Memory"); Spacer()
                Text(String(format: "%.1f of %d GB", sampler.memUsed / gb, Int(sampler.memTotal / gb))).font(.system(size: 12)).foregroundStyle(secondary) }
            MemoryBar(extras: extras, appearance: appearance, height: 6)
            ForEach(Array(extras.topMemory.prefix(3).enumerated()), id: \.element.id) { i, app in
                if i > 0 { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5) }
                AppRow(app: app, value: String(format: "%.1f GB", app.value / gb))
            }
            Spacer(minLength: 0)
        }
    }
}

struct MemoryStrip: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        HStack(spacing: 12) {
            WLabel(symbol: "memorychip", text: "Memory")
            Text(String(format: "%.1f", sampler.memUsed / gb)).font(.system(size: 24, weight: .medium, design: .rounded))
                + Text(" / \(Int(sampler.memTotal / gb))").font(.system(size: 13)).foregroundColor(secondary)
            MemoryBar(extras: extras, appearance: appearance, height: 8)
            Circle().fill(appearance.accent(extras.memPressure >= 4 ? .red : extras.memPressure >= 2 ? .yellow : .green)).frame(width: 8, height: 8)
        }.frame(maxHeight: .infinity)
    }
}
