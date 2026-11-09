// Every widget Hyaline offers: id, group, name, size, look and options.

import SwiftUI
import AppKit

enum WSize: String {
    case small, medium, large, slim, tall
    var cg: CGSize {
        switch self {
        case .small: return Metrics.small
        case .medium: return Metrics.medium
        case .large: return Metrics.large
        case .slim: return CGSize(width: 344, height: (Metrics.medium.height - Metrics.gap) / 2)   // 74: two stack to a medium, medium + two to a large
        case .tall: return Metrics.tall
        }
    }
    var label: String { ["small": "Small", "medium": "Medium", "large": "Large", "slim": "Slim", "tall": "Tall"][rawValue]! }
}

struct WidgetSetting {
    let key: String
    let title: String
    let prompt: String
    var multiline = false
}

/// An on/off option in the widget's right-click menu, saved with the widget.
struct WidgetToggle {
    let key: String
    let title: String
    var defaultOn = false
}

struct WidgetKind {
    let id: String
    let group: String
    let name: String
    let size: WSize
    var look: WidgetLook = .glass
    /// SwiftUI content, drawn inside the panel's padding.
    var view: ((WidgetContext) -> AnyView)?
    /// AppKit content for the glass-numeral clocks; gets the panel's font weight.
    var native: ((WidgetPanel) -> NSView)?
    /// SwiftUI content that also reads the widget's own settings.
    var configured: ((WidgetContext, WidgetConfig) -> AnyView)?
    /// Settings offered in the widget's right-click menu.
    var settings: [WidgetSetting] = []
    /// On/off options in the right-click menu.
    var toggles: [WidgetToggle] = []
    var hasFontWeight: Bool { native != nil }
}

enum Registry {
    static var groups: [String] { baseGroups + moreGroups }
    static var kinds: [WidgetKind] { baseKinds + moreKinds }
    static let baseGroups = ["Clock", "Mood", "CPU and system", "Memory", "Battery", "Network", "Storage", "Energy", "Time"]

