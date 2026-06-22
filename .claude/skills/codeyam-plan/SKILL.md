---
name: codeyam-plan
autoApprove: true
description: |
  Plan a new feature or bug fix. Asks what you want to build/fix, investigates
  the codebase for context, writes a structured plan to .codeyam/plans/, and
  commits it.
---

# Plan a Feature or Bug Fix

Investigate the codebase and create a structured plan file ready for the codeyam editor workflow.

## Critical Rule: Plan Only — Never Implement

**You are a planner, not an implementer.** Your job is to write a `.codeyam/plans/*.md` file describing what to change and why. You must NEVER:

- Edit, create, or modify source code files (`.ts`, `.tsx`, `.rs`, `.json`, etc.)
- Run `cargo`, `npm`, `vitest`, `tsc`, or any build/test command
- Make fixes, refactors, or "quick improvements" to the codebase
- Apply the plan you just wrote

Even if the fix is obvious and small, **write it in the plan and stop.** The user will execute the plan later through the editor workflow. If you catch yourself about to edit a source file, stop and put that change into the plan's Implementation section instead.

The only files you may write are:
- `.codeyam/plans/<slug>.md` (the plan itself)
- `git add` / `git commit` of that plan file (and **only** that plan file — never `git add -A`, never a bare `git commit` that would sweep in unrelated staged work). This is the plan-creation commit specifically — it must contain only the plan file. The feature-commit step at the end of the editor workflow has a different rule: it auto-commits all non-gitignored leftovers.

The one read-only CLI call this skill makes is `codeyam-editor-dev editor last-plan-prefix` in Step 2 (to suggest the most recent prefix). It prints to stdout and changes nothing — it is not an "implementation" command.

## Workflow

### Step 1: Ask what to build or fix

**Do NOT use the AskUserQuestion tool for this step.** AskUserQuestion is a structured multiple-choice tool — using it here will produce a menu, which is exactly what we don't want. Instead, output the question below as plain assistant text and stop, waiting for the user's reply in the next turn.

Output **exactly** this and nothing else (no preamble, no tool calls, no follow-up options):

> **What do you want to build or fix?**
>
> Describe the feature, enhancement, or bug in as much detail as you'd like.

Then end your turn. The user will reply with a freeform description.

Take the user's response as the plan basis and move to the name-prefix step (Step 2), then on to investigation. Only ask a follow-up question if the response is genuinely ambiguous (e.g., you can't tell which part of the codebase is involved). Never ask about type, scope, priority, or any other categorization — infer those from the description and the codebase.

### Step 2: Ask about a name prefix

A prefix tags the plan's filename and title by author or work item — developer initials (`jc`), a feature code (`auth`), or a ticket number (`PROJ-123`). Default the suggestion to whatever the most recent plan used, then ask:

1. Run `codeyam-editor-dev editor last-plan-prefix` and capture its trimmed stdout as `lastPrefix`. It prints the prefix of the single most-recently-created plan (scanning both the queue and `.codeyam/plans/completed/`), or nothing when that newest plan has no prefix — or there are no plans yet.

2. **If `lastPrefix` is non-empty**, use `AskUserQuestion` — this is the one place in this skill where the structured menu is right, because there's now a concrete prior prefix to anchor the options:
   - Question: "Would you like to prefix the plan's filename and title?"
   - Option 1 (Recommended): label = the `lastPrefix` value (e.g. `improve32`), description = "Reuse the prefix from your most recent plan."
   - Option 2: label = "None", description = "No prefix — derive the filename and title from the description alone."
   - The auto-injected **Other** field lets the user type a different prefix.

   Interpret the answer: Option 1 → use `lastPrefix`; "None" → no prefix; an **Other** reply → the trimmed typed value as the prefix.

