import Foundation

/// How an item should be removed. Core principle #5: prefer the Trash; permanent
/// deletion requires a separate, explicit confirmation.
enum RemovalMode: String, Codable, CaseIterable, Identifiable {
    case trash
    case permanentDelete

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: return tr("removal.trash.title")
        case .permanentDelete: return tr("removal.perm.title")
        }
    }

    var explanation: String {
        switch self {
        case .trash: return tr("removal.trash.explain")
        case .permanentDelete: return tr("removal.perm.explain")
        }
    }
}

/// Why a single item could not be removed.
struct CleanFailure: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let reason: String
}

/// Aggregate result of a clean operation, shown to the user afterwards.
struct CleanOutcome {
    var removedCount: Int = 0
    /// Total size of successfully processed targets. Moving to Trash is
    /// recoverable and does not immediately increase free disk space, so this
    /// must not be presented as bytes already freed.
    var processedBytes: Int64 = 0
    var failures: [CleanFailure] = []
    var mode: RemovalMode = .trash

    var hasFailures: Bool { !failures.isEmpty }
    var formattedProcessed: String { ByteFormat.string(fromBytes: processedBytes) }

    static let none = CleanOutcome()
}
