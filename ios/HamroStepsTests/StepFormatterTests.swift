import Foundation
import Testing
@testable import HamroSteps

struct StepFormatterTests {
    private let us = Locale(identifier: "en_US")

    @Test(arguments: [(0, "0"), (7, "7"), (1_234, "1,234"), (1_234_567, "1,234,567"), (-25, "0")])
    func count(_ steps: Int, _ expected: String) {
        #expect(StepFormatter.count(steps, locale: us) == expected)
    }

    @Test func countFollowsTheLocale() {
        #expect(StepFormatter.count(12_345, locale: Locale(identifier: "de_DE")) == "12.345")
    }

    @Test(arguments: [(980, "980"), (1_500, "1.5K"), (12_000, "12K"), (12_345, "12.3K"), (-1, "0")])
    func compact(_ steps: Int, _ expected: String) {
        #expect(StepFormatter.compact(steps, locale: us) == expected)
    }

    @Test func withUnitPluralises() {
        #expect(StepFormatter.withUnit(1, locale: us) == "1 step")
        #expect(StepFormatter.withUnit(0, locale: us) == "0 steps")
        #expect(StepFormatter.withUnit(10_500, locale: us) == "10,500 steps")
    }
}
