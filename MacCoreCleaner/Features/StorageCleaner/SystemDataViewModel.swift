import SwiftUI

@MainActor
final class SystemDataViewModel: ObservableObject {
    @Published private(set) var report: SystemDataReport?
    @Published private(set) var isAnalyzing = false
    @Published private(set) var isCleaning = false
    @Published private(set) var wasCancelled = false
    @Published private(set) var progress = ScanProgress.idle
    @Published var reviewing: CategoryScanResult?
    @Published var showConfirm = false
    @Published var mode: RemovalMode = .trash
    @Published private(set) var pendingItems: [CleanableItem] = []
    @Published private(set) var lastOutcome: CleanOutcome?

    private let analyzer: SystemDataAnalyzer
    private let cleaner: CleanerService
    private var analysisTask: Task<Void, Never>?
    private var generation = UUID()

    init(safety: SafetyGuard = SafetyGuard(), report: SystemDataReport? = nil) {
        analyzer = SystemDataAnalyzer(safety: safety)
        cleaner = CleanerService(safety: safety)
        self.report = report
    }

    func analyze(keepOutcome: Bool = false) {
        guard !isCleaning, reviewing == nil, !showConfirm else { return }
        analysisTask?.cancel()
        let token = UUID()
        generation = token
        isAnalyzing = true
        wasCancelled = false
        report = nil
        progress = .idle
        if !keepOutcome { lastOutcome = nil }
        analysisTask = Task { [weak self] in
            guard let self else { return }
            let report = await analyzer.analyze { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.progress = update
                }
            }
            guard !Task.isCancelled, generation == token else { return }
            self.report = report
            isAnalyzing = false
        }
    }

    func cancelAnalysis() {
        guard isAnalyzing else { return }
        generation = UUID()
        analysisTask?.cancel()
        isAnalyzing = false
        wasCancelled = true
    }

    func review(_ group: SystemDataGroup) {
        guard !isAnalyzing, !isCleaning, let category = group.categoryID, !group.items.isEmpty else { return }
        reviewing = CategoryScanResult(category: .metadata(for: category), items: group.items)
    }

    func stageClean() {
        guard !isCleaning, let review = reviewing, !review.selectedItems.isEmpty else { return }
        pendingItems = review.selectedItems
        mode = .trash
        reviewing = nil
        showConfirm = true
    }

    func cancelClean() {
        showConfirm = false
        pendingItems = []
    }

    func clean() async {
        guard !isCleaning, !pendingItems.isEmpty else { return }
        let items = pendingItems
        isCleaning = true
        showConfirm = false
        lastOutcome = await cleaner.clean(items: items, mode: mode)
        pendingItems = []
        isCleaning = false
        analyze(keepOutcome: true)
    }
}
