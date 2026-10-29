import Foundation
import SwiftUI
import AppKit

/// One reviewable entry in a Smart Scan group. Holds one or more URLs (browser
/// data categories map to several files) plus its safety and selection state.
struct SmartEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var detail: String?
    var sizeBytes: Int64
    var safety: SafetyLevel
    var urls: [URL]
    var isSelected: Bool
    var isEnabled: Bool = true
    var browser: BrowserKind? = nil

    var formattedSize: String { ByteFormat.string(fromBytes: sizeBytes) }
}

/// A Smart Scan result group (System / Developer / Large Files / Browser), each
/// removed with its own safety scope.
struct SmartGroup: Identifiable {
    let id: String
    var titleKey: String
    var icon: String
    var tint: Color
    var scope: RemovalScope
    var entries: [SmartEntry]
    var isExpanded: Bool = true

    var totalBytes: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }
    var selectedEntries: [SmartEntry] { entries.filter { $0.isSelected && $0.isEnabled } }
    var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.sizeBytes } }
    var selectedCount: Int { selectedEntries.count }
    var isEmpty: Bool { entries.isEmpty }
    var allSelected: Bool {
        let enabled = entries.filter(\.isEnabled)
        return !enabled.isEmpty && enabled.allSatisfy(\.isSelected)
    }
}

/// Orchestrates the one-click Smart Scan across all cleaners. Auto-selects only
/// Safe-rated items; large files and browser cookies/history stay unselected.
@MainActor
final class SmartScanViewModel: ObservableObject {
    private let services: AppServices

    @Published var groups: [SmartGroup] = []
    @Published var isScanning = false
    @Published var hasScanned = false
    @Published var scanFraction: Double = 0
    @Published var scanPhase: String = ""

    @Published var showConfirm = false
    @Published var pendingItems: [CleanableItem] = []
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isCleaning = false

    private var scanTask: Task<Void, Never>?
    private var pendingGroups: [SmartGroup] = []

    init(services: AppServices? = nil) { self.services = services ?? .shared }

    // MARK: Derived

    var totalFound: Int64 { groups.reduce(0) { $0 + $1.totalBytes } }
    var selectedBytes: Int64 { groups.reduce(0) { $0 + $1.selectedBytes } }
    var selectedCount: Int { groups.reduce(0) { $0 + $1.selectedCount } }

    func binding(for groupID: String) -> Binding<SmartGroup>? {
        guard groups.contains(where: { $0.id == groupID }) else { return nil }
        return Binding(
            get: { [weak self] in
                self?.groups.first(where: { $0.id == groupID })
                    ?? SmartGroup(id: groupID, titleKey: "", icon: "", tint: .gray, scope: .cleaning, entries: [])
            },
            set: { [weak self] value in
                guard let self, let index = self.groups.firstIndex(where: { $0.id == groupID }) else { return }
                self.groups[index] = value
            }
        )
    }

    // MARK: Scan

