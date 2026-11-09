// The lock-screen clock: numerals made of Liquid Glass.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Glass-numeral lock-screen clock

/// The iOS 26-style tall clock: the numerals are Liquid Glass cut to the shape of the
/// glyphs (a CALayer mask on an NSGlassEffectView), with a faint light outline on top.
/// The face is SF Pro's variable axes pushed past "Compressed": width 30 (Compressed is
/// 47), optical size 96, near-minimum weight. `column` stacks hours over minutes.
final class GlassClockView: NSView {
    private let column: Bool
    private let glass = NSGlassEffectView()
    private let underGlass = NSGlassEffectView()   // optional frosted layer beneath, same shape
    private var timer: Timer?
    private var shownMinute = -1
    /// A second glass of this variant under the main one, in the same digit shape, so the
    /// clear glass refracts frost instead of the raw wallpaper (0 = none).
    static var underVariant = 6
    /// Glass variant for the numerals: soft glass, 14 over 6.
    static var variant = 14
    /// wght axis (1–1000).
    static var weight: Double = 180
    /// opsz axis (17–96); the user picked 70.
    static var opticalSize = 70.0

    private let weight: Double
    private let showDate: Bool
    /// The date above the numerals, as on the iOS lock screen (optional).
    private let dateLabel = NSTextField(labelWithString: "")
    private var shownDay = -1

    init(column: Bool, weight: Double, showDate: Bool = false) {
        self.column = column
        self.weight = weight
        self.showDate = showDate
        super.init(frame: .zero)
        wantsLayer = true
        if showDate {
            dateLabel.font = .systemFont(ofSize: column ? 15 : 20, weight: .semibold)
            dateLabel.textColor = NSColor.white.withAlphaComponent(0.85)
            dateLabel.alignment = .center
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            dateLabel.shadow = shadow
            addSubview(dateLabel)
        }
        glass.setVariant(GlassClockView.variant)
        underGlass.setVariant(max(GlassClockView.underVariant, 0))
        if GlassClockView.underVariant > 0 { addSubview(underGlass) }
        addSubview(glass)
        // Wake once a minute, just after it turns, instead of every second.
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime) ?? Date()
        let t = Timer(fire: next.addingTimeInterval(0.05), interval: 60, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    override func layout() {
        super.layout()
        shownMinute = -1
        tick()
    }

    private func tick() {
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        guard minute != shownMinute, bounds.width > 0 else { return }
        shownMinute = minute
        let dateBand: CGFloat = showDate ? (column ? 30 : 36) : 0
        if showDate {
            let day = Calendar.current.component(.day, from: now)
            if day != shownDay {
                shownDay = day
                dateLabel.stringValue = now.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            dateLabel.frame = NSRect(x: 0, y: bounds.maxY - dateBand + 2, width: bounds.width, height: column ? 22 : 28)
        }
        let h = Calendar.current.component(.hour, from: now)
        let lines = column ? [String(format: "%02d", h), String(format: "%02d", minute)]
                           : ["\((h + 11) % 12 + 1):\(String(format: "%02d", minute))"]
        // The Large clock is condensed; the Tall column uses SF Pro at its normal width.
        var area = bounds.insetBy(dx: 6, dy: 6)
        area.size.height -= dateBand
        let path = GlassClockView.numeralsPath(lines, in: area, width: column ? 100 : 30, weight: weight)
        glass.frame = bounds
        underGlass.frame = bounds
        glass.setShape(path)
        underGlass.setShape(path)
    }

    /// SF Pro with its variable axes set directly (the named widths stop at Compressed = 47).
    static func numeralFont(_ size: CGFloat, width: Double = 30, weight: Double = GlassClockView.weight) -> NSFont {
        let axes: [NSNumber: NSNumber] = [
            0x7764_7468 as NSNumber: NSNumber(value: width),     // wdth: 30 narrowest, 100 normal
            0x6F70_737A as NSNumber: NSNumber(value: opticalSize), // opsz
            0x7767_6874 as NSNumber: NSNumber(value: weight),    // wght: near minimum
        ]
        let base = NSFont.systemFont(ofSize: size).fontDescriptor
        return NSFont(descriptor: base.addingAttributes([.variation: axes]), size: size) ?? .systemFont(ofSize: size)
    }

    /// The glyph outlines of `lines`, as large as fits `rect`, centred, lines stacked
    /// with a small gap. This is the shape the glass itself takes.
    static func numeralsPath(_ lines: [String], in rect: NSRect, width: Double, weight: Double) -> CGPath {
        let gap: CGFloat = 10
        var size: CGFloat = 600
        var built: [(CTLine, CGRect)] = []
        while size > 20 {
            let font = numeralFont(size, width: width, weight: weight)
            built = lines.map { text in
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                return (line, CTLineGetBoundsWithOptions(line, .useGlyphPathBounds))
            }
            let width = built.map { $0.1.width }.max() ?? 0
            let height = built.map { $0.1.height }.reduce(0, +) + gap * CGFloat(built.count - 1)
            if width <= rect.width && height <= rect.height { break }
            size -= 4
        }
        let total = built.map { $0.1.height }.reduce(0, +) + gap * CGFloat(built.count - 1)
        var top = rect.midY + total / 2
        let path = CGMutablePath()
        for (line, box) in built {
            let x0 = rect.midX - box.width / 2 - box.minX
            let y0 = top - box.height - box.minY
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let attrs = CTRunGetAttributes(run) as NSDictionary
                let font = attrs[kCTFontAttributeName as String] as! CTFont
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                for i in 0..<count {
                    if let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                        path.addPath(g, transform: CGAffineTransform(translationX: x0 + positions[i].x, y: y0 + positions[i].y))
                    }
                }
            }
            top -= box.height + gap
        }
        return path
    }
}
