import XCTest
import Darwin
@testable import MacCoreCleaner

final class TelemetryTests: XCTestCase {
    func testNetworkCountersPreserveMoreThanFourGiBAndRejectMalformedRecords() {
        var message = if_msghdr2()
        message.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
        message.ifm_type = UInt8(RTM_IFINFO2)
        message.ifm_flags = IFF_UP
        message.ifm_index = 2
        message.ifm_data.ifi_ibytes = 8_000_000_000
        message.ifm_data.ifi_obytes = 6_000_000_000
        let data = withUnsafeBytes(of: &message) { Data($0) }
        let counters = NetworkService.decodeInterfaceCounters(data) { _ in "en0" }
        XCTAssertEqual(counters.count, 1)
        XCTAssertEqual(counters.first?.receivedBytes, 8_000_000_000)
        XCTAssertEqual(counters.first?.sentBytes, 6_000_000_000)
        message.ifm_flags = IFF_UP | IFF_LOOPBACK
        let loopback = withUnsafeBytes(of: &message) { Data($0) }
        XCTAssertTrue(NetworkService.decodeInterfaceCounters(loopback) { _ in "lo0" }.isEmpty)
        for malformed in [Data(), Data([0, 0, 0, 0]), Data([255, 255, 0, 0]), data.prefix(8)] {
            XCTAssertTrue(NetworkService.decodeInterfaceCounters(malformed) { _ in "en0" }.isEmpty)
        }
    }

    func testModernBatteryNestedCapacityAndPowerUnits() {
        let reading = BatteryElectrical.parse([
            "Voltage": 12160, "InstantAmperage": 0,
            "MaxCapacity": 100,
            "BatteryData": ["AppleRawCurrentCapacity": 6015, "AppleRawMaxCapacity": 7634, "DesignCapacity": 8694],
            "PowerTelemetryData": ["SystemPowerIn": 23700, "SystemLoad": 21650,
                                   "SystemVoltageIn": 19930, "SystemCurrentIn": 1190],
            "AdapterDetails": ["Watts": 90, "Current": 4500]
        ], pluggedIn: true)
        XCTAssertEqual(reading.voltage, 12.16)
        XCTAssertEqual(reading.batteryWatts, 0) // zero is measured, not unknown
        XCTAssertEqual(reading.inputWatts, 23.7)
        XCTAssertEqual(reading.systemWatts, 21.65)
        XCTAssertEqual(reading.adapterRatedWatts, 90)
        XCTAssertEqual(reading.inputVoltage, 19.93)
        XCTAssertEqual(reading.currentCapacity, 6015)
        XCTAssertEqual(reading.maximumCapacity, 7634)
        XCTAssertEqual(reading.designCapacity, 8694)
        XCTAssertEqual(reading.capacityRatio!, 7634.0 / 8694, accuracy: 0.0001)
        XCTAssertNil(reading.temperature)
    }

    func testLegacyBatterySignedCurrentsAndDisconnectedAdapter() {
        for current: NSNumber in [NSNumber(value: -1500), NSNumber(value: UInt32.max - 1499), NSNumber(value: UInt64.max - 1499)] {
            let reading = BatteryElectrical.parse([
                "Voltage": 12000, "Amperage": current,
                "AppleRawMaxCapacity": 7000, "DesignCapacity": 8500,
                "AdapterDetails": ["Watts": 90], "PowerTelemetryData": ["SystemPowerIn": 23000]
            ], pluggedIn: false)
            XCTAssertEqual(reading.current, -1.5)
            XCTAssertEqual(reading.batteryWatts, -18)
            XCTAssertNil(reading.adapterRatedWatts)
            XCTAssertNil(reading.inputWatts)
        }
    }

    func testMissingAndInvalidTelemetryRemainsUnknown() {
        let missing = BatteryElectrical.parse(["MaxCapacity": 100, "DesignCapacity": 8500], pluggedIn: true)
        XCTAssertNil(missing.maximumCapacity) // 100 is normalized %, never mAh
        XCTAssertNil(missing.batteryWatts)
        XCTAssertNil(missing.capacityRatio)
        let invalid = BatteryElectrical.parse(["Voltage": -1, "InstantAmperage": 999999999,
                                               "Temperature": 65535, "AppleRawMaxCapacity": -1], pluggedIn: true)
        XCTAssertNil(invalid.voltage)
        XCTAssertNil(invalid.current)
        XCTAssertNil(invalid.temperature)
        XCTAssertNil(invalid.maximumCapacity)
        XCTAssertEqual(BatteryElectrical.temperatureCelsius(2700), 27)
        for value in [nil, -1, 0, 65535, Int.max] as [Int?] {
            XCTAssertNil(BatteryElectrical.validMinutes(value))
        }
        XCTAssertEqual(BatteryElectrical.validMinutes(45), 45)
    }

