import Foundation
import SwiftUI

/// Drives the Storage screen. Per spec, each category is *reviewed* before any
/// removal: the user opens a category, inspects/selects its items, and only then
/// confirms a Trash move. Scanning runs off the main thread inside the services.
@MainActor
final class StorageCleanerViewModel: ObservableObject {

    let categories: [CleanCategoryID] = [.userCache, .userLogs, .trash, .downloadsLargeFiles]

    @Published var results: [CategoryScanResult] = []
    @Published var scanProgress: ScanProgress = .idle
    @Published var isScanning = false
    @Published var hasScanned = false

    // Review + clean flow
    @Published var reviewing: CleanCategoryID?      // category whose items are open in the review sheet
    @Published var showConfirm = false
    @Published var pendingItems: [CleanableItem] = []
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isEmptyingTrash = false
    @Published private(set) var isCleaning = false

    private let services: AppServices
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    // MARK: Derived

    /// Total bytes found across all categories (the big "Recoverable" number).
    var totalRecoverable: Int64 { results.totalBytes }
    var advancedMode: Bool { services.settings.advancedMode }

    func result(for id: CleanCategoryID) -> CategoryScanResult? {
        results.first { $0.id == id }
    }

    var reviewingResult: CategoryScanResult? {
        guard let reviewing else { return nil }
        return result(for: reviewing)
    }

    var reviewingSelectedItems: [CleanableItem] {
        reviewingResult?.selectedItems ?? []
    }

    /// Two-way binding to the category currently being reviewed (drives checkboxes).
    func reviewBinding() -> Binding<CategoryScanResult>? {
        guard let id = reviewing, let idx = results.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { [weak self] in
                guard let self, self.results.indices.contains(idx) else {
                    return CategoryScanResult(category: .metadata(for: id), items: [])
                }
                return self.results[idx]
            },
            set: { [weak self] newValue in
                guard let self, self.results.indices.contains(idx) else { return }
                self.results[idx] = newValue
            }
        )
    }

    // MARK: Scanning

    func scan() {
        guard !isCleaning else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        isScanning = true
        hasScanned = true
        scanProgress = .idle
        lastOutcome = nil

        scanTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.services.scanner.scan(
                categories: self.categories,
                progress: { progress in Task { @MainActor in
                    guard self.scanGeneration == generation else { return }
                    self.scanProgress = progress
                } }
            )
            if !Task.isCancelled {
                // Pre-expand so the review sheet shows items immediately.
                self.results = result.map { var r = $0; r.isExpanded = true; return r }
            }
            if self.scanGeneration == generation { self.isScanning = false }
        }
    }

    func cancelScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: Review + clean

    func openReview(_ id: CleanCategoryID) {
        guard !isCleaning, !isScanning else { return }
        reviewing = id
    }

    /// Capture the reviewed selection, close the review sheet, and open the
    /// confirmation modal (two separate sheets, never nested).
    func startClean() {
        let items = reviewingSelectedItems
        guard !items.isEmpty, !isCleaning, !isScanning else { return }
        isEmptyingTrash = reviewing == .trash
        pendingItems = items
        // Items already in ~/.Trash cannot be moved to Trash again. Emptying
        // Trash is therefore an explicit permanent-delete flow with its own
        // acknowledgement in the confirmation sheet.
        mode = isEmptyingTrash ? .permanentDelete : services.settings.effectiveRemovalMode
        reviewing = nil
        showConfirm = true
    }

    func performClean() async {
        let items = pendingItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        showConfirm = false
        defer { isCleaning = false }
        let outcome = await services.cleaner.clean(items: items, mode: mode)
        lastOutcome = outcome
        pendingItems = []
        isEmptyingTrash = false

        let removed = Set(
            items.filter { item in !outcome.failures.contains { $0.url == item.url } }.map { $0.id }
        )
        for index in results.indices {
            results[index].items.removeAll { removed.contains($0.id) }
        }
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
        isEmptyingTrash = false
    }
}
