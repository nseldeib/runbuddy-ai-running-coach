# Otterpace — TestFlight & DNS walkthrough

The detailed Xcode / App Store Connect / DNS companion to the master sequence in
**[go-live-runbook.md](go-live-runbook.md)** (start there for the full order).
Everything here happens in Xcode, App Store Connect, Namecheap, and Vercel — it
can't be done from the codeyam CLI.

## Status at a glance

**Done in-repo ✅**
- Rebranded to **Otterpace** (mascot stays **Buddy**); bundle id `com.otterpace.app`.
- All features built: HealthKit, Sign in with Apple (+ account deletion),
  AI coach (BYO key), Strava import, movement reminders, analytics.
- App icon (1024² opaque, asset catalog wired) + branded launch screen.
- Version `1.0` / build `1`; `ITSAppUsesNonExemptEncryption = NO` set (skips the
  export-compliance prompt — Otterpace uses only standard HTTPS/TLS).
- `swift test` green (83/83); backend type-checks clean.

**Yours, outside the repo (this doc):** Apple Developer App ID + capabilities,
the App Store Connect app record, DNS, archive/upload, privacy label.

---

## A. DNS — point otterpace.com at Vercel (Namecheap)

Do this **after** the site is deployed on Vercel (runbook Phase 1). Add the domain
in Vercel first so it tells you the exact records, then enter them in Namecheap.

1. **Vercel** → `otterpace` project → **Settings → Domains** → add `otterpace.com`.
   Vercel shows the records to create — typically:
   - **A** `@ → 76.76.21.21`
   - **CNAME** `www → cname.vercel-dns.com`

   Use whatever Vercel displays; that page is authoritative.
2. **Namecheap** → **Domain List → Manage** otterpace.com → **Advanced DNS**:
   - **Delete the defaults** Namecheap auto-creates: `CNAME @ → parkingpage.namecheap.com`
     and any `URL Redirect Record` (they'll fight the new records).
   - **Add New Record** ×2:

     | Type         | Host | Value                  | TTL       |
     |--------------|------|------------------------|-----------|
     | A Record     | `@`  | `76.76.21.21`          | Automatic |
     | CNAME Record | `www`| `cname.vercel-dns.com` | Automatic |

   - Enter the CNAME value without a trailing dot (Namecheap adds it). **Save** each row.
3. **Vercel** re-checks automatically (minutes, up to ~24–48 h worst case). When it
   reads **Valid Configuration**, set `otterpace.com` as primary (so `www`
   redirects to it). **HTTPS is issued automatically** — no cert work.
4. **Verify:**
   ```
   dig otterpace.com +short        # → 76.76.21.21
   dig www.otterpace.com +short    # → cname.vercel-dns.com / Vercel IPs
   ```
   Then `https://otterpace.com`, `/privacy`, and `…/api/coach` (405 to GET) all
   respond, and Strava's callback domain (`otterpace.com`) resolves.

> Web DNS only. Adding `hello@otterpace.com` later is separate **MX** records and
> won't conflict with the above.

---

## B. Add the build as a new TestFlight app

### 1. Register the App ID (once)
[developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles →
**Identifiers → +** → App IDs → App → Bundle ID `com.otterpace.app` (explicit) →
enable **HealthKit** and **Sign In with Apple** → Register. *(Xcode automatic
signing can also create this on first archive; doing it explicitly avoids
surprises.)*

### 2. Create the app record
[App Store Connect](https://appstoreconnect.apple.com) → **Apps → + → New App**:
- Platform **iOS**, Name **Otterpace** (must be unique on the App Store — keep a
  fallback like "Otterpace Run" ready), Primary Language, Bundle ID
  `com.otterpace.app`, SKU `otterpace-ios`, Full access. → Create.

### 3. Prep the build in Xcode (`App.xcodeproj`)
- **Signing & Capabilities**: enable **Automatically manage signing**, pick your
  **Team**, confirm bundle id `com.otterpace.app`.
- **+ Capability → HealthKit** and **+ Capability → Sign in with Apple**. Ensure
  `App/App.entitlements` is the target's *Code Signing Entitlements* (it carries
  both entitlements). `NSHealthShareUsageDescription` is already in Info.plist.
- Set the **app config values** in `App/Info.plist` for live integrations:
  `StravaClientID`, `PostHogProjectKey` (runbook Phases 3–4). The `otterpace://`
  URL scheme and `ITSAppUsesNonExemptEncryption = NO` are already there.
- Version `1.0` / Build `1` (bump **Build** for every later upload).

### 4. Archive & upload
- Destination **Any iOS Device (arm64)** — Archive is disabled for simulators.
- **Product → Archive** → Organizer → **Distribute App → App Store Connect →
  Upload** (keep defaults: automatic signing, upload symbols).

### 5. After upload
- The build appears in App Store Connect → **TestFlight** as "Processing"
  (5–30 min; you get an email).
- Fill **Test Information** (beta description + feedback email). Export compliance
  is auto-answered by the `ITSAppUsesNonExemptEncryption` key.
- **Internal testing** (≤100 App Store Connect team users): add them to an internal
  group → they install via the **TestFlight** app and redeem — **no Beta App
  Review**, available immediately.
- **External testing** (public/email testers): needs a one-time **Beta App Review**
  + the **App Privacy** label completed first (runbook Phase 7;
  see `app-store-listing.md`).

### 6. Smoke-test the TestFlight build
On a real device, run the runbook **Phase 6** checklist end-to-end: HealthKit,
Sign in with Apple, AI coach, Strava, reminders, analytics.

---

## C. App name vetting (for the record)
"Otterpace" was chosen over otter-themed candidates: App Store (fitness) had no
"Otterpace", no conflicting trademark in fitness (Otter.ai / OtterBox are
unrelated categories), and `otterpace.com` was available (secured on Namecheap).
Rejected: OtterRun (event + parked domain collision), Lutra (existing trademark),
PaceOtter (crowded "Pace___" field), OtterBuddyRun (long/redundant).
