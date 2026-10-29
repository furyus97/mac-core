import XCTest
import AppKit
@testable import MacCoreCleaner

final class NetworkFormattingAndLifecycleTests: XCTestCase {
    @MainActor
    func testNetworkUnitsStaySymbolicInEverySupportedLanguage() throws {
        let localization = LocalizationManager.shared
        let previous = localization.language
        defer { localization.language = previous }
        for language in AppLanguage.allCases where language != .system {
            localization.language = language
            for (value, unit) in [(0.0, "B/s"), (791, "B/s"), (1000, "KB/s"),
                                  (30_000, "KB/s"), (3_200_000, "MB/s"), (2_000_000_000, "GB/s")] {
                let result = ByteFormat.networkRate(value)
                XCTAssertTrue(result.hasSuffix(" " + unit), "\(language): \(result)")
                XCTAssertFalse(result.contains("바이트"))
            }
        }
        localization.language = .korean
        XCTAssertEqual(ByteFormat.networkRate(791), "791 B/s")
        XCTAssertEqual(ByteFormat.networkRate(0), "0 B/s")
        XCTAssertEqual(ByteFormat.networkRate(30_000), "30 KB/s")
        XCTAssertEqual(ByteFormat.networkRate(3_200_000), "3.2 MB/s")
        XCTAssertEqual(ByteFormat.networkRate(999_999), "1 MB/s")
        XCTAssertEqual(ByteFormat.networkRate(-1), "0 B/s")
        XCTAssertEqual(ByteFormat.networkRate(.nan), "—")
        XCTAssertEqual(ByteFormat.networkRate(.infinity), "—")
        XCTAssertFalse(ByteFormat.networkRate(Double.greatestFiniteMagnitude).isEmpty)
        localization.language = .german
        XCTAssertEqual(ByteFormat.networkRate(3_200_000), "3,2 MB/s")
    }

    @MainActor
    func testClosingTheLastWindowDoesNotRequestApplicationTermination() {
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }
}
