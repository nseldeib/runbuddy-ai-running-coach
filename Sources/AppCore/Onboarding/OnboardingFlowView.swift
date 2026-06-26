import SwiftUI

// MARK: - First-run welcome tour
//
// A brief, swipeable three-page carousel shown once on first launch (and
// replayable from Settings) before the Sign-in screen. Reuses the app's mascot
// (`PuffyBuddy`), theme (`Palette`/`Typography`), and the gradient capsule button
// from `ConnectHero`, so it feels native on day one. Presented by `ContentView`
// as a top-of-`ZStack` overlay, the same way Settings/Sign-in are gated.
struct OnboardingFlowView: View {
    var onFinish: () -> Void
    @State private var page: Int

    init(onFinish: @escaping () -> Void = {}, startPage: Int = 0) {
        self.onFinish = onFinish
        _page = State(initialValue: min(max(0, startPage), OnboardingFlowView.pages.count - 1))
    }

    private struct Page: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let mood: BuddyMood
    }

    // One source of truth for the page count (kept in sync with OnboardingState.pageCount).
    private static let pages: [Page] = [
        Page(title: "Meet Buddy",
             body: "Hi, I'm Buddy! 🐾 Your friendly movement coach, here to cheer you on every day.",
             mood: .ready),
        Page(title: "Day-by-day coaching",
             body: "I turn your steps and runs into gentle, day-by-day guidance, toward 10,000 steps a day, without overdoing it.",
             mood: .jogging),
        Page(title: "Ask me anything",
             body: "Tap the Coach tab to ask about your training, and get a friendly weekly review of how you're trending.",
             mood: .cheering),
    ]

    private var isLastPage: Bool { page >= Self.pages.count - 1 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Palette.bgTop, Palette.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                pager
                if isLastPage {
                    Button(action: onFinish) {
                        Text("Get started")
                            .font(Typography.headline)
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
                    .padding(.bottom, 28)
                    .accessibilityLabel("Get started")
                }
            }

            if !isLastPage {
                Button("Skip", action: onFinish)
                    .font(Typography.caption)
                    .foregroundColor(Palette.subtle)
                    .padding(18)
                    .accessibilityLabel("Skip the welcome tour")
            }
        }
    }

    // Paged carousel. PageTabViewStyle / index dots are iOS-only, so guard them;
    // the macOS test build still compiles with a plain TabView.
    private var pager: some View {
        let tabs = TabView(selection: $page) {
            ForEach(Array(Self.pages.enumerated()), id: \.offset) { idx, p in
                pageView(p).tag(idx)
            }
        }
        #if os(iOS)
        return tabs
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        return tabs
        #endif
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 22) {
            Spacer()
            PuffyBuddy(mood: p.mood, size: 140).accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(p.title)
                    .font(Typography.title)
                    .foregroundColor(Palette.ink)
                Text(p.body)
                    .font(Typography.callout)
                    .foregroundColor(Palette.subtle)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .padding(.horizontal, 28)
            }
            Spacer()
            Spacer()
        }
    }
}
