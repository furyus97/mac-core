import Foundation
import CoreServices

/// Lists installed third-party applications and discovers their leftover support
/// files for the Applications (uninstaller) screen.
///
/// Like every other analysis service, this type only *describes* what exists and
/// what could be removed — it never deletes anything itself. Removal is the
/// exclusive job of `CleanerService`, which re-validates every item through
/// `SafetyGuard` (with the `.application` scope) immediately before trashing it.
///
/// All file work runs off the main thread inside `Task.detached`, fails
/// gracefully (an unreadable bundle or directory is skipped, not fatal), and is
/// read-only.
final class AppInventoryService: AppInventory {

    init() {}

    /// Directories scanned for `*.app` bundles.
    private static func applicationRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    /// `~/Library` subfolders searched for an app's leftover support files.
    private static let leftoverFolders: [String] = [
        "Application Support",
        "Caches",
        "Preferences",
        "Logs",
        "Containers",
        "Saved Application State",
        "HTTPStorages",
        "WebKit",
        "Cookies",
        "LaunchAgents",
    ]

    // MARK: - Installed apps

    func installedApps() async -> [InstalledApp] {
        let task = Task.detached(priority: .userInitiated) { () -> [InstalledApp] in
            let fm = FileManager.default
            var apps: [InstalledApp] = []
            var seen = Set<String>()

            for root in Self.applicationRoots() {
                if Task.isCancelled { break }
                guard FileScanner.exists(root) else { continue }

                let bundles = FileScanner.topLevelItems(in: root, includeHidden: false)
                    .filter { $0.pathExtension.lowercased() == "app" }

                for bundleURL in bundles {
                    if Task.isCancelled { break }
                    guard let app = Self.readApp(at: bundleURL, fileManager: fm) else { continue }
                    // De-dupe by identity (bundle id or path) across roots.
                    if seen.insert(app.id).inserted {
                        apps.append(app)
                    }
                }
            }

            // Largest first so the biggest reclaimable apps surface at the top.
            apps.sort { $0.sizeBytes > $1.sizeBytes }
            return apps
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// Reads an app bundle's metadata. Returns nil only when the URL is not a
    /// readable bundle.
    private static func readApp(at bundleURL: URL, fileManager fm: FileManager) -> InstalledApp? {
        let info = infoDictionary(for: bundleURL)

        let fallbackName = bundleURL.deletingPathExtension().lastPathComponent
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? fallbackName
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "—"
        let bundleID = info?["CFBundleIdentifier"] as? String
        let isSystem = bundleID?.hasPrefix("com.apple.") == true

        let size = FileScanner.recursiveSize(of: bundleURL, isCancelled: { Task.isCancelled })

        // Prefer creation date; fall back to last modification date.
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
        let values = try? bundleURL.resourceValues(forKeys: resourceKeys)
        let installDate = values?.creationDate ?? values?.contentModificationDate

        return InstalledApp(
            id: bundleID ?? bundleURL.path(percentEncoded: false),
            name: name,
            version: version,
            bundleURL: bundleURL,
            bundleID: bundleID,
            sizeBytes: size,
            installDate: installDate,
            isSystem: isSystem,
            lastUsedDate: MDItemCreateWithURL(nil, bundleURL as CFURL).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
        )
    }

    /// The bundle's Info.plist as a dictionary, via `Bundle` first and a direct
    /// read of `Contents/Info.plist` as a fallback.
    private static func infoDictionary(for bundleURL: URL) -> [String: Any]? {
        if let info = Bundle(url: bundleURL)?.infoDictionary, !info.isEmpty {
            return info
        }
        let plistURL = bundleURL.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        else { return nil }
        return plist as? [String: Any]
    }

    // MARK: - Leftovers

    func leftovers(for app: InstalledApp) async -> [CleanableItem] {
        // Without a bundle id there is no reliable way to match support files.
        guard let bundleID = app.bundleID, !bundleID.isEmpty else { return [] }

        let task = Task.detached(priority: .userInitiated) { () -> [CleanableItem] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let library = home.appending(path: "Library", directoryHint: .isDirectory)

            var items: [CleanableItem] = []

            for folder in Self.leftoverFolders {
                if Task.isCancelled { break }

                let dir = library.appending(path: folder, directoryHint: .isDirectory)
                guard FileScanner.exists(dir) else { continue }

                for entry in FileScanner.topLevelItems(in: dir, includeHidden: true) {
                    if Task.isCancelled { break }

                    guard Self.matchesLeftover(entry.lastPathComponent, bundleID: bundleID) else { continue }

                    let meta = FileScanner.metadata(for: entry)
                    let size = FileScanner.recursiveSize(of: entry, isCancelled: { Task.isCancelled })

                    let item = CleanableItem(
                        url: entry,
                        displayName: entry.lastPathComponent,
                        detail: dir.lastPathComponent,
                        sizeBytes: size,
                        modifiedDate: meta.modified,
                        safety: .caution,
                        categoryID: .application,
                        isDirectory: meta.isDirectory,
                        isSelected: false
                    )
                    items.append(item)
                }
            }

            // Largest first.
            items.sort { $0.sizeBytes > $1.sizeBytes }
            return items
        }
        return await withTaskCancellationHandler(
            operation: { await task.value },
            onCancel: { task.cancel() }
        )
    }

    /// A prefix may belong to a sibling app (e.g. Chrome Canary). Shared group
    /// containers and fuzzy names cannot safely establish exclusive ownership.
    static func matchesLeftover(_ name: String, bundleID: String) -> Bool {
        let name = name.lowercased()
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return false }
        return ["", ".plist", ".savedstate", ".binarycookies"].contains { name == id + $0 }
    }
}
