// Showcase: preset widget layouts over generated wallpapers, for screenshots to share.
// Real widgets on the real desktop, so the glass is real; the wallpaper is a window
// just above the desktop picture, so your own wallpaper setting is never touched.
// Calendar and reminders show sample data while it runs; Now Playing shows what's
// really playing. Your widgets are
// hidden meanwhile and come back as they were; nothing is saved.

import AppKit
import SwiftUI

struct ShowcaseLayout {
    enum Anchor { case left, right, center }
    /// Widgets placed on Apple's 180pt grid: column, and row in steps of half a row.
    struct Group { let anchor: Anchor; let items: [(id: String, col: CGFloat, row: CGFloat)] }
    let name: String
    /// The wallpaper it was designed around.
    let wallpaper: String
    let groups: [Group]

    static let all: [ShowcaseLayout] = [
        // Made for photos in the Showcase folder: widgets go where the picture is quiet.
        ShowcaseLayout(name: "Blossom", wallpaper: "Blossom", groups: [
            Group(anchor: .left, items: [("lock-wide", 0, 0), ("cal-week", 2, 0), ("wx-curve", 2, 1),
                                         ("np-bar", 0, 2), ("wx-strip", 0, 3), ("cal-next-slim", 0, 3.5)]),
        ]),
        ShowcaseLayout(name: "Event Horizon", wallpaper: "Event Horizon", groups: [
            Group(anchor: .left, items: [("sys-all", 0, 0), ("cpu-cores", 2, 0), ("temp-list", 0, 2),
                                         ("temp-slim", 0, 3), ("en-slim", 0, 3.5)]),
            Group(anchor: .right, items: [("lock-column", 0, 0)]),
        ]),
        ShowcaseLayout(name: "Lake", wallpaper: "Lake", groups: [
            Group(anchor: .left, items: [("lock-wide", 0, 0)]),
            Group(anchor: .right, items: [("wx-curve", 0, 0), ("sun-arc", 0, 1), ("cal-next", 0, 2), ("wx-big", 1, 2)]),
        ]),
        ShowcaseLayout(name: "Morning", wallpaper: "Dusk", groups: [
            Group(anchor: .left, items: [("lock-wide", 0, 0), ("wx-curve", 0, 2), ("cal-next-slim", 0, 3), ("np-strip", 0, 3.5)]),
            Group(anchor: .right, items: [("cal-agenda", 0, 0), ("rem-list", 0, 2), ("wx-big", 0, 3), ("sun-arc", 1, 3)]),
        ]),
        ShowcaseLayout(name: "Calm", wallpaper: "Bloom", groups: [
            Group(anchor: .center, items: [("lock-wide", 0, 0), ("mood-serif", 0, 2)]),
        ]),
        ShowcaseLayout(name: "System", wallpaper: "Graphite", groups: [
            Group(anchor: .left, items: [("lock-column", 0, 0), ("clock-minimal", 0, 2), ("wx-big", 0, 3)]),
            Group(anchor: .right, items: [("sys-all", 0, 0), ("cpu-cores", 2, 0), ("mem-level", 3, 0), ("temp-gauge", 3, 1),
                                         ("temp-list", 0, 2), ("en-list", 2, 2), ("temp-slim", 0, 3), ("en-slim", 0, 3.5),
                                         ("cpu-strip", 2, 3), ("mem-strip", 2, 3.5)]),
        ]),
        ShowcaseLayout(name: "Music", wallpaper: "Sunset", groups: [
            Group(anchor: .left, items: [("mood-poster", 0, 0), ("np-bar", 0, 2), ("np-vinyl", 0, 3), ("np-art", 1, 3)]),
            Group(anchor: .right, items: [("clock-dayarc", 0, 0), ("wx-curve", 0, 1), ("cal-week", 0, 2), ("np-strip", 0, 3), ("clock-strip", 0, 3.5)]),
        ]),
        ShowcaseLayout(name: "Everything", wallpaper: "Aurora", groups: [
            Group(anchor: .center, items: [
                ("lock-wide", 0, 0), ("wx-curve", 0, 2), ("cal-week-slim", 0, 3), ("np-strip", 0, 3.5),
                ("cal-agenda", 2, 0), ("np-bar", 2, 2), ("cpu-arc", 2, 3), ("mem-level", 3, 3),
                ("clock-flip", 4, 0), ("clock-minimal", 5, 0), ("clock-world", 4, 1), ("sys-all", 4, 2),
                ("bat-devices", 6, 0), ("disk-column", 7, 0), ("temp-list", 6, 2), ("en-list", 6, 3),
            ]),
        ]),
    ]

