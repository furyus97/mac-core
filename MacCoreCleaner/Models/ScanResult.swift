import Foundation

/// Progress reported by a long-running scan so the UI can show a live indicator
/// without blocking. (Tech requirement: scans are async and never freeze the UI.)
struct ScanProgress: Equatable {
    var fractionCompleted: Double      // 0.0 ... 1.0
    var phase: String                  // e.g. "사용자 캐시 스캔 중"
    var currentPath: String?

    static let idle = ScanProgress(fractionCompleted: 0, phase: "", currentPath: nil)
}

/// The result of scanning a single category: its metadata plus the items found.
struct CategoryScanResult: Identifiable, Hashable {
    let category: CleanCategory
    var items: [CleanableItem]
    /// Disclosure state for the collapsible UI.
    var isExpanded: Bool

    var id: CleanCategoryID { category.id }

    init(category: CleanCategory, items: [CleanableItem], isExpanded: Bool = false) {
        self.category = category
        self.items = items
        self.isExpanded = isExpanded
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    var itemCount: Int { items.count }

    var selectedItems: [CleanableItem] { items.filter(\.isSelected) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.sizeBytes } }
    var selectedCount: Int { selectedItems.count }

    var isEmpty: Bool { items.isEmpty }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.isSelected) }
    var anySelected: Bool { items.contains(where: \.isSelected) }

    var formattedTotal: String { ByteFormat.string(fromBytes: totalBytes) }
}

extension Array where Element == CategoryScanResult {
    var totalBytes: Int64 { reduce(0) { $0 + $1.totalBytes } }
    var selectedBytes: Int64 { reduce(0) { $0 + $1.selectedBytes } }
    var selectedCount: Int { reduce(0) { $0 + $1.selectedCount } }
    var selectedItems: [CleanableItem] { flatMap(\.selectedItems) }
}