3. **If `lastPrefix` is empty** (no plans, or the newest plan has no prefix), do **NOT** use the AskUserQuestion tool — same reason as Step 1: with no prior prefix to suggest, a prefix is just freeform text, not a fixed multiple-choice menu. Output the prompt below as plain assistant text and stop, waiting for the user's reply in the next turn:

   > **Would you like to prefix the plan's filename and title?**
   >
   > For example your developer initials (`jc`), a feature code (`auth`), or a
   > ticket number (`PROJ-123`). Reply with the prefix to use, or reply `no` to
   > skip.

   Interpret the reply: a negative or empty reply (`no`, `none`, `skip`, or blank) → **no prefix**, proceed with today's behavior; any other reply → the trimmed text as the **prefix**.

4. In **every** branch, strip any double-quote (`"`) characters from the resulting prefix before carrying it into the "Write the plan file" step (Step 5), so both the `title:` and the new `prefix:` frontmatter lines stay valid YAML.

Then move on to investigation (Step 3).

### Step 3: Investigate the codebase

Based on the user's description, explore the relevant parts of the codebase to understand:

1. **Where the change lives** — which files, components, modules, or crates are involved
2. **How things currently work** — read the relevant code to understand current behavior
3. **What needs to change** — identify the specific modifications, new files, or new components needed
4. **What to reuse** — find existing helpers, components, types, or patterns that should be leveraged
5. **What tests exist** — check for existing test coverage in the affected areas

**Always check the project's registries and glossary first** — they are the
authoritative index of reusable code in a codeyam project. Skipping these is
what produces generic "look at the codebase" plans the editor workflow has
to re-research at the `explore` slug:

- `codeyam-editor-dev editor glossary-find <name>` (flags: `--prefix`,
  `--substring`, `--feature`, `--format`) — look up named entries
- `codeyam-editor-dev editor glossary-list` / `glossary-untested` /
  `glossary-by-tag <tag>` — projections across the whole table
- `.codeyam/glossary-index.txt` — line-oriented, greppable sidecar; safe to
  Read or grep directly. Use this when you need to scan for similar names
  or topics rather than look up a known entry
- `.codeyam/test-registry.json` — every registered test, its file, and the
  glossary entries it exercises. Use it to find which tests cover the
  area you're about to touch
- `.codeyam/deps-index.txt` — line-oriented projection of
  `dependency-graph.json`. Use it to find which functions/components
  call into the area you're touching, and what already exists nearby
  that you might reuse

NEVER `Read` `.codeyam/glossary.json` directly — it exceeds the Read tool
limit. Use the CLI / index sidecar.

After the registry/glossary pass, use the Explore agent or direct
Glob/Grep/Read tools to investigate code the indexes pointed you at. Be
thorough — the plan quality depends on understanding the codebase.

**Constrained-file pre-check.** Once investigation has produced the
candidate file list, run it through the editor so the plan never invites an
edit the guards will reject:

```bash
codeyam-editor-dev editor classify-constrained-files <path>... --format json
```

It returns only the constrained files (unconstrained paths are dropped),
each tagged with one or both of:

- **`leanContract`** — a SKILL.md governed by an enforced max-line-count
  test (`skill_md_is_lean`). When `atLimit` is true, additions fail that
  test, so the plan must NOT schedule new lines there. Route the new
  guidance to a step `.txt` file under
  `crates/codeyam-editor/src/commands/editor/steps/library/` and name that
  file in the plan. Reductions (refactors that shrink the file) stay fine.
- **`agentConfig`** — a file the harness reads as instructions/settings
  (`.claude/`, `.gemini/`, `ui/.claude/`, `settings.json`, keybindings).
  Edits trip the auto-mode self-modification guard. If the plan genuinely
  needs the change, confirm with the user once (Step 4) that it's an
  authorized agent-config edit before writing it into the plan; otherwise
  route the intent elsewhere.

Surfacing these at plan time avoids the costly discover-at-edit-time cycle —
a full test run to reveal a lean-limit failure, plus a confusing self-mod
denial mid-implementation.

**Reminder: investigation means reading, not changing.** Use only Read, Grep, Glob, and Explore tools here. Do not edit any files during investigation.

### Step 4: Clarify scope