    /// Where each widget goes on a screen's visible area.
    func frames(in visible: NSRect) -> [(WidgetKind, NSRect)] {
        let cell = Metrics.small.width + Metrics.gap, margin: CGFloat = 40
        let placed = groups.map { group -> (Group, [(WidgetKind, NSRect)], NSSize) in
            let items = group.items.compactMap { item -> (WidgetKind, NSRect)? in
                guard let kind = Registry.kind(item.id) else { return nil }
                return (kind, NSRect(origin: CGPoint(x: item.col * cell, y: item.row * cell), size: kind.size.cg))
            }
            let w = items.map { $0.1.maxX }.max() ?? 0, h = items.map { $0.1.maxY }.max() ?? 0
            return (group, items, NSSize(width: w, height: h))
        }
        let tallest = placed.map(\.2.height).max() ?? 0
        let top = visible.midY + tallest / 2
        return placed.flatMap { group, items, size -> [(WidgetKind, NSRect)] in
            let left: CGFloat
            switch group.anchor {
            case .left: left = visible.minX + margin
            case .right: left = visible.maxX - margin - size.width
            case .center: left = visible.midX - size.width / 2
            }
            // Group rows run down from the top; screen coordinates run up.
            return items.map { kind, r in
                (kind, NSRect(x: left + r.minX, y: top - r.minY - r.height, width: r.width, height: r.height))
            }
        }
    }
}

struct ShowcaseWallpaper {
    let name: String
    var colors: [Color] = []   // 3 × 3 mesh, top row first
    var image: NSImage? = nil

    /// Pictures dropped here show up as wallpapers too. Kept out of the repo.
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Hyaline/Showcase")

    static var all: [ShowcaseWallpaper] { pictures + generated }

    static var pictures: [ShowcaseWallpaper] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["png", "jpg", "jpeg", "heic", "tiff"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in NSImage(contentsOf: url).map { ShowcaseWallpaper(name: url.deletingPathExtension().lastPathComponent, image: $0) } }
    }

    static func named(_ name: String) -> Int? { all.firstIndex { $0.name == name } }

    static let generated: [ShowcaseWallpaper] = [
        ShowcaseWallpaper(name: "Dusk", colors: [
            rgb(0x1B1440), rgb(0x3A1F6B), rgb(0x24184F),
            rgb(0x6A2E7F), rgb(0xD9628A), rgb(0x4A2373),
            rgb(0xF29E6D), rgb(0xF6C38B), rgb(0xB84E7C)]),
        ShowcaseWallpaper(name: "Aurora", colors: [
            rgb(0x061A24), rgb(0x0B3B3F), rgb(0x0A1F33),
            rgb(0x0F6B5C), rgb(0x2FD3A0), rgb(0x3B2B7A),
            rgb(0x071C2A), rgb(0x1C5D6E), rgb(0x6C3FB0)]),
        ShowcaseWallpaper(name: "Ocean", colors: [
            rgb(0x041A3A), rgb(0x0A3D7A), rgb(0x062552),
            rgb(0x0F5FA8), rgb(0x3FB7E0), rgb(0x0B4C8C),
            rgb(0x0A2F66), rgb(0x8FE3F2), rgb(0x1D7BC2)]),
        ShowcaseWallpaper(name: "Sunset", colors: [
            rgb(0xF7B267), rgb(0xF79D65), rgb(0xF4845F),
            rgb(0xF27059), rgb(0xD8576B), rgb(0xA53F7A),
            rgb(0x6B2D7B), rgb(0x45266E), rgb(0x2A1D5C)]),
        ShowcaseWallpaper(name: "Graphite", colors: [
            rgb(0x2B2F36), rgb(0x1E2126), rgb(0x30353D),
            rgb(0x1A1C20), rgb(0x47546A), rgb(0x22262C),
            rgb(0x3A4250), rgb(0x16181B), rgb(0x2E3440)]),
        ShowcaseWallpaper(name: "Bloom", colors: [
            rgb(0xF6D5E5), rgb(0xE7C6F2), rgb(0xC9D7F8),
            rgb(0xF2A7C3), rgb(0xD7B4F0), rgb(0x9FB8F2),
            rgb(0xF7C59F), rgb(0xE79BB8), rgb(0x8CA7E8)]),
    ]

    private static func rgb(_ hex: Int) -> Color {
        Color(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct ShowcaseWallpaperView: View {
    let wallpaper: ShowcaseWallpaper
    var body: some View {
        if let image = wallpaper.image {
            Color.black.overlay(Image(nsImage: image).resizable().scaledToFill()).clipped()
        } else {
            mesh
        }
    }
    private var mesh: some View {
        // Slightly uneven points, so the blend reads as light rather than a grid.
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.55, 0], [1, 0],
            [0, 0.45], [0.42, 0.58], [1, 0.4],
            [0, 1], [0.6, 1], [1, 1],
        ], colors: wallpaper.colors, smoothsColors: true)
    }
}

