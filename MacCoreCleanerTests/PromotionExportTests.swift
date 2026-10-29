import XCTest
import SwiftUI
import AppKit
@testable import MacCoreCleaner

/// Opt-in artwork export. No cleanup runs, user files are never scanned, and
/// all readings are illustrative fixtures displayed by the real production UI.
/// TEST_RUNNER_MACCORE_EXPORT_PROMOTIONS=1 enables this test with xcodebuild.
final class PromotionExportTests: XCTestCase {
    @MainActor
    func testExportLocalizedPromotionImages() async throws {
        guard ProcessInfo.processInfo.environment["MACCORE_EXPORT_PROMOTIONS"] == "1" else {
            throw XCTSkip("Set TEST_RUNNER_MACCORE_EXPORT_PROMOTIONS=1 to export marketing assets.")
        }
        // Close only this test host's live window while rendering isolated views.
        // Its live sidebar/layout must not react to every export locale/theme.
        for window in NSApplication.shared.windows {
            window.close()
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appending(path: "프로모션 이미지/_제작원본")
        let catalog = try JSONDecoder().decode([PromotionLocale].self, from: Data(contentsOf: assets.appending(path: "copy.json")))
        let background = try XCTUnwrap(NSImage(contentsOf: assets.appending(path: "campaign-background.png")))
        let icon = try XCTUnwrap(NSImage(contentsOf: root.appending(path: "MacCoreCleaner/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png")))
        let selected = ProcessInfo.processInfo.environment["MACCORE_PROMO_LOCALES"]?.split(separator: ",").map(String.init)
        let localization = LocalizationManager.shared
        let previous = localization.language
        defer { localization.language = previous }
        let output = FileManager.default.temporaryDirectory.appending(path: "MacCore-Promotions")
        for entry in catalog where selected == nil || selected!.contains(entry.language) {
            localization.language = try XCTUnwrap(AppLanguage(rawValue: entry.language))
            let suite = "MacCore.Promotion.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            let settings = SettingsStore(defaults: defaults)
            settings.menuBarMonitor = true
            settings.menuBarMemoryBytes = true
            settings.menuBarSeparators = true
            settings.menuBarDisplayStyle = .compact
            settings.menuBarExpandedDetails = true
            settings.setMenuBarMetric(.battery, isEnabled: true)
            let dashboard = makeDashboard()
            let hardware = makeHardware()
            dashboard.temperature = hardware.temperature
            let nav = NavigationModel()
            let folder = output.appending(path: entry.folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            XCTAssertEqual(entry.slides.count, 5)
            for index in 0..<entry.slides.count {
                let dark = index == 2 || index == 3
                let content: AnyView
                let size: CGSize
                let scale: CGFloat
                switch index {
                case 0:
                    nav.selection = .dashboard
                    content = AnyView(ContentView(dashboardModel: dashboard, automaticallyRefresh: false))
                    size = CGSize(width: 1280, height: 1080)
                    scale = 0.69
                case 1:
                    content = AnyView(VStack(spacing: 0) {
                        ScreenHeader(item: .storage)
                        SystemDataSection(vm: makeStorage()).padding(28)
                        Spacer(minLength: 0)
                    }.background(AppColor.background))
                    size = CGSize(width: 1080, height: 900)
                    scale = 0.82
                case 2, 3:
                    let metric: DashboardMetric = index == 2 ? .temperature : .battery
                    setHistory(hardware, metric: metric)
                    content = AnyView(VStack(spacing: 0) {
                        ScreenHeader(item: index == 2 ? .temperature : .battery)
                        HardwareMonitorView(metric: metric, vm: hardware, automaticallyRefresh: false)
                    })
                    size = CGSize(width: 1200, height: 1030)
                    scale = 0.74
                default:
                    content = AnyView(PromotionMenuPreview(settings: settings, localization: localization))
                    size = CGSize(width: 900, height: 770)
                    scale = 1
                }
                let screen = content
                    .environmentObject(settings).environmentObject(PermissionManager())
                    .environmentObject(localization).environmentObject(nav)
                    .environment(\.locale, localization.locale)
                    .environment(\.layoutDirection, localization.layoutDirection)
                    .environment(\.colorScheme, dark ? .dark : .light)
                let canvas = PromotionCanvas(entry: entry, index: index, background: background,
                    icon: icon, screen: AnyView(screen), screenSize: size, screenScale: scale, dark: dark)
                let file = folder.appending(path: "0\(index + 1)-\(["overview", "storage", "temperature", "battery-power", "menu-bar"][index]).png")
                try await render(canvas, file: file, dark: dark)
            }
            defaults.removePersistentDomain(forName: suite)
        }
        print("PROMOTION_OUTPUT: \(output.path)")
    }

    @MainActor
    private func makeDashboard() -> DashboardViewModel {
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
        vm.cpuHistory = [0.1, 0.2, 0.12, 0.28, 0.18, 0.15, 0.22, 0.16, 0.18]
        vm.memHistory = [0.5, 0.52, 0.56, 0.55, 0.59, 0.61, 0.59]
        vm.network = NetworkSnapshot(downBytesPerSec: 3_200_000, upBytesPerSec: 420_000,
            totalDownBytes: 100_000_000, totalUpBytes: 20_000_000, primaryInterface: "en0")
        vm.battery = BatterySnapshot(isPresent: true, percentage: 82, isCharging: false,
            isPluggedIn: false, cycleCount: 120, health: nil, timeToEmptyMinutes: 310)
        vm.topProcesses = [ProcessSample(pid: 9001, name: "Preview", cpuPercent: 1.8,
            memoryBytes: 160_000_000, isOwnedByCurrentUser: false)]
        return vm
    }

    @MainActor
    private func makeHardware() -> HardwareMonitorViewModel {
        let model = HardwareMonitorViewModel()
        model.updated = Date(timeIntervalSince1970: 1793099400)
        model.battery = BatterySnapshot(isPresent: true, percentage: 80, isCharging: false,
            isPluggedIn: true, cycleCount: 198, health: "Good", timeToEmptyMinutes: nil,
            electrical: BatteryElectrical(voltage: 12.16, current: 0, temperature: 27,
                currentCapacity: 6015, maximumCapacity: 7634, designCapacity: 8694,
                adapterRatedWatts: 90, adapterCurrentLimit: 4.5, inputVoltage: 19.93,
                inputCurrent: 1.19, inputWatts: 23.7, systemWatts: 21.65))
        let names = ["gas gauge battery", "NAND CH0 temp", "PMU tcal", "PMU tdev1", "PMU tdev2", "PMU tdie0", "PMU tdie1", "PMU TP0s"]
        let readings = names.enumerated().map {
            TemperatureReading(name: $0.element, celsius: 27 + Double($0.offset * 4), sensorID: "example:\($0.offset)")
        }
        model.temperature = TemperatureSnapshot(cpu: nil, gpu: nil, battery: 27, average: 41,
            maxValue: 55, sensorCount: readings.count, readings: readings)
        model.ranges = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, ($0.celsius - 3)...($0.celsius + 2)) })
        return model
    }

    @MainActor
    private func setHistory(_ model: HardwareMonitorViewModel, metric: DashboardMetric) {
        var first: [TelemetryPoint] = []
        var second: [TelemetryPoint] = []
        for index in 0..<45 {
            let date = model.updated!.addingTimeInterval(Double(index - 44) * 2.5)
            let wave = sin(Double(index) / 4)
            first.append(TelemetryPoint(id: date, value: metric == .temperature ? 52 + wave * 3 : 0))
            second.append(TelemetryPoint(id: date, value: 21.65 + wave * 2))
        }
        model.history = first
        model.secondaryHistory = second
    }

    @MainActor
    private func makeStorage() -> SystemDataViewModel {
        let cache = CleanableItem(url: URL(fileURLWithPath: "/Users/example/Library/Caches/Sample"),
            sizeBytes: 2_500_000_000, safety: .safe, categoryID: .userCache, isDirectory: true)
        let derived = CleanableItem(url: URL(fileURLWithPath: "/Users/example/Library/Developer/Xcode/DerivedData/Sample"),
            sizeBytes: 3_200_000_000, safety: .safe, categoryID: .xcodeDerivedData, isDirectory: true)
        let groups: [SystemDataGroup] = [
            .init(id: "cache", titleKey: "cat.userCache.title", root: URL(fileURLWithPath: "/Users/example/Library/Caches"),
                  sizeBytes: 4_000_000_000, categoryID: .userCache, items: [cache], isPartial: false),
            .init(id: "derived", titleKey: "cat.xcodeDerivedData.title", root: URL(fileURLWithPath: "/Users/example/Library/Developer/Xcode/DerivedData"),
                  sizeBytes: 3_200_000_000, categoryID: .xcodeDerivedData, items: [derived], isPartial: false),
            .init(id: "support", titleKey: "sd.support", root: URL(fileURLWithPath: "/Users/example/Library/Application Support"),
                  sizeBytes: 8_000_000_000, categoryID: nil, items: [], isPartial: false),
            .init(id: "backups", titleKey: "sd.backups", root: URL(fileURLWithPath: "/Users/example/Library/Application Support/MobileSync/Backup"),
                  sizeBytes: 12_000_000_000, categoryID: nil, items: [], isPartial: false)
        ]
        return SystemDataViewModel(report: SystemDataReport(groups: groups))
    }

    @MainActor
    private func render<V: View>(_ view: V, file: URL, dark: Bool) async throws {
        let size = NSSize(width: 1440, height: 900)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 800_000_000)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2880, pixelsHigh: 1800,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // Flatten the rendered opaque canvas into an sRGB buffer without alpha.
        let rgb = try XCTUnwrap(CGContext(data: nil, width: 2880, height: 1800,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        rgb.draw(try XCTUnwrap(bitmap.cgImage), in: CGRect(x: 0, y: 0, width: 2880, height: 1800))
        let opaque = NSBitmapImageRep(cgImage: try XCTUnwrap(rgb.makeImage()))
        let png = try XCTUnwrap(opaque.representation(using: .png, properties: [:]))
        XCTAssertEqual(bitmap.pixelsWide, 2880)
        XCTAssertEqual(bitmap.pixelsHigh, 1800)
        XCTAssertFalse(opaque.hasAlpha)
        XCTAssertGreaterThan(png.count, 100_000)
        try png.write(to: file, options: .atomic)
        print("PROMOTION_PNG: \(file.path)")
        window.close()
    }
}

