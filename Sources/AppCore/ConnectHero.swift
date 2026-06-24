import SwiftUI

// The day-one empty state shown before Apple Health is connected: Buddy waving,
// a warm explainer, the connect call-to-action, and a privacy reassurance.
struct ConnectHero: View {
    let onConnect: () -> Void
    var onSettings: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topTrailing) {
            heroContent
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Palette.subtle)
                    .padding(18)
            }
            .accessibilityLabel("Settings")
        }
    }

    private var heroContent: some View {
        VStack(spacing: 24) {
            Spacer()
            PuffyBuddy(mood: .ready, size: 140)
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Hi, I'm Buddy! 🐾")
                    .font(Typography.title)
                    .foregroundColor(Palette.ink)
                Text("Connect Apple Health and I'll turn your steps and runs into friendly, day-by-day coaching — toward 10,000 steps a day, without overdoing it.")
                    .font(Typography.callout)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(.horizontal, 28)
            }
            Button(action: onConnect) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Connect Apple Health")
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
            Text("Your health data stays on your device.")
                .font(Typography.caption)
                .foregroundColor(Palette.subtle)
            Spacer()
        }
    }
}
