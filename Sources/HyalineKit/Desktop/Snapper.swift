// Snapping to other widgets (ours and Apple's), gutters and screen edges.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Snapping

/// Snaps a dragged widget to the edges and 16pt gutters of nearby widgets (ours and
/// Apple's) and to the screen margins, and keeps it from overlapping any of them.
enum Snapper {
    static let gap = Metrics.gap          // gutter between widgets, as in Apple's layout
    static let threshold: CGFloat = 10    // how close an edge must be to pull the widget
    static let appleWindowInset: CGFloat = 8 // Apple's widget windows pad the plate by 8pt

    /// Apple's own desktop widgets, found by their window layer (one above ours).
    /// Bounds are readable without Screen Recording permission.
    static func appleWidgetFrames() -> [NSRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let appleLayer = WidgetPanel.desktopLevel.rawValue + 1
        let ourPID = Int(ProcessInfo.processInfo.processIdentifier)
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == appleLayer,
                  info[kCGWindowOwnerPID as String] as? Int != ourPID,
                  let dict = info[kCGWindowBounds as String] as? [String: Any],
                  let cg = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  cg.width > 2 * appleWindowInset, cg.height > 2 * appleWindowInset else { return nil }
            // CoreGraphics measures from the top of the primary screen; AppKit from the bottom.
            let rect = NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
            // macOS sometimes moves its widget windows partly off screen for a moment
            // (they were seen above the top edge). Those aren't where the widgets sit, so
            // reacting to them pushed our widgets sideways.
            guard NSScreen.screens.contains(where: { $0.frame.contains(rect) }) else { return nil }
            return rect.insetBy(dx: appleWindowInset, dy: appleWindowInset)
        }
    }

    // MARK: Snapping (only to things near the widget) and overlap nudging

    /// Obstacles close enough to matter for snapping: within 48pt of the widget.
    private static func nearby(_ r: NSRect, _ obstacles: [NSRect]) -> [NSRect] {
        obstacles.filter { $0.insetBy(dx: -48, dy: -48).intersects(r) }
    }

    private static func nearest(_ value: CGFloat, in candidates: [CGFloat]) -> CGFloat {
        guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
              abs(best - value) <= threshold else { return value }
        return best
    }

    /// Live snapping while dragging: pulls to the edges and 16pt gutters of widgets right
    /// next to this one, and to the screen margins. Widgets elsewhere on screen are ignored.
    static func snap(_ origin: NSPoint, size: NSSize, obstacles: [NSRect], screen: NSRect) -> NSPoint {
        let near = nearby(NSRect(origin: origin, size: size), obstacles)
        // Screen margins and the centre of the screen on both axes.
        var xs = [screen.minX + Metrics.screenMargin, screen.maxX - Metrics.screenMargin - size.width, screen.midX - size.width / 2]
        var ys = [screen.minY + Metrics.screenMargin, screen.maxY - Metrics.screenMargin - size.height, screen.midY - size.height / 2]
        for o in near {
            xs += [o.minX, o.maxX - size.width, o.maxX + gap, o.minX - gap - size.width]
            ys += [o.minY, o.maxY - size.height, o.maxY + gap, o.minY - gap - size.height]
        }
        return NSPoint(x: nearest(origin.x, in: xs), y: nearest(origin.y, in: ys))
    }

    private static func clamp(_ f: NSRect, _ screen: NSRect) -> NSRect {
        var r = f
        r.origin.x = min(max(r.minX, screen.minX), screen.maxX - r.width)
        r.origin.y = min(max(r.minY, screen.minY), screen.maxY - r.height)
        return r
    }

    /// On drop: if the widget overlaps something (or sits inside its `gap`), push it out by
    /// the smallest possible move, along one axis, repeating for chains. It never jumps
    /// elsewhere on screen; if it can't be freed it goes back to `fallback`.
    static func resolve(_ frame: NSRect, obstacles: [NSRect], screen: NSRect, gap: CGFloat, fallback: NSRect) -> NSRect {
        var f = clamp(frame, screen)
        func hit(_ r: NSRect) -> NSRect? {
            obstacles.first { r.intersects($0.insetBy(dx: -(gap - 0.5), dy: -(gap - 0.5))) }
        }
        for _ in 0..<12 {
            guard let o = hit(f) else { return f }
            let e = o.insetBy(dx: -gap, dy: -gap)
            let moves: [(CGFloat, CGFloat)] = [(e.minX - f.maxX, 0), (e.maxX - f.minX, 0), (0, e.minY - f.maxY), (0, e.maxY - f.minY)]
            let best = moves.min { abs($0.0) + abs($0.1) < abs($1.0) + abs($1.1) }!
            f = clamp(f.offsetBy(dx: best.0, dy: best.1), screen)
        }
        if hit(f) == nil { return f }
        // Boxed in: look outward for the nearest free spot (8pt steps), so a widget never
        // stays on top of another one.
        let start = clamp(frame, screen)
        var best: NSRect?, bestD = CGFloat.infinity
        for dx in stride(from: -640, through: 640, by: 8) {
            for dy in stride(from: -640, through: 640, by: 8) {
                let d = hypot(CGFloat(dx), CGFloat(dy))
                guard d < bestD else { continue }
                let c = start.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy))
                guard screen.contains(c), hit(c) == nil else { continue }
                best = c; bestD = d
            }
        }
        return best ?? fallback
    }
}
