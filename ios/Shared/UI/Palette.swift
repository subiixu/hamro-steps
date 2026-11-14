import SwiftUI

/// Named colours from SharedAssets.xcassets/Colors, each with a dark variant.
/// Views use these (or system semantic styles like `.primary`), never literals.
/// Declared on `ShapeStyle where Self == Color` so both `Color.canvas` and
/// `.foregroundStyle(.canvas)` work.
extension ShapeStyle where Self == Color {
    static var accent: Color { Color("AccentColor") }
    static var canvas: Color { Color("Canvas") }
    static var surface: Color { Color("Surface") }
    static var surfaceMuted: Color { Color("SurfaceMuted") }
    static var streak: Color { Color("Streak") }
    static var cheer: Color { Color("Cheer") }
    static var goal: Color { Color("Goal") }
}
