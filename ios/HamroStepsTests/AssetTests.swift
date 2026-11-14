import Testing
import UIKit
@testable import HamroSteps

/// Every `Icon` and named colour must exist in the built asset catalog.
struct AssetTests {
    @Test(arguments: Icon.allCases)
    func iconExistsAsTemplate(_ icon: Icon) throws {
        let image = try #require(UIImage(named: icon.rawValue))
        #expect(image.renderingMode == .alwaysTemplate)
        #expect(image.size == CGSize(width: 24, height: 24))
    }

    @Test(arguments: ["AccentColor", "AccentText", "Canvas", "Surface", "SurfaceMuted", "SecondaryText", "Goal", "GoalText"])
    func colourExists(_ name: String) {
        #expect(UIColor(named: name) != nil)
    }

    /// Light mode only: a colour must not change in dark appearance.
    @Test(arguments: ["AccentColor", "AccentText", "Canvas", "Surface", "SurfaceMuted", "SecondaryText", "Goal", "GoalText"])
    func colourHasNoDarkVariant(_ name: String) throws {
        let colour = try #require(UIColor(named: name))
        let light = colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        #expect(light == dark)
    }
}
