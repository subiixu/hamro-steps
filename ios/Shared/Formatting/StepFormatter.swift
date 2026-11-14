import Foundation

/// Step counts as people read them. Negative input is clamped to zero.
enum StepFormatter {
    /// "12,345" (grouped for the locale).
    static func count(_ steps: Int, locale: Locale = .current) -> String {
        max(0, steps).formatted(.number.grouping(.automatic).locale(locale))
    }

    /// "12K", "1.5K", "980": for tight spaces like the widget and week bars.
    static func compact(_ steps: Int, locale: Locale = .current) -> String {
        max(0, steps).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
    }

    /// "1 step", "12,345 steps".
    static func withUnit(_ steps: Int, locale: Locale = .current) -> String {
        let value = max(0, steps)
        let unit = value == 1 ? String(localized: "step") : String(localized: "steps")
        return "\(count(value, locale: locale)) \(unit)"
    }
}
