import Foundation

/// One item on the Space Map: a direct child of the folder being measured.
struct SpaceNode: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    /// Allocated size on disk (recursive for folders and packages).
    let bytes: Int64
    /// `true` only for folders the user can drill into. Packages (`.app`,
    /// `.photoslibrary`, …) are reported as single, non-drillable items.
    let isDirectory: Bool
    /// Optional hint of how much of this item is known to be safely reclaimable
    /// (shown as a coral badge). `nil` when unknown.
    var reclaimableBytes: Int64?

    init(url: URL, name: String? = nil, bytes: Int64, isDirectory: Bool, reclaimableBytes: Int64? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.bytes = bytes
        self.isDirectory = isDirectory
        self.reclaimableBytes = reclaimableBytes
    }
}

/// The measured contents of one folder.
struct SpaceListing: Sendable, Equatable {
    /// Largest direct children, sorted by size (descending), at most `limit`.
    var nodes: [SpaceNode]
    /// Sum of every measured direct child (including the ones beyond `limit`).
    var totalBytes: Int64
    /// Children that did not make the `limit` cut.
    var remainderCount: Int
    var remainderBytes: Int64
    /// `true` when the result is incomplete: cancelled, the entry budget was
    /// exhausted, or some children could not be read.
    var isPartial: Bool

    static let empty = SpaceListing(nodes: [], totalBytes: 0, remainderCount: 0, remainderBytes: 0, isPartial: false)
}

/// Live progress while a folder is being measured. `nodes` grows as each child
/// finishes, so the UI can draw bubbles before the whole folder is done.
struct SpaceMapProgress: Sendable {
    var measuredChildren: Int
    var totalChildren: Int
    var partial: SpaceListing
}

/// Used/free summary of a volume (the startup disk by default).
struct VolumeSummary: Sendable, Equatable {
    var name: String
    var totalBytes: Int64
    var availableBytes: Int64
    var usedBytes: Int64 { max(0, totalBytes - availableBytes) }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

/// Read-only disk-usage measurement for the Space Map. Never modifies anything.
///
///  * Sizes are *allocated* sizes (what the files really occupy on disk).
///  * Symbolic links are skipped (never followed, never counted).
///  * Packages count as one item and are not drillable.
///  * Other mounted volumes inside the tree are not descended into.
///  * Work is cancellable and bounded by an entry budget; when a bound is hit
///    the listing is flagged `isPartial` instead of silently being wrong.
enum SpaceMapService {
    /// The on-disk name (apps without ".app"), so labels follow the app language rather than Finder's.
    static func name(of url: URL) -> String {
        let name = url.lastPathComponent
        return url.pathExtension == "app" ? url.deletingPathExtension().lastPathComponent : name
    }

    /// Max file-system entries visited for one `children(of:)` call.
    static let defaultEntryBudget = 4_000_000
    /// How many children are measured concurrently.
    private static let parallelism = 4

