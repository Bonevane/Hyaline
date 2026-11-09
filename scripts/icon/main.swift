import AppKit
import SwiftUI

// Draws Hyaline's app icon at every size macOS needs, into an .iconset that iconutil
// turns into AppIcon.icns. The mark comes from HyalineMark, the same shape the menu
// bar uses. Built with scripts/make-icon.sh.

func rgb(_ hex: Int) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

// Graphite: the same one-colour gradient structure as Bridge and WheelBridge.
let top = rgb(0x34383F)
let bottom = rgb(0x1B1D22)

func png(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext

    // Apple's grid: the rounded square is 824/1024 of the canvas, with a continuous corner.
    let inset = s * (1 - 824.0 / 1024) / 2
    let square = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    context.saveGState()
    context.addPath(RoundedRectangle(cornerRadius: s * 185 / 1024, style: .continuous).path(in: square).cgPath)
    context.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: square.maxY), end: CGPoint(x: 0, y: square.minY), options: [])
    context.restoreGState()

    // The mark fills the square inset by 21% on each side.
    context.addPath(HyalineMark.path(in: square.insetBy(dx: square.width * 0.21, dy: square.height * 0.21)))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath(using: .evenOdd)

    return rep.representation(using: .png, properties: [:])!
}

let folder = CommandLine.arguments[1]
try! FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                     ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
                     ("512x512", 512), ("512x512@2x", 1024)] {
    try! png(size).write(to: URL(fileURLWithPath: "\(folder)/icon_\(name).png"))
}
