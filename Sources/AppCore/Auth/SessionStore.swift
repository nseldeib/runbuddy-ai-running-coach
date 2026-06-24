import Foundation

// MARK: - Session store (Sign in with Apple, optional)
//
// Tracks whether the user has signed in with Apple, chosen to continue as a
// guest, or hasn't decided yet. Sign in with Apple is OPTIONAL — it never gates
// HealthKit or the dashboard (per the "no account required for MVP" spec); it
// only provides a stable identity for a future cross-device/sync story.
//
// Local-only: the Apple user identifier is kept in the Keychain (via the injected
// `TokenStoring`), with no backend. The token store is injectable so the state
// logic is unit-testable without touching the real Keychain.

public enum SessionState: Equatable {
    case undecided                 // show the sign-in screen
    case guest                     // chose "continue without an account"
    case signedIn(userID: String)  // signed in with Apple
}

/// Minimal persistence seam for the Apple user identifier (Keychain in prod,
/// in-memory in tests).
public protocol TokenStoring {
    func read(_ account: String) -> String?
    func save(_ value: String, account: String)
    func delete(_ account: String)
}

public final class SessionStore: ObservableObject {
    @Published public private(set) var state: SessionState

    private let tokens: TokenStoring
    private let defaults: UserDefaults
    private static let account = "otterpace.appleUserID"
    private static let guestKey = "otterpaceGuestChosen"

    /// `seeded` / `wantsSignInPreview` let CodeYam scenarios skip the sign-in
    /// screen by default (so the existing scenarios go straight to content), while
    /// a scenario can still opt in to preview the sign-in screen.
    public init(tokens: TokenStoring = KeychainTokenStore(),
                defaults: UserDefaults = .standard,
                seeded: Bool = HealthSource.isScenarioSeeded(),
                wantsSignInPreview: Bool = UserDefaults.standard.string(forKey: "rbStartScreen") == "signin") {
        self.tokens = tokens
        self.defaults = defaults
        if let id = tokens.read(Self.account) {
            state = .signedIn(userID: id)
        } else if defaults.bool(forKey: Self.guestKey) {
            state = .guest
        } else if seeded && !wantsSignInPreview {
            state = .guest               // scenarios skip sign-in unless previewing it
        } else {
            state = .undecided
        }
    }

    /// Record a successful Sign in with Apple (the stable `user` identifier).
    public func signIn(userID: String) {
        tokens.save(userID, account: Self.account)
        state = .signedIn(userID: userID)
    }

    /// Continue without an account — remembered so we don't re-prompt.
    public func continueAsGuest() {
        defaults.set(true, forKey: Self.guestKey)
        state = .guest
    }

    /// Sign out of Apple but keep using the app as a guest (no re-prompt).
    public func signOut() {
        tokens.delete(Self.account)
        defaults.set(true, forKey: Self.guestKey)
        state = .guest
    }

    /// Delete the local account: forget the Apple identity AND the guest choice,
    /// returning to the welcome screen. This is the in-app account-deletion path
    /// App Store guideline 5.1.1(v) requires for apps offering account sign-in.
    public func deleteAccount() {
        tokens.delete(Self.account)
        defaults.set(false, forKey: Self.guestKey)
        state = .undecided
    }

    /// Return to the sign-in screen to upgrade a guest into a signed-in account.
    public func presentSignIn() {
        defaults.set(false, forKey: Self.guestKey)
        state = .undecided
    }
}
