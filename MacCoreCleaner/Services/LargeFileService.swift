import Foundation

/// Finds large files across the user's media/document folders for the Large Files
/// screen. Read-only: it only discovers candidates — removal is always handled by
/// `CleanerService` after explicit user review and confirmation.
///
/// The enumeration runs entirely off the main thread, skips hidden files and the
/// contents of packages (e.g. `.app`, `.photoslibrary`), and tolerates unreadable
/// entries so a single permission error never aborts the whole scan.
final class LargeFileService: LargeFileScanning {

    init() {}

    /// User folders worth scanning for big files. Missing folders are skipped.
    private static let rootSubpaths: [String] = [
        "Downloads", "Desktop", "Documents", "Movies", "Music", "Pictures",
    ]

    /// Hard cap so the UI stays responsive even on very large home folders.
    private static let maxResults = 500

    func scan(roots requestedRoots: [URL]?, minBytes: Int64, progress: @escaping (ScanProgress) -> Void) async -> [CleanableItem] {
        let task = Task.detached(priority: .userInitiated) { [requestedRoots] () -> [CleanableItem] in
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser

            let candidateRoots = requestedRoots ?? Self.rootSubpaths
                .map { home.appendingPathComponent($0, isDirectory: true) }
            let roots: [URL] = candidateRoots.filter { FileScanner.exists($0) }

            guard !roots.isEmpty else {
                progress(ScanProgress(fractionCompleted: 1, phase: "", currentPath: nil))
                return []
            }

            let resourceKeys: [URLResourceKey] = [
                .fileSizeKey,
                .totalFileAllocatedSizeKey,
                .isRegularFileKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
            ]
            let resourceKeySet = Set(resourceKeys)

            var items: [CleanableItem] = []
            let total = Double(roots.count)

            for (index, root) in roots.enumerated() {
                if Task.isCancelled { break }

                progress(ScanProgress(
                    fractionCompleted: Double(index) / total,
                    phase: root.lastPathComponent,
                    currentPath: root.path(percentEncoded: false)
                ))

                guard let enumerator = fm.enumerator(
                    at: root,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, _ in true }
                ) else { continue }

                while let fileURL = enumerator.nextObject() as? URL {
                    if Task.isCancelled { break }

                    guard let values = try? fileURL.resourceValues(forKeys: resourceKeySet),
                          values.isRegularFile == true else { continue }

                    let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                    guard size >= minBytes else { continue }

                    items.append(CleanableItem(
                        url: fileURL,
                        sizeBytes: size,
                        modifiedDate: values.contentModificationDate,
                        accessedDate: values.contentAccessDate,
                        safety: .caution,
                        categoryID: .largeFile,
                        isDirectory: false,
                        isSelected: false
                    ))
                }
            }

            progress(ScanProgress(fractionCompleted: 1, phase: "", currentPath: nil))

            if Task.isCancelled { return [] }

            return Array(items.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(Self.maxResults))
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }
}
