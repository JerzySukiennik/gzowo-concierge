// Gzowo Concierge for macOS - system monitor: SMC temperatures and fans, CPU and GPU load, memory with the hungriest apps, disk, network and battery.
import AppKit
import Darwin
import IOKit
import IOKit.ps

private struct SMCKeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad = (UInt8(0), UInt8(0), UInt8(0)) }

private struct SMCParam {
    var key: UInt32 = 0
    var vers = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt16(0))
    var pLimit = (UInt16(0), UInt16(0), UInt32(0), UInt32(0), UInt32(0))
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    static let shared = SMC()
    private var conn: io_connect_t = 0
    private var infos: [UInt32: SMCKeyInfo] = [:]
    private var missing = Set<UInt32>()

    private init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        IOServiceOpen(svc, mach_task_self_, 0, &conn)
        IOObjectRelease(svc)
    }

    private static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func name(_ v: UInt32) -> String { String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "" }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        guard conn != 0 else { return nil }
        var out = SMCParam(), size = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCParam>.stride, &out, &size)
        return r == kIOReturnSuccess && out.result == 0 ? out : nil
    }

    func value(_ key: String) -> Double? {
        let k = Self.code(key)
        if missing.contains(k) { return nil }
        var info = infos[k]
        if info == nil {
            var p = SMCParam(); p.key = k; p.data8 = 9
            guard let o = call(&p) else { missing.insert(k); return nil }
            info = o.keyInfo; infos[k] = o.keyInfo
        }
        guard let info else { return nil }
        var p = SMCParam(); p.key = k; p.keyInfo.dataSize = info.dataSize; p.data8 = 5
        guard let o = call(&p) else { return nil }
        let b = withUnsafeBytes(of: o.bytes) { Array($0.prefix(Int(info.dataSize))) }
        switch Self.name(info.dataType) {
        case "sp78": return b.count >= 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        case "fpe2": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        case "flt ": return b.count >= 4 ? Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24)) : nil
        case "ui8 ": return b.isEmpty ? nil : Double(b[0])
        case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        default: return nil
        }
    }

    func temperature(_ keys: [String]) -> Double? {
        let v = keys.compactMap { value($0) }.filter { $0 > 5 && $0 < 125 }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}

struct AppUsage: Identifiable, Equatable {
    var id: String
    var name: String
    var bytes: UInt64
    var pids: [pid_t]
    var bundle: URL?
    static func == (a: AppUsage, b: AppUsage) -> Bool { a.id == b.id && a.bytes == b.bytes }
}

struct Battery: Equatable {
    var percent: Int
    var charging: Bool
    var plugged: Bool
    var minutesLeft: Int?
    var cycles: Int?
    var health: Int?
}

struct StatsSnapshot: Equatable {
    var cpu: Double = 0
    var cpuTemp: Double?
    var gpu: Double = 0
    var gpuTemp: Double?
    var fans: [Double] = []
    var fanMax: Double = 0
    var memUsed: UInt64 = 0
    var memTotal: UInt64 = 0
    var pressure = 1
    var diskFree: Int64 = 0
    var diskTotal: Int64 = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var netDown: Double = 0
    var netUp: Double = 0
    var battery: Battery?
    var power: Double?
    var cpuHistory: [Double] = []
    var gpuHistory: [Double] = []
    var netHistory: [Double] = []
    var fanHistory: [Double] = []
    var diskHistory: [Double] = []
    var memFraction: Double { memTotal > 0 ? Double(memUsed) / Double(memTotal) : 0 }
}

