import Foundation

/// Words for a profile: the birthday without its year, and someone's
/// local time from their stored time zone.
enum ProfileFormat {
    /// Birthdays are calendar days, not moments: read and written in
    /// Gregorian at GMT so they never shift a day with the phone's zone.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static let earliestBirthYear = 1900

    /// The calendar the birthday picker works in: always Gregorian (the
    /// stored "YYYY-MM-DD" is Gregorian), in the phone's time zone. Not
    /// `Calendar.current`, which may be Buddhist or Japanese and would turn
    /// 1990 into 2533 or Heisei 2.
    static func birthdayCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// "YYYY-MM-DD" → the date at GMT midnight, or `nil` when it isn't a
    /// real day ("2025-02-30") or isn't in that exact shape.
    static func birthdayDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return date
    }

    /// The date the picker chose (in `birthdayCalendar()`) → "YYYY-MM-DD".
    static func birthdayString(from date: Date, in pickerCalendar: Calendar = birthdayCalendar()) -> String {
        let parts = pickerCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The stored birthday as a date for the picker, in `birthdayCalendar()`.
    static func pickerDate(forBirthday text: String, in pickerCalendar: Calendar = birthdayCalendar()) -> Date? {
        guard let date = birthdayDate(text) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return pickerCalendar.date(from: parts)
    }

    /// What the backend accepts: a real day, year 1900 or later, not after
    /// today.
    static func isValidBirthday(_ text: String, today: Date = .now, in todayCalendar: Calendar = birthdayCalendar()) -> Bool {
        guard let date = birthdayDate(text),
              let latest = birthdayDate(birthdayString(from: today, in: todayCalendar))
        else { return false }
        return calendar.component(.year, from: date) >= earliestBirthYear && date <= latest
    }

    /// "12 March" (day and month in the reader's order, never the year), or
    /// `nil` for an unreadable value.
    static func birthday(_ text: String, locale: Locale = .current) -> String? {
        guard let date = birthdayDate(text) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: date)
    }

    /// Their time now, e.g. "9:41 pm", or `nil` when the zone is missing or
    /// unknown.
    static func localTime(timezone: String?, now: Date = .now, locale: Locale = .current) -> String? {
        guard let id = timezone, !id.isEmpty, let zone = TimeZone(identifier: id) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: now)
    }

    /// The profile's place line: "Sydney · 9:41 pm"; just "Sydney" when
    /// their time zone is unknown; "9:41 pm local time" with no city; `nil`
    /// when there's neither.
    static func placeLine(city: String?, timezone: String?, now: Date = .now, locale: Locale = .current) -> String? {
        let place = city.map(FamilyRules.cleanCity).flatMap { $0.isEmpty ? nil : $0 }
        let time = localTime(timezone: timezone, now: now, locale: locale)
        switch (place, time) {
        case let (place?, time?): return "\(place) · \(time)"
        case let (place?, nil): return place
        case let (nil, time?): return String(localized: "\(time) local time")
        case (nil, nil): return nil
        }
    }
}
