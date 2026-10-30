import XCTest
@testable import MacCoreCleaner

/// Space Map + Duplicates. Every test works on its own temporary fixture folder;
/// nothing outside it is scanned, and only fixture files are ever trashed.
final class SpaceMapDuplicatesTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory
            .appending(path: "MacCoreSpaceDupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        home = root.appending(path: "Home", directoryHint: .isDirectory)
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fm.removeItem(at: root) }
        root = nil
        home = nil
    }

    // MARK: Helpers

    @discardableResult
    private func write(_ relative: String, bytes: Int, seed: UInt8 = 7, in base: URL? = nil) throws -> URL {
        let url = (base ?? home).appending(path: relative, directoryHint: .notDirectory)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { raw in
            for i in 0..<bytes { raw[i] = UInt8(truncatingIfNeeded: i &* 31 &+ Int(seed)) }
        }
        try data.write(to: url)
        return url
    }

    private func allocated(_ url: URL) throws -> Int64 {
        let v = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
    }

    private func duplicateFile(_ url: URL) throws -> DuplicateFile {
        let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        return DuplicateFile(url: url, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate, created: v.creationDate)
    }

    // MARK: Space Map

    func testSpaceMapAggregatesAllocatedSizesAndSkipsSymlinks() async throws {
        let map = home.appending(path: "Map", directoryHint: .isDirectory)
        let a1 = try write("Folder/one.bin", bytes: 120_000, in: map)
        let a2 = try write("Folder/Nested/two.bin", bytes: 40_000, in: map)
        let loose = try write("loose.bin", bytes: 9_000, in: map)
        let pkgFile = try write("Tool.app/Contents/MacOS/tool", bytes: 30_000, in: map)
        // A big file outside the measured tree, reachable only through symlinks.
        let outside = try write("Outside/huge.bin", bytes: 2_000_000, in: root)
        try fm.createSymbolicLink(at: map.appending(path: "LinkToOutside"), withDestinationURL: outside.deletingLastPathComponent())
        try fm.createSymbolicLink(at: map.appending(path: "Folder/link.bin"), withDestinationURL: outside)

        let listing = await SpaceMapService.listing(of: map, limit: 12)
        let byName = Dictionary(uniqueKeysWithValues: listing.nodes.map { ($0.url.lastPathComponent, $0) })

        XCTAssertNil(byName["LinkToOutside"], "symlinks must not appear")
        XCTAssertEqual(Set(byName.keys), ["Folder", "loose.bin", "Tool.app"])
        XCTAssertEqual(byName["Folder"]?.bytes, try allocated(a1) + allocated(a2), "symlink inside a folder is not followed or counted")
        XCTAssertEqual(byName["Folder"]?.isDirectory, true)
        XCTAssertEqual(byName["loose.bin"]?.bytes, try allocated(loose))
        XCTAssertEqual(byName["Tool.app"]?.isDirectory, false, "packages are a single, non-drillable item")
        XCTAssertEqual(byName["Tool.app"]?.bytes, try allocated(pkgFile))
        XCTAssertEqual(listing.nodes.map(\.bytes), listing.nodes.map(\.bytes).sorted(by: >))
        XCTAssertEqual(listing.totalBytes, listing.nodes.reduce(0) { $0 + $1.bytes })
        XCTAssertFalse(listing.isPartial)

        let limited = await SpaceMapService.listing(of: map, limit: 1)
        XCTAssertEqual(limited.nodes.count, 1)
        XCTAssertEqual(limited.remainderCount, 2)
        XCTAssertEqual(limited.nodes[0].bytes + limited.remainderBytes, listing.totalBytes)

        let children = await SpaceMapService.children(of: map)
        XCTAssertEqual(children.map(\.url), listing.nodes.map(\.url))
        XCTAssertNotNil(SpaceMapService.volumeSummary())
    }

    func testBubblePackingDoesNotOverlapAndStaysInBounds() {
        let weightSets: [[Double]] = [
            [92, 41, 28, 17, 12, 8, 4, 1.8, 0.9, 0.4, 0.1, 0.01],
            [1],
            [5, 5],
            [100, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
            (1...30).map { Double(($0 * 7919) % 97 + 1) },
            [0, 0, 0],
        ]
        let sizes = [CGSize(width: 360, height: 300), CGSize(width: 900, height: 560), CGSize(width: 220, height: 420)]
        for weights in weightSets {
            for size in sizes {
                let circles = BubblePacker.pack(weights: weights, in: size)
                XCTAssertEqual(circles.count, weights.count)
                XCTAssertEqual(circles, BubblePacker.pack(weights: weights, in: size), "deterministic")
                for c in circles {
                    XCTAssertGreaterThan(c.radius, 0)
                    XCTAssertGreaterThanOrEqual(c.center.x - c.radius, -0.01, "\(size) \(weights)")
                    XCTAssertGreaterThanOrEqual(c.center.y - c.radius, -0.01)
                    XCTAssertLessThanOrEqual(c.center.x + c.radius, size.width + 0.01)
                    XCTAssertLessThanOrEqual(c.center.y + c.radius, size.height + 0.01)
                }
                for i in circles.indices {
                    for j in circles.indices where j > i {
                        let d = hypot(circles[i].center.x - circles[j].center.x, circles[i].center.y - circles[j].center.y)
                        XCTAssertGreaterThanOrEqual(d, circles[i].radius + circles[j].radius - 0.01, "overlap \(i)/\(j) in \(size)")
                    }
                }
            }
        }
        // Area is proportional to weight (above the small visibility floor).
        let circles = BubblePacker.pack(weights: [400, 100, 25], in: CGSize(width: 600, height: 400))
        XCTAssertEqual(circles[0].radius / circles[1].radius, 2, accuracy: 0.001)
        XCTAssertEqual(circles[1].radius / circles[2].radius, 2, accuracy: 0.001)
        XCTAssertTrue(BubblePacker.pack(weights: [], in: CGSize(width: 300, height: 300)).isEmpty)
    }

    // MARK: Duplicates

    func testDuplicateGroupingByContent() async throws {
        let mb = 1_100_000
        let original = try write("Documents/report.bin", bytes: mb, seed: 1)
        let copy = try write("Downloads/report copy.bin", bytes: mb, seed: 1)
        // Same size, same first 64 KB, different tail → must NOT group.
        let sameSize = try write("Documents/other.bin", bytes: mb, seed: 1)
        let handle = try FileHandle(forWritingTo: sameSize)
        try handle.seek(toOffset: UInt64(mb - 1))
        try handle.write(contentsOf: Data([0xFF]))
        try handle.close()
        // Same size, entirely different content → must NOT group.
        try write("Pictures/different.bin", bytes: mb, seed: 99)
        // Excluded: hidden file, symlink, small file, anything in ~/Library, inside a package.
        try write("Documents/.hidden-copy.bin", bytes: mb, seed: 1)
        try fm.createSymbolicLink(at: home.appending(path: "Documents/link.bin"), withDestinationURL: original)
        try write("Documents/small-a.bin", bytes: 4_000, seed: 3)
        try write("Downloads/small-b.bin", bytes: 4_000, seed: 3)
        try write("Library/Caches/cached-copy.bin", bytes: mb, seed: 1)
        try write("Documents/Bundle.app/Contents/payload.bin", bytes: mb, seed: 1)
        // A hard link is the same file, not a duplicate.
        try fm.linkItem(at: copy, to: home.appending(path: "Downloads/hardlink.bin"))

        let roots = DuplicateFinder.defaultRoots(home: home) + [home.appending(path: "Library", directoryHint: .isDirectory)]
        let result = await DuplicateFinder.scan(roots: roots, home: home)

        XCTAssertFalse(result.cancelled)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.groups.count, 1)
        let group = try XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(group.size, Int64(mb))
        XCTAssertEqual(group.wastedBytes, Int64(mb))
        let names = Set(group.files.map(\.name))
        XCTAssertTrue(names.contains("report.bin"))
        XCTAssertTrue(names.isSubset(of: ["report.bin", "report copy.bin", "hardlink.bin"]))
        XCTAssertEqual(group.suggestedKeeper.name, "report.bin", "the copy outside Downloads is kept")

        // Lowering the minimum size finds the small pair too.
        let small = await DuplicateFinder.scan(roots: roots, home: home, minimumSize: 1_000)
        XCTAssertEqual(small.groups.count, 2)
        XCTAssertEqual(small.groups.first?.size, Int64(mb), "sorted by wasted bytes")
    }

    func testKeeperPrefersOutsideDownloadsThenOldest() {
        let dl = home.appending(path: "Downloads/a.bin"), doc = home.appending(path: "Documents/a.bin")
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let files = [
            DuplicateFile(url: dl, size: 10, modified: old, created: old),
            DuplicateFile(url: doc, size: 10, modified: new, created: new),
        ]
        XCTAssertEqual(DuplicateFinder.keeperOrder(files, home: home).first?.url, doc)
        let both = [
            DuplicateFile(url: home.appending(path: "Documents/new.bin"), size: 10, modified: new, created: new),
            DuplicateFile(url: home.appending(path: "Pictures/old.bin"), size: 10, modified: old, created: old),
        ]
        XCTAssertEqual(DuplicateFinder.keeperOrder(both, home: home).first?.url.lastPathComponent, "old.bin")
    }

    func testTrashSkipsChangedFilesAndNeverRemovesLastCopy() async throws {
        let tag = "mc-dup-test-\(UUID().uuidString.prefix(8))"
        let keep = try write("Documents/\(tag)-keep.bin", bytes: 64, seed: 5)
        let unchanged = try write("Downloads/\(tag)-a.bin", bytes: 64, seed: 5)
        let changed = try write("Downloads/\(tag)-b.bin", bytes: 64, seed: 5)
        let files = try [keep, unchanged, changed].map(duplicateFile)
        let group = DuplicateGroup(id: "fixture", size: 64, files: files)
        let fixtureTrash = home.appending(path: ".FixtureTrash", directoryHint: .isDirectory)
        try fm.createDirectory(at: fixtureTrash, withIntermediateDirectories: true)
        let cleaner = CleanerService(safety: SafetyGuard(home: home)) { url in
            try FileManager.default.moveItem(at: url, to: fixtureTrash.appending(path: url.lastPathComponent))
        }

        // Selecting every copy is refused outright: nothing moves.
        let refused = await DuplicateFinder.trash(files, in: [group], cleaner: cleaner)
        XCTAssertEqual(refused.removedCount, 0)
        XCTAssertEqual(refused.failures.count, 3)
        XCTAssertTrue([keep, unchanged, changed].allSatisfy { fm.fileExists(atPath: $0.path) })

        // A file modified after the scan is skipped; the untouched one goes to the Trash.
        try Data(repeating: 1, count: 80).write(to: changed)
        let outcome = await DuplicateFinder.trash([files[1], files[2]], in: [group], cleaner: cleaner)
        XCTAssertEqual(outcome.mode, .trash)
        XCTAssertEqual(outcome.removedCount, 1)
        XCTAssertEqual(outcome.failures.map(\.url), [changed])
        XCTAssertEqual(outcome.failures.first?.reason, tr("dup.changed"))
        XCTAssertFalse(fm.fileExists(atPath: unchanged.path))
        XCTAssertTrue(fm.fileExists(atPath: changed.path))
        XCTAssertTrue(fm.fileExists(atPath: keep.path))

        // Files outside the user-file allowlist are refused by SafetyGuard.
        let stray = try write("\(tag)-stray.bin", bytes: 64, seed: 5, in: root)
        let strayKeep = try write("\(tag)-stray-keep.bin", bytes: 64, seed: 5, in: root)
        let strayFiles = try [strayKeep, stray].map(duplicateFile)
        let strayOutcome = await DuplicateFinder.trash([strayFiles[1]],
                                                        in: [DuplicateGroup(id: "stray", size: 64, files: strayFiles)],
                                                        cleaner: cleaner)
        XCTAssertEqual(strayOutcome.removedCount, 0)
        XCTAssertEqual(strayOutcome.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: stray.path))

        XCTAssertTrue(fm.fileExists(atPath: fixtureTrash.appending(path: unchanged.lastPathComponent).path))
    }

    // MARK: Localization

    func testNewKeysExistInEveryLanguage() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "MacCoreCleaner/Features")
        let files = ["SpaceMap/SpaceMapView.swift", "SpaceMap/SpaceBubbleChart.swift", "SpaceMap/SpaceMapService.swift",
                     "Duplicates/DuplicatesView.swift", "Duplicates/DuplicateFinder.swift"]
        let regex = try NSRegularExpression(pattern: #"tr\(\s*"([^"]+)""#)
        var keys: Set<String> = ["nav.spaceMap", "nav.duplicates"]
        for file in files {
            let code = try String(contentsOf: source.appending(path: file), encoding: .utf8)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                keys.insert(String(code[Range(match.range(at: 1), in: code)!]))
            }
        }
        XCTAssertGreaterThan(keys.count, 40)
        let english = try XCTUnwrap(LocalizationCatalog.tables[.en])
        let featureKeys = Set(english.keys.filter { $0.hasPrefix("spacemap.") || $0.hasPrefix("dup.") })
        XCTAssertEqual(english["nav.spaceMap"], "Space Map")
        XCTAssertEqual(LocalizationCatalog.tables[.ko]?["nav.spaceMap"], "공간 지도")
        XCTAssertEqual(english["nav.duplicates"], "Duplicates")
        XCTAssertEqual(LocalizationCatalog.tables[.ko]?["nav.duplicates"], "중복 파일")
        for language in Lang.allCases {
            let table = try XCTUnwrap(LocalizationCatalog.tables[language], language.rawValue)
            for key in keys.union(featureKeys) {
                let value = try XCTUnwrap(table[key], "\(language.rawValue) is missing \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(language.rawValue): \(key)")
            }
        }
    }
}
