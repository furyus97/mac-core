import Foundation

/// Risk classification shown for every cleanable item.
///
/// Core principle #4: every deletion target is labeled 안전 / 주의 / 위험 so the
/// user can make an informed choice before anything is removed.
enum SafetyLevel: Int, Comparable, Codable, CaseIterable, Identifiable {
    /// 안전 — regenerated automatically by the system or apps (caches, logs).
    case safe = 0
    /// 주의 — the user may still want some of this (downloads, trash contents).
    case caution = 1
    /// 위험 — could affect apps or data; only surfaced, removed only in advanced mode.
    case risky = 2

    var id: Int { rawValue }

    static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Localized short label.
    var title: String {
        switch self {
        case .safe: return tr("safety.safe")
        case .caution: return tr("safety.caution")
        case .risky: return tr("safety.risky")
        }
    }

    /// One-line explanation of what the level means.
    var explanation: String {
        switch self {
        case .safe: return tr("safety.safe.explain")
        case .caution: return tr("safety.caution.explain")
        case .risky: return tr("safety.risky.explain")
        }
    }

    /// SF Symbol used to represent the level.
    var systemImage: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .risky: return "xmark.octagon.fill"
        }
    }
}
