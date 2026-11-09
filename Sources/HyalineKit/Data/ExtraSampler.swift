// Energy, per-app usage, Bluetooth batteries and other slower readings.

import AppKit
import IOKit
import IOKit.ps
import CoreWLAN
import Darwin

struct AppUsage: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let value: Double
}

struct DeviceBattery: Identifiable {
    var id: String { name }
    let name: String
    let percent: Int
    let charging: Bool
}

final class ExtraSampler: ObservableObject {
    // CPU per core, grouped as performance then efficiency
    @Published var cores: [Double] = []
    @Published var performanceCores = 0
    @Published var gpu: Double = 0
    @Published var gpuHistory: [Double] = Array(repeating: 0, count: 40)
    // Memory
    @Published var memApp: Double = 0
    @Published var memWired: Double = 0
    @Published var memCompressed: Double = 0
    @Published var memCached: Double = 0
    @Published var memFree: Double = 0
    @Published var memPressure = 1 // 1 normal, 2 warning, 4 critical
    @Published var memHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var topMemory: [AppUsage] = []
    // Energy
    @Published var topEnergy: [AppUsage] = []
    /// Whole-Mac power draw in W (the battery's SystemLoad telemetry), with recent history.
    @Published var systemPower: Double?
    @Published var powerHistory: [Double] = []
    /// Sum of every app's power, so app shares can be shown against it.
    @Published var appsPower: Double = 0
    private var smoothedEnergy: [pid_t: Double] = [:]
    // Network
    @Published var down: Double = 0
    @Published var up: Double = 0
    @Published var downHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var upHistory: [Double] = Array(repeating: 0, count: 40)
    @Published var wifiName: String?
    @Published var localIP: String?
    @Published var pingMs: Double?
    // Storage
    @Published var diskTotal: Double = 0
    @Published var diskFree: Double = 0
    // Battery detail
    @Published var maxCapacity: Int?
    @Published var cycleCount: Int?
    @Published var batteryTemp: Double?
    @Published var condition: String?
    @Published var chargeHistory: [(Date, Int, Bool)] = []
    @Published var devices: [DeviceBattery] = []

    private var prevCoreTicks: [(UInt64, UInt64)] = []
    private var prevNet: (UInt64, UInt64, Date)?
    private var prevEnergy: [pid_t: (UInt64, Date)] = [:]
    private var slowTick = 0
    private var timer: AdaptiveTimer?
    var isVisible: () -> Bool = { true }
    private let timebase: Double = { var t = mach_timebase_info(); mach_timebase_info(&t); return Double(t.numer) / Double(t.denom) }()

    init() {
        performanceCores = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        loadChargeHistory()
    }

    func start() {
        sample(slow: true)
        timer = AdaptiveTimer(ac: 2, battery: 5) { [weak self] in
            guard let self, self.isVisible() else { return }
            self.slowTick += 1
            // Slow sources (disk, battery detail, devices, Wi-Fi, ping) every ~30 s, ~60 s on battery.
            self.sample(slow: self.slowTick % (PowerMode.shared.onBattery ? 12 : 15) == 0)
        }
    }

    private func sample(slow: Bool) {
        sampleCores()
        sampleGPU()
        sampleMemory()
        sampleNetwork()
        sampleEnergy()
        if slow {
            sampleDisk()
            sampleBatteryDetail()
            sampleDevices()
            sampleWiFi()
            ping()
            recordCharge()
        }
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    // MARK: CPU cores

    private func sampleCores() {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var ticks: [(UInt64, UInt64)] = []
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(info[base + Int(CPU_STATE_IDLE)]), nice = UInt64(info[base + Int(CPU_STATE_NICE)])
            ticks.append((user + sys + nice, user + sys + nice + idle))
        }
        if prevCoreTicks.count == ticks.count {
            cores = zip(ticks, prevCoreTicks).map { now, old in
                let total = Double(now.1 &- old.1)
                return total > 0 ? Double(now.0 &- old.0) / total : 0
            }
        }
        prevCoreTicks = ticks
    }

    // MARK: GPU (IOAccelerator's PerformanceStatistics, the source the Stats app uses)

