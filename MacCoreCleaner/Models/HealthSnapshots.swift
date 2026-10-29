import Foundation

/// Battery reading (IOKit power sources). `isPresent == false` on desktops.
struct BatterySnapshot: Equatable {
    var isPresent: Bool
    var percentage: Int          // 0...100
    var isCharging: Bool
    var isPluggedIn: Bool
    var cycleCount: Int?
    var health: String?          // condition, e.g. "Normal"
    var timeToEmptyMinutes: Int? // nil if charging/unknown
    var timeToFullMinutes: Int? = nil
    var electrical: BatteryElectrical = .init()

    var localizedHealth: String? {
        guard let health else { return nil }
        switch health {
        case "Good", "Normal": return tr("battery.normal")
        case "Fair": return tr("battery.limited")
        case "Poor", "Check Battery", "Permanent Battery Failure": return tr("battery.service")
        default: return health
        }
    }

    static let none = BatterySnapshot(isPresent: false, percentage: 0, isCharging: false, isPluggedIn: true, cycleCount: nil, health: nil, timeToEmptyMinutes: nil)
}

/// Network throughput sample (bytes/sec) plus cumulative counters.
struct NetworkSnapshot: Equatable {
    var downBytesPerSec: Double
    var upBytesPerSec: Double
    var totalDownBytes: Int64
    var totalUpBytes: Int64
    var primaryInterface: String
    var interfaces: [NetworkInterfaceSnapshot] = []

    static let empty = NetworkSnapshot(downBytesPerSec: 0, upBytesPerSec: 0, totalDownBytes: 0, totalUpBytes: 0, primaryInterface: "—")
}

struct NetworkInterfaceSnapshot: Equatable, Identifiable {
    var id: String
    var receivedBytes: Int64
    var sentBytes: Int64
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
}

/// Composite Mac health score (0...100) with a qualitative label and the
/// component breakdown that produced it (transparency).
struct HealthScore: Equatable {
    var score: Int               // 0...100
    var components: [Component]

    struct Component: Equatable, Identifiable {
        var id: String { name }
        var name: String
        var usageFraction: Double // 0...1, for the breakdown bar
        var detail: String
    }

    /// Localized status word shown above the score.
    var word: String {
        switch score {
        case ..<50: return tr("health.poor.word")
        case ..<70: return tr("health.fair.word")
        case ..<85: return tr("health.good.word")
        default:    return tr("health.excellent.word")
        }
    }

    /// Localized caption.
    var caption: String {
        switch score {
        case ..<50: return tr("health.poor.cap")
        case ..<70: return tr("health.fair.cap")
        case ..<85: return tr("health.good.cap")
        default:    return tr("health.excellent.cap")
        }
    }

    static let unknown = HealthScore(score: 0, components: [])

    private static func lerp(_ x: Double, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double) -> Double {
        if x <= x0 { return y0 }
        if x >= x1 { return y1 }
        return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    }

    /// Disk health: full marks until the disk gets genuinely tight (free space
    /// only matters when used climbs past ~70%).
    private static func diskScore(_ used: Double) -> Double {
        switch used {
        case ..<0.60: return lerp(used, 0.0, 0.60, 100, 92)
        case ..<0.80: return lerp(used, 0.60, 0.80, 92, 72)
        case ..<0.90: return lerp(used, 0.80, 0.90, 72, 45)
        default:      return lerp(used, 0.90, 1.00, 45, 8)
        }
    }

    /// Memory health is driven by the OS pressure level (macOS intentionally keeps
    /// RAM ~full as cache, so raw "used %" is not a health signal), nudged by swap.
    private static func memoryScore(_ memory: MemorySnapshot) -> Double {
        let base: Double
        switch memory.pressure {
        case .normal: base = 95
        case .warning: base = 62
        case .critical: base = 28
        }
        let gb = Double(memory.swapUsedBytes) / 1_073_741_824
        let swapPenalty = min(gb * 8, 25) // up to -25 for heavy swap
        return max(base - swapPenalty, 5)
    }

    /// CPU health: momentary spikes are fine; only sustained high usage hurts.
    private static func cpuScore(_ usage: Double) -> Double {
        switch usage {
        case ..<0.50: return lerp(usage, 0.0, 0.50, 100, 90)
        case ..<0.75: return lerp(usage, 0.50, 0.75, 90, 72)
        case ..<0.90: return lerp(usage, 0.75, 0.90, 72, 50)
        default:      return lerp(usage, 0.90, 1.00, 50, 30)
        }
    }

    /// Compute a realistic weighted score from disk / memory / cpu readings.
    /// A typical healthy Mac (moderate disk, normal memory pressure) scores ~90.
    static func compute(disk: DiskSnapshot, memory: MemorySnapshot, cpu: CPUSnapshot) -> HealthScore {
        // A failed disk read (totalBytes == 0) must not score as a pristine 0% disk.
        let diskKnown = disk.totalBytes > 0
        let dScore = diskKnown ? diskScore(disk.usedFraction) : 80
        let mScore = memoryScore(memory)
        let cScore = cpuScore(cpu.totalUsage)

        let weighted: Double = dScore * 0.45 + mScore * 0.35 + cScore * 0.20
        let total: Int = Int(weighted.rounded())

        return HealthScore(
            score: min(max(total, 0), 100),
            components: [
                .init(name: tr("health.comp.storage"), usageFraction: disk.usedFraction,
                      detail: diskKnown ? tr("health.used", ByteFormat.percent(disk.usedFraction)) : tr("health.unavailable")),
                .init(name: tr("health.comp.memory"), usageFraction: memory.usedFraction,
                      detail: tr("health.pressureDetail", memory.pressure.title)),
                .init(name: tr("health.comp.cpu"), usageFraction: cpu.totalUsage,
                      detail: tr("health.used", ByteFormat.percent(cpu.totalUsage))),
            ]
        )
    }
}
