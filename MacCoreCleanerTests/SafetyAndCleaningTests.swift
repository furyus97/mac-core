import XCTest
@testable import MacCoreCleaner

final class SafetyAndCleaningTests: XCTestCase {
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "MacCoreCleanerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        home = root.appending(path: "Home", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        home = nil
    }

    func testCleaningScopeAllowsChildrenButNeverRoots() throws {
        let guardrail = SafetyGuard(home: home)
        let cacheRoot = home.appending(path: "Library/Caches", directoryHint: .isDirectory)
        let cacheItem = cacheRoot.appending(path: "com.example.cache", directoryHint: .isDirectory)

        XCTAssertNotNil(guardrail.violation(for: home, scope: .cleaning))
        XCTAssertNotNil(guardrail.violation(for: cacheRoot, scope: .cleaning))
        XCTAssertNil(guardrail.violation(for: cacheItem, scope: .cleaning))
        XCTAssertNotNil(guardrail.violation(for: URL(fileURLWithPath: "/System"), scope: .cleaning))
    }

    func testSymlinkCannotEscapeAllowlist() throws {
        let cacheRoot = home.appending(path: "Library/Caches", directoryHint: .isDirectory)
        let outside = root.appending(path: "Outside", directoryHint: .isDirectory)
        let link = cacheRoot.appending(path: "escape", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertNotNil(SafetyGuard(home: home).violation(for: link, scope: .cleaning))
    }

    func testCleanerPermanentlyDeletesOnlyAllowedItem() async throws {
        let cacheRoot = home.appending(path: "Library/Caches", directoryHint: .isDirectory)
        let file = cacheRoot.appending(path: "temporary.data", directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try Data("temporary".utf8).write(to: file)
        let actualBytes = FileScanner.recursiveSize(of: file)

        let item = CleanableItem(
            url: file,
            sizeBytes: 9,
            safety: .safe,
            categoryID: .userCache,
            isDirectory: false,
            isSelected: true
        )
        let cleaner = CleanerService(safety: SafetyGuard(home: home))
        let outcome = await cleaner.clean(items: [item], mode: .permanentDelete)

        XCTAssertEqual(outcome.removedCount, 1)
        XCTAssertEqual(outcome.processedBytes, actualBytes)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testCleanerRefusesOutsideItem() async throws {
        let outside = root.appending(path: "do-not-delete.txt", directoryHint: .notDirectory)
        try Data("protected".utf8).write(to: outside)
        let item = CleanableItem(
            url: outside,
            sizeBytes: 9,
            safety: .safe,
            categoryID: .userCache,
            isDirectory: false
        )

        let outcome = await CleanerService(safety: SafetyGuard(home: home))
            .clean(items: [item], mode: .permanentDelete)

        XCTAssertEqual(outcome.removedCount, 0)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testProcessMonitorCannotTerminateCurrentProcess() {
        XCTAssertFalse(ProcessMonitorService().terminate(pid: getpid(), force: false))
    }

    func testGenericCleanerCannotBypassBrowserSafety() {
        let safety = SafetyGuard(home: home)
        for browser in BrowserKind.allCases {
            for url in BrowserCleanerService.paths(for: browser, kind: .cache, home: home) {
                XCTAssertNotNil(safety.violation(for: url, scope: .cleaning), url.path)
            }
        }
        XCTAssertNotNil(safety.violation(for: home.appending(path: "Library/Caches/Google"), scope: .cleaning))
    }

    func testFirefoxBookmarksAndSharedCookieStoreAreNeverCandidates() {
        XCTAssertTrue(BrowserCleanerService.paths(for: .firefox, kind: .history, home: home).isEmpty)
        XCTAssertTrue(BrowserCleanerService.paths(for: .firefox, kind: .loginData, home: home).isEmpty)
        let sharedCookies = home.appending(path: "Library/Cookies/Cookies.binarycookies")
        XCTAssertFalse(BrowserCleanerService.paths(for: .safari, kind: .cookies, home: home).contains(sharedCookies))
        XCTAssertNotNil(SafetyGuard(home: home).violation(for: sharedCookies, scope: .browserData))
        let bookmarks = home.appending(path: "Library/Safari/Bookmarks.plist")
        XCTAssertNotNil(SafetyGuard(home: home).violation(for: bookmarks, scope: .browserData))
    }

    func testCleanerDeduplicatesParentsAndRecountsChangedFiles() async throws {
        let directory = home.appending(path: "Library/Caches/example")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "cache.bin")
        try Data(repeating: 7, count: 8192).write(to: file)
        let bytes = FileScanner.recursiveSize(of: directory)
        let parent = CleanableItem(url: directory, sizeBytes: 1, safety: .safe, categoryID: .userCache, isDirectory: true)
        let child = CleanableItem(url: file, sizeBytes: 1, safety: .safe, categoryID: .userCache, isDirectory: false)
        let outcome = await CleanerService(safety: SafetyGuard(home: home))
            .clean(items: [child, parent, parent], mode: .permanentDelete)
        XCTAssertEqual(outcome.removedCount, 1)
        XCTAssertEqual(outcome.processedBytes, bytes)
        XCTAssertTrue(outcome.failures.isEmpty)
    }

    func testLargeFileScannerDoesNotEnterApplicationPackages() async throws {
        let downloads = home.appending(path: "Downloads")
        let package = downloads.appending(path: "Example.app/Contents")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: package.appending(path: "important"))
        let regular = downloads.appending(path: "large.dat")
        try Data(repeating: 1, count: 8192).write(to: regular)
        let results = await LargeFileService().scan(roots: [downloads], minBytes: 1, progress: { _ in })
        XCTAssertEqual(results.map { $0.url.resolvingSymlinksInPath().path }, [regular.resolvingSymlinksInPath().path])
        XCTAssertEqual(results.first?.isSelected, false)
    }

    func testStorageScanUsesInjectedHomeAndExcludesBrowserCache() async throws {
        let caches = home.appending(path: "Library/Caches")
        let browserCache = caches.appending(path: "com.apple.Safari")
        try FileManager.default.createDirectory(at: browserCache, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8192).write(to: browserCache.appending(path: "cache"))
        let normal = caches.appending(path: "example.cache")
        try Data(repeating: 1, count: 8192).write(to: normal)
        let results = await ScanService(safety: SafetyGuard(home: home)).scan(categories: [.userCache], progress: { _ in })
        XCTAssertEqual(results.flatMap(\.items).map { $0.url.resolvingSymlinksInPath().path }, [normal.resolvingSymlinksInPath().path])
    }

    func testAppLeftoversDoNotMatchSiblingAppsOrSharedContainers() {
        XCTAssertTrue(AppInventoryService.matchesLeftover("com.example.app.plist", bundleID: "com.example.app"))
        XCTAssertTrue(AppInventoryService.matchesLeftover("com.example.app.savedState", bundleID: "com.example.app"))
        XCTAssertFalse(AppInventoryService.matchesLeftover("com.example.app.beta", bundleID: "com.example.app"))
        XCTAssertFalse(AppInventoryService.matchesLeftover("TEAM.com.example.app", bundleID: "com.example.app"))
        XCTAssertFalse(AppInventoryService.matchesLeftover("anything", bundleID: ""))
    }

    func testCurrentAppIsProtectedInEveryScope() {
        let safety = SafetyGuard()
        for scope: RemovalScope in [.cleaning, .application, .browserData, .userFiles] {
            XCTAssertNotNil(safety.violation(for: Bundle.main.bundleURL, scope: scope))
            XCTAssertNotNil(safety.violation(for: Bundle.main.bundleURL.appending(path: "Contents/Info.plist"), scope: scope))
        }
    }

    @MainActor
    func testMenuBarMetricsKeepOneItemAndRespectMaximum() {
        let suiteName = "MacCoreCleanerTests.MenuBar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SettingsStore(defaults: defaults)

        XCTAssertEqual(settings.menuBarMetrics, [.cpu, .memory, .temperature])
        settings.setMenuBarMetric(.diskFree, isEnabled: true)
        settings.setMenuBarMetric(.battery, isEnabled: true)
        XCTAssertEqual(settings.menuBarMetrics, [.cpu, .memory, .temperature, .diskFree])

        settings.moveMenuBarMetric(.diskFree, offset: -1)
        XCTAssertEqual(settings.menuBarMetrics, [.cpu, .memory, .diskFree, .temperature])

        settings.setMenuBarMetric(.cpu, isEnabled: false)
        settings.setMenuBarMetric(.memory, isEnabled: false)
        settings.setMenuBarMetric(.diskFree, isEnabled: false)
        settings.setMenuBarMetric(.temperature, isEnabled: false)
        XCTAssertEqual(settings.menuBarMetrics, [.temperature])
    }

    @MainActor
    func testMenuBarSettingsRecoverInvalidPersistedValues() {
        let suiteName = "MacCoreCleanerTests.MenuBarMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["unknown", "cpu", "cpu", "memory", "temperature", "diskFree", "battery"],
            forKey: "menuBarMetrics"
        )

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.menuBarMetrics, [.cpu, .memory, .temperature, .diskFree])

        defaults.set([], forKey: "menuBarMetrics")
        let recovered = SettingsStore(defaults: defaults)
        XCTAssertEqual(recovered.menuBarMetrics, [.cpu, .memory, .temperature])
    }
}
