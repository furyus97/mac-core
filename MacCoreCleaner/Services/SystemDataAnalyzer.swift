import Foundation

/// Estimates known System Data locations, not macOS's private storage category.
/// Roots are disjoint. Support data/backups are read-only; removal authority is
/// never expanded beyond the existing cleaner allowlist.
struct SystemDataAnalyzer {
    let safety: SafetyGuard

    init(safety: SafetyGuard = SafetyGuard()) { self.safety = safety }

    func analyze(progress: @escaping @Sendable (ScanProgress) -> Void) async -> SystemDataReport? {
        let task = Task.detached(priority: .utility) { () -> SystemDataReport? in
            var groups: [SystemDataGroup] = []
            let specs = self.locations
            for (index, spec) in specs.enumerated() {
                guard !Task.isCancelled else { return nil }
                let root = safety.home.appending(path: spec.path).standardizedFileURL
                progress(ScanProgress(fractionCompleted: Double(index) / Double(specs.count),
                    phase: tr(spec.key), currentPath: root.path))
                var size: Int64 = 0
                var partial = false
                var items: [CleanableItem] = []
                do {
                    // Do not traverse redirected roots, even if they point to another library.
                    let metadata = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                    if metadata.isSymbolicLink == true || root.resolvingSymlinksInPath().path != root.path {
                        partial = true
                    } else if metadata.isDirectory == true {
                        let children = try FileManager.default.contentsOfDirectory(at: root,
                            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                        for child in children {
                            guard !Task.isCancelled else { return nil }
                            // MobileSync/Backup is counted separately; never count it twice.
                            if spec.id == "support" && child.lastPathComponent == "MobileSync" { continue }
                            let measurement = Self.measure(child)
                            size += measurement.bytes
                            partial = partial || measurement.partial
                            if let category = spec.category, !measurement.partial,
                               measurement.bytes > 0, safety.isRemovable(child) {
                                items.append(CleanableItem(url: child, sizeBytes: measurement.bytes,
                                    safety: CleanCategory.metadata(for: category).defaultSafety,
                                    categoryID: category, isDirectory: measurement.isDirectory,
                                    isSelected: false))
                            }
                        }
                    } else {
                        partial = true
                    }
                } catch {
                    let code = (error as NSError).code
                    let domain = (error as NSError).domain
                    // An absent optional tool folder is not an access failure.
                    partial = !(domain == NSCocoaErrorDomain &&
                        [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(code))
                }
                groups.append(SystemDataGroup(id: spec.id, titleKey: spec.key, root: root,
                    sizeBytes: size, categoryID: spec.category,
                    items: items.sorted { $0.sizeBytes > $1.sizeBytes }, isPartial: partial))
            }
            guard !Task.isCancelled else { return nil }
            progress(ScanProgress(fractionCompleted: 1, phase: tr("progress.done"), currentPath: nil))
            return SystemDataReport(groups: groups)
        }
        return await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    private struct Location {
        let id: String
        let key: String
        let path: String
        var category: CleanCategoryID? = nil
    }

    private var locations: [Location] {
        [
            .init(id: "caches", key: "cat.userCache.title", path: "Library/Caches", category: .userCache),
            .init(id: "logs", key: "cat.userLogs.title", path: "Library/Logs", category: .userLogs),
            .init(id: "derived", key: "cat.xcodeDerivedData.title", path: "Library/Developer/Xcode/DerivedData", category: .xcodeDerivedData),
            .init(id: "simulator", key: "cat.simulatorCache.title", path: "Library/Developer/CoreSimulator/Caches", category: .simulatorCache),
            .init(id: "gradle", key: "cat.gradleCache.title", path: ".gradle/caches", category: .gradleCache),
            .init(id: "archives", key: "cat.xcodeArchives.title", path: "Library/Developer/Xcode/Archives"),
            .init(id: "support", key: "sd.support", path: "Library/Application Support"),
            .init(id: "backups", key: "sd.backups", path: "Library/Application Support/MobileSync/Backup"),
            .init(id: "containers", key: "sd.containers", path: "Library/Containers"),
            .init(id: "groups", key: "sd.groups", path: "Library/Group Containers")
        ]
    }

    private static func measure(_ url: URL) -> (bytes: Int64, partial: Bool, isDirectory: Bool) {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey,
                                       .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        var total: Int64 = 0
        var partial = false
        func inspect(_ file: URL) -> URLResourceValues? {
            do {
                let values = try file.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { partial = true; return nil }
                if values.isRegularFile == true {
                    let bytes = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize
                    if let bytes { total += Int64(max(0, bytes)) } else { partial = true }
                }
                return values
            } catch { partial = true; return nil }
        }
        guard let top = inspect(url) else { return (0, true, false) }
        if top.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(at: url,
                includingPropertiesForKeys: Array(keys), options: [],
                errorHandler: { _, _ in partial = true; return true }) else { return (0, true, true) }
            for case let file as URL in enumerator {
                if Task.isCancelled { return (total, true, true) }
                if inspect(file) == nil { enumerator.skipDescendants() }
            }
        }
        return (total, partial, top.isDirectory == true)
    }
}
