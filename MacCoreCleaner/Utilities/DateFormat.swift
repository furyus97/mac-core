import Foundation

enum DateFormat {
    /// Short time ("11:43 AM") in the app language rather than the system locale.
    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(activeLanguage().locale))
    }

    static func string(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.year().month(.abbreviated).day()
            .locale(activeLanguage().locale))
    }

    static func relativeString(_ date: Date?, reference: Date = Date()) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = activeLanguage().locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: reference)
    }

    static func daysSince(_ date: Date?, reference: Date = Date()) -> Int {
        guard let date else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: date, to: reference).day ?? 0)
    }
}
