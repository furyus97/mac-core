import Foundation

/// Protocols decouple the views/view-models from concrete service
/// implementations. The safety-critical services (`CleanerService`,
/// `SafetyGuard`, `PermissionManager`) are concrete; the read-only analysis
/// services are described here and implemented in their own files.

/// Discovers cleanable items for the Storage Cleaner categories.
protocol Scanning {
    /// Scans the requested categories off the main thread, reporting progress.
    /// Returns one result per requested category (empty results included so the
    /// UI can show "0개" rows). Must honor task cancellation.
    func scan(
        categories: [CleanCategoryID],
        progress: @escaping (ScanProgress) -> Void
    ) async -> [CategoryScanResult]
}

/// Discovers cleanable items for the Developer Cleaner categories.
protocol DeveloperCleaning {
    func scan(
        categories: [CleanCategoryID],
        progress: @escaping (ScanProgress) -> Void
    ) async -> [CategoryScanResult]

    /// Size of a display-only tool (e.g. Docker) the app surfaces but never
    /// deletes. Returns 0 when the tool is not installed.
    func displayOnlySize(for id: CleanCategoryID) async -> Int64
}

/// Provides disk capacity and a cheap reclaimable-space estimate for the Dashboard.
protocol StorageAnalyzing {
    func diskSnapshot() -> DiskSnapshot
    /// A fast, approximate estimate of reclaimable space (sizes of cache/log/trash
    /// roots) computed without a full file-by-file scan.
    func quickReclaimableEstimate() async -> Int64
}

/// Lists installed apps and discovers their leftover files (Applications screen).
protocol AppInventory {
    func installedApps() async -> [InstalledApp]
    /// Leftover support files for an app (by bundle id / name), as removable items.
    func leftovers(for app: InstalledApp) async -> [CleanableItem]
}

/// Finds large files in the user's media/document folders (Large Files screen).
protocol LargeFileScanning {
    /// Scans `roots` for files >= `minBytes`. Pass `nil` to scan the default
    /// media/document folders; pass a subset (e.g. Downloads/Desktop) to keep a
    /// Smart Scan fast.
    func scan(roots: [URL]?, minBytes: Int64, progress: @escaping (ScanProgress) -> Void) async -> [CleanableItem]
}

/// Detects browsers and sizes their cache/cookies/history/etc. (Browser screen).
protocol BrowserCleaning {
    func detectBrowsers() async -> [BrowserKind]
    func dataItems(for browsers: [BrowserKind]) async -> [BrowserDataItem]
}

/// Samples CPU, memory and the process table for the monitors.
protocol ProcessMonitoring {
    func sampleCPU() async -> CPUSnapshot
    func sampleMemory() async -> MemorySnapshot
    /// Top processes by CPU, then memory. `limit` caps the returned count.
    func topProcesses(limit: Int) async -> [ProcessSample]
    /// Top processes by resident memory. `limit` caps the returned count.
    func topMemoryProcesses(limit: Int) async -> [ProcessSample]
    /// Sends SIGTERM (or SIGKILL when `force`) to a pid. Returns whether the
    /// signal was delivered. Always invoked only after explicit user confirmation.
    func terminate(pid: Int32, force: Bool) -> Bool
}
