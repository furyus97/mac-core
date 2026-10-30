import Foundation
import CryptoKit
import Darwin

/// One file that is part of a duplicate group.
struct DuplicateFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    /// Logical length in bytes (what is compared and hashed).
    let size: Int64
    /// Modification date recorded at scan time (re-checked before trashing).
    let modified: Date?
    let created: Date?

    var name: String { url.lastPathComponent }
    var path: String { url.path(percentEncoded: false) }
}

/// Files with byte-identical content (same size, same full SHA-256).
struct DuplicateGroup: Identifiable, Hashable, Sendable {
    /// Hex SHA-256 of the content.
    let id: String
    let size: Int64
    /// Sorted with the suggested keeper first (see `DuplicateFinder.keeperOrder`).
    let files: [DuplicateFile]

    var suggestedKeeper: DuplicateFile { files[0] }
    /// Space the extra copies occupy.
    var wastedBytes: Int64 { size * Int64(max(0, files.count - 1)) }
}

struct DuplicateScanProgress: Sendable, Equatable {
    enum Phase: Sendable, Equatable { case collecting, quickHash, fullHash, done }
    var phase: Phase
    /// Candidate files (≥ minimum size) found so far.
    var filesFound: Int
    var filesHashed: Int
    var filesToHash: Int
    var bytesHashed: Int64
    var bytesToHash: Int64

    var fraction: Double {
        switch phase {
        case .collecting: return 0
        case .quickHash: return filesToHash > 0 ? 0.1 + 0.2 * Double(filesHashed) / Double(filesToHash) : 0.1
        case .fullHash: return bytesToHash > 0 ? 0.3 + 0.7 * Double(bytesHashed) / Double(bytesToHash) : 0.3
        case .done: return 1
        }
    }

    static let idle = DuplicateScanProgress(phase: .collecting, filesFound: 0, filesHashed: 0, filesToHash: 0, bytesHashed: 0, bytesToHash: 0)
}

struct DuplicateScanResult: Sendable {
    /// Sorted by wasted bytes, largest first.
    var groups: [DuplicateGroup]
    /// Candidate files examined (≥ minimum size).
    var filesScanned: Int
    /// The file bound was reached; some files were not examined.
    var truncated: Bool
    var cancelled: Bool

    var wastedBytes: Int64 { groups.reduce(0) { $0 + $1.wastedBytes } }
}

/// Finds byte-identical files. Read-only; removal goes through `trash(...)`,
/// which re-verifies every file and then hands off to `CleanerService`
/// (Trash only, `.userFiles` safety scope).
///
/// Pipeline: enumerate regular files ≥ `minimumSize` (skipping hidden files,
/// packages, symlinks, iCloud placeholders and `~/Library`) → group by size →
/// SHA-256 of the first 64 KB → full streamed SHA-256.
enum DuplicateFinder {
    static let minimumSize: Int64 = 1_000_000
    static let maxFiles = 200_000
    static let maxVisitedEntries = 5_000_000
    static let quickHashLength = 64 * 1024
    private static let chunkSize = 1 << 20
    /// `SF_DATALESS`: an iCloud/File Provider placeholder whose bytes aren't local.
    private static let datalessFlag: UInt32 = 0x4000_0000

