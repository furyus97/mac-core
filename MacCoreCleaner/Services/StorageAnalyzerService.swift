import Foundation

/// Reads volume capacity and produces a cheap, approximate estimate of how much
/// space can typically be reclaimed by cleaning common cache/log/trash roots.
final class StorageAnalyzerService: StorageAnalyzing {

    init() {}

    /// Synchronous, cheap read of the root volume's capacity.
    /// Returns ``DiskSnapshot/unknown`` if the resource values cannot be read.
    func diskSnapshot() -> DiskSnapshot {
        let rootURL = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]

        guard let values = try? rootURL.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            return .unknown
        }

        // Prefer the "important usage" figure (matches what Finder/About-this-Mac
        // report as free), falling back to the plain available capacity.
        let free: Int64
        if let important = values.volumeAvailableCapacityForImportantUsage {
            free = important
        } else if let available = values.volumeAvailableCapacity {
            free = Int64(available)
        } else {
            return .unknown
        }

        let name = values.volumeName ?? "Macintosh HD"
        return DiskSnapshot(volumeName: name,
                            totalBytes: Int64(total),
                            freeBytes: free)
    }

    /// Approximate the space reclaimable by cleaning the common cache/log/trash
    /// roots. Runs off the main thread and skips roots that do not exist.
    func quickReclaimableEstimate() async -> Int64 {
        let task = Task.detached(priority: .userInitiated) {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let roots: [URL] = [
                home.appendingPathComponent("Library/Caches", isDirectory: true),
                home.appendingPathComponent("Library/Logs", isDirectory: true),
                home.appendingPathComponent(".Trash", isDirectory: true),
                home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            ]

            var total: Int64 = 0
            for root in roots {
                if Task.isCancelled { break }
                guard FileScanner.exists(root) else { continue }
                let size = FileScanner.recursiveSize(of: root, isCancelled: { Task.isCancelled })
                total += size
            }
            return total
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }
}
