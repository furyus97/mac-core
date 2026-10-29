import Foundation

/// Optional values stay unknown when the hardware does not publish them.
struct BatteryElectrical: Equatable {
    var voltage: Double?
    var current: Double?
    var temperature: Double?
    var currentCapacity: Int?
    var maximumCapacity: Int?
    var designCapacity: Int?
    var adapterRatedWatts: Double?
    var adapterCurrentLimit: Double?
    var inputVoltage: Double?
    var inputCurrent: Double?
    var inputWatts: Double?
    var systemWatts: Double?

    /// Signed battery-terminal power, calculated from measured V × A.
    /// Positive = charging; negative = discharging; not whole-Mac consumption.
    var batteryWatts: Double? {
        guard let voltage, let current else { return nil }
        return voltage * current
    }
    var capacityRatio: Double? {
        guard let maximumCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Double(maximumCapacity) / Double(designCapacity)
    }

    static func parse(_ properties: [String: Any], adapter: [String: Any] = [:], pluggedIn: Bool) -> Self {
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = properties["PowerTelemetryData"] as? [String: Any] ?? [:]
        let registryAdapter = properties["AdapterDetails"] as? [String: Any] ?? [:]
        func number(_ value: Any?, scale: Double = 1, range: ClosedRange<Double>) -> Double? {
            guard let n = value as? NSNumber else { return nil }
            let result = n.doubleValue / scale
            return result.isFinite && range.contains(result) ? result : nil
        }
        func capacity(_ key: String, alternate: String? = nil) -> Int? {
            let raw = properties[key] ?? data[key] ?? alternate.flatMap { data[$0] }
            return number(raw, range: 101...100_000).map(Int.init)
        }
        // IORegistry may encode a signed current as an unsigned 32/64-bit number.
        func signedCurrent(_ raw: Any?) -> Double? {
            guard let value = raw as? NSNumber else { return nil }
            var integer = value.int64Value
            if integer >= 0x80000000 && integer <= 0xffffffff { integer -= 0x100000000 }
            let amps = Double(integer) / 1_000
            return (-100...100).contains(amps) ? amps : nil
        }
        return Self(
            voltage: number(properties["Voltage"], scale: 1_000, range: 1...60),
            current: signedCurrent(properties["InstantAmperage"] ?? properties["Amperage"]),
            temperature: temperatureCelsius(properties["Temperature"]),
            currentCapacity: number(properties["AppleRawCurrentCapacity"] ?? data["AppleRawCurrentCapacity"], range: 0...100_000).map(Int.init),
            maximumCapacity: capacity("AppleRawMaxCapacity", alternate: "FullChargeCapacity"),
            designCapacity: capacity("DesignCapacity"),
            adapterRatedWatts: pluggedIn ? number(adapter["Watts"] ?? registryAdapter["Watts"], range: 1...1_000) : nil,
            adapterCurrentLimit: pluggedIn ? number(adapter["Current"] ?? registryAdapter["Current"], scale: 1_000, range: 0...50) : nil,
            inputVoltage: pluggedIn ? number(telemetry["SystemVoltageIn"], scale: 1_000, range: 1...60) : nil,
            inputCurrent: pluggedIn ? number(telemetry["SystemCurrentIn"], scale: 1_000, range: 0...50) : nil,
            inputWatts: pluggedIn ? number(telemetry["SystemPowerIn"], scale: 1_000, range: 0...1_000) : nil,
            systemWatts: number(telemetry["SystemLoad"], scale: 1_000, range: 0...1_000)
        )
    }

    static func temperatureCelsius(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber else { return nil }
        // AppleSmartBattery publishes centi-degrees Celsius. Do not guess a
        // different unit from an out-of-range value or use lifetime averages.
        let value = number.doubleValue / 100
        return value.isFinite && (-20...100).contains(value) ? value : nil
    }
    static func validMinutes(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 65535 else { return nil }
        return value
    }
}

enum TelemetryFormat {
    static func number(_ value: Double?, unit: String, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.locale(activeLanguage().locale)
            .precision(.fractionLength(digits))) + " " + unit
    }
    static func capacity(_ value: Int?) -> String {
        number(value.map(Double.init), unit: "mAh", digits: 0)
    }
}
