// Owns the widget windows: creates them, saves and restores the layout, and follows
// screen, Space and power changes.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let sampler = SystemSampler()
    let extras = ExtraSampler()
    let appearance = Appearance()
    lazy var context = WidgetContext(sampler: sampler, extras: extras, appearance: appearance)

    /// Widgets on first launch (instance id, registry kind).
    static let defaults: [(String, String)] = [
        ("lock-wide", "lock-wide"), ("lock-column", "lock-column"), ("clock", "clock-stacked"),
        ("mood", "mood-phrase"), ("cpu", "cpu-arc"), ("memory", "mem-level"), ("battery", "bat-big"),
    ]
    /// Ids saved by earlier builds, before layouts recorded the kind.
    static let legacyKinds = ["clock": "clock-stacked", "mood": "mood-phrase", "cpu": "cpu-arc",
                                      "memory": "mem-level", "battery": "bat-big", "lock-wide": "lock-wide", "lock-column": "lock-column"]
    var panels: [WidgetPanel] = []
    var statusItem: NSStatusItem?
    // Variant 6 at 75% is the user-confirmed match, the same in every widget style.
    var surface = SurfaceSettings()
    let darknessSteps: [CGFloat] = stride(from: 0, through: 90, by: 5).map { CGFloat($0) / 100 }

    func applyAll() {
        panels.forEach { $0.apply(surface) }
    }
    var aboveWindows = false

    var styleItem: NSMenuItem?
    var developerItem: NSMenuItem?
    var loginItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LayoutStore.importPrototypeLayouts()
        layoutWidgets()
        #if DEBUG
        if runSelfCheckIfAsked() { return }
        #endif
        restoreLayout(animate: false)
        // Layouts from older builds lack the centre and Apple-widget anchors: record them
        // once, after Apple's widgets have appeared, from the layout as it stands now.
        if let screen = NSScreen.main, LayoutStore.load(for: screen).values.contains(where: { $0.v == nil }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.saveLayout() }
        }
        let anyVisible = { [weak self] in self?.panels.contains { $0.occlusionState.contains(.visible) } ?? false }
        sampler.isVisible = anyVisible
        extras.isVisible = anyVisible
        NowPlayingStore.shared.isVisible = anyVisible
        SensorStore.shared.isVisible = anyVisible
        sampler.start()
        extras.start()
        buildMenu()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screenChanged() }
        // New desktops and full-screen apps come and go; keep the widgets on every
        // normal desktop and out of full-screen spaces.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self.map { DesktopSpaces.sync($0.panels) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self.map { DesktopSpaces.sync($0.panels) } }
        MissionControl.onChange = { [weak self] showing in
            guard let self, !self.aboveWindows else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                // Roughly the length of Mission Control's own zoom animation.
                ctx.duration = showing ? 0.25 : 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panels.forEach { $0.animator().alphaValue = showing ? 0 : 1 }
            }
        }
        MissionControl.start()
    }

    /// Pending re-layouts after a screen change; a new change cancels the old ones.
    var pendingRestores: [DispatchWorkItem] = []
    var lastScreenFrame: NSRect = .zero

    func screenChanged() {
        let frame = NSScreen.main?.frame ?? .zero
        LayoutLog.write("screen change notified: \(frame) (was \(lastScreenFrame))")
        // macOS also posts this for things that don't move our widgets (Dock, menu bar);
        // only a new screen size or position needs a re-layout.
        guard frame != lastScreenFrame else { return }
        lastScreenFrame = frame
        pendingRestores.forEach { $0.cancel() }
        // macOS moves its own widgets a moment after the change and ours follow them,
        // so lay out once soon and once more after theirs have certainly settled.
        pendingRestores = [0.8, 2.5].map { delay in
            let work = DispatchWorkItem { [weak self] in self?.restoreLayout(animate: true) }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    /// Puts every widget back at its saved, edge-anchored position for the current
    /// screen with its saved snapping and look, keeps it on screen and clears overlaps.
    /// Doesn't save, so switching back to the old resolution restores the exact layout.
    func restoreLayout(animate: Bool) {
        guard let screen = NSScreen.main else { return }
        lastScreenFrame = screen.frame
        let saved = LayoutStore.load(for: screen)
        let bounds = screen.visibleFrame
        let apple = Snapper.appleWidgetFrames()
        // Work out every target first, against a fixed picture of Apple's widgets and of
        // ours already placed, then move each window once. Widgets that follow an Apple
        // widget go first, so free ones make room around them, never the reverse.
        let order = panels.sorted { a, b in
            let aa = saved[a.widgetID]?.apple != nil, ba = saved[b.widgetID]?.apple != nil
            return aa != ba ? aa : a.widgetID < b.widgetID
        }
        var placed: [NSRect] = []
        var moves: [(WidgetPanel, NSRect)] = []
        for panel in order {
            var origin = panel.frame.origin
            if let entry = saved[panel.widgetID] {
                panel.snaps = entry.snaps ?? true
                var changed = false
                if let raw = entry.look, let look = WidgetLook(rawValue: raw), look != panel.look { panel.look = look; changed = true }
                if entry.fontWeight != panel.fontWeight { panel.fontWeight = entry.fontWeight; changed = true }
                if changed { panel.apply(surface) }
                origin = LayoutStore.origin(for: entry, size: panel.frame.size, in: screen.frame, apple: apple)
            }
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - panel.frame.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - panel.frame.height)
            let wanted = NSRect(origin: origin, size: panel.frame.size)
            let target = Snapper.resolve(wanted, obstacles: apple + placed, screen: bounds,
                                         gap: panel.snaps ? Snapper.gap : 0, fallback: wanted)
            placed.append(target)
            moves.append((panel, target))
        }
        var moved = 0
        for (panel, target) in moves where abs(panel.frame.minX - target.minX) > 0.5 || abs(panel.frame.minY - target.minY) > 0.5 {
            panel.setFrame(target, display: true, animate: animate)
            moved += 1
        }
        LayoutLog.write("restore: screen \(screen.frame), \(apple.count) Apple widgets, moved \(moved) of \(panels.count)")
        if saved.isEmpty { saveLayout() }
    }

    func saveLayout() {
        guard let screen = NSScreen.main else { return }
        var entries: [String: LayoutStore.Entry] = [:]
        let frames = Dictionary(panels.map { ($0.widgetID, $0.frame) }, uniquingKeysWith: { a, _ in a })
        let anchors = LayoutStore.appleAnchors(frames, apple: Snapper.appleWidgetFrames(), in: screen.frame)
        for panel in panels {
            entries[panel.widgetID] = LayoutStore.entry(for: panel, in: screen.frame, apple: anchors[panel.widgetID])
        }
        LayoutStore.save(entries, for: screen)
    }

    /// Creates the saved widgets (or the defaults on first launch), stacked down the
    /// right of the screen; restoreLayout then moves each to its saved place.
    func layoutWidgets() {
        guard let screen = NSScreen.main else { return }
        let saved = LayoutStore.load(for: screen)
        let list: [(String, String)] = saved.isEmpty ? Self.defaults
            : saved.compactMap { id, e in (e.kind ?? Self.legacyKinds[id]).map { (id, $0) } }.sorted { $0.0 < $1.0 }
        let vf = screen.visibleFrame
        var x = vf.maxX - Metrics.screenMargin, y = vf.maxY - Metrics.screenMargin
        for (id, kindID) in list {
            guard let kind = Registry.kind(kindID) else { continue }
            let size = kind.size.cg
            if y - size.height < vf.minY { y = vf.maxY - Metrics.screenMargin; x -= 360 }
            makePanel(id: id, kind: kind, origin: CGPoint(x: x - size.width, y: y - size.height))
            y -= size.height + Metrics.gap
        }
    }

    @discardableResult
    func makePanel(id: String, kind: WidgetKind, origin: CGPoint, draft: WidgetDraft? = nil) -> WidgetPanel {
        // Settings must be in place before the content is built, so read them first.
        let saved = draft?.values ?? NSScreen.main.map { LayoutStore.load(for: $0)[id]?.values ?? [:] } ?? [:]
        let config = WidgetConfig(values: saved)
        var content = kind.configured?(context, config) ?? kind.view?(context) ?? AnyView(EmptyView())
        let opener = WidgetOpener.action(for: kind, config: config)
        // A tap on the content opens the source app; buttons inside the widget win over it.
        if let opener { content = AnyView(content.contentShape(Rectangle()).onTapGesture(perform: opener)) }
        let panel = WidgetPanel(origin: origin, size: kind.size.cg, content: content, config: config)
        panel.onClick = opener
        panel.widgetID = id
        panel.kind = kind.id
        panel.look = draft?.look ?? kind.look
        panel.fontWeight = draft?.fontWeight
        if let native = kind.native { panel.nativeContent = { [weak panel] in panel.map(native) ?? NSView() } }
        panel.apply(surface)
        panel.obstacles = { [weak self, weak panel] in
            let ours = self?.panels.filter { $0 !== panel }.map(\.frame) ?? []
            return ours + Snapper.appleWidgetFrames()
        }
        panel.onLayoutChange = { [weak self] in self?.saveLayout() }
        panel.onRemove = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
            self.saveLayout()
        }
        panel.orderFrontRegardless()
        panels.append(panel)
        DispatchQueue.main.async { [weak panel] in panel.map { DesktopSpaces.sync([$0]) } }
        return panel
    }

    /// Adds a widget near the middle of the screen, moved to the nearest free spot.
    /// Adds a widget from the gallery: at `origin` (a drag), or near the middle of the screen.
    func addFromGallery(_ kind: WidgetKind, _ draft: WidgetDraft, _ origin: CGPoint?) -> WidgetPanel {
        let id = "\(kind.id)-\(UUID().uuidString.prefix(6))"
        let size = kind.size.cg
        let vf = NSScreen.main?.visibleFrame ?? .zero
        let start = origin ?? CGPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
        let panel = makePanel(id: id, kind: kind, origin: start, draft: draft)
        if origin == nil {
            // The gallery sits in front of the desktop, so a widget under it would be
            // invisible: treat the window as taken space and fade the widget in.
            let galleryFrame = gallery.visibleFrame
            panel.settle(fallback: panel.frame, animate: false, obstacles: panel.obstacles() + [galleryFrame].compactMap { $0 })
            panel.alphaValue = 0
            if let galleryFrame, panel.frame.intersects(galleryFrame) {
                // No room beside the gallery: show it above the gallery for a moment, then
                // let it settle back onto the desktop.
                panel.settle(fallback: panel.frame, animate: false, obstacles: panel.obstacles())
                panel.level = .floating
                NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak panel] in
                    guard let panel else { return }
                    NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 }) {
                        panel.level = WidgetPanel.desktopLevel
                        panel.alphaValue = 1
                    }
                }
            } else {
                NSAnimationContext.runAnimationGroup { $0.duration = 0.35; panel.animator().alphaValue = 1 }
            }
            saveLayout()
        }
        return panel
    }

    lazy var gallery = GalleryWindow(model: GalleryModel(
        context: context, surface: { [unowned self] in self.surface },
        add: { [unowned self] in self.addFromGallery($0, $1, $2) }))

    @objc func showGallery() { gallery.show() }

    @objc func resetLayout() {
        guard let screen = NSScreen.main else { return }
        LayoutStore.clear(for: screen)
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        layoutWidgets()
        restoreLayout(animate: false)
    }

    @objc func toggleAbove(_ sender: NSMenuItem) {
        aboveWindows.toggle()
        sender.state = aboveWindows ? .on : .off
        panels.forEach { $0.level = aboveWindows ? .floating : WidgetPanel.desktopLevel }
    }
}
