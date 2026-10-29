import Foundation
import Combine
import SwiftUI

/// Appearance preference (Settings → Appearance).
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("appearance.system")
        case .light: return tr("appearance.light")
        case .dark: return tr("appearance.dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Live readings that can be placed in the menu-bar title and popover. The
/// persisted order is also the visual order, so the user can prioritise the
/// information that matters most on a crowded menu bar.
enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case temperature
    case diskFree
    case networkDown
    case networkUp
    case battery
    case batteryPower
    case systemPower

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return tr("menubar.metric.cpu")
        case .memory: return tr("menubar.metric.memory")
        case .temperature: return tr("menubar.metric.temperature")
        case .diskFree: return tr("menubar.metric.diskFree")
        case .networkDown: return tr("menubar.metric.networkDown")
        case .networkUp: return tr("menubar.metric.networkUp")
        case .battery: return tr("menubar.metric.battery")
        case .batteryPower: return tr("power.batteryWatts")
        case .systemPower: return tr("power.system")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .temperature: return "thermometer.medium"
        case .diskFree: return "externaldrive"
        case .networkDown: return "arrow.down.circle"
        case .networkUp: return "arrow.up.circle"
        case .battery: return "battery.75"
        case .batteryPower: return "bolt.batteryblock"
        case .systemPower: return "bolt"
        }
    }
}

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
    case detailed
    case compact
    case valuesOnly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .detailed: return tr("menubar.style.detailed")
        case .compact: return tr("menubar.style.compact")
        case .valuesOnly: return tr("menubar.valuesOnly")
        }
    }
}

enum MenuBarRefreshRate: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case efficient
    case relaxed

    var id: String { rawValue }
    var seconds: Double {
        switch self {
        case .fast: return 1
        case .balanced: return 2.5
        case .efficient: return 5
        case .relaxed: return 10
        }
    }
    var title: String {
        switch self {
        case .fast: return tr("menubar.refresh.fast")
        case .balanced: return tr("menubar.refresh.balanced")
        case .efficient: return tr("menubar.refresh.efficient")
        case .relaxed: return tr("menubar.refresh.relaxed")
        }
    }
}

/// User preferences, persisted to `UserDefaults`. Injected into the environment
/// and also reachable via `AppServices.shared.settings`.
@MainActor
final class SettingsStore: ObservableObject {

    private enum Key {
        static let appearance = "appearance"
        static let autoScanOnLaunch = "autoScanOnLaunch"
        static let removalMode = "removalMode"
        static let advancedMode = "advancedMode"
        static let showRiskyItems = "showRiskyItems"
        static let menuBarMonitor = "menuBarMonitor"
        static let menuBarMetrics = "menuBarMetrics"
        static let menuBarDisplayStyle = "menuBarDisplayStyle"
        static let menuBarRefreshRate = "menuBarRefreshRate"
        static let menuBarShowIcon = "menuBarShowIcon"
        static let downloadsThresholdMB = "downloadsThresholdMB"
        static let temperatureSource = "temperatureSource"
    }

    private let defaults: UserDefaults

