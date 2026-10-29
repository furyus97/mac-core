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

    var formattedSize: String { ByteFormat.string(fromBytes: sizeBytes) }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
