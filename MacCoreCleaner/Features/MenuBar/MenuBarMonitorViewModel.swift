import Foundation

struct MenuBarMonitorSnapshot {
    var cpu: Double = 0
    var memFraction: Double = 0
    var memUsedBytes: Int64 = 0
    var diskFree: Int64 = 0
    var diskUsedFraction: Double = 0
    var temperature: Double?
    var temperatureSnapshot: TemperatureSnapshot = .none
    var network: NetworkSnapshot = .empty
    var battery: BatterySnapshot = .none
    var hasSample = false
}

/// Drives the menu-bar live monitor. Uses its OWN `ProcessMonitorService` so its
/// delta-based CPU sampling never contends with the main window's samplers. It
/// also owns a NetworkService because network throughput is delta-based too.
@MainActor
final class MenuBarMonitorViewModel: ObservableObject {
    private let monitor = ProcessMonitorService()
    private let networkMonitor = NetworkService()
    private let services: AppServices

    @Published private(set) var snapshot = MenuBarMonitorSnapshot()

    private var monitorTask: Task<Void, Never>?

    init(services: AppServices? = nil, snapshot: MenuBarMonitorSnapshot = .init()) {
        self.services = services ?? .shared
        self.snapshot = snapshot
    }

    /// Starts the sampling loop once (idempotent).
    func startIfNeeded() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                let seconds = self?.services.settings.menuBarRefreshRate.seconds ?? 2.5
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                if self == nil { break }
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func restart() {
        stop()
        startIfNeeded()
    }

    private func tick() async {
        let metrics = Set(services.settings.menuBarMetrics)
        var next = snapshot

        if metrics.contains(.cpu) {
            next.cpu = (await monitor.sampleCPU()).totalUsage
        }
        if metrics.contains(.memory) {
            let memory = await monitor.sampleMemory()
            next.memFraction = memory.usedFraction
            next.memUsedBytes = memory.usedBytes
        }
        if metrics.contains(.diskFree) {
            let disk = services.storage.diskSnapshot()
            next.diskFree = disk.freeBytes
            next.diskUsedFraction = disk.usedFraction
        }
        if metrics.contains(.temperature) {
            let temperatureMonitor = services.temperature
            next.temperatureSnapshot = await Task.detached(priority: .utility) { temperatureMonitor.sample() }.value
            next.temperature = MenuBarTitleFormatter.selectedTemperature(next.temperatureSnapshot, settings: services.settings)
        }
        if metrics.contains(.networkDown) || metrics.contains(.networkUp) {
            next.network = networkMonitor.sample()
        }
        if metrics.contains(.battery) || metrics.contains(.batteryPower) || metrics.contains(.systemPower) {
            let batteryMonitor = services.battery
            next.battery = await Task.detached(priority: .utility) { batteryMonitor.sample() }.value
        }

        guard !Task.isCancelled else { return }
        next.hasSample = true
        snapshot = next
    }
}
