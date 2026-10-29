import Foundation

/// Discovers cleanable developer artifacts (Xcode DerivedData / Archives and the
/// CoreSimulator caches) for the Developer Cleaner screen.
///
/// Like the read-only Storage scanner, this service only *describes* what could be
/// removed — it never deletes anything itself; removal is the exclusive job of
/// `CleanerService`. Every produced item is still validated through `SafetyGuard`
/// at scan time, and `CleanerService` re-validates it again immediately before
/// removal, so an item that slips through here can never be deleted unsafely.
///
/// All file work runs off the main thread inside `Task.detached`, honors task
/// cancellation, and fails gracefully (a missing root or an unreadable child is
/// skipped, not fatal).
final class DeveloperCleanerService: DeveloperCleaning {

    private let safety: SafetyGuard

    init(safety: SafetyGuard = SafetyGuard()) {
        self.safety = safety
    }

    /// Scans the requested developer categories and returns one result per
    /// requested category, in the same order they were requested. Items are sorted
    /// by size (largest first) and results start collapsed (`isExpanded == false`).
    func scan(
        categories: [CleanCategoryID],
        progress: @escaping (ScanProgress) -> Void
    ) async -> [CategoryScanResult] {
        let safety = self.safety
        let task = Task.detached(priority: .userInitiated) { () -> [CategoryScanResult] in
            var results: [CategoryScanResult] = []
            let total = max(categories.count, 1)

            for (index, id) in categories.enumerated() {
                if Task.isCancelled { break }

                let category = CleanCategory.metadata(for: id)
                let baseFraction = Double(index) / Double(total)
                progress(ScanProgress(
                    fractionCompleted: baseFraction,
                    phase: tr("progress.scanningCat", category.title),
                    currentPath: nil
                ))

                let items = Self.scanCategory(
                    category,
                    safety: safety,
                    baseFraction: baseFraction,
                    span: 1.0 / Double(total),
                    progress: progress
                )

                results.append(CategoryScanResult(category: category, items: items, isExpanded: false))
            }

            progress(ScanProgress(fractionCompleted: 1.0, phase: tr("progress.done"), currentPath: nil))
            return results
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    // MARK: - Per-category scanning

    /// Filesystem roots scanned for a given developer category, relative to home.
    private static func root(for id: CleanCategoryID, home: URL) -> URL? {
        switch id {
        case .xcodeDerivedData:
            return home.appending(path: "Library/Developer/Xcode/DerivedData", directoryHint: .isDirectory)
        case .xcodeArchives:
            return home.appending(path: "Library/Developer/Xcode/Archives", directoryHint: .isDirectory)
        case .simulatorCache:
            return home.appending(path: "Library/Developer/CoreSimulator/Caches", directoryHint: .isDirectory)
        case .swiftPMCache:
            return home.appending(path: "Library/Caches/org.swift.swiftpm", directoryHint: .isDirectory)
        case .homebrewCache:
            return home.appending(path: "Library/Caches/Homebrew", directoryHint: .isDirectory)
        case .gradleCache:
            return home.appending(path: ".gradle/caches", directoryHint: .isDirectory)
        default:
            return nil
        }
    }

    /// Size of a display-only tool (e.g. Docker) that the app never deletes
    /// itself — only surfaces, per the safety policy. Returns 0 if not installed.
    func displayOnlySize(for id: CleanCategoryID) async -> Int64 {
        let task = Task.detached(priority: .utility) { () -> Int64 in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url: URL
            switch id {
            case .dockerData:
                url = home.appending(path: "Library/Containers/com.docker.docker", directoryHint: .isDirectory)
            default:
                return 0
            }
            guard FileScanner.exists(url) else { return 0 }
            return FileScanner.recursiveSize(of: url, isCancelled: { Task.isCancelled })
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Enumerates the top-level children of a category's root, sizing each one and
    /// dropping anything the safety policy refuses. Returns `[]` when the root is
    /// missing or the category is not a developer category.
    private static func scanCategory(
        _ category: CleanCategory,
        safety: SafetyGuard,
        baseFraction: Double,
        span: Double,
        progress: (ScanProgress) -> Void
    ) -> [CleanableItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let root = Self.root(for: category.id, home: home), FileScanner.exists(root) else {
            return []
        }

        let preselect = category.selectedByDefault
        let children = FileScanner.topLevelItems(in: root, includeHidden: true)
        let childCount = max(children.count, 1)

        var items: [CleanableItem] = []
        items.reserveCapacity(children.count)

        for (offset, child) in children.enumerated() {
            if Task.isCancelled { break }

            // Drop anything outside the safety allowlist — never surface it.
            guard safety.isRemovable(child) else { continue }

            let isCancelled = { Task.isCancelled }
            let meta = FileScanner.metadata(for: child)
            let size = FileScanner.recursiveSize(of: child, isCancelled: isCancelled)

            let item = CleanableItem(
                url: child,
                detail: category.title,
                sizeBytes: size,
                modifiedDate: meta.modified,
                accessedDate: meta.accessed,
                safety: category.defaultSafety,
                categoryID: category.id,
                isDirectory: meta.isDirectory,
                isSelected: preselect
            )
            items.append(item)

            let childFraction = baseFraction + span * (Double(offset + 1) / Double(childCount))
            progress(ScanProgress(
                fractionCompleted: min(childFraction, 1.0),
                phase: tr("progress.scanningCat", category.title),
                currentPath: child.path(percentEncoded: false)
            ))
        }

        // Largest items first so the user sees the biggest wins at the top.
        items.sort { $0.sizeBytes > $1.sizeBytes }
        return items
    }
}
