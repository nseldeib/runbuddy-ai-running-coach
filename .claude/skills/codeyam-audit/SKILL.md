---
name: codeyam-audit
autoApprove: true
description: |
  Finalize the current branch outside the editor workflow. Lists any
  deferred-finalize commits since the last successful finalize, runs
  `codeyam-editor-dev editor session-finalize`, and on failure groups the
  audit findings by the deferred commit(s) that introduced them.
  Use when you have accumulated deferred commits, did manual commits
  outside the workflow, or just want to audit the current branch.
---

# Audit and Finalize the Current Branch

Run `codeyam-editor-dev editor session-finalize` on the current branch and surface deferred-commit attribution on failure.

## Critical Rule: Audit Only — Never Apply Fixes Autonomously

This skill **runs** the finalize and **reports** what it found. It does NOT silently fix audit failures. When findings appear, present them and stop — the user (or a follow-up workflow loop) decides how to fix.

## Workflow

### Step 1 — Preflight

Confirm the project is initialized for codeyam-editor:

```bash
codeyam-editor-dev editor config-show >/dev/null 2>&1 || {
  echo "Project is not initialized for codeyam-editor. Run /codeyam-onboard first."
  exit 1
}
```

If the check fails, tell the user to run `/codeyam-onboard` and stop. Do not proceed.

### Step 2 — Summarize the debt

Run `codeyam-editor-dev editor finalize-debt show --format json` and parse the result. The JSON shape is:

```json
{
  "lastFinalizedSha": "9ab37c2",
  "deferred": [
    {"sha": "abc1234...", "shortSha": "abc1234", "subject": "feat: foo", "deferredAt": "2026-05-20T08:14:00Z"}
  ]
}
```

Then present via `AskUserQuestion`:

- **Zero deferred** — option list: `[Run finalize anyway (~7 min), Cancel]`. Question text: "Branch has no deferred commits. Run a full finalize anyway?"
- **Some deferred** — option list: `[Finalize now (~7 min), Cancel]`. Question text names the count and lists each `shortSha — "subject"` line so the user sees what's about to be cleared.

If the user picks Cancel, stop. Do not advance.

### Step 3 — Run finalize

If the user confirmed:

```bash
codeyam-editor-dev editor pre-commit-sync
```

If `pre-commit-sync` fails (queue tenure unhealthy, remote ahead, etc.), surface the exact error verbatim and stop — do **not** retry or work around the bail. Every queue bail names its own recovery command; quote that command to the user.

Then run:

```bash
codeyam-editor-dev editor session-finalize 2>&1 | tee /tmp/codeyam-audit-finalize.log
```

### Step 4 — Report

**On success** (exit 0): tell the user the finalize passed and the deferred-debt index has been cleared. If commits were deferred, note that the trailers remain in commit history as audit trail (visible via `git log --grep="^Codeyam-Finalize: deferred"`).

**On failure** (non-zero exit): re-run `codeyam-editor-dev editor audit --format json` to get the structured failure list with the new `attribution[]` field. The shape:

```json
{
  "passed": false,
  "failures": [{"id": "REGISTRY_TEST_NOT_WIRED", "items": ["..."], "fixCommand": "..."}],
  "attribution": [{"id": "REGISTRY_TEST_NOT_WIRED", "item": "...", "introducedIn": "abc1234...", "causedByHead": true, "causedByForeignClone": false}]
}
```

Intersect each `attribution[].introducedIn` SHA with the `deferred[].sha` list from Step 2. Group findings by attributed deferred commit and present:

> Finalize failed: N findings across M invariants.
>
> - **abc1234** ("feat: foo") — 3 findings (REGISTRY_TEST_NOT_WIRED)
> - **def5678** ("feat: bar") — 4 findings (CANONICAL_JSON_FORM)
> - **Unattributed** — 1 finding (pre-existing or no deferred commit touched it)
>
> Suggested fixes follow each finding's `fixCommand` in the audit JSON.

End the turn. The user (or another workflow / skill) follows up to apply fixes.

### Step 5 — Re-invocation

The skill is idempotent. After the user fixes a failure, they re-invoke `/codeyam-audit` to re-run the finalize. There is no skill-internal loop — the user explicitly decides when to retry.

## What NOT to do

- **Do not edit source to "fix" audit findings autonomously.** Report and stop; let the user direct the fix.
- **Do not bypass queue-tenure bails.** Every bail names its recovery command. Quote it verbatim and stop.
- **Do not skip Step 1's preflight.** A project without `.codeyam/` cannot run finalize; the friendly redirect to `/codeyam-onboard` saves a confusing error.
- **Do not invoke `session-finalize` from inside the editor workflow.** Use the workflow's own Finalize step there. This skill is the explicit "outside the workflow" entry point.
