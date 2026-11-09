// CPU and system widgets.

import SwiftUI
import AppKit

struct CPUArc: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(spacing: 2) {
            WLabel(symbol: "cpu", text: "CPU")
            ZStack {
                Circle().trim(from: 0, to: 2 / 3).rotation(.degrees(150))
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                Circle().trim(from: 0, to: 2 / 3 * sampler.cpu).rotation(.degrees(150))
                    .stroke(appearance.accent(.green), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                VStack(spacing: 0) {
                    Text("\(Int((sampler.cpu * 100).rounded()))%").font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("\(extras.cores.count) cores").font(.system(size: 11)).foregroundStyle(secondary)
                }
            }.frame(width: 104, height: 104).padding(.top, 6)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CPUCores: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        let p = extras.performanceCores
        VStack(alignment: .leading, spacing: 6) {
            WLabel(symbol: "cpu", text: "CPU")
            Text("\(Int((sampler.cpu * 100).rounded()))%").font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
            Spacer(minLength: 0)
            bars(Array(extras.cores.prefix(p)), height: 150, color: appearance.accent(.green))
            SmallCaps(text: "Performance")
            bars(Array(extras.cores.dropFirst(p)), height: 46, color: appearance.accent(.teal)).padding(.top, 4)
            SmallCaps(text: "Efficiency")
        }
    }
    private func bars(_ values: [Double], height: CGFloat, color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(color).frame(height: max(height * v, 3))
                }.frame(width: 9, height: height)
            }
        }
    }
}

struct CPUGraph: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WLabel(symbol: "cpu", text: "CPU · 80 s")
                Spacer()
                Text("\(Int((sampler.cpu * 100).rounded()))%").font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Spark(values: sampler.cpuHistory, color: appearance.accent(.green), fill: true)
            if let top = extras.topEnergy.first {
                HStack { Text("Busiest").foregroundStyle(secondary); Spacer(); AppRow(app: top, value: "").fixedSize() }.font(.system(size: 12.5))
            }
        }
    }
}

struct CPUStrip: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        HStack(spacing: 14) {
            WLabel(symbol: "cpu", text: "CPU")
            Text("\(Int((sampler.cpu * 100).rounded()))%").font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit().frame(width: 64, alignment: .leading)
            Spark(values: sampler.cpuHistory, color: appearance.accent(.green)).frame(height: 30)
        }.frame(maxHeight: .infinity)
    }
}

struct SystemOverview: View {
    @ObservedObject var sampler: SystemSampler
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(spacing: 0) {
            row("cpu", "CPU", "\(Int((sampler.cpu * 100).rounded()))%", sampler.cpuHistory, .green, first: true)
            row("cube.transparent", "GPU", "\(Int((extras.gpu * 100).rounded()))%", extras.gpuHistory, .purple)
            row("memorychip", "Memory", String(format: "%.1f GB", sampler.memUsed / gb), extras.memHistory, .blue)
            let (v, u) = bytesPerSecond(extras.down)
            row("network", "Network", "↓ \(v) \(u)", extras.downHistory, .teal)
        }
    }
    private func row(_ symbol: String, _ name: String, _ value: String, _ values: [Double], _ color: Color, first: Bool = false) -> some View {
        VStack(spacing: 5) {
            HStack { WLabel(symbol: symbol, text: name); Spacer(); Text(value).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit() }
            Spark(values: values, color: appearance.accent(color)).frame(height: 28)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) { if !first { Rectangle().fill(Color.white.opacity(0.14)).frame(height: 0.5) } }
    }
}
