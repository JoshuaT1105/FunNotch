//
//  SystemStatsManager.swift
//  FunNotch
//
//  CPU, memory and disk readings for the notch widgets. All of this comes from
//  Mach and the file system, so nothing here needs a permission.
//

import Combine
import Darwin
import Foundation

@MainActor
final class SystemStatsManager: ObservableObject {
    static let shared = SystemStatsManager()

    /// 0...1 across all cores.
    @Published private(set) var cpuUsage: Double = 0
    /// 0...1 of physical memory in use.
    @Published private(set) var memoryUsage: Double = 0
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    /// 0...1 of the boot volume used.
    @Published private(set) var diskUsage: Double = 0
    @Published private(set) var diskFreeBytes: Int64 = 0

    private var timer: Timer?
    private var previousTicks: (used: UInt64, total: UInt64)?
    /// Widgets are the only consumer, so polling stops when none are shown.
    private var subscribers = 0

    private init() {}

    /// Reference-counted so the timer only runs while something is watching.
    func addSubscriber() {
        subscribers += 1
        if subscribers == 1 { start() }
    }

    func removeSubscriber() {
        subscribers = max(subscribers - 1, 0)
        if subscribers == 0 { stop() }
    }

    private func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        previousTicks = nil
    }

    func refresh() {
        readCPU()
        readMemory()
        readDisk()
    }

    // MARK: - CPU

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)

        let used = user + system + nice
        let total = used + idle

        // The counters are cumulative since boot, so usage is the delta.
        defer { previousTicks = (used, total) }
        guard let previous = previousTicks else { return }

        let usedDelta = Double(used &- previous.used)
        let totalDelta = Double(total &- previous.total)
        guard totalDelta > 0 else { return }

        cpuUsage = min(max(usedDelta / totalDelta, 0), 1)
    }

    // MARK: - Memory

    private func readMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        // "Used" the way Activity Monitor counts it: everything but free and
        // speculative, with purgeable pages given back.
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return }

        memoryUsedBytes = used
        memoryUsage = min(max(Double(used) / Double(total), 0), 1)
    }

    // MARK: - Disk

    private func readDisk() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
        ]) else { return }

        let free = values.volumeAvailableCapacityForImportantUsage ?? 0
        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return }

        diskFreeBytes = free
        diskUsage = min(max(Double(total - free) / Double(total), 0), 1)
    }

    // MARK: - Formatting

    var cpuText: String { "\(Int(round(cpuUsage * 100)))%" }
    var memoryText: String { "\(Int(round(memoryUsage * 100)))%" }
    var diskFreeText: String { formattedFileSize(diskFreeBytes) }
}
