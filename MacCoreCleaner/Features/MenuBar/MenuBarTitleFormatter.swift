import Foundation

@MainActor
enum MenuBarTitleFormatter {
    static func selectedTemperature(_ snapshot: TemperatureSnapshot, settings: SettingsStore) -> Double? {
        if !settings.menuBarSensorID.isEmpty {
            return snapshot.readings.first { $0.id == settings.menuBarSensorID }?.celsius
        }
        return snapshot.value(for: settings.temperatureSource)
    }

    static func value(_ metric: MenuBarMetric, snapshot: MenuBarMonitorSnapshot, settings: SettingsStore) -> String {
        guard snapshot.hasSample else { return "—" }
        switch metric {
        case .cpu: return ByteFormat.percent(snapshot.cpu)
        case .memory:
            return settings.menuBarMemoryBytes ? ByteFormat.string(fromBytes: snapshot.memUsedBytes) : ByteFormat.percent(snapshot.memFraction)
        case .temperature:
            let temperature = snapshot.temperature
            return TelemetryFormat.number(settings.menuBarFahrenheit ? temperature.map { $0 * 9 / 5 + 32 } : temperature,
                                          unit: settings.menuBarFahrenheit ? "°F" : "°C", digits: 0)
        case .diskFree:
            return settings.menuBarDiskPercent ? ByteFormat.percent(snapshot.diskUsedFraction) : ByteFormat.string(fromBytes: snapshot.diskFree)
        case .networkDown: return ByteFormat.networkRate(snapshot.network.downBytesPerSec)
        case .networkUp: return ByteFormat.networkRate(snapshot.network.upBytesPerSec)
        case .battery: return snapshot.battery.isPresent ? ByteFormat.percent(Double(snapshot.battery.percentage) / 100) : "AC"
        case .batteryPower: return TelemetryFormat.number(snapshot.battery.electrical.batteryWatts, unit: "W")
        case .systemPower: return TelemetryFormat.number(snapshot.battery.electrical.systemWatts, unit: "W")
        }
    }

    static func title(snapshot: MenuBarMonitorSnapshot, settings: SettingsStore) -> String {
        settings.menuBarMetrics.map { metric in
            let value = value(metric, snapshot: snapshot, settings: settings)
            let compact = settings.menuBarDisplayStyle == .compact
            let label: String
            switch metric {
            case .cpu: label = compact ? "C" : "CPU"
            case .memory: label = compact ? "M" : "RAM"
            case .temperature: label = compact ? "T" : "TEMP"
            case .diskFree: label = compact ? "D" : settings.menuBarDiskPercent ? "DISK" : "FREE"
            case .networkDown: label = "↓"
            case .networkUp: label = "↑"
            case .battery: label = compact ? "B" : "BAT"
            case .batteryPower: label = compact ? "B⚡" : "BAT⚡"
            case .systemPower: label = compact ? "P" : "SYS"
            }
            // Keep directional arrows even in the values-only style.
            return settings.menuBarDisplayStyle == .valuesOnly && metric != .networkDown && metric != .networkUp
                ? value : label + " " + value
        }.joined(separator: settings.menuBarSeparators ? "  |  " : "  ")
    }

    static var example: MenuBarMonitorSnapshot {
        var sample = MenuBarMonitorSnapshot(cpu: 0.24, memFraction: 0.58, memUsedBytes: 18_560_000_000,
            diskFree: 384_000_000_000, diskUsedFraction: 0.62, temperature: 47, hasSample: true)
        sample.battery = BatterySnapshot(isPresent: true, percentage: 80, isCharging: false,
            isPluggedIn: true, cycleCount: nil, health: nil, timeToEmptyMinutes: nil,
            electrical: BatteryElectrical(voltage: 12.1, current: 0, systemWatts: 21.7))
        return sample
    }
}
