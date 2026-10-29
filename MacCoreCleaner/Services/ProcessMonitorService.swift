import Foundation
import Darwin

/// Samples CPU, memory and the process table for the activity monitors.
///
/// All sampling is implemented with low-level Mach / `sysctl` calls and the
/// `/bin/ps` tool. CPU usage is computed as a delta between successive calls, so
/// the previous per-core tick counts are retained on the instance. Every Mach
/// allocation is balanced with a matching `vm_deallocate`, and all failures
/// degrade gracefully to the corresponding `.empty` snapshot (or `[]`).
final class ProcessMonitorService: ProcessMonitoring {

    /// Previous per-core CPU tick counts, kept so each `sampleCPU` call can
    /// compute the delta since the last call. `nil` until the first sample.
    /// Stored layout: `[core0.user, core0.system, core0.idle, core0.nice, core1.user, ...]`.
    private var previousTicks: [UInt32]?
    private let cpuLock = NSLock()

    init() {}

    // MARK: - CPU

    func sampleCPU() async -> CPUSnapshot {
        return readCPU()
    }

    /// Reads per-core CPU load via `host_processor_info` and returns the usage
    /// delta since the previous call. The first call (no previous reading) is
    /// treated as a baseline and returns `.empty`.
    private func readCPU() -> CPUSnapshot {
        cpuLock.lock()
        defer { cpuLock.unlock() }
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )

        guard result == KERN_SUCCESS, let info = infoArray, cpuCount > 0 else {
            return .empty
        }

