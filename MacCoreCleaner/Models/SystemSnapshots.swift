import Foundation
import Darwin

/// Disk capacity for a volume (Dashboard / Storage analysis).
struct DiskSnapshot: Equatable {
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64

    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }
    var usedFraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(usedBytes) / Double(totalBytes))) : 0
    }

    static let unknown = DiskSnapshot(volumeName: "Macintosh HD", totalBytes: 0, freeBytes: 0)
}

/// Memory pressure level, mirroring the OS notion.
enum MemoryPressure: Int, Comparable, Codable {
    case normal = 0
    case warning = 1
    case critical = 2

    static func < (lhs: MemoryPressure, rhs: MemoryPressure) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .normal: return tr("pressure.normal")
        case .warning: return tr("pressure.warning")
        case .critical: return tr("pressure.critical")
        }
    }
}

/// A point-in-time memory reading.
struct MemorySnapshot: Equatable {
    let totalBytes: Int64
    let usedBytes: Int64
    let freeBytes: Int64
    let activeBytes: Int64
    let wiredBytes: Int64
    let compressedBytes: Int64
    let appBytes: Int64
    let cachedBytes: Int64
    let swapUsedBytes: Int64
    let pressure: MemoryPressure

    var usedFraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(usedBytes) / Double(totalBytes))) : 0
    }

    static let empty = MemorySnapshot(
        totalBytes: 0, usedBytes: 0, freeBytes: 0, activeBytes: 0, wiredBytes: 0,
        compressedBytes: 0, appBytes: 0, cachedBytes: 0, swapUsedBytes: 0, pressure: .normal
    )
}

/// A point-in-time CPU reading. Usage values are fractions in 0.0 ... 1.0.
struct CPUSnapshot: Equatable {
    let totalUsage: Double
    let userUsage: Double
    let systemUsage: Double
    let idle: Double
    let coreUsages: [Double]
    let coreCount: Int

    static let empty = CPUSnapshot(
        totalUsage: 0, userUsage: 0, systemUsage: 0, idle: 1, coreUsages: [], coreCount: 0
    )
}

/// A single running process, as shown in the CPU / Memory monitors.
/// Named `ProcessSample` to avoid clashing with Foundation's `ProcessInfo`.
struct ProcessSample: Identifiable, Hashable {
    let pid: Int32
    let name: String
    let cpuPercent: Double      // 0...N*100 across cores, like Activity Monitor
    let memoryBytes: Int64
    let isOwnedByCurrentUser: Bool
    var threadCount: Int = 0

    var id: Int32 { pid }

    var formattedMemory: String { ByteFormat.string(fromBytes: memoryBytes) }

    /// Only user-owned processes other than this app can be offered as quit
    /// targets. The service repeats the ownership check before signaling.
    var canRequestTermination: Bool {
        isOwnedByCurrentUser && pid > 1 && pid != getpid()
    }

    /// Relative energy indicator derived from CPU usage (Apple's true "Energy
    /// Impact" uses private APIs; we surface a transparent CPU-based proxy).
    var energyProxy: Double { cpuPercent }
}
