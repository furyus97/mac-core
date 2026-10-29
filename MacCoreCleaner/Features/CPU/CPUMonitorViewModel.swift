import Foundation

/// A point in the rolling CPU usage history (for the live line chart).
struct CPUUsagePoint: Identifiable, Equatable {
    let id: Int
    let usage: Double   // 0...1
}

/// Drives the CPU screen: overall + per-core usage, a rolling usage history for
/// the live chart, top CPU processes, and confirm-gated termination.
@MainActor
final class CPUMonitorViewModel: ObservableObject {

    @Published var cpu: CPUSnapshot = .empty
    @Published var history: [CPUUsagePoint] = []
    @Published var topByCPU: [ProcessSample] = []
    @Published var terminateTarget: ProcessSample?

    /// Number of points kept in the rolling chart window.
    let historyWindow = 60

    private let services: AppServices
    private var tick = 0
    private var seededBaseline = false

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    /// Fast path — CPU usage + chart history only. Cheap Mach call, safe to run
    /// on a tight (~1s) interval for a smooth live graph.
    func refreshCPU() async {
        let snap = await services.processMonitor.sampleCPU()
        cpu = snap

        // The first Mach sample is only a delta baseline (~0) — don't chart it.
        guard seededBaseline else { seededBaseline = true; return }

        if history.isEmpty {
            // Start as a flat line at the current value, then evolve smoothly.
            history = (0..<historyWindow).map { CPUUsagePoint(id: $0, usage: snap.totalUsage) }
            tick = historyWindow
        } else {
            history.append(CPUUsagePoint(id: tick, usage: snap.totalUsage))
            tick += 1
            if history.count > historyWindow {
                history.removeFirst(history.count - historyWindow)
            }
        }
    }

    /// Slow path — the process table (spawns `/bin/ps`). Runs on a longer
    /// interval so it never stutters the live CPU graph.
    func refreshProcesses() async {
        topByCPU = await services.processMonitor.topProcesses(limit: 12)
    }

    func requestTerminate(_ process: ProcessSample) {
        terminateTarget = process
    }

    func confirmTerminate() {
        guard let target = terminateTarget else { return }
        if services.processMonitor.terminate(pid: target.pid, force: false) {
            topByCPU.removeAll { $0.pid == target.pid }
        }
        terminateTarget = nil
    }

    func cancelTerminate() {
        terminateTarget = nil
    }
}
