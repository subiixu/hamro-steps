import Foundation

/// Times and durations for walks, status and the feed, in plain words.
enum ActivityFormat {
    /// How long a walk has run: "Just started", "1 min", "12 min",
    /// "1 hr", "1 hr 5 min". Minutes round down.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds)) / 60
        guard total > 0 else { return String(localized: "Just started") }
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return String(localized: "\(minutes) min") }
        if minutes == 0 { return String(localized: "\(hours) hr") }
        return String(localized: "\(hours) hr \(minutes) min")
    }

    /// "Walking for 12 min", or "Just started" in the first minute.
    static func walkingFor(_ walk: ActiveWalk, now: Date) -> String {
        let seconds = now.timeIntervalSince(walk.startedAt)
        guard seconds >= 60 else { return String(localized: "Just started") }
        return String(localized: "Walking for \(elapsed(seconds))")
    }

    /// "Stops by itself at 6:45 PM".
    static func autoStop(_ walk: ActiveWalk, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        String(localized: "Stops by itself at \(timeOfDay(walk.endsAt, locale: locale, timeZone: timeZone))")
    }

    /// "6:45 PM" (or "18:45", following the locale).
    static func timeOfDay(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone)
        return date.formatted(style)
    }

    /// When a status clears: "Until 6:45 PM" today, "Until tomorrow,
    /// 6:45 PM", or "Until Tue, 6:45 PM" further out.
    static func statusUntil(_ date: Date, now: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = timeOfDay(date, locale: locale, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Until \(time)")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "Until tomorrow, \(time)")
        }
        let weekday = date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone).weekday(.abbreviated))
        return String(localized: "Until \(weekday), \(time)")
    }

    /// Feed time: "Just now", then "5 min ago", "2 hr ago", "yesterday".
    static func relative(_ date: Date, now: Date, locale: Locale = .current) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "Just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
