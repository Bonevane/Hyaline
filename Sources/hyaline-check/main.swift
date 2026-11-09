// Checks for the parts of Hyaline that don't need a screen: snapping, saving and
// restoring layouts across resolution changes, the widget list, sizes, the mark and
// update version ordering.
// Run with `swift run hyaline-check`. Command Line Tools ship no XCTest, so this is a
// plain program that prints each result and exits non-zero on any failure.

import AppKit
@testable import HyalineKit

var failures = 0
func check(_ ok: Bool, _ name: String) {
    print(ok ? "  ok    \(name)" : "  FAIL  \(name)")
    if !ok { failures += 1 }
}
func section(_ name: String) { print(name) }

// MARK: Sizes

section("Sizes")
let slim = WSize.slim.cg.height, medium = Metrics.medium.height, large = Metrics.large.height
check(slim * 2 + Metrics.gap == medium, "two slims stack to a medium")
check(medium + Metrics.gap + slim * 2 + Metrics.gap == large, "a medium and two slims stack to a large")
check(Metrics.small.width * 2 + Metrics.gap == Metrics.medium.width, "two smalls side by side make a medium")

// MARK: Snapping

section("Snapping")
let screen = NSRect(x: 0, y: 0, width: 1512, height: 945)
let other = NSRect(x: 400, y: 400, width: 164, height: 164)
let size = NSSize(width: 164, height: 164)
let snapped = Snapper.snap(NSPoint(x: other.maxX + 12, y: other.minY + 4), size: size, obstacles: [other], screen: screen)
check(snapped.x == other.maxX + Snapper.gap, "pulls into a 16pt gutter beside another widget")
check(snapped.y == other.minY, "lines up with the other widget's edge")
let centred = Snapper.snap(NSPoint(x: screen.midX - 82 + 5, y: screen.midY - 82 - 4), size: size, obstacles: [], screen: screen)
check(centred == NSPoint(x: screen.midX - 82, y: screen.midY - 82), "snaps to the centre of the screen")
let free = Snapper.snap(NSPoint(x: 700, y: 700), size: size, obstacles: [], screen: screen)
check(free == NSPoint(x: 700, y: 700), "leaves a widget alone away from anything")
let overlapping = NSRect(x: other.minX + 40, y: other.minY + 20, width: 164, height: 164)
let settled = Snapper.resolve(overlapping, obstacles: [other], screen: screen, gap: Snapper.gap, fallback: overlapping)
check(!settled.insetBy(dx: 1, dy: 1).intersects(other), "moves an overlapping widget to a free spot")
check(screen.contains(settled), "keeps it on screen")

// MARK: Layout across resolutions

section("Layout across resolutions")
// Apple's extra-large widget, which macOS keeps centred when the resolution changes.
let s1 = NSRect(x: 0, y: 0, width: 2000, height: 1300), s2 = NSRect(x: 0, y: 0, width: 2400, height: 1560)
let apple1 = NSRect(x: 540, y: 145, width: 930, height: 453)
let apple2 = NSRect(x: (2400 - 930) / 2, y: 145, width: 930, height: 453)
let ours: [String: NSRect] = [
    "player": NSRect(x: 71, y: 383, width: 453, height: 215), "mood": NSRect(x: 71, y: 145, width: 453, height: 215),
    "power": NSRect(x: 1486, y: 271, width: 453, height: 215), "clock": NSRect(x: 818, y: 750, width: 364, height: 400),
]
let anchors = LayoutStore.appleAnchors(ours, apple: [apple1], in: s1)
check(anchors["player"] != nil && anchors["power"] != nil, "widgets touching Apple's widget follow it")
check(anchors["clock"] == nil, "a widget away from Apple's widgets doesn't")
var sameEverywhere = true, gapsKept = true
for (id, frame) in ours {
    var entry = LayoutStore.position(frame, in: s1); entry.apple = anchors[id]
    if LayoutStore.origin(for: entry, size: frame.size, in: s1, apple: [apple1]) != frame.origin { sameEverywhere = false }
    let moved = NSRect(origin: LayoutStore.origin(for: entry, size: frame.size, in: s2, apple: [apple2]), size: frame.size)
    switch id {
    case "player", "mood": if abs((apple2.minX - moved.maxX) - (apple1.minX - frame.maxX)) > 0.5 { gapsKept = false }
    case "power": if abs((moved.minX - apple2.maxX) - (frame.minX - apple1.maxX)) > 0.5 { gapsKept = false }
    default: check(abs(moved.midX - s2.midX) < 1, "a centred widget stays centred at a new resolution")
    }
}
check(sameEverywhere, "restores every widget exactly at the same resolution")
check(gapsKept, "keeps the gap to Apple's widget at a new resolution")

// MARK: Widget list

section("Widget list")
let ids = Registry.kinds.map(\.id)
check(Set(ids).count == ids.count, "every widget id is unique")
check(Registry.kinds.allSatisfy { $0.view != nil || $0.native != nil || $0.configured != nil }, "every widget has content")
check(Registry.kinds.allSatisfy { Registry.groups.contains($0.group) }, "every widget is in a listed group")
check(Registry.groups.allSatisfy { g in Registry.kinds.contains { $0.group == g } }, "no group is empty")
check(Registry.groups.allSatisfy { GallerySymbols.byGroup[$0] != nil }, "every group has a gallery symbol")
let lockWide = Registry.kind("lock-wide")!
check(WidgetDraft.initial(for: lockWide).values["showDate"] == "0", "new widgets start with their options at the defaults")
check(WidgetDraft.initial(for: Registry.kind("rss")!).values["url"]?.isEmpty == false, "configurable widgets start with something to show")

// MARK: Mark

section("Mark")
let box = CGRect(x: 10, y: 10, width: 100, height: 100)
let mark = HyalineMark.path(in: box)
check(!mark.isEmpty && box.insetBy(dx: -0.5, dy: -0.5).contains(mark.boundingBoxOfPath), "the mark fills its box and stays inside it")
check(HyalineMark.menuBarImage().isTemplate, "the menu-bar glyph is a template image")

// MARK: Updates

section("Updates")
check(Updater.isNewer("0.3.10", than: "0.3.9"), "0.3.10 is newer than 0.3.9")
check(Updater.isNewer("1.0", than: "0.9.9"), "1.0 is newer than 0.9.9")
check(!Updater.isNewer("0.2.0", than: "0.2"), "0.2.0 isn't newer than 0.2")
check(!Updater.isNewer("0.1.0", than: "0.2.0"), "an older release is never offered")

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
