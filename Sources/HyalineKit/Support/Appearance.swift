// Follows the system widget style (System Settings › Appearance).

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Appearance

/// Follows System Settings › Appearance › Icon & widget style, which macOS stores in
/// the global `AppleIconAppearanceTheme` default (e.g. "ClearDark"; absent = Default).
final class Appearance: ObservableObject {
    enum Style: String { case full = "Default", clear = "Clear", tinted = "Tinted" }

    @Published private(set) var style: Style = Appearance.readStyle()
    var monochrome: Bool { style != .full }
    private var poll: AdaptiveTimer?

    init() {
        // There is no documented change notification for this setting, so listen for
        // the interface-theme broadcast and also re-read every few seconds.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(refresh),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        poll = AdaptiveTimer(ac: 3, battery: 10) { [weak self] in self?.refresh() }
    }

    @objc func refresh() {
        let next = Appearance.readStyle()
        if next != style { style = next }
    }

    private static func readStyle() -> Style {
        // UserDefaults(suiteName:) refuses the global domain, so read it as a persistent domain.
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        let theme = global?["AppleIconAppearanceTheme"] as? String ?? ""
        if theme.hasPrefix("Clear") { return .clear }
        if theme.hasPrefix("Tinted") { return .tinted }
        return .full
    }

    /// Clear: every accent becomes the primary label colour (Apple's monochrome look).
    /// Tinted: accents take the system accent colour (an approximation of Apple's tint).
    /// Default: the widget's own colours.
    func accent(_ color: Color) -> Color {
        switch style {
        case .full: return color
        case .clear: return .white
        case .tinted: return Color(nsColor: .controlAccentColor)
        }
    }
}
