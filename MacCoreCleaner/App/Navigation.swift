import Foundation

/// Sidebar destinations for the implemented Mac Core feature set.
enum NavItem: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case smartScan
    case storage
    case memory
    case cpu
    case temperature
    case battery
    case network
    case developer
    case applications
    case largeFiles
    case browser
    case speed
    case protection
    case spaceMap
    case duplicates
    case settings

    var id: String { rawValue }

    /// Localized sidebar / screen title.
    var title: String { tr("nav.\(rawValue)") }

    var systemImage: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.50percent"
        case .smartScan: return "sparkles"
        case .storage: return "externaldrive.fill"
        case .memory: return "memorychip.fill"
        case .cpu: return "cpu.fill"
        case .temperature: return "thermometer.medium"
        case .battery: return "bolt.batteryblock"
        case .network: return "network"
        case .developer: return "hammer.fill"
        case .applications: return "app.badge.fill"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .browser: return "safari.fill"
        case .speed: return "bolt.fill"
        case .protection: return "checkmark.shield.fill"
        case .spaceMap: return "circle.hexagongrid.fill"
        case .duplicates: return "square.on.square"
        case .settings: return "gearshape.fill"
        }
    }
}
