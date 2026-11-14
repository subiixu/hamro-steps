import SwiftUI

/// Named colours from SharedAssets.xcassets/Colors, each with a dark variant.
/// Views use these (or system semantic styles like `.primary`), never literals.
/// Declared on `ShapeStyle where Self == Color` so both `Color.canvas` and
/// `.foregroundStyle(.canvas)` work.
///
/// There is deliberately no red "failure" colour: a missed day or an error is
/// shown in neutral tones (PRD: celebrate, never shame).
extension ShapeStyle where Self == Color {
    static var accent: Color { Color("AccentColor") }
    static var canvas: Color { Color("Canvas") }
    static var surface: Color { Color("Surface") }
    static var surfaceMuted: Color { Color("SurfaceMuted") }
    /// Goal reached: the ring past 100% and the "hit" week markers.
    static var goal: Color { Color("Goal") }
    /// Accent for text, links and small icons: darker than `accent` in light
    /// mode so it passes WCAG AA (4.5:1) on canvas, surface and surfaceMuted.
    /// Use as `.tint(.accentText)` on lists and bordered buttons.
    static var accentText: Color { Color("AccentText") }
    /// Secondary text (subtitles, hints). Replaces system `.secondary`, whose
    /// grey falls below AA on the cream canvas.
    static var secondaryText: Color { Color("SecondaryText") }
}

extension Color {
    /// A member's avatar colour, sent by the backend as "#RRGGBB". Anything
    /// unreadable falls back to the accent colour.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .accent
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