    func scan(preservingOutcome: Bool = false) {
        guard !isCleaning else { return }
        scanTask?.cancel()
        isScanning = true
        hasScanned = true
        if !preservingOutcome { lastOutcome = nil }
        scanFraction = 0
        groups = []

        scanTask = Task { [weak self] in
            guard let self else { return }
            var result: [SmartGroup] = []

            // 1) System caches & logs. Trash requires a permanent-delete
            // acknowledgement and large downloads are covered by stage 3, so
            // neither belongs in the one-click safe group.
            await self.stage(0.0, "smart.phase.system")
            let storage = await self.services.scanner.scan(
                categories: [.userCache, .userLogs], progress: { _ in })
            guard !Task.isCancelled else { return }
            result.append(self.makeGroup("system", "smart.group.system", "internaldrive.fill", .blue, .cleaning, from: storage))

            // 2) Developer caches
            await self.stage(0.25, "smart.phase.developer")
            // SPM/Homebrew live under ~/Library/Caches (already covered by the
            // system-caches scan above), so exclude them here to avoid duplicates.
            let dev = await self.services.developer.scan(
                categories: [.xcodeDerivedData, .xcodeArchives, .simulatorCache, .gradleCache],
                progress: { _ in })
            guard !Task.isCancelled else { return }
            result.append(self.makeGroup("developer", "smart.group.developer", "hammer.fill",
                                         CleanGroup.developer.tint, .cleaning, from: dev))

            // 3) Large files
            await self.stage(0.5, "smart.phase.large")
            // Smart Scan only checks Downloads + Desktop for speed; the dedicated
            // Large Files screen scans all media/document folders.
            let home = FileManager.default.homeDirectoryForCurrentUser
            let smartLargeRoots = [home.appending(path: "Downloads"), home.appending(path: "Desktop")]
            let large = await self.services.largeFiles.scan(
                roots: smartLargeRoots,
                minBytes: Int64(max(self.services.settings.downloadsThresholdMB, 10)) * 1_000_000, progress: { _ in })
            guard !Task.isCancelled else { return }
            let largeEntries = large.map { item in
                SmartEntry(name: item.displayName, detail: item.url.deletingLastPathComponent().lastPathComponent,
                           sizeBytes: item.sizeBytes, safety: .caution, urls: [item.url], isSelected: false)
            }
            result.append(SmartGroup(id: "large", titleKey: "smart.group.large", icon: "doc.fill",
                                     tint: .indigo, scope: .userFiles, entries: largeEntries))

            // 4) Browser data
            await self.stage(0.75, "smart.phase.browser")
            let browsers = await self.services.browser.detectBrowsers()
            guard !Task.isCancelled else { return }
            let discoveredBrowserItems = await self.services.browser.dataItems(for: browsers)
            guard !Task.isCancelled else { return }
            let bitems = self.services.settings.showRiskyItems
                ? discoveredBrowserItems
                : discoveredBrowserItems.filter { $0.kind.safety != .risky }
            let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let browserEntries = bitems.map { item in
                let isRunning = !item.browser.bundleIdentifiers.isDisjoint(with: runningIDs)
                return SmartEntry(name: "\(item.browser.displayName) · \(tr(item.kind.titleKey))",
                                  detail: isRunning ? tr("browser.quitToClean", item.browser.displayName) : nil,
                                  sizeBytes: item.sizeBytes, safety: item.kind.safety,
                                  urls: item.paths, isSelected: item.kind.safety == .safe && !isRunning,
                                  isEnabled: !isRunning, browser: item.browser)
            }
            result.append(SmartGroup(id: "browser", titleKey: "smart.group.browser", icon: "safari.fill",
                                     tint: .teal, scope: .browserData, entries: browserEntries))

            if Task.isCancelled { return }
            self.groups = self.deduplicated(result).filter { !$0.isEmpty }
            self.scanFraction = 1
            self.isScanning = false
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        isScanning = false
    }

    private func stage(_ fraction: Double, _ phaseKey: String) async {
        scanFraction = fraction
        scanPhase = tr(phaseKey)
    }

    /// Builds a group from category scan results, auto-selecting Safe items only.
    private func makeGroup(_ id: String, _ titleKey: String, _ icon: String, _ tint: Color,
                           _ scope: RemovalScope, from results: [CategoryScanResult]) -> SmartGroup {
        let entries: [SmartEntry] = results.flatMap { result in
            result.items.map { item in
                SmartEntry(name: item.displayName, detail: result.category.title,
                           sizeBytes: item.sizeBytes, safety: item.safety,
                           urls: [item.url], isSelected: item.safety == .safe)
            }
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
        return SmartGroup(id: id, titleKey: titleKey, icon: icon, tint: tint, scope: scope, entries: entries)
    }

    /// Browser-specific candidates often overlap top-level user-cache entries
    /// (for example Chrome's cache). Prefer the more specific Browser group and
    /// ensure a path, its parent, or its child can never be counted twice.
    private func deduplicated(_ groups: [SmartGroup]) -> [SmartGroup] {
        let priority = ["browser", "developer", "large", "system"]
        var claimed: [[String]] = []
        var filteredByID: [String: SmartGroup] = [:]

        for id in priority {
            guard var group = groups.first(where: { $0.id == id }) else { continue }
            group.entries = group.entries.filter { entry in
                let paths = entry.urls.map { $0.standardizedFileURL.pathComponents }
                let overlaps = paths.contains { path in
                    claimed.contains { existing in
                        Self.isPrefix(path, of: existing) || Self.isPrefix(existing, of: path)
                    }
                }
                if !overlaps { claimed.append(contentsOf: paths) }
                return !overlaps
            }
            filteredByID[id] = group
        }
        return groups.compactMap { filteredByID[$0.id] }
    }

    private static func isPrefix(_ candidate: [String], of path: [String]) -> Bool {
        candidate.count <= path.count && Array(path.prefix(candidate.count)) == candidate
    }

    // MARK: Clean

    func startClean() {
        guard selectedCount > 0, !isCleaning, !isScanning else { return }
        pendingGroups = groups
        // Build a flat preview (one row per selected entry) for the confirm sheet.
        pendingItems = groups.flatMap { group in
            group.selectedEntries.map { entry in
                CleanableItem(url: entry.urls.first ?? URL(fileURLWithPath: "/"),
                              displayName: entry.name, detail: entry.detail,
                              sizeBytes: entry.sizeBytes, safety: entry.safety,
                              categoryID: .userCache, isDirectory: true)
            }
        }
        mode = .trash
        showConfirm = true
    }

    func performClean() async {
        guard !isCleaning, !pendingItems.isEmpty else { return }
        isCleaning = true
        showConfirm = false
        defer { isCleaning = false }
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // Group every selected URL by its group's removal scope.
        var byScope: [RemovalScope: [CleanableItem]] = [:]
        var combined = CleanOutcome(mode: .trash)
        for group in pendingGroups {
            for entry in group.selectedEntries {
                if let browser = entry.browser,
                   !browser.bundleIdentifiers.isDisjoint(with: runningIDs) {
                    combined.failures.append(CleanFailure(
                        url: entry.urls.first ?? URL(fileURLWithPath: "/"),
                        reason: tr("browser.runningError", browser.displayName)
                    ))
                    continue
                }
                for (i, url) in entry.urls.enumerated() {
                    let item = CleanableItem(url: url, displayName: entry.name,
                                             sizeBytes: i == 0 ? entry.sizeBytes : 0,
                                             safety: entry.safety, categoryID: .userCache, isDirectory: true)
                    byScope[group.scope, default: []].append(item)
                }
            }
        }
        for (scope, items) in byScope {
            let outcome = await services.cleaner.clean(items: items, mode: .trash, scope: scope)
            combined.removedCount += outcome.removedCount
            combined.processedBytes += outcome.processedBytes
            combined.failures.append(contentsOf: outcome.failures)
        }
        lastOutcome = combined
        pendingItems = []
        pendingGroups = []
        isCleaning = false
        scan(preservingOutcome: true)
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
        pendingGroups = []
    }
}
