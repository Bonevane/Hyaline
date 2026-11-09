// The desktop window each widget lives in: glass surface, dragging, right-click menu.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Desktop window

/// Per-widget surface, picked from the widget's right-click menu.
enum WidgetLook: String, CaseIterable {
    case glass = "Glass"     // Apple-matched dark glass (variant 6 + 75% shade)
    case frosted = "Frosted" // the same glass without the shade: lighter
    case clear = "Clear"     // no background; content only (for the clock)
}

/// Glass settings shared by all widgets, from the menu bar menu.
struct SurfaceSettings {
    var variant = 6
    var darkness: CGFloat = 0.75
    var extraBlur = false
    var border = true
}

/// Views that take mouse drags themselves, so the panel doesn't move the widget.
protocol HandlesOwnDrag: AnyObject {}

final class WidgetPanel: NSPanel {
    private let content: AnyView
    private let size: CGSize

    init(origin: CGPoint, size: CGSize, content: AnyView, config: WidgetConfig = WidgetConfig()) {
        self.content = content
        self.config = config
        self.size = size
        super.init(contentRect: NSRect(origin: origin, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false // dragging is handled in sendEvent, with snapping
        // .transient: hidden in Mission Control, like Apple's widgets (.stationary kept
        // them on screen there).
        // Not "join all spaces": DesktopSpaces puts the widgets on every normal desktop
        // but not in full-screen apps. .stationary keeps them in place when you click the
        // wallpaper to reveal the desktop; DesktopSpaces adds the Mission Control fade.
        // Sticky (join all spaces) like Apple's widget windows, so the window server keeps
        // drawing them while desktops slide; DesktopSpaces then takes them back out of
        // full-screen app spaces, which is the exact state Apple's widgets are in.
        // Sticky (drawn while desktops slide) and stationary (left in place when you click
        // the wallpaper). DesktopSpaces keeps them out of full-screen apps, and
        // MissionControl hides them while Mission Control is open.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        level = WidgetPanel.desktopLevel
    }

    // MARK: Dragging with snapping

    /// Stable name used to save this widget's position.
    var widgetID = ""
    /// Per widget. On: pulls to nearby widget edges, 16pt gutters and screen margins.
    /// Off: glides freely under the cursor with no snapping.
    var snaps = true
    /// Per widget surface: Apple-matched glass, lighter frosted glass, or no background.
    var look: WidgetLook = .glass
    private var lastSurface = SurfaceSettings()
    /// For widgets drawn in AppKit rather than SwiftUI (the glass-numeral clocks).
    var nativeContent: (() -> NSView)?
    /// Registry id of what this panel shows.
    var kind = ""
    /// Per-widget font weight for the glass clocks (nil = the default, 180).
    var fontWeight: Double?
    /// Per-widget settings (note text, script command, …), saved with the layout.
    let config: WidgetConfig
    var onRemove: () -> Void = {}
    /// Frames this widget must align with and never overlap: our other widgets and Apple's.
    var obstacles: () -> [NSRect] = { [] }
    /// Called after the user moves the widget or changes its snapping, to save the layout.
    var onLayoutChange: () -> Void = {}
    private var dragMouseStart: NSPoint = .zero
    private var dragOriginStart: NSPoint = .zero
    private var dragObstacles: [NSRect] = []
    private var dragging = false

    /// A saved on/off option for this widget.
    func isOn(_ key: String, default fallback: Bool) -> Bool {
        config.values[key].map { $0 == "1" } ?? fallback
    }

    @objc private func flipToggle(_ sender: NSMenuItem) {
        guard let toggle = Registry.kind(kind)?.toggles[sender.tag] else { return }
        config.set(toggle.key, isOn(toggle.key, default: toggle.defaultOn) ? "0" : "1")
        apply(lastSurface)   // rebuilds the content with the new option
        onLayoutChange()     // saves it with the layout
    }

    /// Click without a drag on AppKit content (the glass clocks); SwiftUI content taps itself.
    var onClick: (() -> Void)?
    /// True while a press that began on a `HandlesOwnDrag` view (a seek bar) is held.
    private var passThrough = false

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let root = contentView {
            passThrough = root.hitTest(root.convert(event.locationInWindow, from: nil)) is HandlesOwnDrag
        }
        if passThrough, [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) {
            if event.type == .leftMouseUp { passThrough = false }
            super.sendEvent(event); return
        }
        switch event.type {
        case .leftMouseDown:
            dragMouseStart = NSEvent.mouseLocation
            dragOriginStart = frame.origin
            dragObstacles = obstacles()
            dragging = false
        case .leftMouseDragged:
            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - dragMouseStart.x, dy = mouse.y - dragMouseStart.y
            if !dragging && hypot(dx, dy) < 3 { break }
            dragging = true
            let raw = NSPoint(x: dragOriginStart.x + dx, y: dragOriginStart.y + dy)
            setFrameOrigin(snappedOrigin(raw, screen: currentScreen()))
            return
        case .leftMouseUp where !dragging && nativeContent != nil:
            onClick?()
        case .leftMouseUp where dragging:
            dragging = false
            settle(fallback: NSRect(origin: dragOriginStart, size: frame.size), animate: true)
            onLayoutChange()
            return
        case .rightMouseDown:
            showContextMenu(event)
            return
        default:
            break
        }
        super.sendEvent(event)
    }

    private func snappedOrigin(_ raw: NSPoint, screen: NSScreen?) -> NSPoint {
        guard snaps, let screen else { return raw }
        return Snapper.snap(raw, size: frame.size, obstacles: dragObstacles, screen: screen.visibleFrame)
    }

    /// If the widget overlaps another (ours or Apple's), moves it to the nearest free spot,
    /// else back to `fallback`. Applies with snapping on or off.
    func settle(fallback: NSRect, animate: Bool, obstacles fresh: [NSRect]? = nil) {
        guard let screen = currentScreen() else { return }
        let target = Snapper.resolve(frame, obstacles: fresh ?? dragObstacles, screen: screen.visibleFrame,
                                     gap: snaps ? Snapper.gap : 0, fallback: fallback)
        if target != frame { setFrame(target, display: true, animate: animate) }
    }

    private func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let snapping = menu.addItem(withTitle: "Snapping", action: #selector(toggleSnapping), keyEquivalent: "")
        snapping.target = self
        snapping.state = snaps ? .on : .off
        menu.addItem(.separator())
        let header = menu.addItem(withTitle: "Look", action: nil, keyEquivalent: "")
        header.isEnabled = false
        for option in WidgetLook.allCases {
            let entry = menu.addItem(withTitle: option.rawValue, action: #selector(pickLook(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = option.rawValue
            entry.state = option == look ? .on : .off
            entry.indentationLevel = 1
        }
        if let settings = Registry.kind(kind)?.settings, !settings.isEmpty {
            menu.addItem(.separator())
            for (i, setting) in settings.enumerated() {
                let e = menu.addItem(withTitle: setting.title, action: #selector(editSetting(_:)), keyEquivalent: "")
                e.target = self; e.tag = i
            }
        }
        if let toggles = Registry.kind(kind)?.toggles, !toggles.isEmpty {
            menu.addItem(.separator())
            for (i, toggle) in toggles.enumerated() {
                let e = menu.addItem(withTitle: toggle.title, action: #selector(flipToggle(_:)), keyEquivalent: "")
                e.target = self; e.tag = i
                e.state = isOn(toggle.key, default: toggle.defaultOn) ? .on : .off
            }
        }
        if Registry.kind(kind)?.hasFontWeight == true {
            menu.addItem(.separator())
            let weights = NSMenu()
            for w in [60, 120, 180, 250, 320, 400, 500] {
                let isDefault = Double(w) == GlassClockView.weight
                let e = weights.addItem(withTitle: isDefault ? "\(w) (default)" : "\(w)", action: #selector(pickWeight(_:)), keyEquivalent: "")
                e.target = self; e.tag = w
                e.state = Double(w) == (fontWeight ?? GlassClockView.weight) ? .on : .off
            }
            menu.setSubmenu(weights, for: menu.addItem(withTitle: "Font weight", action: nil, keyEquivalent: ""))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Remove widget", action: #selector(removeSelf), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? NSView())
    }

    @objc private func pickWeight(_ sender: NSMenuItem) {
        fontWeight = Double(sender.tag) == GlassClockView.weight ? nil : Double(sender.tag)
        apply(lastSurface)
        onLayoutChange()
    }

    @objc private func removeSelf() { onRemove() }

    /// Asks for a setting's value in a small dialog, then saves it with the layout.
    @objc private func editSetting(_ sender: NSMenuItem) {
        guard let setting = Registry.kind(kind)?.settings[sender.tag] else { return }
        let alert = NSAlert()
        alert.messageText = setting.prompt
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let current = config.values[setting.key] ?? ""
        let input: NSView
        if setting.multiline {
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
            let text = NSTextView(frame: scroll.bounds)
            text.string = current
            text.isRichText = false
            text.font = .systemFont(ofSize: 13)
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            input = scroll
        } else {
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.stringValue = current
            input = field
        }
        alert.accessoryView = input
        NSApp.activate()
        alert.window.initialFirstResponder = (input as? NSScrollView)?.documentView ?? input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = ((input as? NSScrollView)?.documentView as? NSTextView)?.string ?? (input as? NSTextField)?.stringValue ?? ""
        config.set(setting.key, value.trimmingCharacters(in: setting.multiline ? .whitespaces : .whitespacesAndNewlines))
        onLayoutChange()
    }

    @objc private func toggleSnapping() {
        snaps.toggle()
        onLayoutChange()
    }

    @objc private func pickLook(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let next = WidgetLook(rawValue: raw) else { return }
        look = next
        apply(lastSurface)
        onLayoutChange()
    }

    func currentScreen() -> NSScreen? {
        if dragging {
            let mouse = NSEvent.mouseLocation
            if let s = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) { return s }
        }
        return screen ?? NSScreen.main
    }

    // Just above the desktop icons, where Apple's own widgets sit.
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // The public glass API only gives the frosted variant. NSGlassEffectView has a
    // private `_variant` (0–20 on macOS 26.6); some variants draw the real rim and
    // edge lensing. Private API: fine for a direct-download build, may break on updates.
    // Lab result: variant 9 + a dark tint gives a dark plate that keeps the thin
    // glass rim, closest to Apple's desktop widgets. Scrim states drop the rim, and
    // the clear variants (11, 14, 19) ignore tint.
    // tintColor on variant 6 is all-or-nothing, so darkness comes from a black layer
    // inside the glass instead (lab: darkens smoothly and keeps the rim). Extra blur
    // puts a behind-window blur under the glass, so the glass refracts an already
    // blurred backdrop.
    func apply(_ surface: SurfaceSettings) {
        lastSurface = surface
        contentView = WidgetPanel.surfaceView(look: look, surface: surface, size: size, content: content, native: nativeContent)
    }

    /// The widget's plate and content as a view: what a panel shows, and what the gallery
    /// previews show, so the two always match. `scale` draws a smaller copy (the style
    /// choices in the gallery's edit popup): real glass at the smaller size, content scaled.
    static func surfaceView(look: WidgetLook, surface: SurfaceSettings, size full: CGSize, scale: CGFloat = 1,
                            content: AnyView, native: (() -> NSView)?) -> NSView {
        let size = CGSize(width: full.width * scale, height: full.height * scale)
        let bounds = NSRect(origin: .zero, size: size)
        let radius = Metrics.radius * scale
        // AppKit content is drawn at full size and scaled by the view's bounds.
        func nativeBody(_ make: () -> NSView) -> NSView {
            let body = make()
            body.frame = NSRect(origin: .zero, size: full)
            body.autoresizingMask = [.width, .height]
            guard scale != 1 else { return body }
            let holder = NSView(frame: bounds)
            holder.addSubview(body)
            holder.setBoundsSize(full)
            return holder
        }
        func scaled(_ view: some View) -> AnyView {
            AnyView(view.frame(width: full.width, height: full.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width, height: size.height, alignment: .topLeading))
        }

        if look == .clear, let make = native {
            let body = nativeBody(make)
            body.frame = bounds
            body.autoresizingMask = [.width, .height]
            return body
        }
        if look == .clear {
            // No plate at all: just the content, with a soft shadow so it stays
            // readable on any wallpaper.
            let host = NSHostingView(rootView: scaled(content.padding(Metrics.padding)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 1))
                .environment(\.colorScheme, .dark))
            host.frame = bounds
            host.autoresizingMask = [.width, .height]
            return host
        }

        let darkness = look == .frosted ? 0 : surface.darkness
        let host = NSHostingView(rootView: scaled(ZStack {
            content.padding(Metrics.padding)
            if surface.border { EdgeBorder() }
        }).environment(\.colorScheme, .dark))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]

        let shade = NSView(frame: bounds)
        shade.wantsLayer = true
        // Measured from a screenshot: Apple's plate over this wallpaper is rgb(61,65,76),
        // Fitted from a side-by-side crop at 70%: Apple's plate rgb(39.4,42.9,50.6), ours with
        // rgb(7,7,13) gave rgb(37.5,39.2,47.3). Solving for the glass underneath gives this
        // colour, which should land on Apple's value at 70%.
        shade.layer?.backgroundColor = NSColor(srgbRed: 10 / 255, green: 12 / 255, blue: 18 / 255, alpha: darkness).cgColor
        if let make = native {
            let body = nativeBody(make)
            body.frame = bounds
            body.autoresizingMask = [.width, .height]
            shade.addSubview(body)
        } else {
            shade.addSubview(host)
        }

        let glass = NSGlassEffectView(frame: bounds)
        glass.cornerRadius = radius
        glass.setVariant(surface.variant)
        glass.contentView = shade

        let root = NSView(frame: bounds)
        if surface.extraBlur {
            let blur = NSVisualEffectView(frame: bounds)
            blur.material = .underWindowBackground
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.maskImage = WidgetPanel.roundedMask(radius: radius)
            root.addSubview(blur)
        }
        root.addSubview(glass)
        return root
    }

    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