private struct PromotionLocale: Decodable {
    let language: String
    let folder: String
    let locale: String
    let footer: String
    let slides: [PromotionCopy]
    var rtl: Bool { language == "arabic" }
}

private struct PromotionCopy: Decodable {
    let label: String
    let title: String
    let body: String
    let points: [String]
}

private struct PromotionCanvas: View {
    let entry: PromotionLocale
    let index: Int
    let background: NSImage
    let icon: NSImage
    let screen: AnyView
    let screenSize: CGSize
    let screenScale: CGFloat
    let dark: Bool
    private let ink = Color(red: 0.12, green: 0.16, blue: 0.19)
    private let secondary = Color(red: 0.32, green: 0.37, blue: 0.40)
    private let accent = Color(red: 0.22, green: 0.39, blue: 0.48)
    private var copy: PromotionCopy { entry.slides[index] }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.96, green: 0.96, blue: 0.95)
            Image(nsImage: background).resizable().scaledToFill().frame(width: 1440, height: 900).clipped().opacity(0.7)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                    Text("Mac Core").font(.system(size: 21, weight: .semibold)).foregroundStyle(ink)
                }.environment(\.layoutDirection, .leftToRight)
                Spacer().frame(height: 127)
                Text(copy.label).font(.system(size: 11, weight: .semibold)).tracking(entry.rtl ? 0 : 1.5)
                    .foregroundStyle(accent).padding(.bottom, 20)
                Text(copy.title).font(.system(size: 47, weight: .semibold)).tracking(entry.rtl ? 0 : -1.7)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true).foregroundStyle(ink)
                    .padding(.bottom, 25)
                RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 38, height: 3).padding(.bottom, 24)
                Text(copy.body).font(.system(size: 17, weight: .regular)).lineSpacing(7)
                    .foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 17) {
                    ForEach(Array(copy.points.enumerated()), id: \.offset) { offset, point in
                        HStack(alignment: .top, spacing: 10) {
                            Text(String(format: "%02d", offset + 1)).font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(accent).frame(width: 20).padding(.top, 4)
                            Text(point).font(.system(size: 13, weight: .medium)).foregroundStyle(ink)
                                .frame(width: 320, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(.top, 36)
                Spacer(minLength: 0)
            }
            .frame(width: 350, height: 750, alignment: .topLeading)
            .environment(\.layoutDirection, entry.rtl ? .rightToLeft : .leftToRight)
            .offset(x: entry.rtl ? 1018 : 68, y: 65)

            Group {
                if index == 4 {
                    screen.frame(width: screenSize.width, height: screenSize.height)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            ForEach([Color(red: 0.96, green: 0.38, blue: 0.35), Color(red: 0.96, green: 0.74, blue: 0.30), Color(red: 0.34, green: 0.72, blue: 0.39)], id: \.self) { color in
                                Circle().fill(color).frame(width: 10, height: 10)
                            }
                            Spacer()
                            Text("Mac Core").font(.system(size: 12, weight: .medium)).foregroundStyle(dark ? .white.opacity(0.6) : .black.opacity(0.5))
                            Spacer()
                            Color.clear.frame(width: 46, height: 1)
                        }.padding(.horizontal, 18).frame(height: 32)
                            .background(dark ? Color(white: 0.16) : Color(white: 0.94))
                        screen.frame(width: screenSize.width, height: screenSize.height)
                    }
                    .frame(width: screenSize.width)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.black.opacity(0.13), lineWidth: 1))
                    .shadow(color: .black.opacity(0.13), radius: 22, x: 0, y: 14)
                }
            }
            .scaleEffect(screenScale, anchor: .topLeading)
            .frame(width: screenSize.width * screenScale, height: (screenSize.height + (index == 4 ? 0 : 32)) * screenScale, alignment: .topLeading)
            .offset(x: entry.rtl ? 62 : 494, y: index == 4 ? 68 : 64)

            HStack {
                Text(entry.footer).font(.system(size: 10)).foregroundStyle(secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 1080, alignment: .leading)
                Spacer()
                Text("MAC CORE   /   0\(index + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5).foregroundStyle(secondary)
            }.frame(width: 1304).offset(x: 68, y: 864)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: 1440, height: 900)
        .clipped()
    }
}

