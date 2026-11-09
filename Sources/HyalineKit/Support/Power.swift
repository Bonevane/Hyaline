// Battery-aware pacing: every update in Hyaline still runs on battery, just less often.

import Foundation
import IOKit.ps
import Combine

/// Whether the Mac is running on battery, kept current from the power-source
/// change notification (no polling).
final class PowerMode: ObservableObject {
    static let shared = PowerMode()
    @Published private(set) var onBattery = PowerMode.read()
    private var source: CFRunLoopSource?

    private init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<PowerMode>.fromOpaque(ctx).takeUnretainedValue()
            let now = PowerMode.read()
            if now != me.onBattery { me.onBattery = now }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            source = s
        }
    }

    private static func read() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPSBatteryPowerValue
    }

    /// Picks the interval for the current power source.
    static func pace(_ ac: TimeInterval, battery: TimeInterval) -> TimeInterval { shared.onBattery ? battery : ac }
}

/// A repeating main-run-loop timer with one interval on power and a longer one on
/// battery; it reschedules itself when the power source changes.
final class AdaptiveTimer {
    private let ac: TimeInterval, battery: TimeInterval
    private let block: () -> Void
    private var timer: Timer?
    private var watch: AnyCancellable?

    init(ac: TimeInterval, battery: TimeInterval, _ block: @escaping () -> Void) {
        self.ac = ac; self.battery = battery; self.block = block
        watch = PowerMode.shared.$onBattery.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.schedule() }
        }
    }
    deinit { timer?.invalidate() }

    private func schedule() {
        timer?.invalidate()
        let interval = PowerMode.pace(ac, battery: battery)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.block() }
        t.tolerance = interval * 0.25 // lets macOS batch wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