@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var snap = StatsSnapshot()
    @Published private(set) var apps: [AppUsage] = []
    private var timer: Timer?
    private var prevCPU: [(UInt64, UInt64)] = []
    private var prevNet: (UInt64, UInt64, Date)?
    private var prevDisk: (UInt64, UInt64, Date)?
    private var detailed = false
    private var lastApps = Date.distantPast
    private let queue = DispatchQueue(label: "fun.gzowo.concierge.stats", qos: .utility)
    private var icons: [String: NSImage] = [:]

    var onTick: (StatsSnapshot) -> Void = { _ in }

    func run(every seconds: TimeInterval, detailed: Bool) {
        self.detailed = detailed
        timer?.invalidate()
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func icon(for app: AppUsage) -> NSImage {
        if let i = icons[app.id] { return i }
        let img = app.bundle.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .unixExecutable)
        icons[app.id] = img
        return img
    }

    private func tick() {
        let wantApps = detailed && Date().timeIntervalSince(lastApps) > 2.5
        if wantApps { lastApps = Date() }
        let prevCPU = self.prevCPU, prevNet = self.prevNet, prevDisk = self.prevDisk, old = snap, detailed = self.detailed
        queue.async { [weak self] in
            var s = old
            let (cpu, ticks) = Self.cpuLoad(prevCPU)
            s.cpu = cpu
            let smc = SMC.shared
            s.cpuTemp = smc.temperature(["TC1C", "TC2C", "TC3C", "TC4C", "TC5C", "TC6C", "TC7C", "TC8C"]) ?? smc.temperature(["TC0E", "TC0P"])
            s.gpu = Self.gpuLoad()
            s.gpuTemp = [smc.temperature(["TGDD", "TGDE", "TGDF"]), smc.temperature(["TG0D", "TG0P"])].compactMap { $0 }.first
            let (used, total, pressure) = Self.memory()
            s.memUsed = used; s.memTotal = total; s.pressure = pressure
            var net = prevNet, disk = prevDisk
            if detailed {
                let count = Int(smc.value("FNum") ?? 0)
                s.fans = (0..<min(count, 4)).compactMap { smc.value("F\($0)Ac") }
                s.fanMax = (0..<min(count, 4)).compactMap { smc.value("F\($0)Mx") }.max() ?? 0
                s.power = smc.value("PSTR")
                (s.diskFree, s.diskTotal) = Self.diskSpace()
                let n = Self.netBytes(), now = Date()
                if let p = prevNet { let dt = max(0.2, now.timeIntervalSince(p.2)); s.netDown = Double(n.0 &- p.0) / dt; s.netUp = Double(n.1 &- p.1) / dt }
                net = (n.0, n.1, now)
                let d = Self.diskBytes()
                if let p = prevDisk { let dt = max(0.2, now.timeIntervalSince(p.2)); s.diskRead = Double(d.0 &- p.0) / dt; s.diskWrite = Double(d.1 &- p.1) / dt }
                disk = (d.0, d.1, now)
                s.battery = Self.battery()
                s.netHistory = Array((s.netHistory + [s.netDown + s.netUp]).suffix(40))
                s.diskHistory = Array((s.diskHistory + [s.diskRead + s.diskWrite]).suffix(40))
                s.fanHistory = Array((s.fanHistory + [s.fans.max() ?? 0]).suffix(40))
            }
            s.cpuHistory = Array((s.cpuHistory + [cpu]).suffix(40))
            s.gpuHistory = Array((s.gpuHistory + [s.gpu]).suffix(40))
            let apps = wantApps ? Self.topApps() : nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.prevCPU = ticks
                self.prevNet = net
                self.prevDisk = disk
                if self.snap != s { self.snap = s }
                if let apps, apps != self.apps { self.apps = apps }
                self.onTick(s)
            }
        }
    }

    // MARK: readers

    private nonisolated static func cpuLoad(_ prev: [(UInt64, UInt64)]) -> (Double, [(UInt64, UInt64)]) {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS, let info else { return (0, prev) }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        var ticks: [(UInt64, UInt64)] = []
        for i in 0..<Int(count) {
            let b = i * Int(CPU_STATE_MAX)
            let user = UInt64(info[b + Int(CPU_STATE_USER)]), sys = UInt64(info[b + Int(CPU_STATE_SYSTEM)]), nice = UInt64(info[b + Int(CPU_STATE_NICE)]), idle = UInt64(info[b + Int(CPU_STATE_IDLE)])
            ticks.append((user + sys + nice, user + sys + nice + idle))
        }
        guard prev.count == ticks.count else { return (0, ticks) }
        var busy: UInt64 = 0, all: UInt64 = 0
        for (a, b) in zip(prev, ticks) { busy += b.0 &- a.0; all += b.1 &- a.1 }
        return (all > 0 ? Double(busy) / Double(all) : 0, ticks)
    }

    private nonisolated static func gpuLoad() -> Double {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(it) }
        var best = 0.0
        while case let s = IOIteratorNext(it), s != 0 {
            if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
               let u = (stats["Device Utilization %"] as? NSNumber)?.doubleValue { best = max(best, u / 100) }
            IOObjectRelease(s)
        }
        return best
    }

    private nonisolated static func memory() -> (UInt64, UInt64, Int) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let r = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        let page = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        guard r == KERN_SUCCESS else { return (0, total, 1) }
        let appMem = (UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)) * page
        let used = appMem + UInt64(stats.wire_count) * page + UInt64(stats.compressor_page_count) * page
        var level: Int32 = 1, size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return (min(used, total), total, Int(level))
    }

    private nonisolated static func diskSpace() -> (Int64, Int64) {
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }

    private nonisolated static func diskBytes() -> (UInt64, UInt64) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(it) }
        var r: UInt64 = 0, w: UInt64 = 0
        while case let s = IOIteratorNext(it), s != 0 {
            if let st = IORegistryEntryCreateCFProperty(s, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                r += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(s)
        }
        return (r, w)
    }

    private nonisolated static func netBytes() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }
        var down: UInt64 = 0, up: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let name = String(cString: a.pointee.ifa_name)
            if let addr = a.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"), let data = a.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes); up += UInt64(d.ifi_obytes)
            }
            p = a.pointee.ifa_next
        }
        return (down, up)
    }

    private nonisolated static func battery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for src in list {
            guard let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            var b = Battery(percent: max > 0 ? cur * 100 / max : cur, charging: d[kIOPSIsChargingKey] as? Bool ?? false, plugged: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            if let t = d[kIOPSTimeToEmptyKey] as? Int, t > 0, !b.plugged { b.minutesLeft = t }
            let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if svc != 0 {
                func prop(_ k: String) -> Int? { (IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue }
                b.cycles = prop("CycleCount")
                if let design = prop("DesignCapacity"), design > 0, let full = prop("AppleRawMaxCapacity") ?? prop("NominalChargeCapacity") { b.health = min(100, full * 100 / design) }
                IOObjectRelease(svc)
            }
            return b
        }
        return nil
    }

    private nonisolated static func topApps() -> [AppUsage] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        let me = getuid()
        var groups: [String: AppUsage] = [:]
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(got) where pid > 0 {
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size, info.pbi_uid == me else { continue }
            var usage = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &usage) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) } }
            guard ok == 0, usage.ri_phys_footprint > 0 else { continue }
            guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let p = String(cString: path)
            var key = p, name = URL(fileURLWithPath: p).lastPathComponent, bundle: URL?
            if let r = p.range(of: ".app/") {
                let appPath = String(p[..<r.lowerBound]) + ".app"
                key = appPath; bundle = URL(fileURLWithPath: appPath)
                name = FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
            } else if p.hasPrefix("/System/") || p.hasPrefix("/usr/libexec/") || p.hasPrefix("/usr/sbin/") {
                key = "system"; name = "System macOS"
            }
            var g = groups[key] ?? AppUsage(id: key, name: name, bytes: 0, pids: [], bundle: bundle)
            g.bytes += usage.ri_phys_footprint
            g.pids.append(pid)
            groups[key] = g
        }
        return groups.values.sorted { $0.bytes > $1.bytes }.prefix(12).map { $0 }
    }
}

enum Fmt {
    static func bytes(_ b: Double, decimals: Bool = true) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = b, i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1024; i += 1 }
        let num = (i >= 2 && decimals && v < 100) ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return num.replacingOccurrences(of: ".", with: ",") + " " + units[i]
    }
    static func rate(_ b: Double) -> String { bytes(b) + "/s" }
    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
    static func temp(_ t: Double?) -> String { t.map { "\(Int($0.rounded()))°" } ?? "" }
}
