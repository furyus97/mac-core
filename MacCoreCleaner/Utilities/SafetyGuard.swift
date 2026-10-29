import Foundation

/// Raised when a removal target fails the safety policy.
struct SafetyViolation: Error, LocalizedError {
    let url: URL
    let reason: String
    var errorDescription: String? { reason }
}

/// What kind of removal a request represents. Each scope shares the same hard
/// system denylist + structural guards, but has its own allowlist of roots whose
/// *contents* may be removed. This lets user-initiated actions (uninstall an app,
/// delete a chosen large file, clear browser data) work without ever weakening
/// protection of system locations.
enum RemovalScope {
    case cleaning      // automated cache/log/dev cleaning (strictest)
    case userFiles     // user-chosen files in Downloads/Desktop/Documents/Media
    case application   // app bundles + their leftover support files
    case browserData   // browser cache/cookies/history/etc.
}

/// The single source of truth for *what may ever be removed*.
///
/// Two layers, applied to every scope:
///  1. **Hard denylist + structural guards** — core system locations
///     (`/System`, `/bin`, `/sbin`, `/usr`, `/Library/Apple`, …), the volume
///     root, the user's home, and symlink-escape are refused outright.
///  2. **Per-scope allowlist** — an item may be removed only if it lives strictly
///     inside one of that scope's roots (never the root itself).
struct SafetyGuard {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    private func h(_ path: String) -> URL { home.appending(path: path, directoryHint: .isDirectory).standardizedFileURL }

    // MARK: Per-scope allowlists (contents removable; root itself protected)

    /// Cleaning roots (Storage + Developer screens).
    var cleaningRoots: [URL] {
        [
            h("Library/Caches"), h("Library/Logs"), h(".Trash"), h("Downloads"),
            h("Library/Developer/Xcode/DerivedData"), h("Library/Developer/Xcode/Archives"),
            h("Library/Developer/CoreSimulator/Caches"), h(".gradle"),
        ]
    }
    /// Backwards-compatible alias used by the older API.
    var allowedRoots: [URL] { cleaningRoots }

    private var userFileRoots: [URL] {
        [h("Downloads"), h("Desktop"), h("Documents"), h("Movies"), h("Music"), h("Pictures")]
    }