    /// Appearance preference (system / light / dark).
    @Published var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    /// Auto-run a quick scan when the app launches.
    @Published var autoScanOnLaunch: Bool { didSet { defaults.set(autoScanOnLaunch, forKey: Key.autoScanOnLaunch) } }
    /// Default removal mode (Trash vs permanent).
    @Published var removalMode: RemovalMode { didSet { defaults.set(removalMode.rawValue, forKey: Key.removalMode) } }
    /// Unlocks risky/advanced-only actions (e.g., permanent delete, advanced categories).
    @Published var advancedMode: Bool { didSet { defaults.set(advancedMode, forKey: Key.advancedMode) } }
    /// Whether risky-rated items are displayed at all.
    @Published var showRiskyItems: Bool { didSet { defaults.set(showRiskyItems, forKey: Key.showRiskyItems) } }
    /// Shows the live menu-bar monitor.
    @Published var menuBarMonitor: Bool { didSet { defaults.set(menuBarMonitor, forKey: Key.menuBarMonitor) } }
    /// Ordered readings shown in the status item and its popover.
    @Published private(set) var menuBarMetrics: [MenuBarMetric] {
        didSet { defaults.set(menuBarMetrics.map(\.rawValue), forKey: Key.menuBarMetrics) }
    }
    @Published var menuBarDisplayStyle: MenuBarDisplayStyle {
        didSet { defaults.set(menuBarDisplayStyle.rawValue, forKey: Key.menuBarDisplayStyle) }
    }
    @Published var menuBarRefreshRate: MenuBarRefreshRate {
        didSet { defaults.set(menuBarRefreshRate.rawValue, forKey: Key.menuBarRefreshRate) }
    }
    @Published var menuBarShowIcon: Bool {
        didSet { defaults.set(menuBarShowIcon, forKey: Key.menuBarShowIcon) }
    }
    @Published var menuBarMemoryBytes: Bool { didSet { defaults.set(menuBarMemoryBytes, forKey: "menuBarMemoryBytes") } }
    @Published var menuBarDiskPercent: Bool { didSet { defaults.set(menuBarDiskPercent, forKey: "menuBarDiskPercent") } }
    @Published var menuBarFahrenheit: Bool { didSet { defaults.set(menuBarFahrenheit, forKey: "menuBarFahrenheit") } }
    @Published var menuBarSeparators: Bool { didSet { defaults.set(menuBarSeparators, forKey: "menuBarSeparators") } }
    @Published var menuBarSensorID: String { didSet { defaults.set(menuBarSensorID, forKey: "menuBarSensorID") } }
    @Published var menuBarFontSize: Double { didSet { defaults.set(menuBarFontSize, forKey: "menuBarFontSize") } }
    @Published var menuBarExpandedDetails: Bool { didSet { defaults.set(menuBarExpandedDetails, forKey: "menuBarExpandedDetails") } }
    /// Size threshold (MB) for "large" downloads.
    @Published var downloadsThresholdMB: Int { didSet { defaults.set(downloadsThresholdMB, forKey: Key.downloadsThresholdMB) } }
    /// Which sensor the Dashboard temperature card displays.
    @Published var temperatureSource: TemperatureSource { didSet { defaults.set(temperatureSource.rawValue, forKey: Key.temperatureSource) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.appearance: AppearanceMode.system.rawValue,
            Key.autoScanOnLaunch: false,
            Key.removalMode: RemovalMode.trash.rawValue,
            Key.advancedMode: false,
            Key.showRiskyItems: false,
            Key.menuBarMonitor: false,
            Key.menuBarMetrics: [
                MenuBarMetric.cpu.rawValue,
                MenuBarMetric.memory.rawValue,
                MenuBarMetric.temperature.rawValue,
            ],
            Key.menuBarDisplayStyle: MenuBarDisplayStyle.detailed.rawValue,
            Key.menuBarRefreshRate: MenuBarRefreshRate.balanced.rawValue,
            Key.menuBarShowIcon: true,
            Key.downloadsThresholdMB: 100,
            Key.temperatureSource: TemperatureSource.average.rawValue,
        ])
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        autoScanOnLaunch = defaults.bool(forKey: Key.autoScanOnLaunch)
        let storedAdvancedMode = defaults.bool(forKey: Key.advancedMode)
        let storedRemovalMode = RemovalMode(rawValue: defaults.string(forKey: Key.removalMode) ?? "") ?? .trash
        advancedMode = storedAdvancedMode
        removalMode = storedRemovalMode == .permanentDelete && !storedAdvancedMode ? .trash : storedRemovalMode
        showRiskyItems = defaults.bool(forKey: Key.showRiskyItems)
        menuBarMonitor = defaults.bool(forKey: Key.menuBarMonitor)
        menuBarMetrics = Self.sanitizedMenuBarMetrics(defaults.stringArray(forKey: Key.menuBarMetrics))
        menuBarDisplayStyle = MenuBarDisplayStyle(
            rawValue: defaults.string(forKey: Key.menuBarDisplayStyle) ?? ""
        ) ?? .detailed
        menuBarRefreshRate = MenuBarRefreshRate(
            rawValue: defaults.string(forKey: Key.menuBarRefreshRate) ?? ""
        ) ?? .balanced
        menuBarShowIcon = defaults.bool(forKey: Key.menuBarShowIcon)
        menuBarMemoryBytes = defaults.bool(forKey: "menuBarMemoryBytes")
        menuBarDiskPercent = defaults.bool(forKey: "menuBarDiskPercent")
        menuBarFahrenheit = defaults.bool(forKey: "menuBarFahrenheit")
        menuBarSeparators = defaults.bool(forKey: "menuBarSeparators")
        menuBarSensorID = defaults.string(forKey: "menuBarSensorID") ?? ""
        let storedSize = defaults.double(forKey: "menuBarFontSize")
        menuBarFontSize = [11.0, 12, 13].contains(storedSize) ? storedSize : 12
        menuBarExpandedDetails = defaults.object(forKey: "menuBarExpandedDetails") as? Bool ?? true
        downloadsThresholdMB = min(max(defaults.integer(forKey: Key.downloadsThresholdMB), 10), 5_000)
        temperatureSource = TemperatureSource(rawValue: defaults.string(forKey: Key.temperatureSource) ?? "") ?? .average
    }

    /// The effective removal mode, forcing Trash unless advanced mode allows
    /// permanent deletion. (Safety: permanent delete is gated behind advanced mode.)
    var effectiveRemovalMode: RemovalMode {
        (removalMode == .permanentDelete && advancedMode) ? .permanentDelete : .trash
    }

    static let maxMenuBarMetrics = 4

    var availableMenuBarMetrics: [MenuBarMetric] {
        MenuBarMetric.allCases.filter { !menuBarMetrics.contains($0) }
    }

    /// Keeps at least one metric visible and caps the title at four readings so
    /// Mac Core cannot consume an unreasonable amount of menu-bar space.
    func setMenuBarMetric(_ metric: MenuBarMetric, isEnabled: Bool) {
        if isEnabled {
            guard !menuBarMetrics.contains(metric),
                  menuBarMetrics.count < Self.maxMenuBarMetrics else { return }
            menuBarMetrics.append(metric)
        } else {
            guard menuBarMetrics.count > 1 else { return }
            menuBarMetrics.removeAll { $0 == metric }
        }
    }

    func moveMenuBarMetric(_ metric: MenuBarMetric, offset: Int) {
        guard let source = menuBarMetrics.firstIndex(of: metric) else { return }
        let destination = source + offset
        guard menuBarMetrics.indices.contains(destination) else { return }
        menuBarMetrics.swapAt(source, destination)
    }

    private static func sanitizedMenuBarMetrics(_ rawValues: [String]?) -> [MenuBarMetric] {
        var unique: [MenuBarMetric] = []
        for rawValue in rawValues ?? [] {
            guard let metric = MenuBarMetric(rawValue: rawValue), !unique.contains(metric) else { continue }
            unique.append(metric)
            if unique.count == maxMenuBarMetrics { break }
        }
        return unique.isEmpty ? [.cpu, .memory, .temperature] : unique
    }
}
