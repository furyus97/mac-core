import Foundation

/// Stable identifier for every category the app can scan and clean.
///
/// MVP categories are marked below; the remaining cases are reserved so that
/// post-MVP features (Browser Cleaner, App Uninstaller, …) can be added without
/// changing the scanning contracts.
enum CleanCategoryID: String, CaseIterable, Codable, Hashable, Identifiable {
    // MARK: Storage Cleaner (MVP)
    case userCache
    case userLogs
    case trash
    case downloadsLargeFiles

    // MARK: Developer Cleaner (MVP)
    case xcodeDerivedData
    case xcodeArchives
    case simulatorCache
    case swiftPMCache
    case homebrewCache
    case gradleCache
    case dockerData

    // MARK: Other feature item kinds
    case application
    case largeFile

    // MARK: Reserved for post-MVP
    case systemLogs
    case browserCache
    case mailCache
    case iosBackups
    case updateLeftovers

    var id: String { rawValue }
}

/// Where a category belongs in the UI (drives which screen shows it).
enum CleanGroup: String, Codable, Hashable {
    case storage
    case developer
    case system
}

/// Static metadata describing a cleanable category. Title/subtitle are localized
/// at access time (keyed by `id.rawValue`) so they follow the current language
/// without rebuilding the catalog. The actual files are discovered at scan time
/// and returned as `CleanableItem`s.
struct CleanCategory: Identifiable, Hashable {
    let id: CleanCategoryID
    let systemImage: String
    let group: CleanGroup
    /// Default risk level for the category; individual items may override it.
    let defaultSafety: SafetyLevel
    /// Whether items in this category are pre-selected after a scan.
    let selectedByDefault: Bool
    /// Human-readable description of the root location(s) scanned (a path —
    /// identical in every language).
    let locationDescription: String

    /// Localized title (e.g. "사용자 캐시" / "User Cache").
    var title: String { tr("cat.\(id.rawValue).title") }
    /// Localized subtitle.
    var subtitle: String { tr("cat.\(id.rawValue).sub") }

    static func == (lhs: CleanCategory, rhs: CleanCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension CleanCategory {
    /// The catalog of categories the MVP knows about.
    static let catalog: [CleanCategoryID: CleanCategory] = [
        .userCache: CleanCategory(
            id: .userCache, systemImage: "shippingbox.fill", group: .storage,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Caches"),
        .userLogs: CleanCategory(
            id: .userLogs, systemImage: "doc.text.fill", group: .storage,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Logs"),
        .trash: CleanCategory(
            id: .trash, systemImage: "trash.fill", group: .storage,
            defaultSafety: .caution, selectedByDefault: false,
            locationDescription: "~/.Trash"),
        .downloadsLargeFiles: CleanCategory(
            id: .downloadsLargeFiles, systemImage: "arrow.down.circle.fill", group: .storage,
            defaultSafety: .caution, selectedByDefault: false,
            locationDescription: "~/Downloads"),
        .xcodeDerivedData: CleanCategory(
            id: .xcodeDerivedData, systemImage: "hammer.fill", group: .developer,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Developer/Xcode/DerivedData"),
        .xcodeArchives: CleanCategory(
            id: .xcodeArchives, systemImage: "archivebox.fill", group: .developer,
            defaultSafety: .caution, selectedByDefault: false,
            locationDescription: "~/Library/Developer/Xcode/Archives"),
        .simulatorCache: CleanCategory(
            id: .simulatorCache, systemImage: "iphone.gen3", group: .developer,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Developer/CoreSimulator/Caches"),
        .swiftPMCache: CleanCategory(
            id: .swiftPMCache, systemImage: "shippingbox.fill", group: .developer,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Caches/org.swift.swiftpm"),
        .homebrewCache: CleanCategory(
            id: .homebrewCache, systemImage: "mug.fill", group: .developer,
            defaultSafety: .safe, selectedByDefault: true,
            locationDescription: "~/Library/Caches/Homebrew"),
        .gradleCache: CleanCategory(
            id: .gradleCache, systemImage: "square.stack.3d.up.fill", group: .developer,
            defaultSafety: .safe, selectedByDefault: false,
            locationDescription: "~/.gradle/caches"),
        .dockerData: CleanCategory(
            id: .dockerData, systemImage: "cube.transparent.fill", group: .developer,
            defaultSafety: .risky, selectedByDefault: false,
            locationDescription: "~/Library/Containers/com.docker.docker"),
    ]

    /// Lookup helper with a safe fallback so the UI never crashes on an unknown id.
    static func metadata(for id: CleanCategoryID) -> CleanCategory {
        catalog[id] ?? CleanCategory(
            id: id, systemImage: "questionmark.folder", group: .storage,
            defaultSafety: .caution, selectedByDefault: false, locationDescription: "")
    }
}
