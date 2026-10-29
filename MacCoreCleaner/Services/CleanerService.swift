import Foundation
import AppKit

/// Performs the actual removal of selected items. This is the only type in the
/// app that deletes anything, and it enforces the safety policy on every item:
///
///  * Each item is re-validated through `SafetyGuard` **immediately before**
///    removal — not just at scan time — so a stale or tampered list cannot cause
///    an unsafe deletion.
///  * The default mode moves items to the Trash (recoverable). Permanent deletion
///    only happens when the caller explicitly passes `.permanentDelete`, which the
///    UI gates behind an extra confirmation and advanced mode.
///  * Failures are collected and reported per item; one failure never aborts the
///    rest, and the reason is surfaced to the user.
///  * No shell commands, no `rm -rf`, no privilege escalation — only
///    `FileManager` APIs.
final class CleanerService {
    // Serialize removals even when the user navigates between cleaner screens.
    private static let removalQueue = DispatchQueue(label: "com.maccore.removal", qos: .userInitiated)

    private let safety: SafetyGuard

    init(safety: SafetyGuard = SafetyGuard()) {
        self.safety = safety
    }

    /// Removes the given items off the main thread and returns an aggregate outcome.
    /// - Parameters:
    ///   - items: the user-selected items to remove.
    ///   - mode: `.trash` (default, recoverable) or `.permanentDelete`.
    ///   - progress: optional 0...1 progress callback (invoked on a background queue).
    func clean(
        items: [CleanableItem],
        mode: RemovalMode,
        scope: RemovalScope = .cleaning,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> CleanOutcome {
        await withCheckedContinuation { continuation in
            Self.removalQueue.async { [safety] in
                let fm = FileManager.default
                var outcome = CleanOutcome(mode: mode)
                let targets = Self.canonicalTargets(from: items)
                let total = max(targets.count, 1)

                for (index, item) in targets.enumerated() {
                    defer { progress?(Double(index + 1) / Double(total)) }

                    // Skip anything already gone — not an error.
                    guard fm.fileExists(atPath: item.url.path(percentEncoded: false)) else { continue }

                    // Final safety gate — refuse anything outside the scope allowlist.
                    if let reason = safety.violation(for: item.url, scope: scope) {
                        outcome.failures.append(CleanFailure(url: item.url, reason: reason))
                        continue
                    }

                    // A browser category may contain several paths and may have
                    // changed since scanning. Account only for this actual target.
                    let currentBytes = FileScanner.recursiveSize(of: item.url)
                    if let reason = safety.violation(for: item.url, scope: scope) {
                        outcome.failures.append(CleanFailure(url: item.url, reason: reason))
                        continue
                    }
                    if scope == .browserData, let reason = Self.runningBrowserReason(for: item.url, home: safety.home) {
                        outcome.failures.append(CleanFailure(url: item.url, reason: reason))
                        continue
                    }
                    do {
                        switch mode {
                        case .trash:
                            try fm.trashItem(at: item.url, resultingItemURL: nil)
                        case .permanentDelete:
                            try fm.removeItem(at: item.url)
                        }
                        outcome.removedCount += 1
                        outcome.processedBytes += max(0, currentBytes)
                    } catch {
                        outcome.failures.append(
                            CleanFailure(url: item.url, reason: error.localizedDescription)
                        )
                    }
                }

                continuation.resume(returning: outcome)
            }
        }
    }

    /// Recheck after waiting in the removal queue; a browser may have launched
    /// since the user reviewed the confirmation sheet.
    private static func runningBrowserReason(for url: URL, home: URL) -> String? {
        let runningIDs = DispatchQueue.main.sync {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        for browser in BrowserKind.allCases where !browser.bundleIdentifiers.isDisjoint(with: runningIDs) {
            let paths = BrowserDataKind.allCases.flatMap {
                BrowserCleanerService.paths(for: browser, kind: $0, home: home)
            }
            if paths.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
                return tr("browser.runningError", browser.displayName)
            }
        }
        return nil
    }

    /// Removes duplicate targets and descendants of a target that is already
    /// selected. Besides producing an honest item count, this avoids trying to
    /// delete a child after its parent has already been moved.
    private static func canonicalTargets(from items: [CleanableItem]) -> [CleanableItem] {
        let sorted = items.sorted {
            $0.url.standardizedFileURL.pathComponents.count
                < $1.url.standardizedFileURL.pathComponents.count
        }
        var seen = Set<String>()
        var result: [CleanableItem] = []

        for item in sorted {
            let path = item.url.standardizedFileURL.path
            guard seen.insert(path).inserted else { continue }
            let components = (path as NSString).pathComponents
            let hasSelectedParent = result.contains { candidate in
                let parent = (candidate.url.standardizedFileURL.path as NSString).pathComponents
                return components.count > parent.count && Array(components.prefix(parent.count)) == parent
            }
            if !hasSelectedParent { result.append(item) }
        }
        return result
    }
}
