// Self-checks for development (layout and snapping are checked by `swift run hyaline-check`), compiled into debug builds only. Each renders from
// off-screen windows or synthetic frames; nothing on the screen is ever captured.
//
//   HYALINE_GALLERY=dir          every widget kind, on flat stand-in plates, to PNG pages
//   HYALINE_GALLERY_ONLY=a,b     limit that to some kinds
//   HYALINE_GALLERY_WINDOW=dir   the Widget Gallery and two edit popups, to PNGs
//   HYALINE_SHOWCASE=dir         every showcase layout on a wallpaper, plates as stand-ins
//   HYALINE_DEBUG_FRAMES=file    how many of Apple's widgets and which window layers are visible

#if DEBUG
import AppKit
import SwiftUI

extension AppDelegate {
    /// Runs the check named in the environment, if any. True when one ran.
    func runSelfCheckIfAsked() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["HYALINE_GALLERY"] { galleryTest(to: dir); return true }
        if let dir = env["HYALINE_GALLERY_WINDOW"] {
            panels.forEach { $0.orderOut(nil) }
            sampler.start(); extras.start()
            GallerySelfCheck.render(to: dir, model: GalleryModel(context: context, surface: { [unowned self] in self.surface },
                                                                  add: { [unowned self] in self.addFromGallery($0, $1, $2) }))
            return true
        }
        if let dir = env["HYALINE_SHOWCASE"] { showcasePreview(to: dir); return true }
        if let out = env["HYALINE_DEBUG_FRAMES"] {
            let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let lines = ["apple frames: \(Snapper.appleWidgetFrames().count)", "windows visible: \(all.count)",
                         "layers: \(Set(all.compactMap { $0[kCGWindowLayer as String] as? Int }).sorted().prefix(8))"]
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            NSApp.terminate(nil); return true
        }
        return false
    }

    /// Every showcase layout over a wallpaper, at this screen's size, with flat
    /// stand-ins for the glass. For checking composition before going live.
    func showcasePreview(to dir: String) {
        GalleryMode.on = true; SampleData.on = true
        CalendarStore.shared.useSample(true)
        panels.forEach { $0.orderOut(nil) }
        sampler.start(); extras.start()
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let full = screen.frame, visible = screen.visibleFrame
        var windows: [(String, NSWindow)] = []
        for (i, layout) in ShowcaseLayout.all.enumerated() {
            let wallpaper = ShowcaseWallpaper.all[ShowcaseWallpaper.named(layout.wallpaper) ?? 0]
            let items = layout.frames(in: visible)
            let page = ZStack(alignment: .topLeading) {
                ShowcaseWallpaperView(wallpaper: wallpaper)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let (kind, r) = item
                    ZStack {
                        if kind.look != .clear {
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(Color.black.opacity(0.42))
                            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                        }
                        (kind.configured?(self.context, WidgetConfig()) ?? kind.view?(self.context) ?? AnyView(
                            Text("Glass clock").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white.opacity(0.7))))
                            .padding(Metrics.padding)
                    }
                    .frame(width: r.width, height: r.height).clipped()
                    .offset(x: r.minX - full.minX, y: full.maxY - r.maxY)
                }
            }
            .frame(width: full.width, height: full.height, alignment: .topLeading)
            .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: page)
            host.frame = NSRect(origin: .zero, size: full.size)
            let w = NSWindow(contentRect: NSRect(x: -40_000 - CGFloat(i) * 3_000, y: -40_000, width: full.width, height: full.height),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host
            w.orderFrontRegardless()
            windows.append(("showcase-\(i + 1)-\(layout.name.lowercased())", w))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            for (name, w) in windows {
                guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// Self-check: renders every SwiftUI widget kind straight to PNG pages, inside the
    /// app, from an off-screen window. Nothing on the user's screen is ever captured.
    /// Plates are drawn as flat stand-ins (glass can't render off-screen).
    func galleryTest(to dir: String) {
        GalleryMode.on = true
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        sampler.start(); extras.start()
        let pageSize = NSSize(width: 1180, height: 760)
        var pages: [[(WidgetKind, CGPoint)]] = [[]]
        var x: CGFloat = 20, rowTop: CGFloat = pageSize.height - 20, rowH: CGFloat = 0
        let only = ProcessInfo.processInfo.environment["HYALINE_GALLERY_ONLY"]?.split(separator: ",").map(String.init)
        for kind in Registry.kinds where kind.native == nil && (only.map { $0.contains(kind.id) } ?? true) {
            let size = kind.size.cg
            if x + size.width > pageSize.width - 20 { x = 20; rowTop -= rowH + 20; rowH = 0 }
            if rowTop - size.height < 20 { pages.append([]); x = 20; rowTop = pageSize.height - 20; rowH = 0 }
            pages[pages.count - 1].append((kind, CGPoint(x: x, y: rowTop - size.height)))
            x += size.width + 20; rowH = max(rowH, size.height)
        }
        var windows: [NSWindow] = []
        for (index, page) in pages.enumerated() {
            let root = NSView(frame: NSRect(origin: .zero, size: pageSize))
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.12, blue: 0.16, alpha: 1).cgColor
            for (kind, origin) in page {
                let config = WidgetConfig(values: ["text": "call amma about sunday\nrenew passport", "command": "echo hello from a script; date",
                                                   "user": "torvalds", "url": "https://www.apple.com/newsroom/rss-feed.rss"])
                let content = kind.configured?(context, config) ?? kind.view?(context) ?? AnyView(EmptyView())
                let clear = kind.look == .clear
                let host = NSHostingView(rootView: ZStack {
                    if !clear {
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).fill(Color(red: 0.153, green: 0.168, blue: 0.2))
                        RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    content.padding(Metrics.padding).frame(width: kind.size.cg.width, height: kind.size.cg.height).clipped()
                }.environment(\.colorScheme, .dark))
                host.frame = NSRect(origin: origin, size: kind.size.cg)
                root.addSubview(host)
            }
            // Far off every screen, so it draws but is never on display.
            let w = NSWindow(contentRect: NSRect(x: -20_000 - CGFloat(index) * 2_000, y: -20_000, width: pageSize.width, height: pageSize.height),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = root
            w.orderFrontRegardless()
            windows.append(w)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (only == nil ? 6 : 20)) {
            for (i, w) in windows.enumerated() {
                guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/page-\(i + 1).png"))
            }
            NSApp.terminate(nil)
        }
    }
}

/// Self-check: renders the real gallery and two edit popups to PNGs from off-screen
/// windows (HYALINE_GALLERY_WINDOW=dir). Glass can't render off-screen, so plates are blank.
enum GallerySelfCheck {
    static func render(to dir: String, model: GalleryModel) {
        model.group = "Clock"
        let pages: [(String, AnyView, NSSize)] = [
            ("gallery-window", AnyView(GalleryView(model: model)), NSSize(width: 1240, height: 760)),
            ("popup-lock-wide", AnyView(StylePopover(kind: Registry.kind("lock-wide")!, model: model,
                                                     draft: model.binding(Registry.kind("lock-wide")!)) {}), NSSize(width: 560, height: 420)),
            ("popup-rss", AnyView(StylePopover(kind: Registry.kind("rss")!, model: model,
                                               draft: model.binding(Registry.kind("rss")!)) {}), NSSize(width: 560, height: 360)),
        ]
        var windows: [(String, NSWindow)] = []
        for (i, page) in pages.enumerated() {
            let host = NSHostingView(rootView: page.1.frame(width: page.2.width, height: page.2.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: page.2)
            let w = NSWindow(contentRect: NSRect(x: -30_000 - CGFloat(i) * 3_000, y: -30_000, width: page.2.width, height: page.2.height),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = host
            w.orderFrontRegardless()
            windows.append((page.0, w))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            for (name, w) in windows {
                guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
