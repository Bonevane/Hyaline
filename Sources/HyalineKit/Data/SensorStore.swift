// Temperatures (HID event system) and fan speeds (AppleSMC).

import AppKit
import EventKit
import CoreLocation
import IOKit

/// SMC parameter block (matches the kernel's SMCParamStruct layout, 80 bytes).
struct SMCParam {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var keyInfoPadding: (UInt8, UInt8, UInt8) = (0, 0, 0)   // C pads the key-info struct to 12 bytes
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SensorStore: ObservableObject {
    static let shared = SensorStore()
    @Published var cpu: Double?
    @Published var gpu: Double?
    @Published var ssd: Double?
    @Published var battery: Double?
    @Published var fans: [Double] = []
    @Published var peakCPU: Double = 0
    /// Fan maximum speeds, read once (rpm), so fans can be shown as a share of full speed.
    @Published var fanMax: [Double] = []
    /// Recent readings, oldest first, one every 3 s (last ~3 minutes).
    @Published var cpuHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    private var client: AnyObject?
    private var smc: io_connect_t = 0
    private var started = false
    var isVisible: () -> Bool = { true }

    func start() {
        guard !started else { return }
        started = true
        if let c = HIDSensors.createClient(kCFAllocatorDefault)?.takeRetainedValue() {
            _ = HIDSensors.setMatching(c, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
            client = c
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        if service != 0 { IOServiceOpen(service, mach_task_self_, 0, &smc); IOObjectRelease(service) }
        sample()
        timer = AdaptiveTimer(ac: 3, battery: 8) { [weak self] in if self?.isVisible() ?? false { self?.sample() } }
    }
    private var timer: AdaptiveTimer?

    private func sample() {
        var dies: [Double] = [], nand: Double?, gas: Double?
        if let client, let services = HIDSensors.copyServices(client)?.takeRetainedValue() as? [AnyObject] {
            for s in services {
                guard let name = HIDSensors.copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                      let event = HIDSensors.copyEvent(s, 15, 0, 0)?.takeRetainedValue() else { continue }
                let v = HIDSensors.floatValue(event, 15 << 16)
                guard v > 0, v < 130 else { continue }
                if name.hasPrefix("PMU tdie") { dies.append(v) }
                else if name.hasPrefix("NAND") { nand = max(nand ?? 0, v) }
                else if name.contains("gas gauge") { gas = v }
            }
        }
        cpu = dies.max()
        if let c = cpu { peakCPU = max(peakCPU, c); cpuHistory = Array((cpuHistory + [c]).suffix(60)) }
        ssd = nand; battery = gas
        // GPU sensors are only in the SMC on Apple silicon (M2 key names).
        gpu = ["Tg0f", "Tg0j", "Tg0D", "Tg05"].compactMap { readFloat($0) }.filter { $0 > 0 && $0 < 130 }.max()
        if let g = gpu { gpuHistory = Array((gpuHistory + [g]).suffix(60)) }
        let count = Int(readByte("FNum") ?? 0)
        fans = (0..<count).compactMap { readFloat("F\($0)Ac") }
        if fanMax.count != count { fanMax = (0..<count).map { readFloat("F\($0)Mx") ?? 6000 } }
    }

    private func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        guard smc != 0 else { return nil }
        var output = SMCParam()
        var outSize = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(smc, 2, &input, MemoryLayout<SMCParam>.stride, &output, &outSize)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private func readBytes(_ key: String) -> (UInt32, [UInt8])? {
        var info = SMCParam(); info.key = fourCC(key); info.data8 = 9              // read key info
        guard let i = call(&info) else { return nil }
        var read = SMCParam(); read.key = fourCC(key); read.dataSize = i.dataSize; read.data8 = 5   // read bytes
        guard let out = call(&read) else { return nil }
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(i.dataSize))) }
        return (i.dataType, bytes)
    }

    private func readFloat(_ key: String) -> Double? {
        guard let (type, b) = readBytes(key), type == fourCC("flt "), b.count == 4 else { return nil }
        return Double(b.withUnsafeBytes { $0.load(as: Float32.self) })
    }

    private func readByte(_ key: String) -> UInt8? { readBytes(key)?.1.first }
}
