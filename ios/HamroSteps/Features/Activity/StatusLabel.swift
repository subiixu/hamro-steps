import SwiftUI

/// A member's status in one line for their row: the preset's icon and
/// label, or their own words. Shows nothing when there's no status or it
/// has expired.
struct StatusLabel: View {
    let status: MemberStatus?
    var now: Date = .now

    @ScaledMetric(relativeTo: .subheadline) private var iconSize: CGFloat = 16

    var body: some View {
        if let status, status.isActive(at: now), let text = status.displayText {
            HStack(spacing: 5) {
                (status.preset?.icon ?? .statusCustom).size(iconSize)
                Text(text)
                    .lineLimit(1)
            }
            .font(.subheadline)
            .foregroundStyle(.secondaryText)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Status: \(text)"))
        }
    }
}

#Preview {
    let later = ActivityTime.millis(.now.addingTimeInterval(3600))
    VStack(alignment: .leading, spacing: 12) {
        StatusLabel(status: MemberStatus(preset: .atWork, expiresAt: later))
        StatusLabel(status: MemberStatus(text: "Visiting Pokhara", expiresAt: later))
        StatusLabel(status: nil)
    }
    .padding()
}
