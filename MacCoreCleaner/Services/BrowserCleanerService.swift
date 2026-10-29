import Foundation

/// Detects installed browsers and sizes their cache/cookies/history/etc. for the
/// Browser screen. Read-only: it only enumerates known data locations and reports
/// their sizes — removal is always performed by `CleanerService` under the
/// `.browserData` scope, which re-validates every path through `SafetyGuard`.
final class BrowserCleanerService: BrowserCleaning {

    private let home: URL

    init() {
        self.home = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: Detection

    func detectBrowsers() async -> [BrowserKind] {
        let task = Task.detached(priority: .userInitiated) { [home] in
            func exists(_ relative: String) -> Bool {
                FileScanner.exists(home.appending(path: relative, directoryHint: .isDirectory))
            }

            var browsers: [BrowserKind] = [.safari]   // always present on macOS
            if exists("Library/Application Support/Google/Chrome") { browsers.append(.chrome) }
            if exists("Library/Application Support/Microsoft Edge") { browsers.append(.edge) }
            if exists("Library/Application Support/Firefox") { browsers.append(.firefox) }
            return browsers
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    // MARK: Sizing

    func dataItems(for browsers: [BrowserKind]) async -> [BrowserDataItem] {
        let task = Task.detached(priority: .userInitiated) { [home] in
            var items: [BrowserDataItem] = []

            for browser in browsers {
                if Task.isCancelled { break }
                for kind in BrowserDataKind.allCases {
                    if Task.isCancelled { break }

                    let candidates = Self.paths(for: browser, kind: kind, home: home)
                    let existing = candidates.filter { FileScanner.exists($0) }
                    guard !existing.isEmpty else { continue }

                    var size: Int64 = 0
                    for url in existing {
                        if Task.isCancelled { break }
                        size += FileScanner.recursiveSize(of: url, isCancelled: { Task.isCancelled })
                    }

                    items.append(
                        BrowserDataItem(
                            browser: browser,
                            kind: kind,
                            sizeBytes: size,
                            paths: existing,
                            isSelected: kind.selectedByDefault
                        )
                    )
                }
            }
            return items
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    // MARK: Known paths

    /// Candidate paths for a (browser, data-kind) pair. Non-existent ones are
    /// filtered out by the caller; an empty result means "skip this kind".
    static func paths(for browser: BrowserKind, kind: BrowserDataKind, home: URL) -> [URL] {
        func u(_ relative: String) -> URL {
            home.appending(path: relative, directoryHint: .notDirectory)
        }
        func chromiumProfiles(_ relativeRoot: String) -> [URL] {
            let root = home.appending(path: relativeRoot, directoryHint: .isDirectory)
            return FileScanner.topLevelItems(in: root, includeHidden: false).filter { url in
                let name = url.lastPathComponent
                return FileScanner.metadata(for: url).isDirectory
                    && (name == "Default" || name.hasPrefix("Profile "))
            }
        }
        func chromiumPaths(_ relativeRoot: String, child: String, sqlite: Bool = false) -> [URL] {
            chromiumProfiles(relativeRoot).flatMap { profile in
                let target = profile.appending(path: child, directoryHint: .notDirectory)
                return sqlite
                    ? [target, URL(fileURLWithPath: target.path + "-wal"), URL(fileURLWithPath: target.path + "-shm")]
                    : [target]
            }
        }

        switch browser {
        case .safari:
            switch kind {
            case .cache:
                return [
                    u("Library/Caches/com.apple.Safari"),
                    u("Library/Containers/com.apple.Safari/Data/Library/Caches"),
                ]
            case .cookies:
                return [
                    u("Library/Containers/com.apple.Safari/Data/Library/Cookies"),
                ]
            case .history:
                return [
                    u("Library/Safari/History.db"),
                    u("Library/Safari/History.db-wal"),
                    u("Library/Safari/History.db-shm"),
                ]
            case .downloads:
                return [u("Library/Safari/Downloads.plist")]
            case .session:
                return [
                    u("Library/Safari/LastSession.plist"),
                    u("Library/Safari/SessionState"),
                ]
            case .loginData:
                return []
            }

        case .chrome:
            let root = "Library/Application Support/Google/Chrome"
            switch kind {
            case .cache:
                return [
                    u("Library/Caches/Google/Chrome"),
                    u("Library/Caches/com.google.Chrome"),
                ]
            case .cookies:
                return chromiumPaths(root, child: "Cookies", sqlite: true)
                    + chromiumPaths(root, child: "Network/Cookies", sqlite: true)
            case .history:
                return chromiumPaths(root, child: "History", sqlite: true)
            case .downloads:
                return []   // tracked inside History; skip the duplicate
            case .session:
                return chromiumPaths(root, child: "Sessions")
                    + chromiumPaths(root, child: "Current Session")
                    + chromiumPaths(root, child: "Current Tabs")
            case .loginData:
                return chromiumPaths(root, child: "Login Data", sqlite: true)
            }

        case .edge:
            let root = "Library/Application Support/Microsoft Edge"
            switch kind {
            case .cache:
                return [
                    u("Library/Caches/Microsoft Edge"),
                    u("Library/Caches/com.microsoft.edgemac"),
                ]
            case .cookies:
                return chromiumPaths(root, child: "Cookies", sqlite: true)
                    + chromiumPaths(root, child: "Network/Cookies", sqlite: true)
            case .history:
                return chromiumPaths(root, child: "History", sqlite: true)
            case .downloads:
                return []
            case .session:
                return chromiumPaths(root, child: "Sessions")
            case .loginData:
                return chromiumPaths(root, child: "Login Data", sqlite: true)
            }

        case .firefox:
            switch kind {
            case .cache:
                return [
                    u("Library/Caches/Firefox"),
                    u("Library/Caches/org.mozilla.firefox"),
                ]
            case .downloads:
                return []   // tracked inside places.sqlite; skip
            case .cookies, .history, .session, .loginData:
                let fileNames = Self.firefoxProfileFileNames(for: kind)
                guard !fileNames.isEmpty else { return [] }
                let profilesDir = home.appending(
                    path: "Library/Application Support/Firefox/Profiles",
                    directoryHint: .isDirectory
                )
                let profiles = FileScanner.topLevelItems(in: profilesDir, includeHidden: false)
                    .filter { FileScanner.metadata(for: $0).isDirectory }
                return profiles.flatMap { profile in
                    fileNames.flatMap { name in
                        let relative = profile.appending(path: name, directoryHint: .notDirectory)
                        if name.hasSuffix(".sqlite") {
                            return [relative, URL(fileURLWithPath: relative.path + "-wal"), URL(fileURLWithPath: relative.path + "-shm")]
                        }
                        return [relative]
                    }
                }
            }
        }
    }

    /// Per-kind file/folder names living inside each Firefox profile folder.
    private static func firefoxProfileFileNames(for kind: BrowserDataKind) -> [String] {
        switch kind {
        case .cookies:   return ["cookies.sqlite"]
        case .history:   return [] // places.sqlite also contains bookmarks; never delete it wholesale.
        case .session:   return ["sessionstore-backups"]
        case .loginData: return [] // key4.db contains key material beyond saved website passwords.
        default:         return []
        }
    }
}
