// CPU, memory, battery, network and disk, sampled once for every widget.

import AppKit
import SwiftUI
import IOKit.ps
import Darwin

// MARK: - Shared sampler (one poller for every stats widget)

final class SystemSampler: ObservableObject {
    @Published var cpu: Double = 0
    @Published var cpuHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var memUsed: Double = 0
    @Published var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    @Published var batteryPercent: Int?
    @Published var charging = false
    @Published var onAC = false
    @Published var minutesLeft: Int?

    private var previousTicks: (used: UInt64, total: UInt64)?
    private var timer: AdaptiveTimer?
    var isVisible: () -> Bool = { true }

    func start() {
        sample()
        timer = AdaptiveTimer(ac: 2, battery: 5) { [weak self] in
            guard let self, self.isVisible() else { return } // pause while covered
            self.sample()
        }
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let prev = previousTicks, ticks.total > prev.total {
                cpu = Double(ticks.used - prev.used) / Double(ticks.total - prev.total)
                cpuHistory.append(cpu)
                cpuHistory.removeFirst(cpuHistory.count - 40)
            }
            previousTicks = ticks
        }
        if let used = Self.memoryUsed() { memUsed = used }
        readBattery()
    }

    private static func cpuTicks() -> (used: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    // Approximates Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Double(getpagesize())
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private func readBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            batteryPercent = nil
            return
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            batteryPercent = Int((Double(current) / Double(max) * 100).rounded())
            charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let left = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            minutesLeft = left > 0 ? left : nil
            return
        }
        batteryPercent = nil
    }
}