/// The running showcase: its wallpaper window and widgets.
final class Showcase {
    var layout = 0
    var wallpaper = 0
    let wallpapers = ShowcaseWallpaper.all
    private var backdrop: NSWindow?
    private(set) var panels: [WidgetPanel] = []

    func showWallpaper(on screen: NSScreen) {
        let view = NSHostingView(rootView: ShowcaseWallpaperView(wallpaper: wallpapers[min(wallpaper, wallpapers.count - 1)]).ignoresSafeArea())
        if backdrop == nil {
            let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            // Above the desktop picture, below the desktop icons and every widget.
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.hasShadow = false
            backdrop = w
        }
        backdrop?.setFrame(screen.frame, display: false)
        backdrop?.contentView = view
        backdrop?.orderFrontRegardless()
    }

    func replacePanels(_ new: [WidgetPanel]) {
        panels.forEach { $0.orderOut(nil) }
        panels = new
    }

    func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        backdrop?.orderOut(nil)
        backdrop = nil
    }
}

extension AppDelegate {
    func showcaseMenu() -> NSMenu {
        let menu = NSMenu()
        for (i, layout) in ShowcaseLayout.all.enumerated() {
            let e = menu.addItem(withTitle: layout.name, action: #selector(pickShowcaseLayout(_:)), keyEquivalent: "")
            e.target = self; e.tag = i
        }
        menu.addItem(.separator())
        for (i, wallpaper) in ShowcaseWallpaper.all.enumerated() {
            if i == ShowcaseWallpaper.pictures.count, i > 0 { menu.addItem(.separator()) }
            let e = menu.addItem(withTitle: "\(wallpaper.name) wallpaper", action: #selector(pickShowcaseWallpaper(_:)), keyEquivalent: "")
            e.target = self; e.tag = i
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "End Showcase", action: #selector(endShowcase), keyEquivalent: "").target = self
        return menu
    }

    /// Ticks the current layout and wallpaper (called as the menu opens).
    func refreshShowcaseMenu(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(pickShowcaseLayout(_:)) { item.state = showcase?.layout == item.tag ? .on : .off }
            if item.action == #selector(pickShowcaseWallpaper(_:)) { item.state = showcase?.wallpaper == item.tag ? .on : .off }
            if item.action == #selector(endShowcase) { item.isEnabled = showcase != nil }
        }
    }

    /// A layout comes with the wallpaper it was made for; pick another wallpaper after.
    @objc func pickShowcaseLayout(_ sender: NSMenuItem) {
        let layout = ShowcaseLayout.all[sender.tag]
        startShowcase(layout: sender.tag, wallpaper: ShowcaseWallpaper.named(layout.wallpaper) ?? showcase?.wallpaper ?? 0)
    }

    @objc func pickShowcaseWallpaper(_ sender: NSMenuItem) {
        startShowcase(layout: showcase?.layout ?? 0, wallpaper: sender.tag)
    }

    func startShowcase(layout: Int, wallpaper: Int) {
        guard let screen = NSScreen.main else { return }
        let first = showcase == nil
        let show = showcase ?? Showcase()
        showcase = show
        if first {
            // Hide your widgets (they come back on End Showcase) and swap in sample events.
            panels.forEach { $0.orderOut(nil) }
            SampleData.on = true
            CalendarStore.shared.useSample(true)
        }
        show.wallpaper = wallpaper
        show.showWallpaper(on: screen)
        if first || show.layout != layout || show.panels.isEmpty {
            show.layout = layout
            let mine = panels
            let new = ShowcaseLayout.all[layout].frames(in: screen.visibleFrame).enumerated().map { i, item in
                let panel = makePanel(id: "showcase-\(i)", kind: item.0, origin: item.1.origin)
                panel.snaps = false
                return panel
            }
            panels = mine   // showcase widgets aren't yours: kept apart and never saved
            show.replacePanels(new)
        }
    }

    @objc func endShowcase() {
        guard let show = showcase else { return }
        show.close()
        showcase = nil
        SampleData.on = false
        CalendarStore.shared.useSample(false)
        panels.forEach { $0.orderFrontRegardless() }
    }
}
