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

    @Test(arguments: ["AccentColor", "Canvas", "Surface", "SurfaceMuted", "Streak", "Cheer", "Goal"])
    func colourExists(_ name: String) {
        #expect(UIColor(named: name) != nil)
    }
}
