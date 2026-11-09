// The menu-bar menu. The glass tuning controls from development live in a Developer
// submenu that only appears when the menu is opened with Option held.

import AppKit
import ServiceManagement

@MainActor
extension AppDelegate {
    func buildMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = HyalineMark.menuBarImage()
        let menu = NSMenu()
        // Shown only while a new version is waiting.
        updateItem = menu.addItem(withTitle: "", action: #selector(showUpdates), keyEquivalent: "")
        updateItem?.target = self
        updateItem?.isHidden = true
        menu.addItem(withTitle: "Widget Gallery…", action: #selector(showGallery), keyEquivalent: "g").target = self
        menu.addItem(.separator())
        // Read-only: the widget style comes from System Settings › Appearance.
        styleItem = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menu.delegate = self
        menu.addItem(withTitle: "Keep above windows", action: #selector(toggleAbove(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Reset layout", action: #selector(resetLayout), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(showUpdates), keyEquivalent: "").target = self
        loginItem = menu.addItem(withTitle: "Open at Login", action: #selector(toggleOpenAtLogin(_:)), keyEquivalent: "")
        loginItem?.target = self
        developerItem = menu.addItem(withTitle: "Developer", action: nil, keyEquivalent: "")
        menu.setSubmenu(developerMenu(), for: developerItem!)
        menu.addItem(withTitle: "Quit Hyaline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        appearance.refresh()
        styleItem?.title = "Widget style: \(appearance.style.rawValue) (System Settings)"
        developerItem?.isHidden = !NSEvent.modifierFlags.contains(.option)
        loginItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        if let sub = showcaseItem?.submenu { refreshShowcaseMenu(sub) }
        // Keep the Developer menu showing while a showcase runs, to switch or end it.
        if showcase != nil { developerItem?.isHidden = false }
        if let waiting = Updater.shared.release {
            updateItem?.title = "Update to Hyaline \(waiting.version)…"
            updateItem?.isHidden = false
        } else {
            updateItem?.isHidden = true
        }
    }

    @objc func showUpdates() { updates.show() }

    /// Registers Hyaline as a login item (System Settings › General › Login Items).
    @objc func toggleOpenAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription
            NSApp.activate()
            alert.runModal()
        }
        // macOS may want approval in System Settings first.
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = service.status == .enabled ? .on : .off
    }

    /// Glass and clock tuning used while matching Apple's widgets.
    private func developerMenu() -> NSMenu {
        let menu = NSMenu()
        let variants = NSMenu()
        for v in 0...20 {
            let entry = variants.addItem(withTitle: "Variant \(v)", action: #selector(pickVariant(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = v
            entry.state = v == surface.variant ? .on : .off
        }
        let variantItem = menu.addItem(withTitle: "Glass variant", action: nil, keyEquivalent: "")
        menu.setSubmenu(variants, for: variantItem)
        let shades = NSMenu()
        for (i, step) in darknessSteps.enumerated() {
            let entry = shades.addItem(withTitle: step == 0 ? "None" : String(format: "%g%%", (step * 1000).rounded() / 10), action: #selector(pickDarkness(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = i
            entry.state = abs(step - surface.darkness) < 0.001 ? .on : .off
        }
        let shadeItem = menu.addItem(withTitle: "Darkness", action: nil, keyEquivalent: "")
        menu.setSubmenu(shades, for: shadeItem)
        let blurItem = menu.addItem(withTitle: "Extra blur", action: #selector(toggleBlur(_:)), keyEquivalent: "")
        blurItem.target = self
        let borderItem = menu.addItem(withTitle: "Edge border", action: #selector(toggleBorder(_:)), keyEquivalent: "")
        borderItem.target = self
        borderItem.state = surface.border ? .on : .off
        menu.addItem(.separator())
        // Tall glass clock: which glass the digits are made of, and the font weight.
        let clockGlass = NSMenu()
        // tag = top variant × 100 + frosted under-layer variant (0 = none)
        let current = GlassClockView.variant * 100 + GlassClockView.underVariant
        for (title, tag) in [("Frost + refraction (11 over 6)", 1106), ("Frosted refraction (9)", 900),
                             ("Soft frost (14 over 6)", 1406), ("Clear, refracting (11)", 1100)] {
            let e = clockGlass.addItem(withTitle: title, action: #selector(pickClockGlass(_:)), keyEquivalent: "")
            e.target = self; e.tag = tag; e.state = tag == current ? .on : .off
        }
        menu.setSubmenu(clockGlass, for: menu.addItem(withTitle: "Clock glass", action: nil, keyEquivalent: ""))
        let clockWeight = NSMenu()
        for w in [60, 120, 180, 250, 320, 400] {
            let e = clockWeight.addItem(withTitle: "\(w)", action: #selector(pickClockWeight(_:)), keyEquivalent: "")
            e.target = self; e.tag = w; e.state = Double(w) == GlassClockView.weight ? .on : .off
        }
        menu.setSubmenu(clockWeight, for: menu.addItem(withTitle: "Clock weight", action: nil, keyEquivalent: ""))
        let clockOptical = NSMenu()
        for o in [50, 60, 70, 80, 96] {
            let e = clockOptical.addItem(withTitle: "\(o)", action: #selector(pickClockOptical(_:)), keyEquivalent: "")
            e.target = self; e.tag = o; e.state = Double(o) == GlassClockView.opticalSize ? .on : .off
        }
        menu.setSubmenu(clockOptical, for: menu.addItem(withTitle: "Clock optical size", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        showcaseItem = menu.addItem(withTitle: "Showcase", action: nil, keyEquivalent: "")
        menu.setSubmenu(showcaseMenu(), for: showcaseItem!)
        return menu
    }

    @objc func pickVariant(_ sender: NSMenuItem) {
        surface.variant = sender.tag
        sender.menu?.items.forEach { $0.state = $0.tag == surface.variant ? .on : .off }
        applyAll()
    }

    @objc func pickDarkness(_ sender: NSMenuItem) {
        surface.darkness = darknessSteps[sender.tag]
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        applyAll()
    }

    @objc func toggleBorder(_ sender: NSMenuItem) {
        surface.border.toggle()
        sender.state = surface.border ? .on : .off
        applyAll()
    }

    @objc func toggleBlur(_ sender: NSMenuItem) {
        surface.extraBlur.toggle()
        sender.state = surface.extraBlur ? .on : .off
        applyAll()
    }

    @objc func pickClockGlass(_ sender: NSMenuItem) {
        GlassClockView.variant = sender.tag / 100
        GlassClockView.underVariant = sender.tag % 100
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        applyAll()
    }

    @objc func pickClockOptical(_ sender: NSMenuItem) {
        GlassClockView.opticalSize = Double(sender.tag)
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        applyAll()
    }

    @objc func pickClockWeight(_ sender: NSMenuItem) {
        GlassClockView.weight = Double(sender.tag)
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        applyAll()
    }
}
