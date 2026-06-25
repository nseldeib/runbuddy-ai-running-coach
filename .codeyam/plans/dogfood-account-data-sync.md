---
title: "dogfood: Persist Data to a User Account"
mode: ui
createdAt: "2026-06-25T16:01:48Z"
prefix: "dogfood"
source: manual
dependsOn: ["dogfood-durable-apple-sign-in"]
---

## Summary

Today all user data lives only on-device: the step goal and preferences in
`UserDefaults` (`Preferences.swift`), the Apple sign-in identity in the Keychain,
and HealthKit data that currently never leaves the device. `SessionStore`'s own
comment notes the Apple identifier exists for "a future cross-device/sync story"
that isn't built yet. This plan adds an **optional** account-backed persistence
layer: when the user is signed in with Apple, their data can sync to the existing
Supabase backend, keyed to their account, so it carries across reinstalls and
devices. Sync is layered as **two independent opt-ins** — settings/preferences,
and (separately, off by default) health/activity data — so the user, not the
app, decides whether health data ever leaves the device. It reuses the exact
Supabase-via-PostgREST pattern already used for Strava tokens.

## Key Decisions

- **Health-data sync is a user choice, off by default** — on-device-only stays
  the default, but the user can explicitly opt in to syncing their health/activity
  data to their account (and opt back out). Settings/preferences sync is a
  separate, lighter opt-in. Two independent toggles rather than one all-or-nothing
  switch, so a privacy-minded user can sync settings without health data.
- **Explicit, informed consent for health sync** — because health data is
  sensitive, opting in requires a clear consent moment that states what's
  uploaded, where it's stored, and that they can turn it off and delete it. This
  is the main UI/UX implication (see "UI/UX implications" below) and an App Store
  / privacy expectation.
- **Gate all sync behind Sign in with Apple** — sync is only available to
  `signedIn` users, keyed to the stable Apple `userID`. Guests stay fully local.
  This is why the plan **depends on `dogfood-durable-apple-sign-in`**: durable
  identity is the prerequisite for meaningful sync.
- **Reuse the Strava backend pattern, not a new stack** — add Supabase tables +
  `api/account/*` serverless functions that mirror `api/_lib/strava.ts`
  (PostgREST endpoint, service-role key, `merge-duplicates` upsert). No new SDKs
  or infra.
- **Separate the two payloads server-side** — settings/preferences and
  health/activity data go in distinct tables/rows so revoking health sync (and
  deleting the uploaded health data) never touches preferences, and so a
  settings-only user never has a health row at all.
- **Last-write-wins merge on `updated_at`** — simple, predictable conflict
  handling for single-user blobs; avoids premature CRDT complexity.

## UI/UX implications (because health sync is now opt-in)

- **Settings**: two distinct toggles — "Sync my settings" and "Sync my health &
  activity data" — each with its own last-synced status; the health toggle reads
  as off/private by default.
