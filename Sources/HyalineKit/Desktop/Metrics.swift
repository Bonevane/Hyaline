// Widget sizes, matched to Apple's desktop widgets.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Metrics (checked against Apple's widgets in a screenshot: sizes match)

enum Metrics {
    static let gap: CGFloat = 16
    static let small = CGSize(width: 164, height: 164)
    static let medium = CGSize(width: 344, height: 164)
    static let large = CGSize(width: 344, height: 344)
    static let tall = CGSize(width: 164, height: 344)
    static let radius: CGFloat = 22
    static let padding: CGFloat = 14
    static let screenMargin: CGFloat = 24
}
