import SwiftUI

// The Ask Coach screen's title bar: a text-only title and a subtitle that names
// Buddy and reflects the coaching mode. A trailing "Weekly" pill opens the
// generated Weekly Review recap. Buddy's mascot is intentionally omitted here so
// it appears exactly once per screen — the mood-reactive avatar on each reply.
struct AskCoachHeader: View {
    var connected: Bool = false
    var onWeeklyReview: () -> Void = {}

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Ask Coach")
                    .font(Typography.title3)
                    .foregroundColor(Palette.ink)
                Text(connected ? "Buddy • AI coach" : "Buddy")
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
            }
            Spacer()
            Button(action: onWeeklyReview) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(Typography.caption)
                    Text("Weekly")
                        .font(Typography.captionStrong)
                }
                .foregroundColor(Palette.brandDeep)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Palette.brand.opacity(0.14)))
            }
            .accessibilityLabel("Open weekly review")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
