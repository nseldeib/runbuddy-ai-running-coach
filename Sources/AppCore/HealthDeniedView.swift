import SwiftUI

// Shown when the user has declined Health access: a calm, non-shaming explainer
// with a button to open Settings. Buddy stays friendly — denial is fine, the app
// just can't show live activity until access is granted.
struct HealthDeniedView: View {
    var onOpenSettings: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topTrailing) {
            deniedContent
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Palette.subtle)
                    .padding(18)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var deniedContent: some View {
        VStack(spacing: 22) {
            Spacer()
            PuffyBuddy(mood: .resting, size: 120).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Health access is off")
                    .font(Typography.title)
                    .foregroundColor(Palette.ink)
                Text("Otterpace reads your steps from Apple Health, all on your device. Turn on Health access in Settings and Buddy will start coaching from your real activity.")
                    .font(Typography.callout)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }
            Button(action: onOpenSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gear")
                    Text("Open Settings")
                        .font(Typography.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [Palette.brand, Palette.brandDeep],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 24)
            .accessibilityLabel("Open Settings to enable Health access")
            Text("Your health data never leaves your device.")
                .font(Typography.caption)
                .foregroundColor(Palette.subtle)
            Spacer()
        }
    }
}
