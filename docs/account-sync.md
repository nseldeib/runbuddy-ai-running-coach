# Account data sync (optional)

Otterpace can optionally back up a signed-in user's data to the same Supabase
backend used for Strava tokens, keyed to the stable **Sign in with Apple** user
identifier, so it survives reinstalls and follows the user across devices.

Sync is **off until the user turns it on**, and is split into two independent
opt-ins so a privacy-minded user can sync settings without ever syncing health
data:

| Stream | Toggle | Default | Table |
| --- | --- | --- | --- |
| Settings / preferences (step goal, etc.) | "Sync my settings" | off | `account_prefs` |
| Health / activity snapshot | "Sync my health & activity data" | **off** | `account_health` |

Health sync additionally requires a one-time **consent moment** before the first
upload (what's uploaded, where it's stored, that it's reversible + deletable),
and turning it off offers to delete the already-uploaded data.

## Authentication (Sign in with Apple → bearer session)

The Apple user identifier is **stable but not a secret**, so it is never accepted
from the client as proof of identity. Instead:

1. At sign-in the app sends Apple's short-lived **identity token** (a JWT) to
   `POST /api/account/session`. The server verifies it against Apple's public
   JWKS (`issuer = https://appleid.apple.com`, `audience = APPLE_BUNDLE_ID`,
   expiry) — see `api/_lib/apple.ts`.
2. On success it mints a high-entropy **bearer token**, stores only its SHA-256
   hash in `account_sessions`, and returns the raw token once. The app keeps it
   in the Keychain (`AccountSession.swift`).
3. Every `account/*` request sends `Authorization: Bearer <token>`; the server
   resolves the user from the token (`requireUser`). **The client never sends a
   `userId`** — this closes the cross-user (IDOR) hole where any caller could
   read/delete another user's data by guessing/learning their Apple id.
4. `DELETE /api/account/session` (sign-out / delete-account) revokes the token.

## Endpoints (Vercel serverless, `api/account/*`)

Supabase is reached via its PostgREST endpoint with the service-role key (no SDK
in the bundle), upserts use `Prefer: resolution=merge-duplicates`. Conflict
handling is **last-write-wins on `updated_at`**. Every endpoint below (except
`session`) requires the bearer and returns **401** without it. The user id is
derived from the token, never the body/query.

- `POST   /api/account/session { identityToken }` → `{ token }` (mint) / `DELETE` → revoke
- `GET    /api/account/sync` → `{ found, prefs, updated_at }`
- `PUT    /api/account/sync   { prefs, updatedAt }` → upsert (rejects any health
  field in `prefs` as defense in depth; remote wins if newer; 413 if oversized)
- `GET    /api/account/health` → `{ found, health, updated_at }`
- `PUT    /api/account/health { health, updatedAt }` → upsert (remote wins if newer; 413 if oversized)
- `DELETE /api/account/health` → delete the row (opt-out / delete data)

## Environment

Reuses the Strava/Supabase env, plus one new variable for token verification:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `APPLE_BUNDLE_ID` — the app's bundle id, matched against the identity token's
  `aud` claim. Defaults to `com.otterpace.app`.

## Supabase tables (create once)

```sql
create table account_prefs (
  user_id    text primary key,
  prefs      jsonb not null,
  updated_at timestamptz default now()
);

create table account_health (        -- only ever written when the user opts in
  user_id    text primary key,
  health     jsonb not null,
  updated_at timestamptz default now()
);

create table account_sessions (      -- bearer tokens; only the hash is stored
  token_hash text primary key,
  user_id    text not null,
  created_at timestamptz default now()
);
```

The tables are kept separate so revoking/deleting health sync never touches
preferences, and a settings-only user never has a row in `account_health` at all.

## iOS side

- `Sources/AppCore/Account/AccountSyncService.swift` — gates every push on
  sign-in + the relevant opt-in; health upload has a single hard-gated chokepoint.
  The HTTP seam (`AccountSyncTransport`) is injectable and attaches the bearer;
  merge logic (`SyncMerge`) is pure and unit-tested in `AccountSyncTests.swift`.
- `Sources/AppCore/Account/AccountSession.swift` — exchanges the Apple identity
  token for a bearer at sign-in and stores it in the Keychain; revokes it on
  sign-out / delete-account. Storage seam unit-tested in `AccountSessionTests.swift`.
- `Sources/AppCore/Account/SyncConsent.swift` — the two opt-in flags + the
  health-consent acknowledgement (health can't be enabled without it).
- `Sources/AppCore/SettingsView.swift` — the two toggles, consent sheet, and the
  delete-or-keep choice on health opt-out (signed-in only).

Guests, and signed-in users with the toggles off, sync nothing.
