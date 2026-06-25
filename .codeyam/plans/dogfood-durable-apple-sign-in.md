---
title: "dogfood: Durable Sign in with Apple Session"
mode: ui
createdAt: "2026-06-25T16:01:47Z"
prefix: "dogfood"
source: manual
---

## Summary

Dogfooding showed the user getting returned to the welcome/sign-in screen too
often after signing in with Apple. There is **no intentional session expiry** in
the code: `SessionStore` restores `signedIn` whenever the Apple user identifier
is present in the Keychain (`KeychainTokenStore`, stored
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), which should persist
indefinitely. So the premature "logout" is an unintended drop, not a TTL. This
plan (1) makes the signed-in state genuinely durable by validating the stored
Apple credential the way Apple intends — `getCredentialState(forUserID:)` on
launch/foreground and listening for the revocation notification — and (2) makes
the session end *only* on real revocation, landing the user in guest mode rather
than back at the welcome screen so the app never nags. The result is a long-lived
(not infinite) session that survives relaunches and only ends when the user
actually revokes Apple access.

## Key Decisions

- **Validate, don't blindly trust or blindly drop** — adopt Apple's recommended
  lifecycle: on launch/foreground, call
  `ASAuthorizationAppleIDProvider().getCredentialState(forUserID:)` for the
  stored ID. `.authorized` → stay signed in; `.revoked`/`.notFound` → end the
  session. Also subscribe to
  `ASAuthorizationAppleIDProvider.credentialRevokedNotification` to react to
  real revocation immediately.
- **Throttle revalidation for longevity, not churn** — record a
  `lastValidatedAt` timestamp and only re-check the credential state every N
  hours (e.g. 24h), and treat transient/offline check failures as "stay signed
  in." This is what makes the session feel long-lived instead of re-prompting.
- **Revocation lands in guest, not undecided** — when the credential is genuinely
  revoked, transition to `.guest` (keep using the app, no welcome-screen nag)
  rather than `.undecided`. `deleteAccount()` remains the explicit path back to
  the welcome screen.
- **Keep it unit-testable via a seam** — mirror the existing injectable
  `TokenStoring` pattern: introduce an `AppleCredentialChecking` protocol so the
  state-machine logic can be tested with a fake credential state (the real
  `ASAuthorizationAppleIDProvider` is never hit in the XCTest suite).

## Implementation

### 1. Credential-state revalidation seam

**New file**: `Sources/AppCore/Auth/AppleCredentialChecker.swift`

A small `AppleCredentialChecking` protocol (`func state(forUserID:) async -> …`)
with a production implementation wrapping
`ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)`, and an
in-memory fake for tests. Map Apple's states to a simple
`authorized | revoked | notFound | unknown` enum.

### 2. Durable session lifecycle in `SessionStore`

**File**: `Sources/AppCore/Auth/SessionStore.swift`

- Inject `AppleCredentialChecking` (default = real impl), alongside the existing
  `TokenStoring`/`UserDefaults` seams.
- Add `func revalidate() async`: if `signedIn`, and `lastValidatedAt` is older
  than the revalidation window, check credential state — `authorized` → refresh
  `lastValidatedAt` and stay; `revoked`/`notFound` → call a new graceful
  `endSession()` that drops to `.guest` (clears the Keychain ID, sets the guest
  flag); `unknown`/offline → keep the session and leave `lastValidatedAt`.
- Persist `lastValidatedAt` in `UserDefaults`. Set it on `signIn(userID:)`.
- Subscribe to `credentialRevokedNotification` and call `revalidate()` on fire.
- Audit existing transitions (`signOut`, `deleteAccount`, the init branch order)
  to confirm nothing drops a signed-in user spuriously; document the intended
  longevity in the file's header comment.

### 3. Trigger revalidation at the right moments

**File**: `Sources/AppCore/ContentView.swift`

The `@StateObject private var session` already owns the session. Call
`session.revalidate()` on app launch and on
`scenePhase` → `.active` (foreground). Guard it so scenario-seeded previews
(`HealthSource.isScenarioSeeded()`) don't perform network credential checks.

### 4. Tests

**File**: `Tests/AppCoreTests/SessionStoreTests.swift` (extend or add)

XCTest cases with the fake `AppleCredentialChecking` + in-memory `TokenStoring`:
signed-in + `authorized` → stays signed in across relaunch; within the window →
no re-check; `revoked` → drops to `.guest` (not `.undecided`); `unknown`/offline
→ stays signed in. Each `func testX()` prefaced with a `//` description comment;
register via `codeyam-editor editor reconcile-registry --auto-apply`.

## Reused existing code

- `SessionStore` + `SessionState` from `Sources/AppCore/Auth/SessionStore.swift`
  — the state machine extended here.
- `KeychainTokenStore` / the `TokenStoring` protocol from
  `Sources/AppCore/Auth/KeychainTokenStore.swift` — the durable identifier store
  and the injectable-seam pattern this plan mirrors for credential checking.
- `SignInView` (`Auth/SignInView.swift`) — `signIn(userID:)` entry point that
  now also stamps `lastValidatedAt`.
- `ContentView`'s `@StateObject session` + `scenePhase` — where revalidation is
  triggered.
- `HealthSource.isScenarioSeeded()` — to keep previews offline/deterministic.

## Scenarios to Demonstrate

- **Persists across relaunch**: signed-in scenario re-opened → still on the
  dashboard, no welcome screen.
- **Graceful revocation**: credential reported `revoked` → app continues in guest
  mode (not bounced to the welcome screen).
- **Offline relaunch**: credential check fails/unknown → session retained.
- **Sign-in screen preview**: `rbStartScreen = "signin"` still shows the welcome
  screen for first-run/undecided.
