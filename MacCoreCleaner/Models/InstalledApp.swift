import Foundation

/// An installed application (Applications screen / uninstaller).
struct InstalledApp: Identifiable, Hashable {
    let id: String           // bundle id, or path when missing
    let name: String
    let version: String
    let bundleURL: URL
    let bundleID: String?
    let sizeBytes: Int64
    let installDate: Date?
    /// Apple/system apps (e.g. under /System/Applications) — surfaced but not removable.
    let isSystem: Bool
    /// Spotlight's last-used date, when macOS recorded one.
    var lastUsedDate: Date? = nil

    /// Not opened for at least six months (only when Spotlight knows a date).
    func isUnused(now: Date = Date()) -> Bool {
        guard let lastUsedDate else { return false }
        return now.timeIntervalSince(lastUsedDate) > 182 * 24 * 3600
    }

    var formattedSize: String { ByteFormat.string(fromBytes: sizeBytes) }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
