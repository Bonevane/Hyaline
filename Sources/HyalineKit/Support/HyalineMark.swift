import AppKit
import SwiftUI

/// Hyaline's mark: a solid back pane behind an outlined front pane, with a gap between them.
/// The app icon (scripts/make-icon.sh) and the menu-bar glyph both draw this one shape,
/// so the two can never drift apart.
public enum HyalineMark {
    /// Apple's icon corner ratio (185/1024 of an 824/1024 square), continuous curvature.
    static let ratio: CGFloat = 185.0 / 824

    // Proportions of the unit square the mark fills.
    static let size: CGFloat = 0.66       // each pane's side
    static let thickness: CGFloat = 0.075 // the front pane's outline
    static let gap: CGFloat = 0.065       // space cut out of the back pane around the front one
    static let shift: CGFloat = 0.30      // how far the back pane sits up and to the left

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        RoundedRectangle(cornerRadius: max(radius, 0.0001), style: .continuous).path(in: r).cgPath
    }

    /// The mark in `rect`, y pointing up. Fill it with the even-odd rule.
    /// Corners are concentric: the front outline's inner edge has the icon's ratio,
    /// its outer edge adds the thickness, and the gap cut adds the gap on top again.
    public static func path(in rect: CGRect) -> CGPath {
        let front = CGRect(x: 1 - size, y: 0, width: size, height: size)
        let inner = front.insetBy(dx: thickness, dy: thickness)
        let innerRadius = inner.width * ratio
        let outerRadius = innerRadius + thickness
        let cut = rounded(front.insetBy(dx: -gap, dy: -gap), outerRadius + gap)
        let back = CGRect(x: 1 - size - shift, y: shift, width: size, height: size)

        let unit = CGMutablePath()
        unit.addPath(rounded(back, back.width * ratio).subtracting(cut))
        unit.addPath(rounded(front, outerRadius))
        unit.addPath(rounded(inner, innerRadius))
        var place = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width, y: rect.height)
        return unit.copy(using: &place) ?? unit
    }

    /// A template image for the menu bar, so macOS tints it for light, dark and highlighted states.
    public static func menuBarImage(points: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path(in: bounds.insetBy(dx: 1, dy: 1)))
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hyaline"
        return image
    }
}
