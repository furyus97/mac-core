import Foundation

/// Shared, cancellable filesystem helpers used by all scan services.
/// All work is synchronous but cheap to call inside a background `Task`; pass an
/// `isCancelled` closure so long enumerations stop promptly when the user cancels.
enum FileScanner {

    struct Metadata {
        var sizeBytes: Int64
        var modified: Date?
        var accessed: Date?
        var isDirectory: Bool
        var isPackage: Bool
    }

    private static let metadataKeys: Set<URLResourceKey> = [
        .fileSizeKey, .totalFileAllocatedSizeKey,
        .contentModificationDateKey, .contentAccessDateKey,
        .isDirectoryKey, .isRegularFileKey, .isPackageKey,
    ]

    /// Lightweight metadata for a single item (does not recurse into directories).
    static func metadata(for url: URL) -> Metadata {
        let values = try? url.resourceValues(forKeys: metadataKeys)
        let isDir = values?.isDirectory ?? false
        let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        return Metadata(
            sizeBytes: size,
            modified: values?.contentModificationDate,
            accessed: values?.contentAccessDate,
            isDirectory: isDir,
            isPackage: values?.isPackage ?? false
        )
    }

    /// Total size on disk of a file or (recursively) a directory tree. Recurses
    /// into packages too (e.g. `.app` bundles), so an app's true size is counted.
    /// Symlinked directories are not traversed, so cycles are impossible.
    static func recursiveSize(of url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        let meta = metadata(for: url)
        guard meta.isDirectory else { return meta.sizeBytes }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true } // skip unreadable entries, keep going
        ) else {
            return meta.sizeBytes
        }

        for case let fileURL as URL in enumerator {
            if isCancelled() { break }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Immediate children of a directory (one level deep). Returns `[]` if the
    /// directory is missing or unreadable (e.g., permission denied → skip).
    static func topLevelItems(in directory: URL, includeHidden: Bool = true) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions =
            includeHidden ? [] : [.skipsHiddenFiles]
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(metadataKeys),
            options: options
        )
        return contents ?? []
    }

    /// True if a path exists on disk.
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
