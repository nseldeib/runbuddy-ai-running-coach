import XCTest
@testable import AppCore

// Pure-logic tests for the first-run welcome tour's launch gating, against an
// injected UserDefaults suite (mirroring SessionStoreTests / ModelTests).
final class OnboardingStateTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "OnboardingStateTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // First launch (nothing seen, not seeded) shows the tour.
    func testFirstLaunchShows() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        XCTAssertTrue(OnboardingState.shouldShow(defaults: d, seeded: false, startScreen: ""))
    }

    // After markSeen(), it never auto-shows again.
    func testSeenHidesTour() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        OnboardingState.markSeen(d)
        XCTAssertTrue(OnboardingState.hasSeen(d))
        XCTAssertFalse(OnboardingState.shouldShow(defaults: d, seeded: false, startScreen: ""))
    }

    // A scenario-seeded run skips the tour by default (no opt-in).
    func testSeededScenarioSkips() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        XCTAssertFalse(OnboardingState.shouldShow(defaults: d, seeded: true, startScreen: ""))
    }

    // startScreen == "onboarding" forces the tour even when already seen (preview/replay).
    func testStartScreenForcesShow() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        OnboardingState.markSeen(d)
        XCTAssertTrue(OnboardingState.shouldShow(defaults: d, seeded: true, startScreen: "onboarding"))
    }

    // startPage reads + clamps rbOnboardingPage into the valid range.
    func testStartPageClamps() {
        let (d, name) = freshDefaults(); defer { d.removePersistentDomain(forName: name) }
        XCTAssertEqual(OnboardingState.startPage(d), 0)               // unset -> 0
        d.set(1, forKey: "rbOnboardingPage")
        XCTAssertEqual(OnboardingState.startPage(d), 1)
        d.set(-3, forKey: "rbOnboardingPage")
        XCTAssertEqual(OnboardingState.startPage(d), 0)               // negative -> 0
        d.set(99, forKey: "rbOnboardingPage")
        XCTAssertEqual(OnboardingState.startPage(d), OnboardingState.pageCount - 1) // beyond last -> last
    }
}