@MainActor
private struct PromotionMenuPreview: View {
    @ObservedObject var settings: SettingsStore
    let localization: LocalizationManager
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 16) {
                Image(systemName: "waveform.path.ecg").foregroundStyle(AppColor.primary)
                Text(MenuBarTitleFormatter.title(snapshot: MenuBarTitleFormatter.example, settings: settings))
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                Spacer(minLength: 0)
            }.padding(.horizontal, 22).frame(width: 850, height: 46)
                .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.black.opacity(0.12)))
                .offset(x: 10, y: 10)
            VStack(spacing: 0) {
                Text(tr("nav.settings")).font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 46).background(AppColor.sidebar)
                Form { MenuBarPreferences(settings: settings, initiallyExpanded: true) }.formStyle(.grouped)
            }.frame(width: 690, height: 950)
                .environment(\.layoutDirection, localization.layoutDirection)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.black.opacity(0.12)))
                .shadow(color: .black.opacity(0.10), radius: 16, y: 10)
                .scaleEffect(0.70, anchor: .topLeading)
                .frame(width: 483, height: 665, alignment: .topLeading)
                .offset(x: 0, y: 76)
            MenuBarPanel(vm: MenuBarMonitorViewModel(snapshot: MenuBarTitleFormatter.example),
                         settings: settings, localization: localization, automaticallyRefresh: false)
                .frame(width: 320)
                .background(AppColor.background)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.12)))
                .shadow(color: .black.opacity(0.13), radius: 18, y: 12)
                .offset(x: 523, y: 145)
        }
        .frame(width: 900, height: 770, alignment: .topLeading)
        .environment(\.layoutDirection, .leftToRight)
    }
}
