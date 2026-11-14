import Foundation

/// "Today" is a Nepal day for everyone (PRD F5): it starts and ends at
/// midnight in Asia/Kathmandu (UTC+5:45), wherever the phone is.
enum NepalDay {
    static let timeZone = TimeZone(identifier: "Asia/Kathmandu")!

    /// Gregorian, Nepal time, weeks start on Monday. Pass this to the step
    /// source so HealthKit buckets by Nepal midnights.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    /// "YYYY-MM-DD" of the Nepal day containing `date`.
    static func string(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Start (Nepal midnight) of a "YYYY-MM-DD" day.
    static func start(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The Monday-to-Sunday Nepal week containing `date`, as day strings.
    static func week(containing date: Date) -> [String] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: interval.start).map(string(for:))
        }
    }
}
