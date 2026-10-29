import XCTest
@testable import MacCoreCleaner

final class LocalizationTests: XCTestCase {
    func testLiteralTranslationKeysExistInCatalog() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "MacCoreCleaner")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: source, includingPropertiesForKeys: nil))
        let regex = try NSRegularExpression(pattern: #"tr\(\s*"([^"]+)""#)
        let english = try XCTUnwrap(LocalizationCatalog.tables[.en])
        for case let file as URL in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let key = String(code[Range(match.range(at: 1), in: code)!])
                if key.contains("\\(") { continue } // dynamic enum keys are checked below
                XCTAssertNotNil(english[key], "Missing key \(key) in \(file.lastPathComponent)")
            }
        }
        for item in NavItem.allCases { XCTAssertNotNil(english["nav.\(item.rawValue)"]) }
        for item in CleanCategory.catalog.keys {
            XCTAssertNotNil(english["cat.\(item.rawValue).title"])
            XCTAssertNotNil(english["cat.\(item.rawValue).sub"])
        }
    }

    func testEveryLanguageHasEveryKeyAndMatchingFormatArguments() throws {
        let english = try XCTUnwrap(LocalizationCatalog.tables[.en])
        XCTAssertGreaterThan(english.count, 300)
        let regex = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:\.\d+)?(?:ll|l)?[@diuf]"#)
        func placeholders(_ value: String) -> [String] {
            regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
                let part = String(value[Range($0.range, in: value)!])
                return part.replacingOccurrences(of: #"\d+\$"#, with: "", options: .regularExpression)
            }.sorted()
        }
        for language in Lang.allCases {
            let table = try XCTUnwrap(LocalizationCatalog.tables[language])
            XCTAssertEqual(Set(table.keys), Set(english.keys), language.rawValue)
            for (key, reference) in english {
                let value = try XCTUnwrap(table[key], "\(language): \(key)")
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key)
                XCTAssertEqual(placeholders(value), placeholders(reference), "\(language): \(key)")
            }
            let folder = try XCTUnwrap(Bundle.main.path(forResource: language.rawValue, ofType: "lproj"))
            let info = try Data(contentsOf: URL(fileURLWithPath: folder).appending(path: "InfoPlist.strings"))
            let strings = try XCTUnwrap(PropertyListSerialization.propertyList(from: info, format: nil) as? [String: String])
            for key in ["NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription"] {
                XCTAssertFalse(try XCTUnwrap(strings[key]).isEmpty)
            }
        }
    }

    @MainActor
    func testLanguageResolutionAndMigration() {
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["zh-TW"]), .zhHant)
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["zh-HK"]), .zhHant)
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["zh-CN"]), .zhHans)
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["pt-PT"]), .ptBR)
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["it-IT", "fr-FR"]), .fr)
        XCTAssertEqual(LocalizationManager.resolve(.system, preferred: ["xx"]), .en)
        XCTAssertEqual(AppLanguage(rawValue: "korean")?.resolved, .ko)
        XCTAssertTrue(Lang.ar.isRightToLeft)
        XCTAssertFalse(Lang.en.isRightToLeft)
    }

    func testFormattingHandlesUnavailableAndOutOfRangeValues() {
        XCTAssertFalse(ByteFormat.percent(.nan).contains("nan"))
        XCTAssertEqual(ByteFormat.percent(-1), ByteFormat.percent(0))
        XCTAssertEqual(ByteFormat.percent(2), ByteFormat.percent(1))
        XCTAssertEqual(ByteFormat.temperature(.infinity), "—")
        XCTAssertEqual(DateFormat.string(nil), "—")
        XCTAssertEqual(DateFormat.daysSince(Date().addingTimeInterval(86400)), 0)
    }
}
