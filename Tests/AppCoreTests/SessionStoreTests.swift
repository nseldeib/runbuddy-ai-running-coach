import XCTest
@testable import AppCore

// XCTest (not swift-testing) so results land in the editor's --xunit-output file.
final class SessionStoreTests: XCTestCase {

    private final class MemoryTokens: TokenStoring {
        var store: [String: String] = [:]
        func read(_ account: String) -> String? { store[account] }
        func save(_ value: String, account: String) { store[account] = value }
        func delete(_ account: String) { store[account] = nil }
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "SessionStoreTests.\(UUID().uuidString)")!
    }

    // Production with no saved identity and no guest choice → show the sign-in screen.
    func testFreshProductionIsUndecided() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .undecided)
    }

    // A normal seeded scenario skips sign-in (so existing previews go to content).
    func testSeededScenarioSkipsToGuest() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: true, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .guest)
    }

    // A scenario can opt in to preview the sign-in screen.
    func testSignInPreviewSeedShowsSignIn() {
        let s = SessionStore(tokens: MemoryTokens(), defaults: defaults(), seeded: true, wantsSignInPreview: true)
        XCTAssertEqual(s.state, .undecided)
    }

    // A previously-saved Apple identifier resumes the signed-in state.
    func testExistingTokenResumesSignedIn() {
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "001234.abcDEF"
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(s.state, .signedIn(userID: "001234.abcDEF"))
    }

    // Signing in persists the identifier and moves to signed-in.
    func testSignInPersists() {
        let t = MemoryTokens()
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        s.signIn(userID: "apple-user-1")
        XCTAssertEqual(s.state, .signedIn(userID: "apple-user-1"))
        XCTAssertEqual(t.store["otterpace.appleUserID"], "apple-user-1")
    }

    // Continuing as guest is remembered so we don't re-prompt next launch.
    func testContinueAsGuestRemembered() {
        let d = defaults()
        let s = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        s.continueAsGuest()
        XCTAssertEqual(s.state, .guest)
        let next = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(next.state, .guest)
    }

    // Signing out forgets the Apple identity but keeps the app usable as a guest.
    func testSignOutBecomesGuest() {
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "x"
        let s = SessionStore(tokens: t, defaults: defaults(), seeded: false, wantsSignInPreview: false)
        s.signOut()
        XCTAssertEqual(s.state, .guest)
        XCTAssertNil(t.store["otterpace.appleUserID"])
    }

    // Deleting the account forgets the identity AND the guest choice, returning
    // to the welcome screen (the App Store account-deletion path).
    func testDeleteAccountResets() {
        let d = defaults()
        let t = MemoryTokens(); t.store["otterpace.appleUserID"] = "x"
        let s = SessionStore(tokens: t, defaults: d, seeded: false, wantsSignInPreview: false)
        s.deleteAccount()
        XCTAssertEqual(s.state, .undecided)
        XCTAssertNil(t.store["otterpace.appleUserID"])
        // A fresh launch with no token and no guest choice stays at the welcome screen.
        let next = SessionStore(tokens: MemoryTokens(), defaults: d, seeded: false, wantsSignInPreview: false)
        XCTAssertEqual(next.state, .undecided)
    }
}
