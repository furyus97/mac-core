import Foundation

/// Supported browsers for the Browser cleaner.
enum BrowserKind: String, CaseIterable, Identifiable, Hashable {
    case safari, chrome, edge, firefox
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .safari: return "Safari"
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .firefox: return "Firefox"
        }
    }
    var systemImage: String {
        switch self {
        case .safari: return "safari.fill"
        default: return "globe"
        }
    }

    /// Bundle identifiers used to detect whether the browser is currently open.
    /// Cleaning a live profile is intentionally blocked because the browser can
    /// immediately rewrite its databases and produce partial/corrupt results.
    var bundleIdentifiers: Set<String> {
        switch self {
        case .safari: return ["com.apple.Safari"]
        case .chrome: return ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary"]
        case .edge: return ["com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev"]
        case .firefox: return ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition"]
        }
    }
}

/// A category of browser data.
enum BrowserDataKind: String, CaseIterable, Identifiable, Hashable {
    case cache, cookies, history, session, downloads, loginData
    var id: String { rawValue }

    /// Localization key for the label.
    var titleKey: String { "browser.kind.\(rawValue)" }

    /// Cache is safe & pre-selected; the rest may log you out / lose state.
    var safety: SafetyLevel {
        switch self {
        case .cache, .downloads: return .safe
        case .cookies, .history, .session: return .caution
        case .loginData: return .risky
        }
    }
    var selectedByDefault: Bool { self == .cache }
}

/// A discovered browser-data item (a category for one browser) with its paths.
struct BrowserDataItem: Identifiable, Hashable {
    let browser: BrowserKind
    let kind: BrowserDataKind
    var sizeBytes: Int64
    var paths: [URL]
    var isSelected: Bool

    var id: String { "\(browser.rawValue).\(kind.rawValue)" }
    var formattedSize: String { ByteFormat.string(fromBytes: sizeBytes) }
}
