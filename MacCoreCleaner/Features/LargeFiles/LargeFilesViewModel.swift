import Foundation
import SwiftUI

/// Drives the Large Files screen. Scans the user's media/document folders for
/// files at or above the configured size threshold, lets the user review and
/// select, then hands the selection to `CleanerService` (scope `.userFiles`)
/// for a confirmed Trash move. All heavy work happens off the main thread inside
/// the service; this view-model only orchestrates state on the main actor.
@MainActor
final class LargeFilesViewModel: ObservableObject {

    @Published var files: [CleanableItem] = []
    @Published var scanProgress: ScanProgress = .idle
    @Published var isScanning = false
    @Published var hasScanned = false

    // Clean flow
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

    /// Minimum size (bytes) for a file to be considered "large". Follows the
    /// Settings threshold, with a 10 MB floor so the list never floods.
    var thresholdBytes: Int64 {
        Int64(max(services.settings.downloadsThresholdMB, 10)) * 1_000_000
    }

    var advancedMode: Bool { services.settings.advancedMode }

    var totalCount: Int { files.count }
    var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }

    var selected: [CleanableItem] { files.filter(\.isSelected) }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.sizeBytes } }
    var selectedCount: Int { selected.count }

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
            let result = await self.services.largeFiles.scan(
                roots: nil,
                minBytes: self.thresholdBytes,
                progress: { progress in Task { @MainActor in
                    guard self.scanGeneration == generation else { return }
                    self.scanProgress = progress
                } }
            )
            if !Task.isCancelled {
                self.files = result
            }
            if self.scanGeneration == generation { self.isScanning = false }
        }
    }

    func cancelScan() {
        scanGeneration = UUID()
        scanTask?.cancel()
        isScanning = false
    }

    // MARK: Clean

    /// Capture the current selection and open the confirmation modal.
    func startClean() {
        let items = selected
        guard !items.isEmpty, !isCleaning, !isScanning else { return }
        pendingItems = items
        mode = services.settings.effectiveRemovalMode
        showConfirm = true
    }

    func performClean() async {
        let items = pendingItems
        guard !items.isEmpty, !isCleaning else { return }
        isCleaning = true
        showConfirm = false
        defer { isCleaning = false }
        let outcome = await services.cleaner.clean(items: items, mode: mode, scope: .userFiles)
        lastOutcome = outcome

        let removed = Set(
            items.filter { item in !outcome.failures.contains { $0.url == item.url } }.map(\.id)
        )
        files.removeAll { removed.contains($0.id) }
        pendingItems = []
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
    }
}
