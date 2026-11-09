// Now Playing widgets: player, strip and vinyl, with a working seek bar.

import SwiftUI
import AppKit

func artwork(_ s: NowPlayingStore, _ size: CGFloat, _ radius: CGFloat) -> some View {
    Group {
        if let img = s.artwork { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
        else { ZStack { Color.white.opacity(0.08); Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundStyle(secondary) } }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
}

struct Controls: View {
    @ObservedObject var s: NowPlayingStore
    var body: some View {
        HStack(spacing: 22) {
            Button { s.command("previous track") } label: { Image(systemName: "backward.fill") }
            Button { s.command("playpause") } label: { Image(systemName: s.playing ? "pause.fill" : "play.fill") }
            Button { s.command("next track") } label: { Image(systemName: "forward.fill") }
        }.buttonStyle(.plain).font(.system(size: 15))
    }
}

struct NothingPlaying: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(secondary)
            Text("Nothing playing").font(.system(size: 12.5)).foregroundStyle(secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NowPlayingArt: View {
    @ObservedObject var s = NowPlayingStore.shared
    var body: some View {
        Group {
            if let title = s.title {
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geo in artwork(s, max(geo.size.width, geo.size.height), 0) }
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(s.artist).font(.system(size: 12.5)).foregroundStyle(Color.white.opacity(0.75)).lineLimit(1)
                    }.padding(Metrics.padding)
                }.padding(-Metrics.padding)
            } else { NothingPlaying() }
        }.onAppear { s.start() }
    }
}

struct NowPlayingPlayer: View {
    @ObservedObject var s = NowPlayingStore.shared
    var body: some View {
        Group {
            if let title = s.title {
                HStack(spacing: 14) {
                    artwork(s, 136, 12)
                    VStack(alignment: .leading, spacing: 2) {
                        SmallCaps(text: s.player)
                        Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1).padding(.top, 4)
                        Text(s.artist).font(.system(size: 13)).foregroundStyle(secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        SeekBar(s: s)
                        Controls(s: s).frame(maxWidth: .infinity).padding(.top, 2)
                    }
                }
            } else { NothingPlaying() }
        }.onAppear { s.start() }
    }
}

/// Scrubbable progress: drag or click anywhere on the bar to seek. The position ticks
/// between polls, and the panel leaves drags here alone instead of moving the widget.
struct SeekBar: View {
    @ObservedObject var s: NowPlayingStore
    @ObservedObject var power = PowerMode.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: power.onBattery ? 2 : 1)) { ctx in
            let pos = s.scrub.map { $0 * s.duration } ?? s.livePosition(at: ctx.date)
            VStack(spacing: 3) {
                Track(value: s.duration > 0 ? pos / s.duration : 0, height: s.scrub == nil ? 3 : 5)
                    .frame(height: 12)
                    .overlay(ScrubArea { fraction, ended in
                        if ended { s.seek(to: fraction * s.duration); s.scrub = nil } else { s.scrub = fraction }
                    })
                HStack { Text(clock(pos)); Spacer(); Text("-" + clock(max(s.duration - pos, 0))) }
                    .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(secondary)
            }
        }
    }
}

/// An AppKit view so it can own the mouse: WidgetPanel skips window dragging for
/// any view that adopts `HandlesOwnDrag`.
struct ScrubArea: NSViewRepresentable {
    let onScrub: (Double, Bool) -> Void
    func makeNSView(context: Context) -> ScrubView { let v = ScrubView(); v.onScrub = onScrub; return v }
    func updateNSView(_ v: ScrubView, context: Context) { v.onScrub = onScrub }
    final class ScrubView: NSView, HandlesOwnDrag {
        var onScrub: (Double, Bool) -> Void = { _, _ in }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private func fraction(_ e: NSEvent) -> Double { Double(min(max(convert(e.locationInWindow, from: nil).x / max(bounds.width, 1), 0), 1)) }
        override func mouseDown(with e: NSEvent) { onScrub(fraction(e), false) }
        override func mouseDragged(with e: NSEvent) { onScrub(fraction(e), false) }
        override func mouseUp(with e: NSEvent) { onScrub(fraction(e), true) }
    }
}

struct NowPlayingStrip: View {
    @ObservedObject var s = NowPlayingStore.shared
    var body: some View {
        Group {
            if let title = s.title {
                HStack(spacing: 12) {
                    artwork(s, 48, 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                        Text(s.artist).font(.system(size: 12.5)).foregroundStyle(secondary).lineLimit(1)
                    }
                    Spacer()
                    Controls(s: s)
                }.frame(maxHeight: .infinity)
            } else { NothingPlaying() }
        }.onAppear { s.start() }
    }
}

struct NowPlayingVinyl: View {
    @ObservedObject var s = NowPlayingStore.shared
    @ObservedObject var power = PowerMode.shared
    var body: some View {
        TimelineView(.animation(minimumInterval: power.onBattery ? 1.0 / 8 : 1.0 / 20, paused: !s.playing)) { ctx in
            let angle = s.playing ? (ctx.date.timeIntervalSinceReferenceDate * 60).truncatingRemainder(dividingBy: 360) : 0
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.09)], center: .center, startRadius: 0, endRadius: 64))
                ForEach(0..<9, id: \.self) { i in Circle().stroke(Color.white.opacity(0.05), lineWidth: 0.6).padding(CGFloat(8 + i * 5)) }
                artwork(s, 46, 23)
                Circle().fill(Color(white: 0.09)).frame(width: 6, height: 6)
            }
            .frame(width: 128, height: 128)
            .rotationEffect(.degrees(angle))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.onAppear { s.start() }
    }
}

func clock(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
