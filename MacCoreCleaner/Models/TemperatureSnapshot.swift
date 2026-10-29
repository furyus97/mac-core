import Foundation

/// Which temperature the user wants surfaced on the Dashboard.
enum TemperatureSource: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, battery, average, max
    var id: String { rawValue }
    /// Localization key for the picker label.
    var titleKey: String { "temp.src.\(rawValue)" }
}

/// One named hardware temperature sensor reading (°C).
struct TemperatureReading: Identifiable, Hashable {
    let name: String
    let celsius: Double
    var sensorID: String = ""
    var channel: Int? = nil
    var id: String { sensorID.isEmpty ? name : sensorID }
    var displayName: String { channel.map { "\(name) · \($0)" } ?? name }
    var canPin: Bool { !id.hasPrefix("hid:session:") }
}

/// A point-in-time temperature reading with pre-computed groupings, so the UI can
/// switch sources without re-reading sensors.
struct TemperatureSnapshot: Equatable {
    var cpu: Double?
    var gpu: Double?
    var battery: Double?
    var average: Double?
    var maxValue: Double?
    var sensorCount: Int
    var readings: [TemperatureReading] = []

    static let none = TemperatureSnapshot(cpu: nil, gpu: nil, battery: nil, average: nil, maxValue: nil, sensorCount: 0)

    /// Any temperature at all available on this Mac?
    var isAvailable: Bool { average != nil || battery != nil }

    /// Never substitute a different sensor for a named source.
    func value(for source: TemperatureSource) -> Double? {
        switch source {
        case .cpu: return cpu
        case .gpu: return gpu
        case .battery: return battery
        case .average: return average
        case .max: return maxValue
        }
    }

    /// Formatted "45°C" or nil.
    func formatted(for source: TemperatureSource) -> String? {
        guard let v = value(for: source) else { return nil }
        return ByteFormat.temperature(v)
    }
}
