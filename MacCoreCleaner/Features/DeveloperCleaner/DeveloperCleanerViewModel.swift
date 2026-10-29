import Foundation
import SwiftUI

/// Drives the Developer screen. Scans Xcode + tool caches (DerivedData, Archives,
/// Simulator, SPM, Homebrew, Gradle), surfaces Docker as display-only, and uses
/// the same review-before-remove flow as Storage.
@MainActor
final class DeveloperCleanerViewModel: ObservableObject {

    /// Cleanable developer categories (all live inside the safety allowlist).
    let cleanableCategories: [CleanCategoryID] = [
        .xcodeDerivedData, .xcodeArchives, .simulatorCache,
        .swiftPMCache, .homebrewCache, .gradleCache,
    ]
    /// Surfaced for awareness but never deleted by the app.
    let displayOnlyCategories: [CleanCategoryID] = [.dockerData]

    @Published var results: [CategoryScanResult] = []
    @Published var dockerSize: Int64 = 0
    @Published var scanProgress: ScanProgress = .idle
    @Published var isScanning = false
    @Published var hasScanned = false

    // Review + clean flow (mirrors StorageCleanerViewModel)
    @Published var reviewing: CleanCategoryID?
    @Published var showConfirm = false
    @Published var pendingItems: [CleanableItem] = []
    @Published var mode: RemovalMode = .trash
    @Published var lastOutcome: CleanOutcome?
    @Published private(set) var isCleaning = false

    private let services: AppServices
    private var scanTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    init(services: AppServices? = nil) {
        self.services = services ?? .shared
    }

    // MARK: Derived

    var totalRecoverable: Int64 { results.totalBytes }
    var advancedMode: Bool { services.settings.advancedMode }

    func result(for id: CleanCategoryID) -> CategoryScanResult? { results.first { $0.id == id } }

    func lastModified(for id: CleanCategoryID) -> Date? {
        result(for: id)?.items.compactMap(\.modifiedDate).max()
    }

    var reviewingResult: CategoryScanResult? {
        guard let reviewing else { return nil }
        return result(for: reviewing)
    }
    var reviewingSelectedItems: [CleanableItem] { reviewingResult?.selectedItems ?? [] }

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
            let found = await self.services.developer.scan(
                categories: self.cleanableCategories,
                progress: { progress in Task { @MainActor in
                    guard self.scanGeneration == generation else { return }
                    self.scanProgress = progress
                } }
            )
            let docker = await self.services.developer.displayOnlySize(for: .dockerData)
            if !Task.isCancelled {
                self.results = found.map { var r = $0; r.isExpanded = true; return r }
                self.dockerSize = docker
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

    func startClean() {
        let items = reviewingSelectedItems
        guard !items.isEmpty, !isCleaning, !isScanning else { return }
        pendingItems = items
        mode = services.settings.effectiveRemovalMode
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
    }
}
