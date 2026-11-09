// Hides the widgets while Mission Control is open, as Apple's widgets do.
//
// Widgets are stationary (so clicking the wallpaper leaves them in place) and sticky
// (so they're drawn while desktops slide). Stationary windows stay visible in Mission
// Control, so we hide them ourselves. The window server posts event 1327 to every app
// 20–45 ms before Mission Control's window appears and 1328 as it closes (found by
// logging all event types against the Dock's window; wallpaper clicks don't send it).
// Event-driven: nothing runs while idle.

import AppKit
import CoreGraphics

enum MissionControl {

    private static let opening: UInt32 = 1327, closing: UInt32 = 1328
    /// Called on the main thread: true when Mission Control opens, false when it closes.
    static var onChange: (Bool) -> Void = { _ in }
    private(set) static var showing = false

    static func start() {
        _ = WindowServer.mainConnection()
        let proc: WindowServer.NotifyProc = { type, _, _, _ in
            DispatchQueue.main.async { MissionControl.handle(type) }
        }
        _ = WindowServer.registerNotify(proc, opening, nil)
        _ = WindowServer.registerNotify(proc, closing, nil)
    }

    private static func handle(_ type: UInt32) {
        let open = type == opening
        guard open != showing else { return }
        showing = open
        onChange(open)
        // Safety net: if Mission Control's window never showed up (some other use of
        // the event), bring the widgets back.
        if open {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard showing, !dockOverlayVisible() else { return }
                showing = false
                onChange(false)
            }
        }
    }

    /// The Dock's full-screen Mission Control window (layer 18).
    private static func dockOverlayVisible() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == 18 }
    }
}