    private func sampleGPU() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any],
                  let util = stats["Device Utilization %"] as? Int else { continue }
            best = max(best ?? 0, Double(util) / 100)
        }
        if let best { gpu = best; push(&gpuHistory, best) }
    }

    // MARK: Memory

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(getpagesize())
        memApp = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
        memWired = Double(stats.wire_count) * page
        memCompressed = Double(stats.compressor_page_count) * page
        memCached = (Double(stats.external_page_count) + Double(stats.purgeable_count)) * page
        memFree = Double(stats.free_count) * page
        memPressure = Self.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        push(&memHistory, (memApp + memWired + memCompressed) / total)
    }

    // MARK: Per-app memory and energy (proc_pid_rusage; ri_energy_nj is the kernel's own energy counter)

    private func rusage(_ pid: pid_t) -> rusage_info_v6? {
        var info = rusage_info_v6()
        let r = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        return r == 0 ? info : nil
    }

    /// Every process's executable path, so helpers can be counted with their app.
    private func allProcessPaths() -> [(pid_t, String)] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var out: [(pid_t, String)] = []
        var buf = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 { out.append((pid, String(cString: buf))) }
        }
        return out
    }

    private func sampleEnergy() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleURL != nil }
        let processes = allProcessPaths()
        var memory: [AppUsage] = [], energy: [AppUsage] = []
        let now = Date()
        var next: [pid_t: (UInt64, Date)] = [:]
        for app in apps {
            // The app's own process plus every helper whose executable lives inside its
            // bundle (browser and Electron apps do most of their work in helpers).
            let root = app.bundleURL!.path + "/"
            let pids = processes.filter { $0.1.hasPrefix(root) }.map(\.0)
            var footprint: UInt64 = 0, joules: UInt64 = 0
            for pid in pids { if let info = rusage(pid) { footprint += info.ri_phys_footprint; joules += info.ri_energy_nj } }
            guard !pids.isEmpty else { continue }
            let key = app.processIdentifier
            let name = app.localizedName ?? "App"
            memory.append(AppUsage(id: key, name: name, icon: app.icon, value: Double(footprint)))
            next[key] = (joules, now)
            if let (old, at) = prevEnergy[key], joules >= old {
                let watts = Double(joules - old) / 1e9 / max(now.timeIntervalSince(at), 0.5)
                // Smoothed, so the ranking doesn't reshuffle on every 2 s spike.
                let smooth = smoothedEnergy[key].map { $0 * 0.6 + watts * 0.4 } ?? watts
                smoothedEnergy[key] = smooth
                energy.append(AppUsage(id: key, name: name, icon: app.icon, value: smooth))
            }
        }
        prevEnergy = next
        topMemory = Array(memory.sorted { $0.value > $1.value }.prefix(5))
        smoothedEnergy = smoothedEnergy.filter { next[$0.key] != nil }
        if !energy.isEmpty {
            topEnergy = Array(energy.sorted { $0.value > $1.value }.prefix(5))
            appsPower = energy.reduce(0) { $0 + $1.value }
        }
        sampleSystemPower()
    }

    private func sampleSystemPower() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard let t = IORegistryEntryCreateCFProperty(service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any], let load = t["SystemLoad"] as? Int, load > 0 else { return }
        let w = Double(load) / 1000
        systemPower = systemPower.map { $0 * 0.5 + w * 0.5 } ?? w
        powerHistory = Array((powerHistory + [systemPower!]).suffix(60))
    }

    // MARK: Network

    private func sampleNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var ip: String?
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en"), let addr = ifa.ifa_addr else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                inBytes += UInt64(data.pointee.ifi_ibytes)
                outBytes += UInt64(data.pointee.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET), ip == nil {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    ip = String(cString: host)
                }
            }
        }
        localIP = ip
        let now = Date()
        if let (oldIn, oldOut, at) = prevNet, inBytes >= oldIn, outBytes >= oldOut {
            let dt = max(now.timeIntervalSince(at), 0.5)
            down = Double(inBytes - oldIn) / dt
            up = Double(outBytes - oldOut) / dt
            push(&downHistory, down)
            push(&upHistory, up)
        }
        prevNet = (inBytes, outBytes, now)
    }

    private func sampleWiFi() {
        // macOS hides the network name unless the app has Location access; nil then.
        wifiName = CWWiFiClient.shared().interface()?.ssid()
    }

    private func ping() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/sbin/ping")
            p.arguments = ["-c", "1", "-t", "2", "1.1.1.1"]
            p.standardOutput = pipe
            p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let ms = out.range(of: #"time=([0-9.]+)"#, options: .regularExpression)
                .flatMap { Double(out[$0].dropFirst(5)) }
            DispatchQueue.main.async { self?.pingMs = ms }
        }
    }

    // MARK: Storage

    private func sampleDisk() {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Double(v.volumeTotalCapacity ?? 0)
        diskFree = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    // MARK: Battery detail (AppleSmartBattery registry entry)

    private func sampleBatteryDetail() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }
        cycleCount = d["CycleCount"] as? Int
        if let t = d["Temperature"] as? Int { batteryTemp = Double(t) / 100 }
        if let raw = d["AppleRawMaxCapacity"] as? Int, let design = d["DesignCapacity"] as? Int, design > 0 {
            maxCapacity = Int((Double(raw) / Double(design) * 100).rounded())
        }
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let first = list.first,
           let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] {
            condition = desc[kIOPSBatteryHealthKey] as? String
        }
    }

    // MARK: Accessory batteries (Apple keyboards, mice, trackpads report BatteryPercent)

    private func sampleDevices() {
        var found: [DeviceBattery] = []
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS {
            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }
                guard let percent = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                      let name = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      !found.contains(where: { $0.name == name }) else { continue }
                found.append(DeviceBattery(name: name, percent: percent, charging: false))
            }
            IOObjectRelease(iterator)
        }
        devices = found
    }

    // MARK: Charge history: macOS keeps none, so Hyaline records it (every ~30 s, kept 24 h)

    private func recordCharge() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef], let first = list.first,
              let d = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any],
              let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { return }
        let charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        chargeHistory.append((Date(), Int(Double(cur) / Double(max) * 100), charging))
        chargeHistory.removeAll { $0.0 < cutoff }
        let stored = chargeHistory.map { [$0.0.timeIntervalSince1970, Double($0.1), $0.2 ? 1 : 0] }
        UserDefaults.standard.set(stored, forKey: "chargeHistory")
    }

    private func loadChargeHistory() {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let stored = UserDefaults.standard.array(forKey: "chargeHistory") as? [[Double]] ?? []
        chargeHistory = stored.compactMap { a in a.count == 3 ? (Date(timeIntervalSince1970: a[0]), Int(a[1]), a[2] > 0) : nil }
            .filter { $0.0 >= cutoff }
    }

    private func push(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > 40 { array.removeFirst(array.count - 40) }
    }
}
