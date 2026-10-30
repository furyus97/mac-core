import Foundation
import SwiftUI

enum Lang: String, CaseIterable {
    case en, ko, ja
    case zhHans = "zh-Hans", zhHant = "zh-Hant"
    case es, fr, de, ptBR = "pt-BR", ar
    var locale: Locale { Locale(identifier: rawValue) }
    var isRightToLeft: Bool { self == .ar }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    // Preserve original stored preference values.
    case system, korean, english, japanese, chineseSimplified, chineseTraditional
    case spanish, french, german, portuguese, arabic
    var id: String { rawValue }
    var resolved: Lang? {
        switch self {
        case .system: return nil
        case .korean: return .ko
        case .english: return .en
        case .japanese: return .ja
        case .chineseSimplified: return .zhHans
        case .chineseTraditional: return .zhHant
        case .spanish: return .es
        case .french: return .fr
        case .german: return .de
        case .portuguese: return .ptBR
        case .arabic: return .ar
        }
    }
    var displayName: String {
        switch self {
        case .system: return tr("set.lang.system")
        case .korean: return "한국어"
        case .english: return "English"
        case .japanese: return "日本語"
        case .chineseSimplified: return "简体中文"
        case .chineseTraditional: return "繁體中文"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .portuguese: return "Português (Brasil)"
        case .arabic: return "العربية"
        }
    }
}

private final class LanguageState: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Lang = .en
    func read() -> Lang {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func write(_ newValue: Lang) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
private let languageState = LanguageState()
func activeLanguage() -> Lang { languageState.read() }

enum LocalizationCatalog {
    static let tables: [Lang: [String: String]] = Dictionary(uniqueKeysWithValues: Lang.allCases.map { language in
        // Every *.strings table in the language folder (except InfoPlist) merges into
        // one catalog, so features can keep their strings in their own table.
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj") else { return (language, [:]) }
        let folder = URL(fileURLWithPath: path)
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "strings" && $0.lastPathComponent != "InfoPlist.strings" }
            .sorted { ($0.lastPathComponent == "Localizable.strings" ? "" : $0.lastPathComponent) < ($1.lastPathComponent == "Localizable.strings" ? "" : $1.lastPathComponent) }
        var merged: [String: String] = [:]
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { continue }
            merged.merge(table) { current, _ in current }
        }
        return (language, merged)
    })
    static func string(_ key: String, language: Lang) -> String {
        tables[language]?[key] ?? tables[.en]?[key] ?? key
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            languageState.write(Self.resolve(language))
        }
    }
    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        languageState.write(Self.resolve(language))
    }
    static func resolve(_ language: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let resolved = language.resolved { return resolved }
        for raw in preferred {
            let code = raw.replacingOccurrences(of: "_", with: "-").lowercased()
            if code.hasPrefix("zh") {
                return code.contains("hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo") ? .zhHant : .zhHans
            }
            if code == "pt" || code.hasPrefix("pt-") { return .ptBR }
            if let match = Lang.allCases.first(where: {
                code == $0.rawValue.lowercased() || code.hasPrefix($0.rawValue.lowercased() + "-")
            }) { return match }
        }
        return .en
    }
    var locale: Locale { Self.resolve(language).locale }
    var layoutDirection: LayoutDirection { Self.resolve(language).isRightToLeft ? .rightToLeft : .leftToRight }
}

func tr(_ key: String) -> String {
    LocalizationCatalog.string(key, language: activeLanguage())
}
func tr(_ key: String, _ args: CVarArg...) -> String {
    String(format: tr(key), locale: activeLanguage().locale, arguments: args)
}
