// Energy widgets: whole-Mac power and the apps using the most.

import SwiftUI
import AppKit

struct EnergyTop: View {
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WLabel(symbol: "bolt.fill", text: "Energy")
            Spacer(minLength: 0)
            if let top = extras.topEnergy.first {
                HStack(spacing: 8) {
                    if let icon = top.icon { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                    Text(top.name).font(.system(size: 19, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                let parts = watts(top.value).split(separator: " ")
                Text(parts.first.map(String.init) ?? "").font(.system(size: 42, weight: .medium, design: .rounded)).foregroundStyle(appearance.accent(.orange))
                    + Text(" " + (parts.last.map(String.init) ?? "")).font(.system(size: 16)).foregroundColor(secondary)
            } else {
                Text("Measuring…").font(.system(size: 13)).foregroundStyle(secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Energy

func powerText(_ w: Double) -> (String, String) {
    w >= 1 ? (String(format: w >= 10 ? "%.0f" : "%.1f", w), "W") : (String(format: "%.0f", w * 1000), "mW")
}

/// Whole-Mac draw on the left, the four hungriest apps on the right. Every row has a
/// fixed slot and height, so nothing shifts as values or the ranking change.
struct EnergyList: View {
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    private let rows = 4
    var body: some View {
        let top = Array(extras.topEnergy.prefix(rows))
        let total = max(top.first?.value ?? 0, 0.001)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WLabel(symbol: "bolt.fill", text: "Power")
                let (num, unit) = powerText(extras.systemPower ?? extras.appsPower)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(num).font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                    Text(unit).font(.system(size: 15)).foregroundStyle(secondary)
                }.foregroundStyle(appearance.accent(.orange)).padding(.top, 2)
                TempTrace(values: extras.powerHistory, style: AnyShapeStyle(appearance.accent(.orange)), minSpan: 6)
                    .frame(maxHeight: .infinity).padding(.vertical, 6)
                Text("whole Mac").font(.system(size: 11.5)).foregroundStyle(secondary)
            }.frame(width: 104, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.12)).frame(width: 1).padding(.vertical, 2)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { i in
                    slot(i < top.count ? top[i] : nil, share: i < top.count ? top[i].value / total : 0, lead: i == 0)
                        .frame(height: 30)
                    if i < rows - 1 { Spacer(minLength: 0) }
                }
            }
        }
    }
    private func slot(_ app: AppUsage?, share: Double, lead: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app?.icon { Image(nsImage: icon).resizable() } else { RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)) }
            }.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(app?.name ?? (extras.topEnergy.isEmpty ? "Measuring…" : " ")).font(.system(size: 12.5)).lineLimit(1)
                        .foregroundStyle(app == nil ? secondary : .white)
                    Spacer(minLength: 4)
                    if let app {
                        let (n, u) = powerText(app.value)
                        Text("\(n) \(u)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(secondary)
                    }
                }
                Track(value: share, color: lead ? appearance.accent(.orange) : Color.white.opacity(0.8), height: 3)
            }
        }
    }
}

/// Slim: whole-Mac draw, then the top three apps, each icon ringed by its share.
struct EnergyStrip: View {
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        let top = Array(extras.topEnergy.prefix(3))
        let lead = max(top.first?.value ?? 0, 0.001)
        let power = extras.systemPower ?? extras.appsPower
        let (pn, pu) = powerText(power)
        HStack(spacing: 8) {
            RingCell(ring: Ring(fraction: power / max(extras.powerHistory.max() ?? 0, 20), color: appearance.accent(.orange),
                                symbol: AnyView(Image(systemName: "bolt.fill")), line: 3.5, symbolSize: 13),
                     value: pn, label: pu, size: 34, valueSize: 16)
            ForEach(0..<3, id: \.self) { i in
                let app = i < top.count ? top[i] : nil
                let (n, u) = powerText(app?.value ?? 0)
                RingCell(ring: Ring(fraction: (app?.value ?? 0) / lead, color: i == 0 ? appearance.accent(.orange) : Color.white.opacity(0.85),
                                    symbol: AnyView(Group {
                                        if let icon = app?.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) } else { Color.clear.frame(width: 20, height: 20) }
                                    }), line: 3, symbolSize: 14),
                         value: app == nil ? "—" : n, label: app == nil ? " " : u, size: 34, valueSize: 16)
                    .help(app?.name ?? "")
            }
        }.frame(maxHeight: .infinity)
    }
}