    private static let childKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isVolumeKey,
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]
    private static let walkKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
    ]

    /// The default root: the user's home folder.
    static var defaultRoot: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Largest direct children of `url`, sorted by allocated size.
    static func children(of url: URL, limit: Int = 12) async -> [SpaceNode] {
        await listing(of: url, limit: limit).nodes
    }

    /// Full listing (with remainder / partial flags) of `url`'s direct children.
    /// - Parameters:
    ///   - limit: how many of the largest children to return in `nodes`.
    ///   - entryBudget: upper bound on visited entries (keeps huge trees bounded).
    ///   - progress: invoked (on a background thread) as each child finishes.
    static func listing(
        of url: URL,
        limit: Int = 12,
        entryBudget: Int = defaultEntryBudget,
        progress: (@Sendable (SpaceMapProgress) -> Void)? = nil
    ) async -> SpaceListing {
        let task = Task.detached(priority: .userInitiated) { () -> SpaceListing in
            await measure(url: url, limit: max(1, limit), entryBudget: max(1, entryBudget), progress: progress)
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Used / free space of the volume holding `url` (startup disk by default).
    static func volumeSummary(for url: URL = URL(fileURLWithPath: "/")) -> VolumeSummary? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey, .volumeLocalizedNameKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let available = important > 0 ? important : Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeSummary(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            totalBytes: Int64(total),
            availableBytes: max(0, available)
        )
    }

    // MARK: - Measurement

    private struct ChildEntry: Sendable {
        let url: URL
        let isDrillable: Bool
        let needsWalk: Bool
        let flatBytes: Int64
    }

    private static func measure(
        url: URL,
        limit: Int,
        entryBudget: Int,
        progress: (@Sendable (SpaceMapProgress) -> Void)?
    ) async -> SpaceListing {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: childKeys, options: []
        ) else {
            return SpaceListing(nodes: [], totalBytes: 0, remainderCount: 0, remainderBytes: 0, isPartial: true)
        }

        var entries: [ChildEntry] = []
        for child in contents {
            guard let values = try? child.resourceValues(forKeys: Set(childKeys)) else { continue }
            if values.isSymbolicLink == true { continue }                 // never follow or count links
            let isDir = values.isDirectory == true
            if isDir && values.isVolume == true { continue }               // another mounted volume
            let isPackage = values.isPackage == true
            let flat = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            entries.append(ChildEntry(
                url: child,
                isDrillable: isDir && !isPackage,
                needsWalk: isDir,
                flatBytes: isDir ? 0 : flat
            ))
        }

        let budget = EntryBudget(limit: entryBudget)
        let parent = url.standardizedFileURL
        var measured: [SpaceNode] = []
        var partial = false
        let total = entries.count

        await withTaskGroup(of: (SpaceNode, Bool).self) { group in
            var iterator = entries.makeIterator()
            var running = 0
            func addNext() -> Bool {
                guard let entry = iterator.next() else { return false }
                group.addTask {
                    let (bytes, complete) = entry.needsWalk
                        ? walk(entry.url, budget: budget)
                        : (entry.flatBytes, true)
                    let node = SpaceNode(
                        url: entry.url,
                        name: SpaceMapService.name(of: entry.url),
                        bytes: bytes,
                        isDirectory: entry.isDrillable,
                        reclaimableBytes: reclaimableHint(for: entry.url, parent: parent, bytes: bytes)
                    )
                    return (node, complete)
                }
                return true
            }
            while running < parallelism, addNext() { running += 1 }
            while let result = await group.next() {
                let (node, complete) = result
                running -= 1
                if !complete { partial = true }
                measured.append(node)
                if let progress {
                    progress(SpaceMapProgress(
                        measuredChildren: measured.count,
                        totalChildren: total,
                        partial: summarize(measured, limit: limit, partial: true)
                    ))
                }
                if Task.isCancelled { partial = true; group.cancelAll(); continue }
                if addNext() { running += 1 }
            }
        }

        if measured.count < entries.count || Task.isCancelled { partial = true }
        return summarize(measured, limit: limit, partial: partial)
    }

    private static func summarize(_ nodes: [SpaceNode], limit: Int, partial: Bool) -> SpaceListing {
        let sorted = nodes.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
        let top = Array(sorted.prefix(limit))
        let rest = sorted.dropFirst(limit)
        return SpaceListing(
            nodes: top,
            totalBytes: sorted.reduce(0) { $0 + $1.bytes },
            remainderCount: rest.count,
            remainderBytes: rest.reduce(0) { $0 + $1.bytes },
            isPartial: partial
        )
    }

    /// Recursive allocated size of a folder or package. Returns `(bytes, complete)`.
    /// Symlinks are never followed (the enumerator doesn't traverse them and they
    /// are not regular files), and mounted volumes are not descended into.
    static func walk(_ url: URL, budget: EntryBudget = EntryBudget(limit: defaultEntryBudget)) -> (Int64, Bool) {
        var complete = true
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: walkKeys,
            options: [],
            errorHandler: { _, _ in complete = false; return true }
        ) else { return (0, false) }

        let keys = Set(walkKeys)
        var total: Int64 = 0
        var counter = 0
        while let item = enumerator.nextObject() as? URL {
            counter += 1
            if counter & 0x3FF == 0 {
                if Task.isCancelled { return (total, false) }
                if !budget.consume(1024) { return (total, false) }
            }
            guard let values = try? item.resourceValues(forKeys: keys) else { complete = false; continue }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            } else if values.isDirectory == true, values.isVolume == true {
                enumerator.skipDescendants()
            }
        }
        return (total, complete)
    }

    /// Conservative "reclaimable" hints: only places the app already knows how to
    /// clean safely (the Trash and the user cache folder).
    private static func reclaimableHint(for url: URL, parent: URL, bytes: Int64) -> Int64? {
        guard bytes > 0 else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let name = url.lastPathComponent
        if parent.path == home.path, name == ".Trash" { return bytes }
        if parent.path == home.appending(path: "Library").standardizedFileURL.path, name == "Caches" { return bytes }
        return nil
    }
}

/// A thread-safe countdown shared by concurrent walkers so the whole listing
/// stays within one entry budget.
final class EntryBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    init(limit: Int) { remaining = limit }
    /// Consumes `count` entries; returns `false` once the budget is exhausted.
    func consume(_ count: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        remaining -= count
        return remaining >= 0
    }
}
