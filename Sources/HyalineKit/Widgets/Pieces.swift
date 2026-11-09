// Shared building blocks for widget views: labels, tracks, sparklines and formatting.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

struct WidgetHeader: View {
    let symbol: String
    let title: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
    }
}

struct Sparkline: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        for (i, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat(min(max(value, 0), 1))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

// The plate's edge border, as on Apple's widgets: light all the way round, fading
// dark at the top-right and bottom-left corners. The glass engine's own edge only
// lights the top-left and bottom-right, and no setting changes that.
struct EdgeBorder: View {
    var body: some View {
        // Angles run clockwise from 3 o'clock: 0.375 = bottom-left, 0.875 = top-right.
        let light = Color.white.opacity(0.35), dark = Color.white.opacity(0.04)
        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
            .strokeBorder(AngularGradient(stops: [
                .init(color: light, location: 0),
                .init(color: light, location: 0.27),
                .init(color: dark, location: 0.375),
                .init(color: light, location: 0.48),
                .init(color: light, location: 0.77),
                .init(color: dark, location: 0.875),
                .init(color: light, location: 0.98),
            ], center: .center), lineWidth: 1)
    }
}

// MARK: - Shared context and pieces

final class WidgetContext {
    let sampler: SystemSampler
    let extras: ExtraSampler
    let appearance: Appearance
    init(sampler: SystemSampler, extras: ExtraSampler, appearance: Appearance) {
        self.sampler = sampler; self.extras = extras; self.appearance = appearance
    }
}

let secondary = Color.white.opacity(0.6)
let faint = Color.white.opacity(0.3)
let gb = 1_073_741_824.0

/// Icon and name label, big enough to read (the review asked for both).
struct WLabel: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            Text(text.uppercased()).font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
        }
        .foregroundStyle(Color.white.opacity(0.75))
        .lineLimit(1)
    }
}

struct SmallCaps: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(secondary)
    }
}

/// Values in 0…1 drawn as a line, optionally with a soft area fill.
struct Spark: View {
    let values: [Double]
    var color: Color = .white
    var fill = false
    var body: some View {
        GeometryReader { geo in
            let maxV = max(values.max() ?? 1, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: geo.size.height * (1 - CGFloat(v / maxV)))
            }
            ZStack {
                if fill {
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: geo.size.height)); pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height)); p.closeSubpath()
                    }.fill(color.opacity(0.18))
                }
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first); pts.dropFirst().forEach { p.addLine(to: $0) }
                }.stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct Track: View {
    let value: Double
    var color: Color = .white
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }.frame(height: height)
    }
}

struct AppRow: View {
    let app: AppUsage
    let value: String
    var body: some View {
        HStack(spacing: 7) {
            if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
            Text(app.name).lineLimit(1)
            Spacer(minLength: 6)
            Text(value).foregroundStyle(secondary).monospacedDigit()
        }.font(.system(size: 13))
    }
}

/// Power in W, or mW below 1 W (most apps idle well under a watt).
func watts(_ w: Double) -> String { w >= 1 ? String(format: "%.1f W", w) : String(format: "%.0f mW", w * 1000) }
func pad2(_ n: Int) -> String { String(format: "%02d", n) }
func bytesPerSecond(_ v: Double) -> (String, String) {
    if v >= 1_000_000 { return (String(format: "%.1f", v / 1_000_000), "MB/s") }
    if v >= 1_000 { return (String(format: "%.0f", v / 1_000), "KB/s") }
    return (String(format: "%.0f", v), "B/s")
}
