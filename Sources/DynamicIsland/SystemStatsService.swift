import AppKit
import SwiftUI
import Darwin

struct SystemStats: Equatable {
    var cpu: Double = 0            // 0…1
    var memoryUsed: Double = 0     // bytes
    var memoryTotal: Double = 1
    var diskFree: Double = 0
    var diskTotal: Double = 1
    var netDown: Double = 0        // bytes/s
    var netUp: Double = 0
    var uptime: TimeInterval = 0

    var memoryFraction: Double { min(memoryUsed / memoryTotal, 1) }
    var diskUsedFraction: Double { min(1 - diskFree / diskTotal, 1) }
}

/// CPU, memory, disk, network and uptime. Polls only while someone is looking (System tab open).
final class SystemStatsService: ObservableObject {
    @Published private(set) var stats = SystemStats()

    private var timer: Timer?
    private var lastTicks: (busy: Double, total: Double)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?

    func setActive(_ active: Bool) {
        if active {
            guard timer == nil else { return }
            sample()
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.sample() }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func sample() {
        var s = stats
        s.cpu = cpuUsage() ?? s.cpu
        let (used, total) = memory()
        s.memoryUsed = used
        s.memoryTotal = total
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            s.diskFree = Double(values.volumeAvailableCapacityForImportantUsage ?? 0)
            s.diskTotal = Double(max(values.volumeTotalCapacity ?? 1, 1))
        }
        let (down, up) = network()
        let now = Date()
        if let last = lastNet, down >= last.down, up >= last.up {
            let dt = max(now.timeIntervalSince(last.at), 0.1)
            s.netDown = Double(down - last.down) / dt
            s.netUp = Double(up - last.up) / dt
        }
        lastNet = (down, up, now)
        s.uptime = ProcessInfo.processInfo.systemUptime
        if s != stats { stats = s }
    }

    private func cpuUsage() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0), system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return nil }
        return (busy - last.busy) / (total - last.total)
    }

    private func memory() -> (Double, Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = Double(sysconf(_SC_PAGESIZE))
        // Same idea as Activity Monitor's "Memory Used": app memory + wired + compressed.
        let app = Double(vm.internal_page_count) - Double(vm.purgeable_count)
        let used = (app + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
        return (max(used, 0), total)
    }

    private func network() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var down: UInt64 = 0, up: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    down += UInt64(d.ifi_ibytes)
                    up += UInt64(d.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        return (down, up)
    }
}

func formatUptime(_ t: TimeInterval) -> String {
    let mins = Int(t / 60)
    let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
