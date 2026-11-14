import SwiftUI

/// Layout constants for the flat, bento-style tiles on the main screens:
/// white tiles on the grey canvas, a hairline edge instead of a shadow.
enum Bento {
    /// Corner radius of a full tile.
    static let radius: CGFloat = 26
    /// Corner radius of a small (half-width) tile.
    static let smallRadius: CGFloat = 24
    /// Gap between tiles, in both directions.
    static let gap: CGFloat = 12
    /// Screen edge to tile.
    static let margin: CGFloat = 16
    /// Inner padding of a tile.
    static let padding: CGFloat = 20
    /// Inner padding of a small tile.
    static let smallPadding: CGFloat = 18
    /// The 1pt hairline that lets a white tile read on the canvas.
    static let edge = Color.black.opacity(0.05)
}

extension View {
    /// The flat tile surface: solid fill, continuous corners, hairline edge,
    /// no shadow. Glass is for floating and tappable controls only.
    func bentoSurface(_ fill: some ShapeStyle = Color.surface, radius: CGFloat = Bento.radius) -> some View {
        background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Bento.edge, lineWidth: 1)
            )
    }
}

/// A white tile, optionally with a small heading ("Today", "This week").
struct Card<Content: View>: View {
    var title: LocalizedStringKey?
    var icon: Icon?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                TileLabel(title, icon: icon)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Bento.padding)
        .bentoSurface()
    }
}

/// The small, quiet heading at the top of a tile, with a leading icon.
struct TileLabel: View {
    let text: LocalizedStringKey
    var icon: Icon?
    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 16

    init(_ text: LocalizedStringKey, icon: Icon? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                icon.size(iconSize)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondaryText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A small grey fact chip under a tile's main number: "3 of 4 synced".
struct InfoChip: View {
    let icon: Icon
    let text: String
    @ScaledMetric(relativeTo: .footnote) private var iconSize: CGFloat = 14

    var body: some View {
        HStack(spacing: 5) {
            icon.size(iconSize)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.surfaceMuted, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// The big full-width button at the bottom of onboarding and setup screens.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                // One line even at the largest sizes, so the bottom bar
                // leaves room for the screen above it.
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// A round Liquid Glass button holding one icon (header actions).
struct GlassIconButton: View {
    let icon: Icon
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.size(22)
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }
}

/// A calm, neutral message (never red): "code not found", "try again".
struct Notice: View {
    let text: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if let retry {
                Button("Try again", action: retry)
                    .font(.body.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.surfaceMuted, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A round coloured avatar with the person's initial (there are no photos in
/// the data model). Grows with Dynamic Type, up to 1.5× its base size.
struct Avatar: View {
    let name: String
    let hex: String
    /// A white ring, for avatars that overlap each other.
    var ringed = false
    private let base: CGFloat
    @ScaledMetric private var size: CGFloat

    init(name: String, hex: String, size: CGFloat = 44, ringed: Bool = false) {
        self.name = name
        self.hex = hex
        self.ringed = ringed
        self.base = size
        _size = ScaledMetric(wrappedValue: size, relativeTo: .title2)
    }

    var body: some View {
        let side = min(size, base * 1.5)
        Text(name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: side * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(Color(hex: hex), in: .circle)
            .overlay {
                if ringed { Circle().strokeBorder(.surface, lineWidth: 2) }
            }
            .accessibilityHidden(true)
    }
}

/// A row of overlapping avatars, at most `limit`, then "+N".
struct AvatarStack: View {
    struct Person: Identifiable {
        let id: String
        let name: String
        let hex: String
    }

    let people: [Person]
    var size: CGFloat = 30
    var limit = 5
    @ScaledMetric(relativeTo: .footnote) private var scale: CGFloat = 1

    var body: some View {
        let shown = people.prefix(limit)
        let extra = people.count - shown.count
        let side = min(size * scale, size * 1.5)
        HStack(spacing: -side * 0.3) {
            ForEach(shown) { person in
                Avatar(name: person.name, hex: person.hex, size: size, ringed: true)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: side * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondaryText)
                    .frame(width: side, height: side)
                    .background(.surfaceMuted, in: .circle)
                    .overlay(Circle().strokeBorder(.surface, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// An input (a text field, the goal stepper) on its own white tile.
    func fieldTile() -> some View {
        padding(.horizontal, Bento.smallPadding)
            .padding(.vertical, 16)
            .bentoSurface(radius: Bento.smallRadius)
    }

    /// A tappable choice tile: white, with an accent border when selected.
    func choiceTile(selected: Bool, radius: CGFloat = Bento.smallRadius) -> some View {
        bentoSurface(radius: radius)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.accent, lineWidth: 2)
                }
            }
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
    }
}

/// The full-width quiet button under a primary one ("Not now", "Done").
struct SecondaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        // Neutral text: the accent tint would fall below AA on glass.
        .tint(.primary)
    }
}

/// "Step 1 of 2" above a setup screen's title.
struct StepCount: View {
    let step: Int
    let total: Int

    var body: some View {
        Text("Step \(step) of \(total)")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.accentText)
    }
}

/// A row inside a tile: leading icon, title, optional value, chevron.
/// Several of these stack in one tile with `TileDivider`s between them.
struct TileRow: View {
    let icon: Icon
    let title: LocalizedStringKey
    var value: String?
    var showsChevron = true
    /// An action ("Share invite", "Leave"): accent title, no chevron.
    var isAction = false
    /// Delete account: system red, the standard iOS cue for removing data.
    var isDestructive = false
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 14) {
            icon.size(iconSize)
                .foregroundStyle(isDestructive ? Color.red : Color.accentText)
            if typeSize.isAccessibilitySize, let value {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(titleStyle)
                    Text(value).foregroundStyle(.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(title)
                    .foregroundStyle(titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let value {
                    Text(value).foregroundStyle(.secondaryText)
                }
            }
            if showsChevron && !isAction {
                Icon.chevronRight.size(14)
                    .foregroundStyle(.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .font(isAction ? .body.weight(.semibold) : .body)
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var titleStyle: Color { isDestructive ? .red : isAction ? .accentText : .primary }
}

/// The hairline between rows inside a tile.
struct TileDivider: View {
    var body: some View {
        Rectangle()
            .fill(Bento.edge)
            .frame(height: 1)
    }
}