    static let baseKinds: [WidgetKind] = {
        func v(_ make: @escaping (WidgetContext) -> some View) -> (WidgetContext) -> AnyView { { AnyView(make($0)) } }
        return [
            WidgetKind(id: "lock-wide", group: "Clock", name: "Stretched lock screen", size: .large, look: .clear,
                       native: { p in GlassClockView(column: false, weight: p.fontWeight ?? GlassClockView.weight,
                                                     showDate: p.isOn("showDate", default: false)) },
                       toggles: [WidgetToggle(key: "showDate", title: "Show date")]),
            WidgetKind(id: "lock-column", group: "Clock", name: "Stretched lock screen", size: .tall, look: .clear,
                       native: { p in GlassClockView(column: true, weight: p.fontWeight ?? GlassClockView.weight,
                                                     showDate: p.isOn("showDate", default: false)) },
                       toggles: [WidgetToggle(key: "showDate", title: "Show date")]),
            WidgetKind(id: "clock-stacked", group: "Clock", name: "Stacked", size: .small, look: .clear, view: v { _ in StackedClock() }),
            WidgetKind(id: "clock-words", group: "Clock", name: "Word clock", size: .small, look: .clear, view: v { _ in WordClock() }),
            WidgetKind(id: "clock-flip", group: "Clock", name: "Split flap", size: .small, view: v { _ in FlipClock() }),
            WidgetKind(id: "clock-minimal", group: "Clock", name: "Minimal dial", size: .small, view: v { MinimalDial(appearance: $0.appearance) }),
            WidgetKind(id: "clock-dayarc", group: "Clock", name: "Day arc", size: .medium, view: v { DayArcClock(appearance: $0.appearance) }),
            WidgetKind(id: "clock-world", group: "Clock", name: "World arcs", size: .medium, view: v { _ in WorldArcs() }),
            WidgetKind(id: "clock-strip", group: "Clock", name: "Strip", size: .slim, view: v { ClockStrip(appearance: $0.appearance) }),

            WidgetKind(id: "mood-phrase", group: "Mood", name: "Phrase", size: .medium, view: v { _ in MoodPhrase() }),
            WidgetKind(id: "mood-serif", group: "Mood", name: "Serif", size: .medium, view: v { _ in MoodSerif() }),
            WidgetKind(id: "mood-poster", group: "Mood", name: "Poster", size: .large, view: v { _ in MoodPoster() }),
            WidgetKind(id: "mood-ticker", group: "Mood", name: "Ticker", size: .slim, view: v { _ in MoodTicker() }),

            WidgetKind(id: "cpu-arc", group: "CPU and system", name: "Arc gauge", size: .small, view: v { CPUArc(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "cpu-cores", group: "CPU and system", name: "Cores", size: .tall, view: v { CPUCores(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "cpu-graph", group: "CPU and system", name: "Load graph", size: .medium, view: v { CPUGraph(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "cpu-strip", group: "CPU and system", name: "Strip", size: .slim, view: v { CPUStrip(sampler: $0.sampler, appearance: $0.appearance) }),
            WidgetKind(id: "sys-all", group: "CPU and system", name: "System", size: .large, view: v { SystemOverview(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),

            WidgetKind(id: "mem-level", group: "Memory", name: "Pressure level", size: .small, view: v { MemoryLevel(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "mem-breakdown", group: "Memory", name: "Breakdown", size: .medium, view: v { MemoryBreakdown(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "mem-apps", group: "Memory", name: "Top apps", size: .medium, view: v { MemoryApps(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "mem-strip", group: "Memory", name: "Strip", size: .slim, view: v { MemoryStrip(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),

            WidgetKind(id: "bat-big", group: "Battery", name: "Big number", size: .small, view: v { BatteryBig(sampler: $0.sampler) }),
            WidgetKind(id: "bat-level", group: "Battery", name: "Charge level", size: .small, view: v { BatteryLevel(sampler: $0.sampler, appearance: $0.appearance) }),
            WidgetKind(id: "bat-glyph", group: "Battery", name: "Battery glyph", size: .small, view: v { BatteryGlyph(sampler: $0.sampler, appearance: $0.appearance) }),
            WidgetKind(id: "bat-glyph-slim", group: "Battery", name: "Battery glyph", size: .slim, view: v { BatteryGlyph(sampler: $0.sampler, appearance: $0.appearance, slim: true) }),
            WidgetKind(id: "bat-history", group: "Battery", name: "Charge history", size: .medium, view: v { BatteryHistory(sampler: $0.sampler, extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "bat-health", group: "Battery", name: "Health", size: .medium, view: v { BatteryHealth(extras: $0.extras) }),
            WidgetKind(id: "bat-devices", group: "Battery", name: "All devices", size: .tall, view: v { BatteryDevices(sampler: $0.sampler, extras: $0.extras) }),

            WidgetKind(id: "net-mirror", group: "Network", name: "Up and down", size: .medium, view: v { NetworkMirror(extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "net-small", group: "Network", name: "Speeds", size: .small, view: v { NetworkSpeeds(extras: $0.extras) }),
            WidgetKind(id: "net-strip", group: "Network", name: "Connection", size: .slim, view: v { NetworkConnection(extras: $0.extras) }),

            WidgetKind(id: "disk-column", group: "Storage", name: "Storage column", size: .tall, view: v { StorageColumn(extras: $0.extras) }),
            WidgetKind(id: "disk-strip", group: "Storage", name: "Storage strip", size: .slim, view: v { StorageStrip(extras: $0.extras) }),

            WidgetKind(id: "en-list", group: "Energy", name: "Energy list", size: .medium, view: v { EnergyList(extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "en-slim", group: "Energy", name: "Power strip", size: .slim, view: v { EnergyStrip(extras: $0.extras, appearance: $0.appearance) }),
            WidgetKind(id: "en-top", group: "Energy", name: "Biggest drain", size: .small, view: v { EnergyTop(extras: $0.extras, appearance: $0.appearance) }),

            WidgetKind(id: "countdown", group: "Time", name: "Countdown", size: .small, view: v { _ in Countdown() }),
            WidgetKind(id: "focus", group: "Time", name: "Focus timer", size: .small, view: v { _ in FocusTimer() }),
            WidgetKind(id: "sun-arc", group: "Time", name: "Sun path", size: .medium, view: v { SunPath(appearance: $0.appearance) }),
        ]
    }()

    static func kind(_ id: String) -> WidgetKind? { kinds.first { $0.id == id } }
}

// MARK: - Registry additions

extension Registry {
    static let moreGroups = ["Calendar", "Reminders", "Weather", "Now Playing", "Temperatures", "Notes", "Scripts and web"]

    static let moreKinds: [WidgetKind] = {
        func v(_ make: @escaping (WidgetContext) -> some View) -> (WidgetContext) -> AnyView { { AnyView(make($0)) } }
        func c(_ make: @escaping (WidgetContext, WidgetConfig) -> some View) -> (WidgetContext, WidgetConfig) -> AnyView { { AnyView(make($0, $1)) } }
        return [
            WidgetKind(id: "cal-week", group: "Calendar", name: "Week strip", size: .medium, view: v { WeekStrip(appearance: $0.appearance) }),
            WidgetKind(id: "cal-week-slim", group: "Calendar", name: "Week strip", size: .slim, view: v { WeekStrip(appearance: $0.appearance, slim: true) }),
            WidgetKind(id: "cal-next", group: "Calendar", name: "Next up", size: .small, view: v { NextUp(appearance: $0.appearance) }),
            WidgetKind(id: "cal-next-slim", group: "Calendar", name: "Next up", size: .slim, view: v { NextUp(appearance: $0.appearance, slim: true) }),
            WidgetKind(id: "cal-agenda", group: "Calendar", name: "Month + agenda", size: .large, view: v { MonthAgenda(appearance: $0.appearance) }),
            WidgetKind(id: "cal-year", group: "Calendar", name: "Year in dots", size: .medium, view: v { YearDots(appearance: $0.appearance) }),
            WidgetKind(id: "cal-day", group: "Calendar", name: "Day timeline", size: .tall, view: v { DayTimeline(appearance: $0.appearance) }),

            WidgetKind(id: "rem-list", group: "Reminders", name: "Reminders", size: .medium, view: v { RemindersList(appearance: $0.appearance) }),

            WidgetKind(id: "wx-big", group: "Weather", name: "Big temperature", size: .small, view: v { WeatherBig(appearance: $0.appearance) }),
            WidgetKind(id: "wx-curve", group: "Weather", name: "Temperature curve", size: .medium, view: v { WeatherCurve(appearance: $0.appearance) }),
            WidgetKind(id: "wx-week", group: "Weather", name: "Week ranges", size: .large, view: v { WeatherWeek(appearance: $0.appearance) }),
            WidgetKind(id: "wx-strip", group: "Weather", name: "Strip", size: .slim, view: v { WeatherStrip(appearance: $0.appearance) }),

            WidgetKind(id: "np-art", group: "Now Playing", name: "Artwork", size: .small, view: v { _ in NowPlayingArt() }),
            WidgetKind(id: "np-bar", group: "Now Playing", name: "Player", size: .medium, view: v { _ in NowPlayingPlayer() }),
            WidgetKind(id: "np-strip", group: "Now Playing", name: "Strip", size: .slim, view: v { _ in NowPlayingStrip() }),
            WidgetKind(id: "np-vinyl", group: "Now Playing", name: "Vinyl", size: .small, view: v { _ in NowPlayingVinyl() }),

            WidgetKind(id: "temp-list", group: "Temperatures", name: "Sensors", size: .medium, view: v { SensorsList(appearance: $0.appearance) }),
            WidgetKind(id: "temp-slim", group: "Temperatures", name: "CPU, GPU and fans", size: .slim, view: v { ThermalStrip(appearance: $0.appearance) }),
            WidgetKind(id: "temp-gauge", group: "Temperatures", name: "Thermometer", size: .small, view: v { Thermometer(appearance: $0.appearance) }),

            WidgetKind(id: "note-sticky", group: "Notes", name: "Note", size: .small, configured: c { NoteWidget(config: $1) },
                       settings: [WidgetSetting(key: "text", title: "Edit note…", prompt: "Note", multiline: true)]),
            WidgetKind(id: "script", group: "Scripts and web", name: "Script output", size: .medium, configured: c { ScriptWidget(config: $1) },
                       settings: [WidgetSetting(key: "command", title: "Set command…", prompt: "Shell command, run every minute (e.g. brew outdated)")]),
            WidgetKind(id: "github", group: "Scripts and web", name: "Contribution grid", size: .medium, configured: c { GitHubWidget(config: $1) },
                       settings: [WidgetSetting(key: "user", title: "Set GitHub username…", prompt: "GitHub username")]),
            WidgetKind(id: "rss", group: "Scripts and web", name: "Feed headlines", size: .medium, configured: c { FeedWidget(config: $1) },
                       settings: [WidgetSetting(key: "url", title: "Set feed URL…", prompt: "RSS or Atom feed URL")]),
        ]
    }()
}