- **Consent sheet**: enabling health sync presents a one-time explainer (what's
  uploaded, that it's tied to the Apple account, how to turn it off / delete it)
  before the first upload.
- **Turn-off = delete option**: turning health sync off offers to delete the
  already-uploaded health data from the backend, with clear confirmation.
- **Marketing/privacy copy changes**: the site's current absolute promise
  ("your Apple Health data stays on your device") must become conditional — "by
  default; only synced if you turn it on." This touches `site/index.html` and
  `site/privacy.html` and should be called out so the claim stays truthful.
- **Status visibility**: a small indicator (last synced / syncing / off) so the
  user always knows the current state of each sync.

## Implementation

### 1. Backend: account stores (prefs + optional health)

**File**: `api/_lib/account.ts` (new) — Supabase helpers mirroring
`api/_lib/strava.ts`: `getPrefs`/`upsertPrefs` and `getHealth`/`upsertHealth`/
`deleteHealth`, against two tables keyed by the Apple user identifier:

```
create table account_prefs (
  user_id    text primary key,
  prefs      jsonb not null,
  updated_at timestamptz default now()
);
create table account_health (        -- only written when the user opts in
  user_id    text primary key,
  health     jsonb not null,         -- derived activity/health snapshot
  updated_at timestamptz default now()
);
```

**New files**: `api/account/sync.ts` (prefs `GET`/`PUT`, last-write-wins) and
`api/account/health.ts` (`GET`/`PUT`/`DELETE`, last-write-wins; `DELETE` removes
the row on opt-out). Validate input; the prefs endpoint must reject health fields
(defense in depth) so prefs-only users never leak health data into the wrong row.

**File**: doc under `docs/` — document the new tables + env reuse
(`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).

### 2. iOS: account sync service

**New file**: `Sources/AppCore/Account/AccountSyncService.swift`

An `async` service that, for a `signedIn` user, syncs whichever streams are
enabled: a `SyncablePreferences` payload always-available behind the settings
toggle, and a `SyncableHealthSnapshot` payload only when the health toggle is on.
Each stream pulls on sign-in/launch and pushes on change; merge by `updatedAt`
(last-write-wins). Network failures are non-fatal — local values remain the
source of truth offline. Make the HTTP seam injectable so merge logic is
unit-testable without a live backend. Health upload is strictly gated on the
opt-in flag at the call site (not just the UI).

### 3. Consent + opt-in/out flags

**New file**: `Sources/AppCore/Account/SyncConsent.swift` (or extend
`Preferences.swift`)

Persist two independent flags (settings-sync enabled, health-sync enabled),
defaulting health to off. Enabling health sync requires passing through the
consent step before the first push; disabling triggers the optional
delete-remote-health flow.

### 4. Wire into preferences + session

**File**: `Sources/AppCore/Preferences.swift`, `Sources/AppCore/Auth/SessionStore.swift`

- Route `Preferences` writes (esp. `setGoalSteps`) through a path that schedules a
  prefs push when settings sync is on.
- On `signIn`/successful revalidation, pull enabled streams and reconcile with
  local. On `deleteAccount`, delete both remote rows and revert to local-only.

### 5. Settings: two toggles, consent, status

**File**: `Sources/AppCore/SettingsView.swift`

In the Account card (only when `signedIn`): a "Sync my settings" toggle and a
separate "Sync my health & activity data" toggle (off by default) that presents
the consent sheet on enable and the delete-on-disable confirmation on turn-off,
each with a last-synced status line. Reuse the existing `row`/`actionRow`/`card`
helpers; guests see a "sign in to sync" affordance instead.

### 6. Privacy + marketing disclosure

**File**: `site/privacy.html`, `site/index.html`

Update the "Accounts & Sign in with Apple" privacy section and the homepage's
on-device claim so they're conditional: settings and (only if the user opts in)
health/activity data sync to the backend keyed to the Apple identifier; health
sync is off by default and deletable. Keep the analytics statement (health is
never sent to analytics) unchanged.

### 7. Tests

**File**: `Tests/AppCoreTests/AccountSyncTests.swift` (new)

XCTest coverage of: prefs merge (remote-newer / local-newer / no-remote);
`SyncablePreferences` and `SyncableHealthSnapshot` round-trips; the guard that
guests never sync; and crucially that **health never uploads while the health
opt-in is off** and that opt-out deletes the remote health row. Use the injectable
HTTP seam; register via `codeyam-editor editor reconcile-registry --auto-apply`.

## Reused existing code

- `api/_lib/strava.ts` — the Supabase PostgREST + service-role + upsert pattern
  that `api/_lib/account.ts` mirrors (incl. `supabaseHeaders`, merge-duplicates).
- `SessionStore` / `SessionState.signedIn(userID:)` from
  `Sources/AppCore/Auth/SessionStore.swift` — sync identity (depends on
  `dogfood-durable-apple-sign-in` for durable identity).
- `Preferences` from `Sources/AppCore/Preferences.swift` — the local prefs this
  layer mirrors; home for the opt-in flags.
- `StravaDeviceKey` pattern in `Sources/AppCore/Strava/StravaService.swift` — the
  existing anonymous-key + injectable `TokenStoring` precedent for backend keys.
- `SettingsView` `card`/`row`/`actionRow` helpers — for the sync toggles + consent.

## Scenarios to Demonstrate

- **Settings sync on, health off (default)**: change the step goal, "reinstall" →
  goal restored from the account; no health data uploaded.
- **Health sync opt-in flow**: enabling the health toggle shows the consent sheet,
  then health snapshot syncs; status shows "synced".
- **Health sync opt-out + delete**: turning health sync off offers to delete the
  remote health data and confirms it's gone.
- **Guest stays local**: guest changes settings → nothing syncs; no account UI.
- **Conflict resolution**: remote newer than local → remote wins on pull (and
  vice versa).
- **Offline**: backend unreachable → local data still works, sync retries later.
- **Account deletion**: `deleteAccount` clears both remote rows and reverts to
  local-only.