        // Always release the kernel-allocated buffer before returning.
        defer {
            let size = vm_size_t(UInt(infoCount) * UInt(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        let cores = Int(cpuCount)
        let ticksPerCore = Int(CPU_STATE_MAX) // user, system, idle, nice

        // Flatten the readings into a stable `[UInt32]` layout we can persist.
        var current = [UInt32](repeating: 0, count: cores * ticksPerCore)
        for core in 0..<cores {
            let base = core * ticksPerCore
            current[base + 0] = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            current[base + 1] = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            current[base + 2] = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            current[base + 3] = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
        }

        // First reading: store baseline, report empty.
        guard let previous = previousTicks, previous.count == current.count else {
            previousTicks = current
            return CPUSnapshot(
                totalUsage: 0,
                userUsage: 0,
                systemUsage: 0,
                idle: 1,
                coreUsages: [Double](repeating: 0, count: cores),
                coreCount: cores
            )
        }

        previousTicks = current

        var coreUsages = [Double](repeating: 0, count: cores)
        var totalUser: Double = 0
        var totalSystem: Double = 0
        var totalNice: Double = 0
        var totalIdle: Double = 0

        for core in 0..<cores {
            let base = core * ticksPerCore
            let dUser = Double(current[base + 0] &- previous[base + 0])
            let dSystem = Double(current[base + 1] &- previous[base + 1])
            let dIdle = Double(current[base + 2] &- previous[base + 2])
            let dNice = Double(current[base + 3] &- previous[base + 3])

            let busy = dUser + dSystem + dNice
            let total = busy + dIdle

            coreUsages[core] = total > 0 ? min(1.0, max(0.0, busy / total)) : 0

            totalUser += dUser
            totalSystem += dSystem
            totalNice += dNice
            totalIdle += dIdle
        }

        let aggregateTotal = totalUser + totalSystem + totalNice + totalIdle
        let userFraction = aggregateTotal > 0 ? totalUser / aggregateTotal : 0
        let systemFraction = aggregateTotal > 0 ? (totalSystem + totalNice) / aggregateTotal : 0
        let idleFraction = aggregateTotal > 0 ? totalIdle / aggregateTotal : 1
        let totalUsage = cores > 0 ? coreUsages.reduce(0, +) / Double(cores) : 0

        return CPUSnapshot(
            totalUsage: min(1.0, max(0.0, totalUsage)),
            userUsage: min(1.0, max(0.0, userFraction)),
            systemUsage: min(1.0, max(0.0, systemFraction)),
            idle: min(1.0, max(0.0, idleFraction)),
            coreUsages: coreUsages,
            coreCount: cores
        )
    }

    // MARK: - Memory

    func sampleMemory() async -> MemorySnapshot {
        return readMemory()
    }

    private func readMemory() -> MemorySnapshot {
        let total = Int64(ProcessInfo.processInfo.physicalMemory)

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS, total > 0 else {
            return .empty
        }

        let page = Int64(vm_kernel_page_size)

        let wired = Int64(stats.wire_count) * page
        let active = Int64(stats.active_count) * page
        let inactive = Int64(stats.inactive_count) * page
        let compressed = Int64(stats.compressor_page_count) * page
        let free = Int64(stats.free_count) * page

        // App memory: internal pages minus purgeable, falling back to active.
        let internalBytes = Int64(stats.internal_page_count) * page
        let purgeableBytes = Int64(stats.purgeable_count) * page
        let appBytes = internalBytes > purgeableBytes ? (internalBytes - purgeableBytes) : active

        // Cached files: external (file-backed) pages, falling back to inactive.
        let externalBytes = Int64(stats.external_page_count) * page
        let cachedBytes = externalBytes > 0 ? externalBytes : inactive

        // Activity-Monitor style "Memory Used".
        let usedBytes = wired + active + compressed
        let freeBytes = free

        let swapUsedBytes = readSwapUsed()

        let usedFraction = total > 0 ? Double(usedBytes) / Double(total) : 0
        let twoGigabytes: Int64 = 2_147_483_648

        // Prefer the OS's real memory-pressure level; fall back to a heuristic.
        // (macOS keeps RAM nearly full as cache, so raw "used %" is a poor signal.)
        let pressure: MemoryPressure = Self.readPressureLevel() ?? {
            if swapUsedBytes > twoGigabytes || usedFraction > 0.92 { return .critical }
            if swapUsedBytes > twoGigabytes / 4 || usedFraction > 0.85 { return .warning }
            return .normal
        }()

        return MemorySnapshot(
            totalBytes: total,
            usedBytes: usedBytes,
            freeBytes: freeBytes,
            activeBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            appBytes: appBytes,
            cachedBytes: cachedBytes,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    /// Reads the OS memory-pressure level (`kern.memorystatus_vm_pressure_level`).
    /// Values: 1 = normal, 2 = warning, 4 = critical. Returns nil on failure.
    private static func readPressureLevel() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        switch level {
        case 4: return .critical
        case 2: return .warning
        case 1: return .normal
        default: return nil
        }
    }

    /// Reads the used swap bytes from the `vm.swapusage` sysctl. Returns 0 on failure.
    private func readSwapUsed() -> Int64 {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        let result = sysctlbyname("vm.swapusage", &usage, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Int64(usage.xsu_used)
    }

    // MARK: - Processes

    func topProcesses(limit: Int) async -> [ProcessSample] {
        await rankedProcesses(limit: limit, sortByMemory: false)
    }

    func topMemoryProcesses(limit: Int) async -> [ProcessSample] {
        await rankedProcesses(limit: limit, sortByMemory: true)
    }

    private func rankedProcesses(limit: Int, sortByMemory: Bool) async -> [ProcessSample] {
        guard limit > 0 else { return [] }
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> [ProcessSample] in
            guard let self else { return [] }
            return self.readProcesses(limit: limit, sortByMemory: sortByMemory)
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    private func readProcesses(limit: Int, sortByMemory: Bool) -> [ProcessSample] {
        let psPath = "/bin/ps"
        guard FileManager.default.isExecutableFile(atPath: psPath) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: psPath)
        process.arguments = ["-axo", "pid=,pcpu=,rss=,user=,comm="]
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let output = Self.readAll(from: pipe)
        process.waitUntilExit()

        guard let text = String(data: output, encoding: .utf8) else { return [] }

        let currentUser = NSUserName()
        var samples: [ProcessSample] = []

        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 5 else { continue }

            guard
                let pid = Int32(fields[0]),
                let cpuPercent = Double(fields[1]),
                let rssKB = Int64(fields[2])
            else { continue }

            let user = String(fields[3])
            // Everything from field 4 onward is the command (may contain spaces).
            let commandPath = fields[4...].joined(separator: " ")
            guard !commandPath.isEmpty else { continue }

            let name = (commandPath as NSString).lastPathComponent
            let displayName = name.isEmpty ? commandPath : name

            samples.append(
                ProcessSample(
                    pid: pid,
                    name: displayName,
                    cpuPercent: cpuPercent,
                    memoryBytes: rssKB * 1024,
                    isOwnedByCurrentUser: user == currentUser
                )
            )
        }

        samples.sort { lhs, rhs in
            if sortByMemory {
                if lhs.memoryBytes != rhs.memoryBytes {
                    return lhs.memoryBytes > rhs.memoryBytes
                }
                return lhs.cpuPercent > rhs.cpuPercent
            } else {
                if lhs.cpuPercent != rhs.cpuPercent {
                    return lhs.cpuPercent > rhs.cpuPercent
                }
                return lhs.memoryBytes > rhs.memoryBytes
            }
        }

        // Enrich only the visible top-N with thread counts (cheap libproc call).
        return samples.prefix(limit).map { sample in
            var enriched = sample
            enriched.threadCount = Self.threadCount(for: sample.pid)
            return enriched
        }
    }

    /// Live thread count for a pid via libproc. Returns 0 if unavailable.
    private static func threadCount(for pid: Int32) -> Int {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard written == size else { return 0 }
        return Int(info.pti_threadnum)
    }

    /// Reads all available data from a pipe's read end until EOF.
    private static func readAll(from pipe: Pipe) -> Data {
        var data = Data()
        let handle = pipe.fileHandleForReading
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    // MARK: - Termination

    func terminate(pid: Int32, force: Bool) -> Bool {
        guard pid > 1, pid != getpid(), Self.ownerUID(for: pid) == getuid() else { return false }
        let signal = force ? SIGKILL : SIGTERM
        return kill(pid, signal) == 0
    }

    private static func ownerUID(for pid: Int32) -> uid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard written == size else { return nil }
        return info.pbi_uid
    }
}
