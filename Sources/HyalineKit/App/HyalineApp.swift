// Starts Hyaline: a menu-bar app (no Dock icon) that owns the widget windows.

import AppKit

public enum HyalineApp {
    static let delegate = AppDelegate()

    public static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
