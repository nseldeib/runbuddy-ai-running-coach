import SwiftUI

// A dismissable Today callout, in Buddy's voice, inviting the user to add a race.
// Shown only when the user has no races yet and hasn't dismissed it. Tapping opens
// Settings (where the Races card lives); the ✕ dismisses it for good.
struct RacePromptBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Got a race coming up?")
                            .font(Typography.headline)
                            .foregroundColor(.white)
                        Text("Tell Buddy and I'll tailor your training toward it.")
                            .font(Typography.caption)
                            .foregroundColor(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 24)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Got a race coming up? Tap to add a race.")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(10)
            }
            .accessibilityLabel("Dismiss race prompt")
        }
    }
}
