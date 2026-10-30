import XCTest
@testable import MacCoreCleaner

final class SpeedProtectionTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appending(path: "SpeedProtectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Only our own temp fixture folder is cleaned up.
        if let tempDir, tempDir.path.contains("SpeedProtectionTests-") {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    private func writePlist(_ dict: [String: Any], named name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    // MARK: - Startup items

    func testParsesLaunchAgentFixture() throws {
        let agents = tempDir.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        _ = try writePlist([
            "Label": "com.example.helper",
            "ProgramArguments": ["/Applications/Example Tool.app/Contents/MacOS/helper", "--daemon"],
            "RunAtLoad": true,
        ], named: "com.example.helper.plist", in: agents)
        _ = try writePlist([
            "Label": "org.sample.sync",
            "Program": "/usr/local/bin/syncd",
            "Disabled": true,
        ], named: "org.sample.sync.plist", in: agents)
        // Invalid / unreadable files are skipped.
        try Data("not a plist".utf8).write(to: agents.appending(path: "broken.plist"))
        _ = try writePlist(["NoLabel": true], named: "nolabel.plist", in: agents)
        try Data("ignored".utf8).write(to: agents.appending(path: "notes.txt"))
        // A symlink pointing outside the folder must not be read.
        let outside = tempDir.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsidePlist = try writePlist(["Label": "net.secret.agent", "Program": "/opt/secret"], named: "target.plist", in: outside)
        try FileManager.default.createSymbolicLink(at: agents.appending(path: "net.linked.agent.plist"), withDestinationURL: outsidePlist)

        let items = StartupItemsService.scan(directory: agents, scope: .userAgent,
                                             overrides: ["com.example.helper": false],
                                             running: ["org.sample.sync": true])
        XCTAssertEqual(items.count, 3, "\(items.map(\.label))")

        let helper = try XCTUnwrap(items.first { $0.label == "com.example.helper" })
        XCTAssertEqual(helper.displayName, "Example Tool")
        XCTAssertEqual(helper.vendor, "Example Tool")
        XCTAssertEqual(helper.programPath, "/Applications/Example Tool.app/Contents/MacOS/helper")
        XCTAssertFalse(helper.isEnabled, "launchctl override wins over the plist")
        XCTAssertNil(helper.isRunning)
        XCTAssertEqual(helper.scope, .userAgent)

        let sync = try XCTUnwrap(items.first { $0.label == "org.sample.sync" })
        XCTAssertEqual(sync.displayName, "syncd")
        XCTAssertEqual(sync.vendor, "Sample")
        XCTAssertFalse(sync.isEnabled, "Disabled key in plist")
        XCTAssertEqual(sync.isRunning, true)

        let linked = try XCTUnwrap(items.first { $0.isLinkedOutside })
        XCTAssertEqual(linked.label, "net.linked.agent", "label comes from the file name, target not read")
        XCTAssertNil(linked.programPath)
        XCTAssertFalse(items.contains { $0.label == "net.secret.agent" })
        XCTAssertFalse(linked.canToggle)
    }

    func testParsesLaunchctlOutputs() {
        let disabled = """
        \tdisabled services = {
        \t\t"com.example.one" => enabled
        \t\t"com.example.two" => disabled
        \t\t"com.example.three" => true
        \t}
        """
        let overrides = StartupItemsService.parseDisabledOverrides(disabled)
        XCTAssertEqual(overrides["com.example.one"], true)
        XCTAssertEqual(overrides["com.example.two"], false)
        XCTAssertEqual(overrides["com.example.three"], false)

        let list = "PID\tStatus\tLabel\n123\t0\tcom.example.one\n-\t0\tcom.example.two\n"
        let running = StartupItemsService.parseLaunchctlList(list)
        XCTAssertEqual(running["com.example.one"], true)
        XCTAssertEqual(running["com.example.two"], false)
        XCTAssertNil(running["Label"])
    }

    private func item(label: String, scope: StartupItem.Scope, folder: URL? = nil) -> StartupItem {
        let dir = folder ?? scope.directory
        return StartupItem(label: label, displayName: label, plistURL: dir.appending(path: "\(label).plist"),
                           programPath: "/usr/bin/true", scope: scope, isEnabled: true, isRunning: nil, vendor: nil)
    }

    func testRefusesToToggleAppleAndNonUserItems() async {
        let apple = item(label: "com.apple.Siri.agent", scope: .userAgent)
        XCTAssertEqual(StartupItemsService.toggleRefusal(for: apple), .appleItem)
        XCTAssertFalse(apple.canToggle)

        let globalAgent = item(label: "com.vendor.agent", scope: .globalAgent)
        XCTAssertEqual(StartupItemsService.toggleRefusal(for: globalAgent), .notUserScope)
        let daemon = item(label: "com.vendor.daemon", scope: .globalDaemon)
        XCTAssertEqual(StartupItemsService.toggleRefusal(for: daemon), .notUserScope)

        // A user-scope item whose plist isn't in ~/Library/LaunchAgents is refused too.
        let elsewhere = item(label: "com.vendor.elsewhere", scope: .userAgent, folder: tempDir)
        XCTAssertEqual(StartupItemsService.toggleRefusal(for: elsewhere), .notUserScope)

        let badLabel = item(label: "bad label/../x", scope: .userAgent)
        XCTAssertNotNil(StartupItemsService.toggleRefusal(for: badLabel))

        // The normal user agent shape is allowed (not executed here).
        XCTAssertNil(StartupItemsService.toggleRefusal(for: item(label: "com.vendor.ok", scope: .userAgent)))

        // setEnabled throws before running launchctl for refused items.
        for refused in [apple, globalAgent, daemon, elsewhere] {
            do {
                try await StartupItemsService.setEnabled(false, for: refused)
                XCTFail("Expected refusal for \(refused.label)")
            } catch let error as StartupToggleError {
                XCTAssertEqual(error, StartupItemsService.toggleRefusal(for: refused))
            } catch {
                XCTFail("Unexpected error \(error)")
            }
        }
    }

    // MARK: - Protection

    private func check(_ id: String, _ state: ProtectionCheck.State, _ weight: Int) -> ProtectionCheck {
        ProtectionCheck(id: id, titleKey: "protect.check.\(id).title", detail: "", state: state, weight: weight, settingsURL: nil)
    }

    func testScoreMath() {
        XCTAssertEqual(ProtectionService.score(of: []), 0)
        XCTAssertEqual(ProtectionService.score(of: [check("a", .on, 25), check("b", .on, 20)]), 100)
        XCTAssertEqual(ProtectionService.score(of: [check("a", .off, 25), check("b", .off, 20)]), 0)
        // 25 + 20 on out of 25 + 20 + 20 + 15 known = 45 / 80 = 56.25 → 56
        XCTAssertEqual(ProtectionService.score(of: [
            check("filevault", .on, 25), check("gatekeeper", .on, 20),
            check("firewall", .off, 20), check("updates", .off, 15),
        ]), 56)
        // Unknown and informational checks are excluded.
        XCTAssertEqual(ProtectionService.score(of: [
            check("filevault", .on, 25), check("firewall", .off, 25),
            check("sip", .unknown, 20), check("xprotect", .on, 0),
        ]), 50)
        XCTAssertEqual(ProtectionService.score(of: [check("sip", .unknown, 20), check("xprotect", .on, 0)]), 0)

        let report = ProtectionReport(score: 56, checks: [check("a", .on, 10), check("b", .off, 10), check("c", .unknown, 10), check("x", .on, 0)])
        XCTAssertEqual(report.onCount, 1)
        XCTAssertEqual(report.offCount, 1)
        XCTAssertEqual(report.knownCount, 2)
        XCTAssertEqual(report.scoredChecks.count, 3)
        XCTAssertTrue(report.hasKnownChecks)
    }

    func testCommandOutputParsers() {
        func r(_ text: String, status: Int32 = 0) -> CommandRunner.Result { .init(status: status, output: text, timedOut: false) }
        XCTAssertEqual(ProtectionService.parseFileVault(r("FileVault is On.\n")), .on)
        XCTAssertEqual(ProtectionService.parseFileVault(r("FileVault is Off.\n")), .off)
        XCTAssertEqual(ProtectionService.parseFileVault(nil), .unknown)
        XCTAssertEqual(ProtectionService.parseFileVault(.init(status: -1, output: "", timedOut: true)), .unknown)
        XCTAssertEqual(ProtectionService.parseFirewall(r("Firewall is enabled. (State = 1)")), .on)
        XCTAssertEqual(ProtectionService.parseFirewall(r("Firewall is disabled. (State = 0)")), .off)
        XCTAssertEqual(ProtectionService.parseGatekeeper(r("assessments enabled")), .on)
        XCTAssertEqual(ProtectionService.parseGatekeeper(r("assessments disabled")), .off)
        XCTAssertEqual(ProtectionService.parseSIP(r("System Integrity Protection status: enabled.")), .on)
        XCTAssertEqual(ProtectionService.parseSIP(r("System Integrity Protection status: disabled.")), .off)
        XCTAssertEqual(ProtectionService.parseSIP(r("System Integrity Protection status: unknown (Custom Configuration).")), .unknown)
        XCTAssertEqual(ProtectionService.parseScreenLock(r("2026-10-30 sysadminctl[1:2] screenLock delay is immediate")), .on)
        XCTAssertEqual(ProtectionService.parseScreenLock(r("2026-10-30 sysadminctl[1:2] screenLock is off")), .off)
        XCTAssertNil(ProtectionService.parseScreenLock(r("Error: not permitted", status: 1)))
        XCTAssertEqual(ProtectionService.updatesState(automaticCheck: true, automaticDownload: nil, automaticallyInstallMacOS: nil), .on)
        XCTAssertEqual(ProtectionService.updatesState(automaticCheck: false, automaticDownload: true, automaticallyInstallMacOS: true), .off)
        XCTAssertEqual(ProtectionService.updatesState(automaticCheck: nil, automaticDownload: nil, automaticallyInstallMacOS: nil), .unknown)
        XCTAssertEqual(ProtectionService.updatesState(automaticCheck: nil, automaticDownload: true, automaticallyInstallMacOS: nil), .on)
    }

    func testXProtectVersionFixture() throws {
        let url = try writePlist(["CFBundleShortVersionString": "5368"], named: "Info.plist", in: tempDir)
        XCTAssertEqual(ProtectionService.xprotectVersion(at: url), "5368")
        XCTAssertNil(ProtectionService.xprotectVersion(at: tempDir.appending(path: "missing.plist")))
        let informational = ProtectionService.xprotectCheck(version: "5368")
        XCTAssertEqual(informational.weight, 0)
        XCTAssertEqual(informational.state, .on)
    }

    // MARK: - Localization

    func testAllNewKeysPresentInEveryLanguage() throws {
        let english = try XCTUnwrap(LocalizationCatalog.tables[.en])
        let newKeys = english.keys.filter { $0.hasPrefix("speed.") || $0.hasPrefix("protect.") } + ["nav.speed", "nav.protection"]
        XCTAssertGreaterThan(newKeys.count, 50)

        // Every literal tr("speed.*") / tr("protect.*") key in the two feature files exists.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "MacCoreCleaner/Features")
        let regex = try NSRegularExpression(pattern: #"tr\(\s*"([^"]+)""#)
        var used: Set<String> = []
        for file in [source.appending(path: "Speed/SpeedView.swift"), source.appending(path: "Protection/ProtectionView.swift")] {
            let code = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let key = String(code[Range(match.range(at: 1), in: code)!])
                if !key.contains("\\(") { used.insert(key) }
            }
        }
        // Keys built dynamically from the check ids.
        for id in ["filevault", "firewall", "gatekeeper", "sip", "updates", "screenlock"] {
            used.formUnion(["protect.check.\(id).title", "protect.check.\(id).on", "protect.check.\(id).off"])
        }
        used.insert("protect.check.xprotect.title")

        for language in Lang.allCases {
            let table = try XCTUnwrap(LocalizationCatalog.tables[language])
            for key in Set(newKeys).union(used) {
                let value = table[key]
                XCTAssertNotNil(value, "\(language.rawValue) missing \(key)")
                XCTAssertFalse(value?.isEmpty ?? true, "\(language.rawValue) empty \(key)")
            }
        }
        XCTAssertEqual(LocalizationCatalog.string("nav.speed", language: .ko), "속도")
        XCTAssertEqual(LocalizationCatalog.string("nav.protection", language: .ko), "보안 상태")
        XCTAssertEqual(LocalizationCatalog.string("nav.speed", language: .en), "Speed")
        XCTAssertEqual(LocalizationCatalog.string("nav.protection", language: .en), "Protection")
    }
}