Based on what you found in investigation, ask 1-2 targeted clarifying questions using AskUserQuestion. These should be **specific questions that emerged from reading the code**, not generic planning questions.

Good questions:
- "I found that X and Y are tightly coupled — should both be in scope, or just X?"
- "The current implementation uses pattern A, but pattern B would be simpler here. Which do you prefer?"
- "This change touches the API layer — should we include backend changes, or keep it frontend-only?"

**Skip this step entirely** if the request is unambiguous and investigation answered all questions. Don't ask questions for the sake of asking — only when the answer genuinely affects the plan.

### Step 5: Write the plan file

Create `.codeyam/plans/<slug>.md` using the Write tool.

**Slug:** Derive from the title — lowercase, alphanumeric + hyphens only. Example: "Session Recovery UX" becomes `session-recovery-ux.md`.

- **With a name prefix** (from Step 2): prepend the slugified prefix —
  `<slugify(prefix)>-<slugify(base title)>`. Slugify both halves the same way
  (lowercase, alphanumeric + hyphens), so punctuation in the prefix — including
  the title's colon separator — is normalized away. Example: prefix `PROJ-123` +
  title "Dark Mode Toggle" → `proj-123-dark-mode-toggle.md`.
- **Without a prefix**: derive from the title exactly as above. Example: title
  "Dark Mode Toggle" → `dark-mode-toggle.md`.

**Plan file format:**

```markdown
---
title: "Feature Name"
mode: ui
createdAt: "YYYY-MM-DDTHH:MM:SSZ"
source: manual
---

## Summary

One-paragraph description of what to build or fix and why.

## Key Decisions

- Decision 1 — why this approach
- Decision 2 — what was considered and why this was chosen

## Implementation

### 1. First change

**File**: `path/to/file.ext`

Description of what to change and why.

### 2. Second change

**New file**: `path/to/new-file.ext`

Description of what this new file does.

## Reused existing code

- `helperName` from `path/to/helper.ts` (glossary entry: `helperName`)
- `ComponentName` from `path/to/Component.tsx` (glossary entry: `ComponentName`)

Cite registry / glossary entries by name when the plan reuses them. This is
what makes the plan "well-researched" enough for the editor workflow's Plan
and Explore steps to fast-path through to Confirm.

## Scenarios to Demonstrate

- Happy path with realistic data
- Empty state
- Edge case 1
- Edge case 2
```

**Frontmatter fields:**
- `title` (required) — Feature name. Becomes the `--feature` value in the editor.
  **With a name prefix** (from Step 2), write it as `"<prefix>: <base title>"`:
  the prefix verbatim (as the user typed it, with any double-quotes stripped), a
  colon, a single space, then the base title. The prefix is kept readable here —
  only the filename slug normalizes it. Example: prefix `PROJ-123` + "Dark Mode
  Toggle" → `title: "PROJ-123: Dark Mode Toggle"`. **Without a prefix**, it's
  just the feature name, e.g. `title: "Dark Mode Toggle"`.
- `mode` (required) — `"ui"` or `"backend"`. Default to `"ui"` unless the change is purely backend.
- `createdAt` (required) — ISO 8601 UTC timestamp of when the plan was created.
- `source` (required) — Always `"manual"` for this skill.
- `prefix` (optional) — The author/work-item prefix, written **verbatim** (any
  double-quotes stripped) when Step 2 produced one. This is the canonical record
  of the prefix — `editor last-plan-prefix` reads it back to seed the next
  plan's default. The title's colon is NOT a reliable delimiter (many titles
  legitimately contain a colon), which is why the prefix is stored explicitly
  here. **Omit the line entirely when no prefix was chosen.**
- `order` (optional) — Positive integer. Controls queue position in the Plan tab.
  Missing/tied plans fall back to ascending `createdAt` (first-created first).
  Usually set via the UI drag or `editor plan-reorder`, not written by hand.
