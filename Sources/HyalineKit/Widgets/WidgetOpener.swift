// What a click on each widget opens: its app or the matching System Settings pane.

import SwiftUI
import AppKit

/// What a single click on a widget opens, as Apple's widgets do: the app the data
/// comes from, or the matching System Settings pane. nil means a click does nothing.
enum WidgetOpener {
    static func action(for kind: WidgetKind, config: WidgetConfig) -> (() -> Void)? {
        switch kind.group {
        case "Clock": return app("com.apple.clock")
        case "Calendar": return app("com.apple.iCal")
        case "Reminders": return app("com.apple.reminders")
        case "Weather": return app("com.apple.weather")
        case "CPU and system", "Memory", "Energy", "Temperatures": return app("com.apple.ActivityMonitor")
        case "Now Playing":
            return {
                let player = NowPlayingStore.shared.player
                open(app: player == "Music" ? "com.apple.Music" : player == "Spotify" ? "com.spotify.client"
                     : NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" } ? "com.spotify.client" : "com.apple.Music")
            }
        case "Battery":
            return kind.id == "bat-devices" ? settings("com.apple.BluetoothSettings") : settings("com.apple.Battery-Settings.extension")
        case "Network": return settings("com.apple.wifi-settings-extension")
        case "Storage": return settings("com.apple.settings.Storage")
        case "Time": return kind.id == "sun-arc" ? app("com.apple.weather") : kind.id == "countdown" ? app("com.apple.iCal") : nil
        case "Scripts and web":
            switch kind.id {
            case "github": return { if let u = config.values["user"], !u.isEmpty, let url = URL(string: "https://github.com/\(u)") { NSWorkspace.shared.open(url) } }
            case "rss": return {
                if let s = config.values["url"], let feed = URL(string: s), let host = feed.host, let site = URL(string: "https://\(host)") { NSWorkspace.shared.open(site) }
            }
            default: return nil
            }
        default: return nil
        }
    }

    private static func app(_ id: String) -> () -> Void { { open(app: id) } }
    private static func open(app id: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    private static func settings(_ pane: String) -> () -> Void {
        { if let url = URL(string: "x-apple.systempreferences:\(pane)") { NSWorkspace.shared.open(url) } }
    }
}
