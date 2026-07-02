---
title: "Subtle Buddy: Text-Only Ask Coach Header"
mode: ui
createdAt: "2026-07-01T12:00:00Z"
source: manual
---

## Summary

In the Ask Coach tab the Buddy mascot currently renders twice on screen at
once: a 34pt `PuffyBuddy` in the header (`AskCoachHeader.swift:12`) and a 30pt
mood-reactive `PuffyBuddy` leading every coach reply (`ChatBubble.swift:26`).
Because coach and user messages strictly alternate (each question yields exactly
one reply; the "thinking…" placeholder is replaced in place, never a second
bubble), any single exchange shows the mascot twice — which reads as too much.
This change drops the mascot from the header, making it text-only, so Buddy
appears exactly **once** per screen: the mood-reactive avatar that leads each
coach reply, where the mood signal is most meaningful. The brand stays intact —
the header still names Buddy in its subtitle, and the mascot remains the visual
lead of every answer.

## Key Decisions

- **Keep the per-message mascot, drop the header mascot** — chosen over dropping
  the per-message avatar because the 30pt `PuffyBuddy` on each coach reply is
  mood-reactive (`message.mood`), so it carries live coaching-tone signal that a
  fixed `.ready` header avatar does not. Anchoring the single remaining instance
  to the replies keeps the most informative version.
- **Do NOT use iMessage-style "avatar only on first of a run" grouping** — it
  was considered and rejected: messages strictly alternate, so every coach reply
  is already a run of one and such grouping would be a no-op (the avatar would
  still show on every reply). The redundancy is header-vs-message, not
  message-vs-message, so the fix is at the header.
- **Header becomes text-only, not restyled with an icon** — keep the change
  minimal and on-brand. The subtitle ("Buddy • AI coach" / "Buddy") already
  names the mascot, so brand identity is preserved textually without a
  competing glyph. The trailing "Weekly" pill and its behavior are unchanged.

## Implementation

### 1. Remove the mascot from the Ask Coach header

**File**: `Sources/AppCore/AskCoachHeader.swift`

Remove the leading `PuffyBuddy(mood: .ready, size: 34)` (line 12) so the header
opens directly with the title/subtitle `VStack`. Adjust the outer `HStack`
layout so the text-only header still reads as a proper title bar:

- Drop the now-oversized `spacing: 10` on the root `HStack` (it existed to gap
  the avatar from the text) — the title `VStack` becomes the leading element and
  should sit at the leading padding edge. Keep the `Spacer()` and the trailing
  "Weekly" button exactly as-is.
- Leave the subtitle logic untouched: it still shows `connected ? "Buddy • AI
  coach" : "Buddy"`, preserving the Buddy name and the connected/locked
  distinction.
- Update the file's top doc comment (lines 3–5), which currently describes "a
  small Buddy avatar beside the screen name," to reflect the text-only title bar.

Net effect: the header is `Ask Coach` / `Buddy • AI coach` on the left, the
Weekly pill on the right, and no mascot.

### 2. Leave the coach-reply mascot unchanged

**File**: `Sources/AppCore/ChatBubble.swift`

No change. The 30pt mood-reactive `PuffyBuddy(mood: message.mood, size: 30)` on
line 26 stays — it is now the single on-screen Buddy instance. Confirm the
existing mood tinting (bubble fill/border to `message.mood.accent`, lines 44–52)
and the amber safety shield continue to work as before.

## Reused existing code

- `PuffyBuddy` from `Sources/AppCore/PuffyBuddy.swift` (glossary entry:
  `PuffyBuddy`) — the procedural mascot view; retained on coach replies, removed
  from the header.
- `AskCoachHeader` from `Sources/AppCore/AskCoachHeader.swift` (glossary entry:
  `AskCoachHeader`) — the file being edited.
- `Typography` / `Palette` (`Theme.swift`) — existing title/subtitle fonts and
  ink/subtle colors already used by the header; no new styling primitives needed.
- `BuddyMood` (glossary entry: `BuddyMood`) — the per-reply mood driving the
  retained avatar; unchanged.

## Scenarios to Demonstrate

- **Ask Coach — single exchange (happy path)**: one user question + one coach
  reply. Verifies the mascot now appears exactly once (on the reply) with a
  text-only header. This is the core before/after (re-capture of the existing
  `ask-coach-*` scenarios, e.g. `ask-coach-run-or-rest`).
- **Ask Coach — empty chat**: connected, no messages yet. Header is text-only;
  the large empty-state mascot (`AskCoachEmptyState`, 96pt) is the only Buddy,
  confirming the empty state is unaffected.
- **Ask Coach — locked (no AI key)**: the connect-key CTA state. Header subtitle
  reads "Buddy"; confirms the text-only header renders in the locked variant and
  the locked-state mascot is untouched.
- **Ask Coach — safety-flagged reply** (e.g. `ask-coach-knee-pain`): a coach
  reply carrying `safetyFlag`. Confirms the retained per-message mascot plus the
  amber "SAFETY FIRST" shield and mood tint still render correctly with the new
  header.
- **Ask Coach — multi-turn thread**: several alternating exchanges. Confirms the
  mascot appears once per coach reply (not doubled with a header instance) down
  the whole thread.
