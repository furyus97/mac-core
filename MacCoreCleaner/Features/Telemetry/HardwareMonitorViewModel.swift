import Foundation

struct TelemetryPoint: Identifiable, Equatable {
    var id: Date
    var value: Double
}

@MainActor
final class HardwareMonitorViewModel: ObservableObject {
    @Published var temperature: TemperatureSnapshot = .none
    @Published var battery: BatterySnapshot = .none
    @Published var network: NetworkSnapshot = .empty
    @Published var history: [TelemetryPoint] = []
    @Published var secondaryHistory: [TelemetryPoint] = []
    @Published var ranges: [String: ClosedRange<Double>] = [:]
    @Published var updated: Date?
    private let networkService = NetworkService()

    func resetBaseline() { networkService.resetBaseline() }

    func refresh(_ metric: DashboardMetric) async {
        let now = Date()
        switch metric {
        case .temperature:
            let reading = await Task.detached(priority: .utility) { TemperatureService().sample() }.value
            guard !Task.isCancelled else { return }
            temperature = reading
            for sensor in reading.readings {
                let previous = ranges[sensor.id] ?? sensor.celsius...sensor.celsius
                ranges[sensor.id] = min(previous.lowerBound, sensor.celsius)...max(previous.upperBound, sensor.celsius)
            }
            append(reading.maxValue, to: &history, at: now)
        case .battery:
            let reading = await Task.detached(priority: .utility) { BatteryService().sample() }.value
            guard !Task.isCancelled else { return }
            battery = reading
            append(reading.electrical.batteryWatts, to: &history, at: now)
            append(reading.electrical.systemWatts, to: &secondaryHistory, at: now)
        case .network:
            network = networkService.sample()
            append(network.downBytesPerSec, to: &history, at: now)
            append(network.upBytesPerSec, to: &secondaryHistory, at: now)
        default: break
        }
        updated = now
    }

    private func append(_ value: Double?, to points: inout [TelemetryPoint], at date: Date) {
        // Missing samples break continuity rather than implying a measured zero.
        guard let value, value.isFinite else { points = []; return }
        points.append(.init(id: date, value: value))
        points.removeAll { $0.id < date.addingTimeInterval(-300) }
        if points.count > 120 { points.removeFirst(points.count - 120) }
    }
}
