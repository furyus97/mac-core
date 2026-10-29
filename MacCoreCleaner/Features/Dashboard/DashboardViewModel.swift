import Foundation

/// Drives the Dashboard: composite health score, disk / memory / cpu readings,
/// battery, network throughput, reclaimable estimate, top processes, and the
/// one-tap "safe clean" flow. All heavy sampling runs off the main thread in the
/// services; this view-model only publishes results on the main actor.
@MainActor
final class DashboardViewModel: ObservableObject {
    private let services: AppServices

    @Published var disk: DiskSnapshot = .unknown
    @Published var memory: MemorySnapshot = .empty
    @Published var cpu: CPUSnapshot = .empty
    @Published var battery: BatterySnapshot = .none
    @Published var network: NetworkSnapshot = .empty
    @Published var temperature: TemperatureSnapshot = .none
    @Published var health: HealthScore = .unknown
    @Published var reclaimable: Int64 = 0
    @Published var topProcesses: [ProcessSample] = []

    // Rolling telemetry for metric-card sparklines.
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []
    @Published var netHistory: [Double] = []
    private let historyCap = 24

    @Published var isLoading = false
    @Published var isEstimating = false
    @Published var lastUpdated: Date?

    // Safe-clean flow
    @Published var pendingItems: [CleanableItem] = []
    @Published var showConfirm = false
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isPreparingClean = false
    @Published private(set) var isCleaning = false

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    /// Refresh all live metrics. CPU/network are sampled twice with a short gap
    /// so the delta-based readings are meaningful.
    /// Live meters (cards + sparklines). Does NOT touch the health score so the
    /// hero ring stays stable instead of jittering every tick.
    func refreshLive() async {
        _ = await services.processMonitor.sampleCPU()
        _ = services.network.sample()
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }

        let cpuSnap = await services.processMonitor.sampleCPU()
        let memSnap = await services.processMonitor.sampleMemory()
        guard !Task.isCancelled else { return }
        let diskSnap = services.storage.diskSnapshot()

        cpu = cpuSnap
        memory = memSnap
        disk = diskSnap
        network = services.network.sample()
        let batteryMonitor = services.battery
        let temperatureMonitor = services.temperature
        async let batteryReading = Task.detached(priority: .utility) { batteryMonitor.sample() }.value
        async let temperatureReading = Task.detached(priority: .utility) { temperatureMonitor.sample() }.value
        let readings = await (batteryReading, temperatureReading)
        guard !Task.isCancelled else { return }
        battery = readings.0
        temperature = readings.1
        topProcesses = await services.processMonitor.topProcesses(limit: 5)
        guard !Task.isCancelled else { return }

        cpuHistory = appended(cpuHistory, cpuSnap.totalUsage)
        memHistory = appended(memHistory, memSnap.usedFraction)
        netHistory = appended(netHistory, network.downBytesPerSec)
    }

    /// Full refresh — live meters + a (re)computed health score. Used on appear
    /// and the manual refresh button, not the live loop.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await refreshLive()
        health = HealthScore.compute(disk: disk, memory: memory, cpu: cpu)
        lastUpdated = Date()
    }

    private func appended(_ arr: [Double], _ value: Double) -> [Double] {
        var a = arr
        a.append(value)
        if a.count > historyCap { a.removeFirst(a.count - historyCap) }
        return a
    }

    func estimateReclaimable() async {
        isEstimating = true
        defer { isEstimating = false }
        reclaimable = await services.storage.quickReclaimableEstimate()
    }

    func quickScan() async {
        await refresh()
        await estimateReclaimable()
    }

    /// One-tap safe cleanup: scans the always-safe categories and stages them for
    /// confirmation (never deletes without the modal).
    func safeClean() async {
        guard !isPreparingClean, !isCleaning else { return }
        isPreparingClean = true
        defer { isPreparingClean = false }
        let results = await services.scanner.scan(categories: [.userCache, .userLogs], progress: { _ in })
        pendingItems = results.flatMap { $0.items }
        mode = .trash
        if pendingItems.isEmpty {
            lastOutcome = CleanOutcome(removedCount: 0, processedBytes: 0, failures: [], mode: mode)
        } else {
            showConfirm = true
        }
    }

    func confirmClean() async {
        guard !isCleaning else { return }
        isCleaning = true
        showConfirm = false
        defer { isCleaning = false }
        let outcome = await services.cleaner.clean(items: pendingItems, mode: mode)
        lastOutcome = outcome
        pendingItems = []
        await quickScan()
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
    }
}
