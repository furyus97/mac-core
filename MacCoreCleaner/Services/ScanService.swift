import Foundation

/// Discovers cleanable items for the Storage Cleaner categories
/// (`.userCache`, `.userLogs`, `.trash`, `.downloadsLargeFiles`).
///
/// All filesystem work runs off the main thread inside a detached task so the UI
/// never freezes, and every long enumeration honors `Task.isCancelled`. Each
/// produced item is double-checked against `SafetyGuard` and dropped if it falls
/// outside the allowlist — defense in depth on top of the scan roots themselves.
final class ScanService: Scanning {

    private let safety: SafetyGuard

    init(safety: SafetyGuard) {
        self.safety = safety
    }

    /// Categories this service knows how to scan. Anything else is ignored.
    private static let supported: Set<CleanCategoryID> = [
        .userCache, .userLogs, .trash, .downloadsLargeFiles,
    ]

    func scan(
        categories: [CleanCategoryID],
        progress: @escaping (ScanProgress) -> Void
    ) async -> [CategoryScanResult] {
        // Only keep categories this service handles, preserving caller order.
        let requested = categories.filter { Self.supported.contains($0) }
        guard !requested.isEmpty else { return [] }

        // Read the user's download threshold up front (on the main actor).
        let rawThresholdMB = await MainActor.run {
            AppServices.shared.settings.downloadsThresholdMB
        }
        let thresholdMB = rawThresholdMB > 0 ? rawThresholdMB : 100
        let thresholdBytes = Int64(thresholdMB) * 1_000_000

        let safety = self.safety

        let task = Task.detached(priority: .userInitiated) { () -> [CategoryScanResult] in
            let home = safety.home
            let total = requested.count
            var results: [CategoryScanResult] = []
            results.reserveCapacity(total)

            for (index, id) in requested.enumerated() {
                if Task.isCancelled { break }

                let category = CleanCategory.metadata(for: id)
                let root = Self.rootURL(for: id, home: home)

                // Report progress as we begin this category.
                progress(ScanProgress(
                    fractionCompleted: Double(index) / Double(total),
                    phase: tr("progress.scanningCat", category.title),
                    currentPath: root.path(percentEncoded: false)
                ))

                var items: [CleanableItem]
                if FileScanner.exists(root) {
                    switch id {
                    case .downloadsLargeFiles:
                        items = Self.scanDownloads(
                            root: root,
                            thresholdBytes: thresholdBytes,
                            category: category,
                            safety: safety
                        )
                    default:
                        items = Self.scanTopLevel(
                            root: root,
                            category: category,
                            safety: safety
                        )
                    }
                } else {
                    items = []
                }

                // Largest first.
                items.sort { $0.sizeBytes > $1.sizeBytes }

                results.append(CategoryScanResult(
                    category: category,
                    items: items,
                    isExpanded: false
                ))
            }

            // Final progress tick once everything gathered (or cancelled).
            progress(ScanProgress(
                fractionCompleted: 1.0,
                phase: tr("progress.done"),
                currentPath: nil
            ))

            return results
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    // MARK: - Scanners

    /// One `CleanableItem` per immediate child of `root`.
    private static func scanTopLevel(
        root: URL,
        category: CleanCategory,
        safety: SafetyGuard
    ) -> [CleanableItem] {
        let selected = category.selectedByDefault
        var items: [CleanableItem] = []

        for child in FileScanner.topLevelItems(in: root) {
            if Task.isCancelled { break }
            guard safety.isRemovable(child) else { continue }

            let meta = FileScanner.metadata(for: child)
            let size = FileScanner.recursiveSize(of: child, isCancelled: { Task.isCancelled })

            let item = CleanableItem(
                url: child,
                sizeBytes: size,
                modifiedDate: meta.modified,
                accessedDate: meta.accessed,
                safety: category.defaultSafety,
                categoryID: category.id,
                isDirectory: meta.isDirectory,
                isSelected: selected
            )
            items.append(item)
        }
        return items
    }

    /// Regular files under `root` whose size is at least `thresholdBytes`.
    private static func scanDownloads(
        root: URL,
        thresholdBytes: Int64,
        category: CleanCategory,
        safety: SafetyGuard
    ) -> [CleanableItem] {
        let selected = category.selectedByDefault
        var items: [CleanableItem] = []

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isDirectoryKey,
                .totalFileAllocatedSizeKey, .fileSizeKey,
                .contentModificationDateKey, .contentAccessDateKey,
            ],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true } // skip unreadable entries, keep going
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if Task.isCancelled { break }

            let meta = FileScanner.metadata(for: fileURL)
            // Only regular files (not directories / packages) at or above threshold.
            guard !meta.isDirectory, meta.sizeBytes >= thresholdBytes else { continue }
            guard safety.isRemovable(fileURL) else { continue }

            let item = CleanableItem(
                url: fileURL,
                sizeBytes: meta.sizeBytes,
                modifiedDate: meta.modified,
                accessedDate: meta.accessed,
                safety: category.defaultSafety,
                categoryID: category.id,
                isDirectory: false,
                isSelected: selected
            )
            items.append(item)
        }
        return items
    }

    // MARK: - Roots

    private static func rootURL(for id: CleanCategoryID, home: URL) -> URL {
        switch id {
        case .userCache:
            return home.appending(path: "Library/Caches", directoryHint: .isDirectory)
        case .userLogs:
            return home.appending(path: "Library/Logs", directoryHint: .isDirectory)
        case .trash:
            return home.appending(path: ".Trash", directoryHint: .isDirectory)
        case .downloadsLargeFiles:
            return home.appending(path: "Downloads", directoryHint: .isDirectory)
        default:
            // Unsupported here; callers filter these out beforehand.
            return home
        }
    }
}
