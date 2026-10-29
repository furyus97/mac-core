import Foundation

/// Value-type format styles avoid mutable shared formatters and honor the app language.
enum ByteFormat {
    /// Network units are technical symbols, never localized words such as
    /// "바이트". Keep decimal separators localized, and avoid lossy Int64 casts.
    static func networkBytes(_ bytes: Double) -> String {
        guard bytes.isFinite else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]
        var value = max(0, bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // Do not display 1000 KB when one-decimal rounding reaches the next unit.
        if unit > 0, (value * 10).rounded() >= 10_000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let text = value.formatted(.number.grouping(.never)
            .precision(.fractionLength(0...(unit == 0 ? 0 : 1)))
            .locale(activeLanguage().locale))
        return text + " " + units[unit]
    }

    static func networkRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite else { return "—" }
        return networkBytes(bytesPerSecond) + "/s"
    }

    static func string(fromBytes bytes: Int64) -> String {
        max(0, bytes).formatted(.byteCount(style: .file,
            allowedUnits: [.kb, .mb, .gb, .tb], spellsOutZero: false)
            .locale(activeLanguage().locale))
    }

    static func percent(_ fraction: Double, decimals: Int = 0) -> String {
        let value = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return value.formatted(.percent.precision(.fractionLength(max(0, min(3, decimals))))
            .locale(activeLanguage().locale))
    }

    /// Per-process CPU can exceed 100% across multiple cores.
    static func processPercent(_ value: Double) -> String {
        (max(0, value.isFinite ? value : 0) / 100).formatted(
            .percent.precision(.fractionLength(1)).locale(activeLanguage().locale))
    }

    static func temperature(_ celsius: Double) -> String {
        guard celsius.isFinite else { return "—" }
        return celsius.formatted(.number.precision(.fractionLength(0))
            .locale(activeLanguage().locale)) + "°C"
    }
}