    /// Default scan roots inside `home` (missing folders are dropped by `scan`).
    static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["Downloads", "Documents", "Desktop", "Pictures", "Movies", "Music"].map {
            home.appending(path: $0, directoryHint: .isDirectory)
        }
    }

    /// Scans `roots` for duplicate files. Cancellable; when cancelled the result
    /// has `cancelled == true` and no groups.
    static func scan(
        roots: [URL],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        minimumSize: Int64 = minimumSize,
        maxFiles: Int = maxFiles,
        progress: (@Sendable (DuplicateScanProgress) -> Void)? = nil
    ) async -> DuplicateScanResult {
        let task = Task.detached(priority: .userInitiated) { () -> DuplicateScanResult in
            run(roots: roots, home: home, minimumSize: max(1, minimumSize), maxFiles: max(1, maxFiles), progress: progress)
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    // MARK: - Pipeline

    private struct Candidate {
        let url: URL
        let size: Int64
        let modified: Date?
        let created: Date?
    }

    private final class Reporter {
        let callback: (@Sendable (DuplicateScanProgress) -> Void)?
        var state = DuplicateScanProgress.idle
        private var last: CFAbsoluteTime = 0
        init(_ callback: (@Sendable (DuplicateScanProgress) -> Void)?) { self.callback = callback }
        func emit(force: Bool = false) {
            guard let callback else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if force || now - last > 0.08 { last = now; callback(state) }
        }
    }

    private static func run(
        roots: [URL], home: URL, minimumSize: Int64, maxFiles: Int,
        progress: (@Sendable (DuplicateScanProgress) -> Void)?
    ) -> DuplicateScanResult {
        let reporter = Reporter(progress)
        let cancelled = DuplicateScanResult(groups: [], filesScanned: 0, truncated: false, cancelled: true)

        // 1. Collect candidates.
        reporter.emit(force: true)
        var truncated = false
        let candidates = collect(roots: roots, home: home, minimumSize: minimumSize, maxFiles: maxFiles,
                                 reporter: reporter, truncated: &truncated)
        if Task.isCancelled { return cancelled }

        // 2. Same size.
        let bySize = Dictionary(grouping: candidates, by: \.size).values.filter { $0.count > 1 }

        // 3. Same first 64 KB.
        let quickSet = bySize.flatMap { $0 }
        reporter.state.phase = .quickHash
        reporter.state.filesToHash = quickSet.count
        reporter.state.filesHashed = 0
        reporter.emit(force: true)
        var quickBuckets: [String: [Candidate]] = [:]
        for candidate in quickSet {
            if Task.isCancelled { return cancelled }
            if let hash = sha256Hex(of: candidate.url, maxBytes: quickHashLength) {
                quickBuckets["\(candidate.size):\(hash)", default: []].append(candidate)
            }
            reporter.state.filesHashed += 1
            reporter.emit()
        }
        let quickGroups = quickBuckets.values.filter { $0.count > 1 }

        // 4. Full content hash (files no larger than the quick window are already fully hashed).
        let fullSet = quickGroups.flatMap { $0 }
        reporter.state.phase = .fullHash
        reporter.state.filesToHash = fullSet.count
        reporter.state.filesHashed = 0
        reporter.state.bytesToHash = fullSet.reduce(0) { $0 + $1.size }
        reporter.state.bytesHashed = 0
        reporter.emit(force: true)
        var fullBuckets: [String: [Candidate]] = [:]
        for group in quickGroups {
            for candidate in group {
                if Task.isCancelled { return cancelled }
                let hash = sha256Hex(of: candidate.url, maxBytes: nil) { bytes in
                    reporter.state.bytesHashed += Int64(bytes)
                    reporter.emit()
                }
                if let hash { fullBuckets["\(candidate.size):\(hash)", default: []].append(candidate) }
                reporter.state.filesHashed += 1
                reporter.emit()
            }
        }
        if Task.isCancelled { return cancelled }

        let groups = fullBuckets.compactMap { key, members -> DuplicateGroup? in
            guard members.count > 1 else { return nil }
            let files = members.map { DuplicateFile(url: $0.url, size: $0.size, modified: $0.modified, created: $0.created) }
            let hash = String(key.split(separator: ":").last ?? Substring(key))
            return DuplicateGroup(id: hash, size: members[0].size, files: keeperOrder(files, home: home))
        }
        .sorted { $0.wastedBytes != $1.wastedBytes ? $0.wastedBytes > $1.wastedBytes : $0.files[0].path < $1.files[0].path }

        reporter.state.phase = .done
        reporter.emit(force: true)
        return DuplicateScanResult(groups: groups, filesScanned: candidates.count, truncated: truncated, cancelled: false)
    }

    private static func collect(
        roots: [URL], home: URL, minimumSize: Int64, maxFiles: Int,
        reporter: Reporter, truncated: inout Bool
    ) -> [Candidate] {
        let fm = FileManager.default
        let library = home.appending(path: "Library", directoryHint: .isDirectory).standardizedFileURL.path
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey,
            .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        ]
        let keySet = Set(keys)

        // Normalize roots: existing directories, not inside ~/Library, not nested in another root.
        let normalized = roots.map { $0.standardizedFileURL }
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
                    && !isSameOrInside(url.path, library)
                    && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            }
        var uniqueRoots: [URL] = []
        for url in normalized.sorted(by: { $0.pathComponents.count < $1.pathComponents.count })
        where !uniqueRoots.contains(where: { isSameOrInside(url.path, $0.path) }) {
            uniqueRoots.append(url)
        }

        var seenInodes = Set<FileIdentity>()
        var result: [Candidate] = []
        var visited = 0

        for root in uniqueRoots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited & 0x1FF == 0, Task.isCancelled { return result }
                if visited > maxVisitedEntries || result.count >= maxFiles { truncated = true; return result }
                guard let values = try? url.resourceValues(forKeys: keySet) else { continue }
                if values.isSymbolicLink == true { continue }
                if values.isDirectory == true {
                    if values.isPackage == true || isSameOrInside(url.standardizedFileURL.path, library) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true, values.isPackage != true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize else { continue }

                // Skip iCloud placeholders (reading would download them) and
                // collapse hard links (trashing one frees nothing).
                var info = stat()
                guard lstat(url.path(percentEncoded: false), &info) == 0,
                      (info.st_mode & S_IFMT) == S_IFREG,
                      info.st_flags & datalessFlag == 0 else { continue }
                guard seenInodes.insert(FileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino))).inserted else { continue }

                result.append(Candidate(url: url, size: size,
                                        modified: values.contentModificationDate, created: values.creationDate))
                reporter.state.filesFound = result.count
                reporter.emit()
            }
        }
        return result
    }

    private struct FileIdentity: Hashable { let device: Int64; let inode: UInt64 }

    // MARK: - Hashing

    /// Streamed SHA-256 (hex) of the first `maxBytes` (or the whole file).
    /// Returns `nil` on read errors or cancellation.
    static func sha256Hex(of url: URL, maxBytes: Int? = nil, onBytes: ((Int) -> Void)? = nil) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = maxBytes ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { return nil }
            let wanted = min(chunkSize, remaining)
            let chunk: Data?
            do {
                chunk = try autoreleasepool { try handle.read(upToCount: wanted) }
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
            onBytes?(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keeper

    /// Orders a group so the copy worth keeping comes first: copies outside
    /// Downloads before ones inside it, then the oldest, then the shortest path.
    static func keeperOrder(_ files: [DuplicateFile], home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [DuplicateFile] {
        let downloads = home.appending(path: "Downloads", directoryHint: .isDirectory).standardizedFileURL.path
        func rank(_ f: DuplicateFile) -> (Int, Date, Int, String) {
            (isSameOrInside(f.url.standardizedFileURL.path, downloads) ? 1 : 0,
             f.created ?? f.modified ?? .distantFuture,
             f.path.count,
             f.path)
        }
        return files.sorted { rank($0) < rank($1) }
    }

    // MARK: - Removal

    /// Why `file` must not be trashed now (it changed since the scan), or `nil`.
    static func changeReason(for file: DuplicateFile) -> String? {
        var info = stat()
        guard lstat(file.url.path(percentEncoded: false), &info) == 0 else { return tr("dup.missing") }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return tr("dup.changed") }
        guard Int64(info.st_size) == file.size else { return tr("dup.changed") }
        let values = try? file.url.resourceValues(forKeys: [.contentModificationDateKey])
        if let recorded = file.modified {
            guard let now = values?.contentModificationDate,
                  abs(now.timeIntervalSince(recorded)) < 0.001 else { return tr("dup.changed") }
        }
        return nil
    }

    /// Moves `selected` duplicates to the Trash — never permanently.
    ///
    /// Before anything moves, each file is re-verified (still a regular file with
    /// the scanned size and modification date); changed or missing files are
    /// skipped and reported. A group never loses its last copy: at least one
    /// unselected, unchanged copy must remain, otherwise that group is skipped.
    /// Everything that passes goes through `CleanerService` (`.userFiles` scope,
    /// so `SafetyGuard` re-checks every path).
    static func trash(_ selected: [DuplicateFile], in groups: [DuplicateGroup], cleaner: CleanerService) async -> CleanOutcome {
        var failures: [CleanFailure] = []
        var approved: [CleanableItem] = []
        let selectedURLs = Set(selected.map { $0.url.standardizedFileURL })
        var handled = Set<URL>()

        for group in groups {
            let picked = group.files.filter { selectedURLs.contains($0.url.standardizedFileURL) }
            guard !picked.isEmpty else { continue }
            picked.forEach { handled.insert($0.url.standardizedFileURL) }
            let survivors = group.files.filter { !selectedURLs.contains($0.url.standardizedFileURL) && changeReason(for: $0) == nil }
            guard !survivors.isEmpty else {
                failures += picked.map { CleanFailure(url: $0.url, reason: tr("dup.noSurvivor")) }
                continue
            }
            for file in picked {
                if let reason = changeReason(for: file) {
                    failures.append(CleanFailure(url: file.url, reason: reason))
                    continue
                }
                approved.append(CleanableItem(
                    url: file.url, sizeBytes: file.size, modifiedDate: file.modified,
                    safety: .caution, categoryID: .largeFile, isDirectory: false, isSelected: true
                ))
            }
        }
        // Anything not belonging to a known group is refused outright.
        for file in selected where !handled.contains(file.url.standardizedFileURL) {
            failures.append(CleanFailure(url: file.url, reason: tr("dup.noSurvivor")))
        }

        var outcome = approved.isEmpty
            ? CleanOutcome(mode: .trash)
            : await cleaner.clean(items: approved, mode: .trash, scope: .userFiles)
        outcome.failures = failures + outcome.failures
        return outcome
    }

    // MARK: - Helpers

    static func isSameOrInside(_ path: String, _ directory: String) -> Bool {
        let p = (path as NSString).pathComponents, d = (directory as NSString).pathComponents
        return p.count >= d.count && Array(p.prefix(d.count)) == d
    }
}
