import Foundation
import Combine

/// Drives the memory monitor screen: live RAM readings plus the heaviest
/// processes, with a confirm-gated terminate suggestion.
///
/// This view-model never purges or "frees" memory directly — macOS manages RAM
/// far better than a manual purge ever could. Instead it surfaces the heaviest
/// app and lets the user choose to quit it (always behind a confirmation alert).
@MainActor
final class MemoryMonitorViewModel: ObservableObject {
    /// The most recent memory snapshot.
    @Published var memory: MemorySnapshot = .empty
    /// Top processes ordered by resident memory (largest first).
    @Published var topByMemory: [ProcessSample] = []
    /// The process awaiting a terminate confirmation, if any.
    @Published var terminateTarget: ProcessSample? = nil

    private let services: AppServices

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    /// The heaviest process owned by the current user — the only process we can
    /// realistically suggest quitting safely.
    var heaviestApp: ProcessSample? {
        topByMemory.first(where: { $0.isOwnedByCurrentUser })
    }

    /// Refresh the memory snapshot and the heaviest-process list.
    func refresh() async {
        memory = await services.processMonitor.sampleMemory()
        topByMemory = await services.processMonitor.topMemoryProcesses(limit: 12)
    }

    /// Stage a process for termination (shows the confirmation alert).
    func requestTerminate(_ p: ProcessSample) {
        terminateTarget = p
    }

    /// Confirm and perform the staged termination (graceful, non-forced), then
    /// clear the target and refresh.
    func confirmTerminate() {
        if let p = terminateTarget {
            _ = services.processMonitor.terminate(pid: p.pid, force: false)
        }
        terminateTarget = nil
        Task { await refresh() }
    }

    func cancelTerminate() {
        terminateTarget = nil
    }
}