    private var appRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications").standardizedFileURL,
            h("Applications"),
            h("Library/Application Support"), h("Library/Caches"), h("Library/Preferences"),
            h("Library/Logs"), h("Library/Containers"), h("Library/Group Containers"),
            h("Library/Saved Application State"), h("Library/HTTPStorages"),
            h("Library/WebKit"), h("Library/Cookies"), h("Library/LaunchAgents"),
        ]
    }

    private var browserRoots: [URL] {
        [
            h("Library/Caches"), h("Library/Application Support"), h("Library/Containers"),
            h("Library/Preferences"), h("Library/Cookies"), h("Library/Safari"),
            h("Library/WebKit"), h("Library/HTTPStorages"), h("Library/Saved Application State"),
        ]
    }

    private func roots(for scope: RemovalScope) -> [URL] {
        switch scope {
        case .cleaning: return cleaningRoots
        case .userFiles: return userFileRoots
        case .application: return appRoots
        case .browserData: return browserRoots
        }
    }

    /// Absolute path prefixes that must never be touched in ANY scope.
    static let protectedPrefixes: [String] = [
        "/System", "/bin", "/sbin", "/usr",
        "/private/var/db", "/private/etc", "/etc", "/var/db",
        "/Library/Apple", "/Library/Application Support/com.apple",
        "/System/Applications", "/cores", "/dev", "/Network", "/Volumes/Recovery",
    ]

    // MARK: Evaluation

    /// `nil` when the URL is safe to remove in `scope`, else a human-readable reason.
    func violation(for url: URL, scope: RemovalScope = .cleaning) -> String? {
        guard url.isFileURL else { return tr("guard.nonFile") }
        let lexical = url.standardizedFileURL
        let resolved = lexical.resolvingSymlinksInPath().standardizedFileURL

        // 0. Reject suspicious / shallow paths.
        if lexical.path == "/" || lexical.pathComponents.count < 3 {
            return tr("guard.shallow")
        }

        // 1. Hard denylist (lexical + symlink-resolved → blocks symlink escape).
        for candidate in [lexical, resolved] {
            for prefix in Self.protectedPrefixes
            where candidate.path == prefix || Self.isContained(path: candidate.path, inDirectory: prefix) {
                return tr("guard.protected", prefix)
            }
        }

        // 2. Never the home folder or a scope root itself.
        if lexical.path == home.path || resolved.path == home.resolvingSymlinksInPath().path { return tr("guard.home") }
        let currentApp = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        if currentApp.pathExtension == "app" {
            if [lexical, resolved].contains(where: {
                $0.path == currentApp.path || Self.isContained(path: currentApp.path, inDirectory: $0.path)
                    || Self.isContained(path: $0.path, inDirectory: currentApp.path)
            }) {
                return tr("guard.currentApp")
            }
        }
        // Generic cache cleaners must not bypass the dedicated browser flow,
        // which checks running browsers and makes profile-data risks explicit.
        if scope == .cleaning {
            for browser in BrowserKind.allCases {
                let caches = BrowserCleanerService.paths(for: browser, kind: .cache, home: home)
                if caches.contains(where: { cache in
                    [lexical, resolved].contains { candidate in
                        candidate.path == cache.path || Self.isContained(path: candidate.path, inDirectory: cache.path)
                            || Self.isContained(path: cache.path, inDirectory: candidate.path)
                    }
                }) { return tr("guard.browserFlow") }
            }
        }
        let scopeRoots = roots(for: scope)
        for root in scopeRoots where lexical.path == root.path || resolved.path == root.resolvingSymlinksInPath().path {
            return tr("guard.root", root.lastPathComponent)
        }

        // 3. Allowlist: must be strictly inside a scope root (lexically AND resolved).
        let insideAllowed = scopeRoots.contains { root in
            isStrictlyInside(lexical, root: root) && isStrictlyInside(resolved, root: root)
        }
        guard insideAllowed else { return tr("guard.outside") }

        // Browser scope is limited to known category targets, not arbitrary
        // support files such as bookmarks or the entire browser profile.
        if scope == .browserData {
            let known = BrowserKind.allCases.flatMap { browser in
                BrowserDataKind.allCases.flatMap { kind in
                    BrowserCleanerService.paths(for: browser, kind: kind, home: home)
                }
            }
            let isKnownTarget = known.contains { target in
                lexical.path == target.standardizedFileURL.path
                    && resolved.path == target.standardizedFileURL.path
            }
            guard isKnownTarget else { return tr("guard.outside") }
        }

        return nil
    }

    func isRemovable(_ url: URL, scope: RemovalScope = .cleaning) -> Bool {
        violation(for: url, scope: scope) == nil
    }

    func assertRemovable(_ url: URL, scope: RemovalScope = .cleaning) throws {
        if let reason = violation(for: url, scope: scope) {
            throw SafetyViolation(url: url, reason: reason)
        }
    }

    // Back-compat (cleaning scope) used by existing scanners/cleaner.
    func violationReason(for url: URL) -> String? { violation(for: url, scope: .cleaning) }

    // MARK: Path containment (lexical, component-wise)

    private func isStrictlyInside(_ url: URL, root: URL) -> Bool {
        let u = url.standardizedFileURL.pathComponents
        let r = root.standardizedFileURL.pathComponents
        guard u.count > r.count else { return false }
        return Array(u.prefix(r.count)) == r
    }

    private static func isContained(path: String, inDirectory directory: String) -> Bool {
        let p = (path as NSString).pathComponents
        let d = (directory as NSString).pathComponents
        guard p.count > d.count else { return false }
        return Array(p.prefix(d.count)) == d
    }
}
