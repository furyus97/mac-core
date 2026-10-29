import Foundation

struct SystemDataGroup: Identifiable {
    let id: String
    let titleKey: String
    let root: URL
    let sizeBytes: Int64
    let categoryID: CleanCategoryID?
    let items: [CleanableItem]
    let isPartial: Bool

    var reviewableBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
}

struct SystemDataReport {
    let groups: [SystemDataGroup]
    var identifiedBytes: Int64 { groups.reduce(0) { $0 + $1.sizeBytes } }
    var reviewableBytes: Int64 { groups.reduce(0) { $0 + $1.reviewableBytes } }
    var isPartial: Bool { groups.contains(where: \.isPartial) }
}
