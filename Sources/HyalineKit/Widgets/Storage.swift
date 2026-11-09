// Storage widgets.

import SwiftUI
import AppKit

struct StorageColumn: View {
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        let used = max(extras.diskTotal - extras.diskFree, 0)
        let frac = extras.diskTotal > 0 ? used / extras.diskTotal : 0
        VStack(alignment: .leading, spacing: 2) {
            WLabel(symbol: "internaldrive", text: "Macintosh HD")
            Text(String(format: "%.0f", extras.diskFree / 1e9)).font(.system(size: 30, weight: .medium, design: .rounded))
                + Text(" GB free").font(.system(size: 13)).foregroundColor(secondary)
            Text(String(format: "of %.0f GB", extras.diskTotal / 1e9)).font(.system(size: 12)).foregroundStyle(secondary)
            HStack(alignment: .bottom, spacing: 12) {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.85)).frame(height: geo.size.height * CGFloat(frac))
                    }
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.1)))
                }.frame(width: 30)
                VStack(alignment: .leading, spacing: 8) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 0) { Text("Used").foregroundStyle(secondary); Text(String(format: "%.0f GB", used / 1e9)) }
                    VStack(alignment: .leading, spacing: 0) { Text("Free").foregroundStyle(secondary); Text(String(format: "%.0f GB", extras.diskFree / 1e9)) }
                }.font(.system(size: 11.5))
            }.padding(.top, 10)
        }
    }
}

struct StorageStrip: View {
    @ObservedObject var extras: ExtraSampler
    var body: some View {
        HStack(spacing: 14) {
            WLabel(symbol: "internaldrive", text: "Storage")
            Text(String(format: "%.0f", extras.diskFree / 1e9)).font(.system(size: 24, weight: .medium, design: .rounded))
                + Text(" GB free").font(.system(size: 12)).foregroundColor(secondary)
            Track(value: extras.diskTotal > 0 ? 1 - extras.diskFree / extras.diskTotal : 0, height: 8)
        }.frame(maxHeight: .infinity)
    }
}
