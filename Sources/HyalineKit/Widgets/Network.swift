// Network widgets: speeds and connection.

import SwiftUI
import AppKit

struct NetworkMirror: View {
    @ObservedObject var extras: ExtraSampler
    @ObservedObject var appearance: Appearance
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                speed("arrow.down", extras.down, appearance.accent(.teal))
                Spacer()
                speed("arrow.up", extras.up, appearance.accent(.purple))
            }
            VStack(spacing: 0) {
                Spark(values: extras.downHistory, color: appearance.accent(.teal), fill: true)
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 0.5)
                Spark(values: extras.upHistory, color: appearance.accent(.purple), fill: true).scaleEffect(x: 1, y: -1)
            }
        }
    }
    private func speed(_ symbol: String, _ v: Double, _ c: Color) -> some View {
        let (n, u) = bytesPerSecond(v)
        return HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(c)
            Text(n).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
            Text(u).font(.system(size: 12)).foregroundStyle(secondary)
        }
    }
}

struct NetworkSpeeds: View {
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        let (dn, du) = bytesPerSecond(extras.down), (un, uu) = bytesPerSecond(extras.up)
        VStack(alignment: .leading, spacing: 2) {
            HStack { WLabel(symbol: "network", text: "Network"); Spacer(); Image(systemName: "wifi").foregroundStyle(secondary) }
            Spacer(minLength: 0)
            Label("DOWN", systemImage: "arrow.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(secondary)
            Text(dn).font(.system(size: 28, weight: .medium, design: .rounded)) + Text(" \(du)").font(.system(size: 13)).foregroundColor(secondary)
            Label("UP", systemImage: "arrow.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(secondary).padding(.top, 4)
            Text(un).font(.system(size: 20, weight: .medium, design: .rounded)) + Text(" \(uu)").font(.system(size: 12)).foregroundColor(secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NetworkConnection: View {
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi").font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(extras.wifiName ?? "Wi-Fi").font(.system(size: 14.5, weight: .semibold))
                Text(extras.localIP ?? "No address").font(.system(size: 12)).foregroundStyle(secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(extras.pingMs.map { String(format: "%.0f", $0) } ?? "—").font(.system(size: 20, weight: .medium, design: .rounded))
                    + Text(" ms").font(.system(size: 12)).foregroundColor(secondary)
                SmallCaps(text: "ping")
            }
        }.frame(maxHeight: .infinity)
    }
}
