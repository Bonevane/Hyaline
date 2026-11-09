// Battery widgets: level, history, health and Bluetooth devices.

import SwiftUI
import AppKit

func timeLeft(_ s: SystemSampler) -> String {
    if s.charging { return "Charging" }
    if s.onAC { return "On power adapter" }   // e.g. held at 80% by charge limiting
    guard let m = s.minutesLeft else { return "Calculating…" }
    return "\(m / 60)h \(m % 60)m left"
}

struct BatteryBig: View {
    @ObservedObject var sampler: SystemSampler
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WLabel(symbol: "battery.100percent", text: "Battery")
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(sampler.batteryPercent ?? 0)").font(.system(size: 76, weight: .medium, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 24, weight: .medium, design: .rounded)).foregroundStyle(secondary)
            }.frame(height: 66, alignment: .bottom)
            Text(timeLeft(sampler)).font(.system(size: 12)).foregroundStyle(secondary).padding(.top, 8)
            Track(value: Double(sampler.batteryPercent ?? 0) / 100, height: 3).padding(.top, 6)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BatteryLevel: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        let pct = sampler.batteryPercent ?? 0
        ZStack(alignment: .bottom) {
            LiquidFill(fraction: Double(pct) / 100, color: appearance.accent(pct <= 20 ? .red : .green))
            VStack(alignment: .leading, spacing: 2) {
                WLabel(symbol: sampler.charging ? "battery.100percent.bolt" : "battery.100percent", text: "Battery")
                Spacer(minLength: 0)
                Text("\(pct)").font(.system(size: 44, weight: .medium, design: .rounded)).monospacedDigit()
                    + Text("%").font(.system(size: 18)).foregroundColor(secondary)
                Text(timeLeft(sampler)).font(.system(size: 12)).foregroundStyle(secondary)
            }
            .padding(Metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(-Metrics.padding)
    }
}

struct BatteryGlyph: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var appearance: Appearance
    var slim = false
    var body: some View {
        let pct = sampler.batteryPercent ?? 0
        HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: slim ? 12 : 13, style: .continuous).strokeBorder(Color.white.opacity(0.85), lineWidth: slim ? 2 : 2.5)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(slim ? Color.white.opacity(0.85) : appearance.accent(pct <= 20 ? .red : .green))
                        .frame(width: max((geo.size.width - 10) * CGFloat(pct) / 100, 8)).padding(5)
                    Text("\(pct)%").fontWeight(.semibold)
                    .font(.system(size: slim ? 14 : 19, design: .rounded)).foregroundStyle(Color(white: 0.1))
                    .padding(.horizontal, 14)
                }
            }
            RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.85)).frame(width: 4, height: slim ? 14 : 18)
            if slim {
                Text(timeLeft(sampler)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(secondary)
                    .lineLimit(1).fixedSize().padding(.leading, 10)
            }
        }
        .frame(height: slim ? 40 : 54)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) { if !slim { Text(timeLeft(sampler)).font(.system(size: 12.5)).foregroundStyle(secondary).padding(.bottom, 8) } }
    }
}

struct BatteryHistory: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { WLabel(symbol: "battery.100percent", text: "Battery · 24 h"); Spacer()
                Text("\(sampler.batteryPercent ?? 0)%").font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit() }
            if extras.chargeHistory.count < 2 {
                Spacer()
                Text("Recording. The graph fills in as Hyaline runs.").font(.system(size: 12.5)).foregroundStyle(secondary)
                Spacer()
            } else {
                Spark(values: extras.chargeHistory.map { Double($0.1) / 100 }, color: appearance.accent(.green), fill: true)
                HStack { Text(extras.chargeHistory.first!.0.formatted(date: .omitted, time: .shortened)); Spacer(); Text("Now") }
                    .font(.system(size: 11)).foregroundStyle(secondary)
            }
        }
    }
}

struct BatteryHealth: View {
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
            stat("Max capacity", extras.maxCapacity.map { "\($0)%" } ?? "—")
            stat("Cycles", extras.cycleCount.map(String.init) ?? "—")
            stat("Condition", extras.condition ?? "Normal", small: true)
            stat("Temperature", extras.batteryTemp.map { String(format: "%.0f°", $0) } ?? "—")
        }.frame(maxHeight: .infinity)
    }
    private func stat(_ label: String, _ value: String, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SmallCaps(text: label)
            Text(value).font(.system(size: small ? 20 : 24, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}

struct BatteryDevices: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WLabel(symbol: "battery.100percent", text: "Batteries").padding(.bottom, 4)
            row("This Mac", sampler.batteryPercent ?? 0, sampler.charging, first: true)
            ForEach(extras.devices) { d in row(d.name, d.percent, d.charging) }
            if extras.devices.isEmpty {
                Text("No accessories reporting").font(.system(size: 12)).foregroundStyle(secondary).padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
    }
    private func row(_ name: String, _ pct: Int, _ charging: Bool, first: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack { Text(name).lineLimit(1); Spacer(); Text("\(pct)%").monospacedDigit(); if charging { Image(systemName: "bolt.fill").font(.system(size: 10)) } }
                .font(.system(size: 13))
            Track(value: Double(pct) / 100)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5) } }
    }
}
