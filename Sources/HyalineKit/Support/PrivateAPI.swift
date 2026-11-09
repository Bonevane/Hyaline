// Every private macOS interface Hyaline uses, in one place. They give the real Liquid
// Glass look, Apple-like Spaces behaviour and temperature readings, none of which the
// public API offers. Fine for a direct download; they can change in any macOS update,
// and this is the file to fix when they do. Not allowed in the Mac App Store.

import AppKit
import ObjectiveC

/// The window server (SkyLight): Spaces membership and system events.
enum WindowServer {
    typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, UInt32, UnsafeMutableRawPointer?) -> Void

    @_silgen_name("CGSMainConnectionID") static func mainConnection() -> Int32
    /// Displays and their Spaces: type 0 is a normal desktop, type 4 a full-screen app.
    @_silgen_name("CGSCopyManagedDisplaySpaces") static func copyDisplaySpaces(_ cid: Int32) -> Unmanaged<CFArray>?
    @_silgen_name("CGSCopySpacesForWindows") static func copySpaces(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> Unmanaged<CFArray>?
    @_silgen_name("CGSAddWindowsToSpaces") static func addWindows(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
    @_silgen_name("CGSRemoveWindowsFromSpaces") static func removeWindows(_ cid: Int32, _ windows: CFArray, _ spaces: CFArray)
    @_silgen_name("CGSSetWindowTags") static func setTags(_ cid: Int32, _ wid: Int, _ tags: UnsafeMutablePointer<UInt32>, _ size: Int32) -> Int32
    /// Event 1327 fires as Mission Control opens, 1328 as it closes.
    @_silgen_name("CGSRegisterNotifyProc") static func registerNotify(_ proc: NotifyProc, _ type: UInt32, _ arg: UnsafeMutableRawPointer?) -> Int32
}

/// The HID event system: Apple silicon's temperature sensors.
enum HIDSensors {
    @_silgen_name("IOHIDEventSystemClientCreate") static func createClient(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?
    @_silgen_name("IOHIDEventSystemClientSetMatching") static func setMatching(_ client: AnyObject, _ matching: CFDictionary) -> Int32
    @_silgen_name("IOHIDEventSystemClientCopyServices") static func copyServices(_ client: AnyObject) -> Unmanaged<CFArray>?
    @_silgen_name("IOHIDServiceClientCopyProperty") static func copyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<AnyObject>?
    @_silgen_name("IOHIDServiceClientCopyEvent") static func copyEvent(_ service: AnyObject, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<AnyObject>?
    @_silgen_name("IOHIDEventGetFloatValue") static func floatValue(_ event: AnyObject, _ field: Int32) -> Double
}

extension NSGlassEffectView {
    /// The private glass variant (0–20 on macOS 26). The public API only gives the
    /// frosted one; some variants draw the real rim and edge lensing.
    func setVariant(_ variant: Int) {
        guard responds(to: NSSelectorFromString("set_variant:")) else { return }
        setValue(variant, forKey: "_variant")
    }

    /// Draws the glass in any shape (the glass clock's numerals), with its own rim and
    /// lensing along the edges.
    func setShape(_ path: CGPath) {
        let sel = NSSelectorFromString("_setPath:")
        guard let method = class_getInstanceMethod(NSGlassEffectView.self, sel) else { return }
        typealias SetPath = @convention(c) (AnyObject, Selector, CGPath) -> Void
        unsafeBitCast(method_getImplementation(method), to: SetPath.self)(self, sel, path)
    }
}
