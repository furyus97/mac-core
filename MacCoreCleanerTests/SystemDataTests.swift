import XCTest
@testable import MacCoreCleaner

final class SystemDataTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "MacCore-SystemData-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try FileManager.default.removeItem(at: home) }
    }

    @discardableResult
    private func file(_ relative: String) throws -> URL {
        let url = home.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 8192).write(to: url)
        return url
    }

    func testReadOnlyDataIsCountedOnceAndNeverOfferedForCleaning() async throws {
        let cache = try file("Library/Caches/example/cache")
        let support = try file("Library/Application Support/Example/data")
        let backup = try file("Library/Application Support/MobileSync/Backup/device/backup")
        let archive = try file("Library/Developer/Xcode/Archives/archive/data")
        let result = await SystemDataAnalyzer(safety: SafetyGuard(home: home)).analyze(progress: { _ in })
        let report = try XCTUnwrap(result)
        XCTAssertFalse(report.isPartial)
        XCTAssertEqual(report.identifiedBytes, [cache, support, backup, archive].reduce(0) {
            $0 + FileScanner.recursiveSize(of: $1)
        })
        XCTAssertEqual(report.reviewableBytes, FileScanner.recursiveSize(of: cache))
        for id in ["support", "backups", "archives", "containers", "groups"] {
            let group = try XCTUnwrap(report.groups.first { $0.id == id })
            XCTAssertNil(group.categoryID)
            XCTAssertTrue(group.items.isEmpty)
        }
        XCTAssertTrue(report.groups.flatMap(\.items).allSatisfy { !$0.isSelected })
    }

    func testBrowserCachesAndSymlinkedTreesAreNotCleanable() async throws {
        try file("Library/Caches/com.apple.Safari/cache")
        let ordinary = try file("Library/Caches/example/cache")
        let important = try file("Documents/important")
        let link = home.appending(path: "Library/Caches/example/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: important)
        let result = await SystemDataAnalyzer(safety: SafetyGuard(home: home)).analyze(progress: { _ in })
        let report = try XCTUnwrap(result)
        XCTAssertTrue(report.isPartial)
        XCTAssertGreaterThan(report.identifiedBytes, 0)
        XCTAssertEqual(report.reviewableBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ordinary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: important.path))
    }

    func testSymlinkedAnalysisRootIsNotTraversed() async throws {
        let important = try file("Documents/important")
        try FileManager.default.createDirectory(at: home.appending(path: "Library"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "Library/Caches"),
            withDestinationURL: important.deletingLastPathComponent())
        let result = await SystemDataAnalyzer(safety: SafetyGuard(home: home)).analyze(progress: { _ in })
        let report = try XCTUnwrap(result)
        XCTAssertTrue(report.isPartial)
        XCTAssertEqual(report.identifiedBytes, 0)
        XCTAssertEqual(report.reviewableBytes, 0)
    }

    func testOnlyReviewedCacheCandidateCanBeRemoved() async throws {
        let cache = try file("Library/Caches/example/cache")
        let backup = try file("Library/Application Support/MobileSync/Backup/device/backup")
        let safety = SafetyGuard(home: home)
        let result = await SystemDataAnalyzer(safety: safety).analyze(progress: { _ in })
        let report = try XCTUnwrap(result)
        let candidates = report.groups.flatMap(\.items)
        XCTAssertEqual(candidates.count, 1)
        let outcome = await CleanerService(safety: safety).clean(items: candidates, mode: .permanentDelete)
        XCTAssertEqual(outcome.removedCount, 1)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
        let refreshed = await SystemDataAnalyzer(safety: safety).analyze(progress: { _ in })
        XCTAssertEqual(refreshed?.reviewableBytes, 0)
    }

    @MainActor
    func testCancellationDoesNotPublishOldAnalysis() async throws {
        let vm = SystemDataViewModel(safety: SafetyGuard(home: home))
        vm.analyze()
        vm.cancelAnalysis()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertTrue(vm.wasCancelled)
        XCTAssertNil(vm.report)
    }

    @MainActor
    func testReviewIsOptInAndConfirmationCapturesSelection() async throws {
        let cache = try file("Library/Caches/example/cache")
        let result = await SystemDataAnalyzer(safety: SafetyGuard(home: home)).analyze(progress: { _ in })
        let group = try XCTUnwrap(result?.groups.first { $0.id == "caches" })
        let vm = SystemDataViewModel(safety: SafetyGuard(home: home))
        vm.review(group)
        vm.stageClean()
        XCTAssertFalse(vm.showConfirm)
        vm.reviewing?.items[0].isSelected = true
        vm.stageClean()
        XCTAssertTrue(vm.showConfirm)
        XCTAssertEqual(vm.mode, .trash)
        XCTAssertEqual(vm.pendingItems.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        vm.cancelClean()
        XCTAssertTrue(vm.pendingItems.isEmpty)
    }
}
