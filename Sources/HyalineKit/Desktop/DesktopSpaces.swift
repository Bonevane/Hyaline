// Keeps widgets on normal desktops and out of full-screen apps.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Layout persistence

/// Saves each widget's position per display, anchored to the screen edges nearest to
/// it. On a resolution change a widget keeps its distance from those edges, so the
/// layout holds its shape the way Apple's does; on relaunch it comes back as it was.
/// Apple's widgets live on the normal desktops only, never in full-screen app spaces, so
/// they slide along with the desktop when you swipe to or from a full-screen app.
/// "Join all spaces" also put ours inside full-screen spaces, and macOS then hid them
/// for the whole slide. This adds our windows to every normal desktop and takes them
/// out of full-screen spaces (private CGS calls; checked again whenever Spaces change).
enum DesktopSpaces {

    /// Window-server tags copied from Apple's own widget windows (read with
    /// CGSGetWindowTags): 0x2 in the low word (fade in Mission Control) and 0x8000 in the
    /// high word, which only their widgets carry.
    static var tags: (UInt32, UInt32) {
        (UInt32(UserDefaults.standard.string(forKey: "widgetTagsLow").flatMap { UInt32($0, radix: 16) } ?? 0x2),
         UInt32(UserDefaults.standard.string(forKey: "widgetTagsHigh").flatMap { UInt32($0, radix: 16) } ?? 0x8000))
    }

    /// (normal desktops, full-screen spaces) across all displays.
    static func spaces() -> (desktops: [Int], fullScreen: [Int]) {
        let displays = WindowServer.copyDisplaySpaces(WindowServer.mainConnection())?.takeRetainedValue() as? [[String: Any]] ?? []
        var desktops: [Int] = [], fullScreen: [Int] = []
        for d in displays {
            for s in d["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = s["ManagedSpaceID"] as? Int else { continue }
                if (s["type"] as? Int) == 0 { desktops.append(id) } else { fullScreen.append(id) }
            }
        }
        return (desktops, fullScreen)
    }

    private static var tagged = Set<Int>()

    static func sync(_ windows: [NSWindow]) {
        let ids = windows.map(\.windowNumber).filter { $0 > 0 }
        guard !ids.isEmpty else { return }
        let (desktops, fullScreen) = spaces()
        let cid = WindowServer.mainConnection()
        // Only touch a window whose membership is actually wrong: re-adding a window to
        // the desktop that's sliding in hides it until the slide ends.
        for id in ids {
            let current = Set(WindowServer.copySpaces(cid, 7, [id] as CFArray)?.takeRetainedValue() as? [Int] ?? [])
            let missing = desktops.filter { !current.contains($0) }
            let extra = fullScreen.filter { current.contains($0) }
            if !missing.isEmpty { WindowServer.addWindows(cid, [id] as CFArray, missing as CFArray) }
            if !extra.isEmpty { WindowServer.removeWindows(cid, [id] as CFArray, extra as CFArray) }
            if !missing.isEmpty || !extra.isEmpty { LayoutLog.write("spaces: window \(id) +\(missing) -\(extra)") }
        }
        if !tagged.isSuperset(of: ids) {
            for id in ids where !tagged.contains(id) { var t: [UInt32] = [tags.0, tags.1]; _ = WindowServer.setTags(cid, id, &t, 64) }
            tagged.formUnion(ids)
        }
    }
}

/// A short log of layout passes, to diagnose resolution-change behaviour:
/// ~/Library/Logs/Hyaline/layout.log (kept under 200 KB).
