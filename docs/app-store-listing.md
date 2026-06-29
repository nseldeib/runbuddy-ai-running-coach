# Otterpace App Store listing copy (draft)

Drop-in metadata for App Store Connect. Char limits noted; the copy is written to
stay truthful to the (updated) privacy posture: health data stays on-device, but
analytics is on, so nothing here claims "no tracking."

---

## Name & subtitle
- **App Name** (≤30): `Otterpace`
  - Alt if you want the descriptor in the name: `Otterpace: Running Coach` (24).
  - ⚠️ The name must be unique on the App Store; check availability when you
    create the app record.
- **Subtitle** (≤30): `Your friendly running coach` (27)
  - Alt: `Your daily running coach` (24)

## Promotional text (≤170, editable anytime without review)
```
Meet Buddy, your friendly running coach. Daily nudges toward your step goal, smart run/rest tips, and a kind weekly review.
```

## Keywords (≤100 chars, comma-separated, no spaces, singular)
Don't repeat words already in the name/subtitle ("running", "coach"); Apple
indexes those automatically. Candidate (95 chars):
```
run,steps,counter,fitness,jog,jogging,training,5k,10k,walk,marathon,health,pace,habit,rest
```

## Description (≤4000)
```
Meet Buddy, your friendly running coach. 🐾

Otterpace turns daily movement into steady, guilt-free progress. Buddy reads your activity from Apple Health and gives simple, encouraging guidance every day.

• Daily step goal: a clean dashboard for steps, distance, and active minutes.
• Ask Buddy: quick, practical answers like "Run or rest today?"
• Smart run/rest tips: Buddy eases off when your training load spikes.
• Weekly review: what went well, and one focus for next week.
• Activity history: recent runs and walks, by week.
• Gentle reminders: optional nudges to move, on your schedule.

Your Apple Health data stays on your device and is never uploaded. No account required. Otterpace is open source.

Optional: connect your own AI key for richer, conversational coaching, or use the built-in coach offline.

Otterpace offers general fitness guidance, not medical advice.
```

## What's New (version 1.0)
```
First release: meet Buddy, your friendly running coach. Daily step goal, Ask Buddy chat, smart run/rest tips, weekly review, activity history, and gentle reminders.
```

## URLs & metadata
- **Privacy Policy URL**: `https://otterpace.com/privacy`
- **Support URL**: `https://otterpace.com` (add a `/support` page later if you want)
- **Marketing URL**: `https://otterpace.com`
- **Primary category**: Health & Fitness · **Secondary**: Lifestyle
- **Age rating**: 4+ (no objectionable content)
- **Copyright**: `2026 Otterpace`

## Privacy "nutrition label" (App Privacy section)
Must be completed before external testing / release; see
`docs/strava-and-analytics.md` for the full mapping. In short:
- **Usage Data → Product Interaction**: collected, *not linked* to identity,
  for Analytics / App Functionality (PostHog).
- **Identifiers**: anonymous analytics/device id, not linked to the user.
- Apple Health data read on-device is **not** "collected" in App Store terms
  (it never leaves the device), but declare any data your backend receives.
- (Strava import is hidden in v1, so there's no Strava activity data to declare
  this release; see the StravaClientID note in `App/Info.plist`.)

## Screenshots (raw 6.5" set, captured and ready to upload)
A 6-shot raw set is committed at `appstore/screenshots/6.5-inch/` (1284×2778,
the size App Store Connect's 6.5" slot accepts; ASC reuses one set for all
display sizes). Captured from the seeded CodeYam scenarios on an iPhone 13 Pro
Max simulator with a clean 9:41 status bar. Upload order (first 3 show on the
install sheet):
1. `01-today-goal-crushed.png`: Today dashboard, goal crushed
2. `02-ask-coach-knee-pain.png`: injury-aware "Safety First" coaching
3. `03-weekly-review-solid-week.png`: Weekly Review
4. `04-welcome-meet-buddy.png`: Meet Buddy onboarding
5. `05-today-fresh-start.png`: day-one dashboard
6. `06-settings.png`: Settings (privacy / BYO key)

Regenerate with `scratchpad/appstore-capture.mjs` (or re-capture at 6.9"
1320×2868 on an iPhone 16 Pro Max sim if you later want the larger size too).