- `dependsOn` (optional) — Array of plan slugs this plan depends on, e.g.
  `dependsOn: ["session-recovery-ux", "auth-rewrite"]`. The Plan tab gates Run
  on this plan until each listed plan has been completed (i.e. archived under
  `.codeyam/plans/completed/`). Use the bracket-array form; a bare scalar
  (`dependsOn: foo`) is also accepted and parsed as a single-element list.

**Worked example (prefixed):** prefix `PROJ-123` + title "Dark Mode Toggle"
produces these coupled lines / paths — note the title's colon and the slug's
lack of one:

```
file:   .codeyam/plans/proj-123-dark-mode-toggle.md
title:  "PROJ-123: Dark Mode Toggle"
prefix: "PROJ-123"
```

**When to use `dependsOn`:** if the user's request is too big to deliver in
one plan and you split it into multiple plans, declare dependencies on the
prerequisites instead of relying on queue order alone. Reference the slugs
of plans you've authored in the same session — they exist in
`.codeyam/plans/`. The user can then run them in any order; the editor
will block Run on a downstream plan until its prerequisites land.

**Guidelines for plan content:**
- Focus on **what the user will see and do**, not just implementation details
- Be specific about file paths — you investigated the codebase, so name real files
- List concrete scenarios with interesting data states (empty, rich, error, edge cases)
- Keep the summary concise — the editor's Step 1 will refine details
- For bug fixes, describe the current broken behavior and the expected correct behavior
- Reference real existing code that should be reused — include file paths
- Honor Step 3's constrained-file pre-check: never leave a section as "edit
  SKILL.md" for a lean file at its limit — name the step `.txt` file the
  guidance should live in instead, and call out any authorized agent-config
  edit explicitly so the editor workflow isn't surprised by the self-mod guard

### Step 6: Present and confirm

Run `codeyam-editor-dev editor plans` to verify the plan is parseable and shows up correctly.

Show the user a brief summary of the plan, then use AskUserQuestion with these options:
- **"Looks good, commit it" (Recommended)** — Commit the plan and finish
- **"I want changes"** — User describes changes, you revise the plan, then re-present
- **"Discard and start over"** — Delete the plan file and go back to Step 1

### Step 7: Act on response

- **Looks good** — Commit the plan, then signal the UI.

  **Commit hygiene:** the plan commit must contain only `.codeyam/plans/<slug>.md`. Use the pathspec form below — do not run a bare `git commit`, since other files may be staged from prior work. (This is the plan-creation commit specifically — it must contain only the plan file. The feature-commit step at the end of the editor workflow has a different rule: it auto-commits all non-gitignored leftovers.) After committing, verify with `git show --stat HEAD` that only the plan file is listed; if anything else appears, run `git reset --soft HEAD~1` and retry with the pathspec form.

  **Always append `[skip ci]` to the commit message.** Plan files don't change source or tests, so CI must not be triggered. This is non-optional — apply it on the initial commit and on any amend.

  ```bash
  git commit -m "plan: <short description of the feature/fix> [skip ci]" -- .codeyam/plans/<slug>.md
  git show --stat --name-only HEAD   # verify only the plan file is in the commit
  codeyam-editor-dev editor plan-complete
  ```
  After the commit succeeds, `plan-complete` triggers a confirmation modal
  in the Plan tab offering to start another plan or return to the queued
  changes list. Only run `plan-complete` on this branch — not on "I want
  changes" (which loops back to Step 6) or "Discard" (which returns to
  Step 1 with no plan saved).
- **I want changes** — Make the requested changes to the plan file, then go back to Step 6
- **Discard** — Delete the plan file and return to Step 1

## Tips

- Spend most of your time in Step 3 (investigation). A plan based on real codebase understanding is far more valuable than a generic one.
- If the feature touches multiple areas, organize the Implementation section by area, not by order of execution.
- Plans with `mode: backend` will suggest backend mode when selected in the editor.
- Don't over-specify implementation — leave room for the editor workflow to make tactical decisions. Focus on the "what" and "why", with enough "how" to be actionable.
