import Foundation

/// A single file or directory that could be removed. Produced by the scan
/// services and shown to the user with full transparency (path, size, dates,
/// safety) before anything is deleted.
struct CleanableItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    var displayName: String
    /// Optional human explanation of what this item is.
    var detail: String?
    var sizeBytes: Int64
    var modifiedDate: Date?
    var accessedDate: Date?
    var safety: SafetyLevel
    var categoryID: CleanCategoryID
    var isDirectory: Bool
    /// User selection state (checkbox). Defaults follow the category.
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        displayName: String? = nil,
        detail: String? = nil,
        sizeBytes: Int64,
        modifiedDate: Date? = nil,
        accessedDate: Date? = nil,
        safety: SafetyLevel,
        categoryID: CleanCategoryID,
        isDirectory: Bool,
        isSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.detail = detail
        self.sizeBytes = sizeBytes
        self.modifiedDate = modifiedDate
        self.accessedDate = accessedDate
        self.safety = safety
        self.categoryID = categoryID
        self.isDirectory = isDirectory
        self.isSelected = isSelected
    }

    var path: String { url.path(percentEncoded: false) }

    var formattedSize: String { ByteFormat.string(fromBytes: sizeBytes) }

    static func == (lhs: CleanableItem, rhs: CleanableItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
