import SwiftUI

/// Small pieces the activity components share.
enum ActivityStyle {
    /// A backend avatar colour ("#E4572E") as a `Color`; the accent colour
    /// when the string isn't a 6-digit hex.
    static func avatarColor(_ hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .accent }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension StatusPreset {
    var icon: Icon {
        switch self {
        case .atWork: .statusWork
        case .atHome: .statusHome
        case .commuting: .statusCommuting
        case .workingOut: .statusWorkout
        case .onAHike: .statusHike
        case .resting: .statusResting
        case .travelling: .statusTravelling
        }
    }
}

/// A member's initial on their avatar colour. Family-wide feed events use
/// a family icon instead.
struct ActivityAvatar: View {
    enum Content {
        case member(FeedActor)
        case family
    }

    let content: Content
    var size: CGFloat = 40

    var body: some View {
        switch content {
        case .member(let actor):
            Text(actor.name.prefix(1).uppercased())
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(ActivityStyle.avatarColor(actor.avatarColor), in: .circle)
                .accessibilityHidden(true)
        case .family:
            Icon.family.size(size * 0.5)
                .foregroundStyle(.goal)
                .frame(width: size, height: size)
                .background(Color.goal.opacity(0.16), in: .circle)
        }
    }
}

/// The small badge on a feed event's avatar saying what kind of moment it
/// is: a walk (accent), a member's steps (goal) or the family goal (goal tint).
struct FeedTypeBadge: View {
    let type: FeedEventType
    @ScaledMetric(relativeTo: .footnote) private var side: CGFloat = 18

    var body: some View {
        let size = min(side, 26)
        if let style {
            style.icon.size(size * 0.6)
                .foregroundStyle(style.foreground)
                .frame(width: size, height: size)
                .background(style.fill, in: .circle)
                .background(.surface, in: .circle)
                .overlay(Circle().strokeBorder(.surface, lineWidth: 2))
                .accessibilityHidden(true)
        }
    }

    private var style: (icon: Icon, fill: Color, foreground: Color)? {
        switch type {
        case .walkStarted: (.walking, .accent, .white)
        case .member5k, .member10k: (.home, .goal, .white)
        case .family50, .family100: (.goal, Color.goal.opacity(0.18), .goalText)
        case .unknown: nil
        }
    }
}

/// Lays children out in rows and wraps when a row is full, so the reaction
/// chips and expiry choices still fit at the largest text sizes.
struct ActivityWrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = fittedSize(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// A child's natural size, or, when that is wider than the whole row (one
    /// chip at the largest text sizes on a narrow phone), its size at the row's
    /// width, so its text wraps instead of running out of the tile.
    private func fittedSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        let fitted = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: min(fitted.width, width), height: fitted.height)
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = fittedSize(subviews[index], width: width)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The compact orb with a visible caption; the caption is what VoiceOver
/// reads (OrbLoader's own messages are about steps and Health).
struct ActivityLoadingRow: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            OrbLoader(compact: true)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