    @MainActor
    func testMenuBarFormatsAndSensorSelectionPersist() throws {
        let suite = "MacCore.TelemetryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.menuBarMemoryBytes = true
        settings.menuBarDiskPercent = true
        settings.menuBarFahrenheit = true
        settings.menuBarSeparators = true
        settings.menuBarSensorID = "sensor:1"
        settings.menuBarFontSize = 13
        settings.menuBarExpandedDetails = false
        settings.menuBarDisplayStyle = .valuesOnly
        let restored = SettingsStore(defaults: defaults)
        XCTAssertTrue(restored.menuBarMemoryBytes)
        XCTAssertTrue(restored.menuBarDiskPercent)
        XCTAssertTrue(restored.menuBarFahrenheit)
        XCTAssertTrue(restored.menuBarSeparators)
        XCTAssertEqual(restored.menuBarSensorID, "sensor:1")
        XCTAssertEqual(restored.menuBarFontSize, 13)
        XCTAssertFalse(restored.menuBarExpandedDetails)
        XCTAssertEqual(restored.menuBarDisplayStyle, .valuesOnly)
        var snapshot = TemperatureSnapshot.none
        snapshot.average = 52
        snapshot.readings = [.init(name: "Same name", celsius: 32, sensorID: "sensor:1"),
                             .init(name: "Same name", celsius: 42, sensorID: "sensor:2")]
        XCTAssertEqual(Set(snapshot.readings.map(\.id)).count, 2)
        XCTAssertEqual(MenuBarTitleFormatter.selectedTemperature(snapshot, settings: restored), 32)
        restored.menuBarSensorID = "missing"
        XCTAssertNil(MenuBarTitleFormatter.selectedTemperature(snapshot, settings: restored))
        restored.menuBarSensorID = ""
        restored.temperatureSource = .cpu
        XCTAssertNil(MenuBarTitleFormatter.selectedTemperature(snapshot, settings: restored)) // no false CPU fallback
        restored.temperatureSource = .average
        XCTAssertEqual(MenuBarTitleFormatter.selectedTemperature(snapshot, settings: restored), 52)
        let text = MenuBarTitleFormatter.title(snapshot: .init(temperature: 0, hasSample: true), settings: restored)
        XCTAssertTrue(text.contains("°F"))
        XCTAssertTrue(text.contains("|"))
        XCTAssertFalse(text.contains("CPU"))
        defaults.set(Double.nan, forKey: "menuBarFontSize")
        XCTAssertEqual(SettingsStore(defaults: defaults).menuBarFontSize, 12)
    }

    func testLiveTelemetryReadIsBoundedAndReadOnly() {
        let temperature = TemperatureService().sample()
        XCTAssertEqual(temperature.readings.count, temperature.sensorCount)
        XCTAssertEqual(Set(temperature.readings.map(\.id)).count, temperature.sensorCount)
        XCTAssertTrue(temperature.readings.allSatisfy { $0.celsius.isFinite && $0.celsius > 0 && $0.celsius < 130 })
        let battery = BatteryService().sample()
        print("TELEMETRY_QA sensors=\(temperature.sensorCount) pinnable=\(temperature.readings.filter(\.canPin).count)")
        print("TELEMETRY_QA battery=\(battery.isPresent) voltage=\(battery.electrical.voltage as Any) power=\(battery.electrical.systemWatts as Any) capacity=\(battery.electrical.maximumCapacity as Any)")
        XCTAssertTrue((0...100).contains(battery.percentage))
        let second = TemperatureService().sample()
        let firstIDs = Set(temperature.readings.map(\.id))
        let secondIDs = Set(second.readings.map(\.id))
        if !firstIDs.isEmpty && !secondIDs.isEmpty {
            XCTAssertEqual(firstIDs, secondIDs, "Stable channels must survive client recreation")
        }
    }

    func testSensorIdentityUsesHardwarePathRatherThanDiscoveryOrder() {
        let first = TemperatureService.sensorIdentity(name: "PMU tdie0", path: "IOService:/sensorA", fallback: "1", session: "a")
        let reordered = TemperatureService.sensorIdentity(name: "PMU tdie0", path: "IOService:/sensorA", fallback: "8", session: "b")
        let other = TemperatureService.sensorIdentity(name: "PMU tdie0", path: "IOService:/sensorB", fallback: "1", session: "a")
        XCTAssertEqual(first, reordered)
        XCTAssertNotEqual(first, other)
        let uncertain = TemperatureService.sensorIdentity(name: "PMU tdie0", path: nil, fallback: "1", session: "a")
        XCTAssertFalse(TemperatureReading(name: "PMU tdie0", celsius: 45, sensorID: uncertain).canPin)
    }

    @MainActor
    func testInitialMenuBarValuesAreUnavailableAndBatteryHealthIsLocalized() {
        let suite = "MacCore.InitialTelemetry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        for metric in MenuBarMetric.allCases {
            XCTAssertEqual(MenuBarTitleFormatter.value(metric, snapshot: .init(), settings: settings), "—")
        }
        var battery = BatterySnapshot.none
        battery.health = "Good"
        XCTAssertEqual(battery.localizedHealth, tr("battery.normal"))
        battery.health = "Fair"
        XCTAssertEqual(battery.localizedHealth, tr("battery.limited"))
        battery.health = "Check Battery"
        XCTAssertEqual(battery.localizedHealth, tr("battery.service"))
    }
}
