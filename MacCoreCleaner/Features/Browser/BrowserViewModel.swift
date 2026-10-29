import Foundation
import SwiftUI
import AppKit

/// Drives the Browser screen. Detects installed browsers, sizes their data
/// categories, and runs the shared review-then-confirm removal flow under the
/// `.browserData` scope. Cache is selected by default; cookies/history/login are
/// opt-in because clearing them can sign the user out or lose sessions.
@MainActor
final class BrowserViewModel: ObservableObject {

    @Published var browsers: [BrowserKind] = []
    @Published var items: [BrowserDataItem] = []
    @Published var isLoading = false
    @Published var runningBrowsers: Set<BrowserKind> = []

    // Review + clean flow (mirrors the other cleaner screens)
    @Published var showConfirm = false
    @Published var pendingItems: [CleanableItem] = []
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isCleaning = false

    private let services: AppServices
    private var pendingBrowsers: Set<BrowserKind> = []

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    // MARK: Loading

    func load() async {
        guard !isCleaning, !isLoading else { return }
        isLoading = true
        refreshRunningBrowsers()
        browsers = await services.browser.detectBrowsers()
        let discovered = await services.browser.dataItems(for: browsers)
        items = services.settings.showRiskyItems
            ? discovered
            : discovered.filter { $0.kind.safety != .risky }
        isLoading = false
    }

    func refreshRunningBrowsers() {
        let runningIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        runningBrowsers = Set(BrowserKind.allCases.filter { !$0.bundleIdentifiers.isDisjoint(with: runningIDs) })
    }

    // MARK: Derived

    /// Bindings for one browser's data rows, so toggles write back into `items`.
    func items(for browser: BrowserKind) -> [Binding<BrowserDataItem>] {
        items.indices
            .filter { items[$0].browser == browser }
            .map { index in
                Binding(
                    get: { [weak self] in
                        guard let self, self.items.indices.contains(index) else {
                            return BrowserDataItem(browser: browser, kind: .cache, sizeBytes: 0, paths: [], isSelected: false)
                        }
                        return self.items[index]
                    },
                    set: { [weak self] newValue in
                        guard let self, self.items.indices.contains(index) else { return }
                        self.items[index] = newValue
                    }
                )
            }
    }

    var selected: [BrowserDataItem] { items.filter { $0.isSelected } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var selectedRunningBrowsers: Set<BrowserKind> {
        Set(selected.map(\.browser)).intersection(runningBrowsers)
    }

    // MARK: Review + clean

    func startClean() {
        guard !selected.isEmpty, !isCleaning, !isLoading else { return }
        refreshRunningBrowsers()
        guard selectedRunningBrowsers.isEmpty else { return }
        pendingBrowsers = Set(selected.map(\.browser))
        pendingItems = selected.flatMap { item in
            item.paths.enumerated().map { index, url in
                CleanableItem(
                    url: url,
                    displayName: url.lastPathComponent,
                    detail: item.browser.displayName,
                    // Attribute the category size once so the outcome summary is
                    // accurate without double-counting SQLite sidecar files.
                    sizeBytes: index == 0 ? item.sizeBytes : 0,
                    safety: item.kind.safety,
                    categoryID: .browserCache,
                    isDirectory: true,
                    isSelected: true
                )
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
        refreshRunningBrowsers()
        if let browser = pendingBrowsers.intersection(runningBrowsers).sorted(by: { $0.displayName < $1.displayName }).first {
            let url = pendingItems.first?.url ?? URL(fileURLWithPath: "/")
            lastOutcome = CleanOutcome(
                removedCount: 0,
                processedBytes: 0,
                failures: [CleanFailure(url: url, reason: tr("browser.runningError", browser.displayName))],
                mode: .trash
            )
            pendingItems = []
            return
        }
        let outcome = await services.cleaner.clean(items: pendingItems, mode: mode, scope: .browserData)
        lastOutcome = outcome
        pendingItems = []
        isCleaning = false
        await load()
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
        pendingBrowsers = []
    }
}
