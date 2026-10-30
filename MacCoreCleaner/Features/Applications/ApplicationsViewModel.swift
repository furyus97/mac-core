import Foundation
import SwiftUI
import AppKit

/// Drives the Applications (uninstaller) screen. Lists installed apps, lets the
/// user review an app together with its leftover support files, and removes the
/// app bundle + selected leftovers via `CleanerService` (Trash, `.application`
/// scope). All file work happens in the injected services off the main thread.
@MainActor
final class ApplicationsViewModel: ObservableObject {

    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false
    @Published var searchText = ""

    // Review + uninstall flow
    @Published var reviewing: InstalledApp?
    @Published var leftovers: [CleanableItem] = []
    @Published var showConfirm = false
    @Published var pendingItems: [CleanableItem] = []
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isCleaning = false
    private var pendingApp: InstalledApp?

    private let services: AppServices
    private var leftoversTask: Task<Void, Never>?

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    // MARK: Derived

    enum Filter: String, CaseIterable, Identifiable { case all, unused, largest; var id: String { rawValue } }
    @Published var filter: Filter = .all

    var unusedCount: Int { apps.filter { !$0.isSystem && $0.isUnused() }.count }

    var filteredApps: [InstalledApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch filter {
        case .all: break
        case .unused: result = result.filter { !$0.isSystem && $0.isUnused() }.sorted { ($0.lastUsedDate ?? .distantPast) < ($1.lastUsedDate ?? .distantPast) }
        case .largest: result.sort { $0.sizeBytes > $1.sizeBytes }
        }
        return result
    }

    /// Size of the leftover items the user has selected (excludes the app bundle).
    var selectedLeftoverBytes: Int64 {
        leftovers.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains { running in
            if let bundleID = app.bundleID, running.bundleIdentifier == bundleID { return true }
            return running.bundleURL?.standardizedFileURL == app.bundleURL.standardizedFileURL
        }
    }

    /// Two-way binding to a leftover item by index, for `CleanableItemRow` checkboxes.
    func leftoverBinding(_ index: Int) -> Binding<CleanableItem> {
        Binding(
            get: { [weak self] in
                guard let self, self.leftovers.indices.contains(index) else {
                    return CleanableItem(url: URL(fileURLWithPath: "/"), sizeBytes: 0, safety: .caution, categoryID: .application, isDirectory: false)
                }
                return self.leftovers[index]
            },
            set: { [weak self] newValue in
                guard let self, self.leftovers.indices.contains(index) else { return }
                self.leftovers[index] = newValue
            }
        )
    }

    // MARK: Loading

    func load() async {
        guard !isCleaning, !isLoading else { return }
        isLoading = true
        apps = await services.appInventory.installedApps()
        isLoading = false
    }

    // MARK: Review

    func openReview(_ app: InstalledApp) {
        guard !app.isSystem, !isRunning(app), !isCleaning else { return }
        reviewing = app
        leftovers = []
        leftoversTask?.cancel()
        leftoversTask = Task { [weak self] in
            guard let self else { return }
            let found = await self.services.appInventory.leftovers(for: app)
            if !Task.isCancelled, self.reviewing == app {
                self.leftovers = found
            }
        }
    }

    // MARK: Uninstall

    func startUninstall() {
        guard let app = reviewing, !app.isSystem, !isRunning(app), !isCleaning else { return }
        let bundleItem = CleanableItem(
            url: app.bundleURL,
            displayName: app.name,
            sizeBytes: app.sizeBytes,
            safety: .caution,
            categoryID: .application,
            isDirectory: true,
            isSelected: true
        )
        pendingItems = [bundleItem] + leftovers.filter(\.isSelected)
        pendingApp = app
        mode = .trash
        reviewing = nil
        showConfirm = true
    }

    func performUninstall() async {
        let items = pendingItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        showConfirm = false
        defer { isCleaning = false }
        if let app = pendingApp, isRunning(app), let appItem = items.first {
            lastOutcome = CleanOutcome(
                removedCount: 0,
                processedBytes: 0,
                failures: [CleanFailure(url: appItem.url, reason: tr("apps.runningError"))],
                mode: .trash
            )
            pendingItems = []
            pendingApp = nil
            return
        }
        let outcome = await services.cleaner.clean(items: items, mode: mode, scope: .application)
        lastOutcome = outcome
        pendingItems = []
        pendingApp = nil
        isCleaning = false
        await load()
    }

    func cancelUninstall() {
        showConfirm = false
        pendingItems = []
        pendingApp = nil
    }
}
