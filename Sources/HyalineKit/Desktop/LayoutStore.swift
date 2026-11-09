// Saving and restoring where every widget is, across resolution changes.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

enum LayoutLog {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Hyaline/layout.log")
    static func write(_ line: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        let text = "\(Date().formatted(.iso8601)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }
}

enum LayoutStore {
    /// Copies layouts saved by the prototype (bundle id dev.hyaline.preview) once, so
    /// widgets stay where they were after the move to the real app.
    static func importPrototypeLayouts() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "importedPrototypeLayouts") else { return }
        defaults.set(true, forKey: "importedPrototypeLayouts")
        guard let old = UserDefaults(suiteName: "dev.hyaline.preview") else { return }
        for (key, value) in old.dictionaryRepresentation() where key.hasPrefix("layout.") && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }

    struct Entry: Codable {
        var fromRight: Bool, dx: CGFloat
        var fromTop: Bool, dy: CGFloat
        var snaps: Bool?   // optional so layouts saved by older builds still load
        var look: String?
        var kind: String?
        var fontWeight: Double?
        var values: [String: String]?
        /// Centre as a fraction of the screen, per axis, for widgets away from the edges
        /// (so a centred clock stays centred). nil = keep the distance from the edge.
        var fx: CGFloat?
        var fy: CGFloat?
        /// Set when the widget is part of a group touching one of Apple's widgets: it then
        /// follows that widget, which macOS moves on its own when the resolution changes.
        var apple: AppleAnchor?
        /// 2 = saved with the anchors above; older layouts are re-saved once on launch.
        var v: Int?
    }

    struct AppleAnchor: Codable {
        var w: CGFloat, h: CGFloat     // which Apple widget (by size)
        var fx: CGFloat, fy: CGFloat   // where it was, as a fraction of the screen (to tell same-sized ones apart)
        var ox: CGFloat, oy: CGFloat   // our origin minus its origin
    }

    /// Our widgets that touch an Apple widget, directly or through a chain of our own
    /// widgets 16pt apart, each tied to the Apple widget nearest along that chain.
    static func appleAnchors(_ frames: [String: NSRect], apple: [NSRect], in screen: NSRect) -> [String: AppleAnchor] {
        func touching(_ a: NSRect, _ b: NSRect) -> Bool { a.insetBy(dx: -(Metrics.gap + 3), dy: -(Metrics.gap + 3)).intersects(b) }
        var owner: [String: NSRect] = [:]
        var queue: [(String, NSRect)] = []
        for a in apple {
            for (id, f) in frames where owner[id] == nil && touching(f, a) { owner[id] = a; queue.append((id, a)) }
        }
        var i = 0
        while i < queue.count {
            let (id, a) = queue[i]; i += 1
            for (other, f) in frames where owner[other] == nil && touching(f, frames[id]!) { owner[other] = a; queue.append((other, a)) }
        }
        return owner.mapValues { a in
            AppleAnchor(w: a.width, h: a.height, fx: (a.midX - screen.minX) / screen.width, fy: (a.midY - screen.minY) / screen.height,
                        ox: 0, oy: 0)
        }.reduce(into: [:]) { out, pair in
            var anchor = pair.value
            let a = owner[pair.key]!, f = frames[pair.key]!
            anchor.ox = f.minX - a.minX; anchor.oy = f.minY - a.minY
            out[pair.key] = anchor
        }
    }

    /// The Apple widget an anchor refers to, on the current screen: same size, nearest
    /// to where it was proportionally.
    static func match(_ anchor: AppleAnchor, in apple: [NSRect], screen: NSRect) -> NSRect? {
        let expected = CGPoint(x: screen.minX + anchor.fx * screen.width, y: screen.minY + anchor.fy * screen.height)
        return apple.filter { abs($0.width - anchor.w) < 3 && abs($0.height - anchor.h) < 3 }
            .min { hypot($0.midX - expected.x, $0.midY - expected.y) < hypot($1.midX - expected.x, $1.midY - expected.y) }
    }

    static func key(for screen: NSScreen) -> String {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let text = CFUUIDCreateString(nil, uuid) {
            return "layout.\(text)"
        }
        return "layout.\(id)"
    }

    static func entry(for panel: WidgetPanel, in screen: NSRect, apple: AppleAnchor? = nil) -> Entry {
        var e = position(panel.frame, in: screen)
        e.snaps = panel.snaps; e.look = panel.look.rawValue; e.kind = panel.kind; e.fontWeight = panel.fontWeight
        e.values = panel.config.values.isEmpty ? nil : panel.config.values
        e.apple = apple
        e.v = 2
        return e
    }

    /// Where a frame sits: distance from the nearest edges, plus the proportional centre
    /// on any axis where it's well away from both edges (over 20% of the screen).
    static func position(_ frame: NSRect, in screen: NSRect) -> Entry {
        let fromRight = frame.midX > screen.midX, fromTop = frame.midY > screen.midY
        let edgeX = min(frame.minX - screen.minX, screen.maxX - frame.maxX)
        let edgeY = min(frame.minY - screen.minY, screen.maxY - frame.maxY)
        return Entry(fromRight: fromRight, dx: fromRight ? screen.maxX - frame.maxX : frame.minX - screen.minX,
                     fromTop: fromTop, dy: fromTop ? screen.maxY - frame.maxY : frame.minY - screen.minY,
                     fx: edgeX > screen.width * 0.2 ? (frame.midX - screen.minX) / screen.width : nil,
                     fy: edgeY > screen.height * 0.2 ? (frame.midY - screen.minY) / screen.height : nil)
    }

    static func origin(for e: Entry, size: NSSize, in screen: NSRect, apple: [NSRect] = []) -> NSPoint {
        if let anchor = e.apple, let a = match(anchor, in: apple, screen: screen) {
            return NSPoint(x: a.minX + anchor.ox, y: a.minY + anchor.oy)
        }
        var p = NSPoint(x: e.fromRight ? screen.maxX - e.dx - size.width : screen.minX + e.dx,
                        y: e.fromTop ? screen.maxY - e.dy - size.height : screen.minY + e.dy)
        if let fx = e.fx { p.x = screen.minX + fx * screen.width - size.width / 2 }
        if let fy = e.fy { p.y = screen.minY + fy * screen.height - size.height / 2 }
        return p
    }

    static func load(for screen: NSScreen) -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(for: screen)),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }

    static func save(_ entries: [String: Entry], for screen: NSScreen) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key(for: screen))
        }
    }

    static func clear(for screen: NSScreen) {
        UserDefaults.standard.removeObject(forKey: key(for: screen))
    }
}
