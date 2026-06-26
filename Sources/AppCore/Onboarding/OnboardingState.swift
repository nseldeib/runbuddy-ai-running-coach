import Foundation

// MARK: - Onboarding persistence + launch gating
//
// Remembers whether the first-run welcome tour has been seen and decides whether
// to show it at launch. Mirrors the `UserPreferences` pattern: UserDefaults-backed
// with an injectable `defaults` so the launch decision is pure and unit-testable —
// not bolted onto `SessionStore` (this is unrelated to the Apple-credential
// lifecycle).
public enum OnboardingState {
    static let seenKey = "otterpaceOnboardingSeen"

    /// Number of pages in the welcome tour — the single source of truth shared
    /// with the view and with `startPage` clamping.
    public static let pageCount = 3

    public static func hasSeen(_ d: UserDefaults = .standard) -> Bool {
        d.bool(forKey: seenKey)
    }

    public static func markSeen(_ d: UserDefaults = .standard) {
        d.set(true, forKey: seenKey)
    }

    /// Whether to show the welcome tour at launch. Pure + deterministic:
    ///   • `startScreen == "onboarding"` → always show (preview/replay opt-in,
    ///     regardless of `hasSeen`).
    ///   • already seen → don't show.
    ///   • scenario-seeded run → don't show (scenarios skip by default, matching
    ///     `SignInView`'s `seeded && !wantsSignInPreview`).
    ///   • otherwise (production first launch) → show.
    public static func shouldShow(defaults d: UserDefaults = .standard,
                                  seeded: Bool = HealthSource.isScenarioSeeded(),
                                  startScreen: String = "") -> Bool {
        if startScreen == "onboarding" { return true }
        if hasSeen(d) { return false }
        if seeded { return false }
        return true
    }

    /// Scenario hook: which page to start on (`rbOnboardingPage`), clamped to the
    /// valid range so a capture can target a specific page. Defaults to 0.
    public static func startPage(_ d: UserDefaults = .standard) -> Int {
        let raw = d.integer(forKey: "rbOnboardingPage")
        return min(max(0, raw), pageCount - 1)
    }
}
