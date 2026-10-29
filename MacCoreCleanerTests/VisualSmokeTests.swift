import XCTest
import SwiftUI
import AppKit
@testable import MacCoreCleaner

/// Render the real SwiftUI views with harmless fixture data, not live cleanup.
/// PNGs are attached to the test result and saved in the test process's temp folder.
final class VisualSmokeTests: XCTestCase {
    @MainActor
    func testCompactTelemetryAndExpandedPreferencesRender() async throws {
        let localization = LocalizationManager.shared
        let previous = localization.language
        defer { localization.language = previous }
        let suite = "MacCore.CompactVisual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.menuBarMemoryBytes = true
        settings.menuBarFahrenheit = true
        settings.menuBarSeparators = true
        settings.menuBarDisplayStyle = .compact
        let model = HardwareMonitorViewModel()
        model.updated = Date()
        model.battery = BatterySnapshot(isPresent: true, percentage: 80, isCharging: false,
            isPluggedIn: true, cycleCount: 198, health: "Good", timeToEmptyMinutes: nil,
            electrical: BatteryElectrical(voltage: 12.16, current: 0, temperature: 27,
                currentCapacity: 6015, maximumCapacity: 7634, designCapacity: 8694,
                adapterRatedWatts: 90, adapterCurrentLimit: 4.5, inputVoltage: 19.93,
                inputCurrent: 1.19, inputWatts: 23.7, systemWatts: 21.65))
        let readings = (0..<28).map { TemperatureReading(name: "PMU tdie\($0)", celsius: 35 + Double($0), sensorID: "fixture:\($0)") }
        model.temperature = TemperatureSnapshot(cpu: nil, gpu: nil, battery: nil, average: 48.5,
            maxValue: 62, sensorCount: 28, readings: readings)
        model.ranges = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, ($0.celsius - 2)...($0.celsius + 2)) })
        for language in [AppLanguage.korean, .german, .arabic] {
            localization.language = language
            let nav = NavigationModel()
            for destination in [NavItem.battery, .temperature] {
                nav.selection = destination
                let root = ContentView(hardwareModel: model, automaticallyRefresh: false)
                    .environmentObject(settings).environmentObject(PermissionManager())
                    .environmentObject(localization).environmentObject(nav)
                    .environment(\.locale, localization.locale)
                    .environment(\.layoutDirection, localization.layoutDirection)
                    .environment(\.colorScheme, .dark)
                try await render(root, name: "compact-\(destination.rawValue)-\(language.rawValue)",
                                 size: NSSize(width: 1080, height: 720), dark: true)
            }
            let preferences = Form { MenuBarPreferences(settings: settings, initiallyExpanded: true) }
                .formStyle(.grouped)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .environment(\.colorScheme, .dark)
            try await render(preferences, name: "expanded-menu-\(language.rawValue)",
                             size: NSSize(width: 780, height: 1000), dark: true)
            let sample = MenuBarTitleFormatter.example
            let menuModel = MenuBarMonitorViewModel(snapshot: sample)
            settings.setMenuBarMetric(.cpu, isEnabled: false)
            settings.setMenuBarMetric(.batteryPower, isEnabled: true)
            let panel = MenuBarPanel(vm: menuModel, settings: settings,
                localization: localization, automaticallyRefresh: false)
                .environment(\.colorScheme, .dark)
            try await render(panel, name: "menu-popover-\(language.rawValue)",
                             size: NSSize(width: 320, height: 520), dark: true)
        }
    }

    @MainActor
    func testDetailedTelemetryScreensRender() async throws {
        let localization = LocalizationManager.shared
        let previous = localization.language
        defer { localization.language = previous }
        let model = HardwareMonitorViewModel()
        model.updated = Date()
        model.battery = BatterySnapshot(isPresent: true, percentage: 80, isCharging: false,
            isPluggedIn: true, cycleCount: 198, health: "Normal", timeToEmptyMinutes: nil,
            electrical: BatteryElectrical(voltage: 12.16, current: 0, temperature: 27,
                currentCapacity: 6015, maximumCapacity: 7634, designCapacity: 8694,
                adapterRatedWatts: 90, adapterCurrentLimit: 4.5, inputVoltage: 19.93,
                inputCurrent: 1.19, inputWatts: 23.7, systemWatts: 21.65))
        let names = ["gas gauge battery", "NAND CH0 temp", "PMU tcal", "PMU tdev1", "PMU tdev2", "PMU tdie0", "PMU tdie1", "PMU TP0s"]
        let readings = names.enumerated().map { TemperatureReading(name: $0.element, celsius: 27 + Double($0.offset * 4)) }
        model.temperature = TemperatureSnapshot(cpu: nil, gpu: nil, battery: 27, average: 41,
            maxValue: 55, sensorCount: readings.count, readings: readings)
        model.ranges = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, ($0.celsius - 3)...($0.celsius + 2)) })
        model.network = NetworkSnapshot(downBytesPerSec: 3_200_000, upBytesPerSec: 420_000,
            totalDownBytes: 100_000_000, totalUpBytes: 20_000_000, primaryInterface: "en0",
            interfaces: [.init(id: "en0", receivedBytes: 100_000_000, sentBytes: 20_000_000,
                               downBytesPerSec: 3_200_000, upBytesPerSec: 420_000)])
        for (language, dark): (AppLanguage, Bool) in [(.korean, true), (.english, false), (.german, true), (.arabic, true)] {
            localization.language = language
            for metric in [DashboardMetric.battery, .temperature, .network] {
                var points: [TelemetryPoint] = []
                for index in 0..<30 {
                    let date = Date().addingTimeInterval(Double(index - 30) * 2.5)
                    let wave = sin(Double(index) / 4)
                    let value: Double
                    if metric == .temperature { value = 45 + wave * 4 }
                    else if metric == .network { value = (3 + wave) * 1_000_000 }
                    else { value = 0 }
                    points.append(TelemetryPoint(id: date, value: value))
                }
                model.history = points
                model.secondaryHistory = points.map { point in
                    let value = metric == .network ? point.value / 8 : 21 + sin(point.id.timeIntervalSince1970 / 5) * 2
                    return TelemetryPoint(id: point.id, value: value)
                }
                let view = HardwareMonitorView(metric: metric, vm: model, automaticallyRefresh: false)
                    .environment(\.locale, localization.locale)
                    .environment(\.layoutDirection, localization.layoutDirection)
                    .environment(\.colorScheme, dark ? .dark : .light)
                try await render(view, name: "telemetry-\(metric.rawValue)-\(language.rawValue)",
                                 size: NSSize(width: 980, height: 1000), dark: dark)
            }
        }
    }

    @MainActor
    func testSystemDataAnalysisScreensRender() async throws {
        let localization = LocalizationManager.shared
        let previous = localization.language
        defer { localization.language = previous }
        let suite = "MacCore.SystemDataVisual.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let cache = CleanableItem(url: URL(fileURLWithPath: "/Users/example/Library/Caches/Example"),
            sizeBytes: 2_500_000_000, safety: .safe, categoryID: .userCache, isDirectory: true)
        let groups = [
            SystemDataGroup(id: "caches", titleKey: "cat.userCache.title",
                root: URL(fileURLWithPath: "/Users/example/Library/Caches"), sizeBytes: 4_000_000_000,
                categoryID: .userCache, items: [cache], isPartial: false),
            SystemDataGroup(id: "derived", titleKey: "cat.xcodeDerivedData.title",
                root: URL(fileURLWithPath: "/Users/example/Library/Developer/Xcode/DerivedData"),
                sizeBytes: 0, categoryID: .xcodeDerivedData, items: [], isPartial: false),
            SystemDataGroup(id: "support", titleKey: "sd.support",
                root: URL(fileURLWithPath: "/Users/example/Library/Application Support"), sizeBytes: 8_000_000_000,
                categoryID: nil, items: [], isPartial: false),
            SystemDataGroup(id: "backups", titleKey: "sd.backups",
                root: URL(fileURLWithPath: "/Users/example/Library/Application Support/MobileSync/Backup"),
                sizeBytes: 12_000_000_000, categoryID: nil, items: [], isPartial: false),
            SystemDataGroup(id: "containers", titleKey: "sd.containers",
                root: URL(fileURLWithPath: "/Users/example/Library/Containers"), sizeBytes: 3_000_000_000,
                categoryID: nil, items: [], isPartial: true)
        ]
        for (language, dark): (AppLanguage, Bool) in [(.korean, false), (.english, true), (.german, false), (.arabic, false)] {
            localization.language = language
            let vm = SystemDataViewModel(report: SystemDataReport(groups: groups))
            let view = SystemDataSection(vm: vm)
                .environmentObject(settings)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .environment(\.colorScheme, dark ? .dark : .light)
                .padding(24)
            try await render(view, name: "system-data-\(language.rawValue)",
                             size: NSSize(width: 830, height: 1000), dark: dark)
        }
    }

    @MainActor
    func testRepresentativeLocalizedScreensRender() async throws {
        let localization = LocalizationManager.shared
        let original = localization.language
        defer { localization.language = original }
        let suite = "MacCore.VisualQA.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let permissions = PermissionManager()
        let nav = NavigationModel()

        for (language, dark): (AppLanguage, Bool) in [
            (.korean, false), (.english, true), (.german, false), (.arabic, false)
        ] {
            localization.language = language
            let vm = DashboardViewModel()
            vm.disk = DiskSnapshot(volumeName: "Macintosh HD", totalBytes: 1_000_000_000_000, freeBytes: 384_000_000_000)
            vm.memory = MemorySnapshot(totalBytes: 32_000_000_000, usedBytes: 19_000_000_000,
                freeBytes: 13_000_000_000, activeBytes: 12_000_000_000, wiredBytes: 3_000_000_000,
                compressedBytes: 4_000_000_000, appBytes: 12_000_000_000, cachedBytes: 8_000_000_000,
                swapUsedBytes: 0, pressure: .normal)
            vm.cpu = CPUSnapshot(totalUsage: 0.18, userUsage: 0.12, systemUsage: 0.06,
                idle: 0.82, coreUsages: Array(repeating: 0.18, count: 10), coreCount: 10)
            vm.health = HealthScore.compute(disk: vm.disk, memory: vm.memory, cpu: vm.cpu)
            vm.reclaimable = 2_400_000_000
            vm.cpuHistory = [0.1, 0.2, 0.12, 0.28, 0.18]
            vm.memHistory = [0.5, 0.52, 0.56, 0.55, 0.59]
            vm.network = NetworkSnapshot(downBytesPerSec: 3_200_000, upBytesPerSec: 420_000,
                totalDownBytes: 100_000_000, totalUpBytes: 20_000_000, primaryInterface: "en0")
            vm.battery = BatterySnapshot(isPresent: true, percentage: 82, isCharging: false,
                isPluggedIn: false, cycleCount: 120, health: nil, timeToEmptyMinutes: 310)
            nav.selection = .dashboard
            let root = ContentView(dashboardModel: vm, automaticallyRefresh: false)
                .environmentObject(settings).environmentObject(permissions)
                .environmentObject(localization).environmentObject(nav)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .environment(\.colorScheme, dark ? .dark : .light)
            try await render(root, name: "dashboard-\(language.rawValue)", size: NSSize(width: 1280, height: 1040), dark: dark)

            let preferences = Form { MenuBarPreferences(settings: settings) }
                .formStyle(.grouped)
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .environment(\.colorScheme, dark ? .dark : .light)
            try await render(preferences, name: "menubar-settings-\(language.rawValue)", size: NSSize(width: 780, height: 680), dark: dark)

            let item = CleanableItem(url: URL(fileURLWithPath: "/Users/example/Downloads/Example.zip"),
                sizeBytes: 120_000_000, safety: .caution, categoryID: .downloadsLargeFiles, isDirectory: false)
            let confirm = ConfirmCleanSheet(items: [item], mode: .constant(.permanentDelete),
                allowPermanent: true, onConfirm: {}, onCancel: {})
                .environment(\.locale, localization.locale)
                .environment(\.layoutDirection, localization.layoutDirection)
                .environment(\.colorScheme, dark ? .dark : .light)
            try await render(confirm, name: "confirmation-\(language.rawValue)", size: NSSize(width: 560, height: 660), dark: dark)
        }
    }

    @MainActor
    private func render<V: View>(_ view: V, name: String, size: NSSize, dark: Bool) async throws {
        let host = NSHostingView(rootView: view.background(AppColor.background))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.setContentSize(size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, "Empty rendering: \(name)")
        let directory = FileManager.default.temporaryDirectory.appending(path: "MacCore-UI-QA")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name + ".png")
        try png.write(to: file)
        print("UI_QA: \(file.path)")
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.close()
    }
}
