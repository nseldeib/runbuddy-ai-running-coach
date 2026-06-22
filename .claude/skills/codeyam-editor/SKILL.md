---
name: codeyam-editor
autoApprove: true
description: CodeYam Editor Mode — scaffold a project and build code + data scenarios together
---

# CodeYam Editor Mode

You are in **Editor Mode**. The user sees a split-screen: this terminal on the left, live preview on the right.

## Preflight: is another session already driving this workflow?

Two `/codeyam-editor` panes on one project corrupt each other's workflow state. Before anything else — before the project description or `step 1` — run `codeyam-editor-dev editor workflow-holder --format json` and branch:

- **Non-zero exit** (e.g. `error: unrecognized subcommand 'workflow-holder'` or an unknown-flag error) — `workflow-holder` is a real, current command, so a parse failure means your `codeyam-editor` binary is **stale**. Do NOT conclude the command doesn't exist, do NOT skip the preflight, and do NOT rebuild or restart the editor yourself: **STOP, do not run `step 1`, and tell the user the editor binary is stale and to ask the maintainer to rebuild it** — never silently proceed, which forfeits the concurrent-session protection this preflight provides. (If you are developing codeyam-editor itself, its CLAUDE.md "Rebuilding the editor mid-session" covers the maintainer-only recovery.)
- **`held_by_other: false`** — no foreign holder (or the lock is yours, e.g. after `/clear` and re-invoke). Proceed normally.
- **`held_by_other: true`, `holder_stale: false`** — a live session is
  driving. Do NOT run `step 1`. Print the holder identity fields
  (`holder_session_id`/`holder_pid`/`holder_acquired_at`/`holder_transcript_path`)
  and tell the user to switch to that pane or wait, then stop.
- **`held_by_other: true`, `holder_stale: true`** — a crashed/abandoned
  session left a stale lock. Do NOT run `step 1`. Tell the user to run
  `codeyam-editor-dev editor session-reset` then re-invoke, then stop.

## Project description is mandatory

Before doing ANYTHING in step 1, read `.codeyam/editor.json` and inspect the `projectDescription` field.

- If it is **empty or missing**, stop and ask the user: *"I don't have a project description yet — what are you building?"*
- If it is **shorter than 20 characters**, contains **no whitespace**, or matches a placeholder like `test`, `todo`, `app`, `demo`, `hello`, `untitled`, `foo`, `bar`, `tbd`, `wip`, `example` (case-insensitive), treat it as not-yet-set and ask the user the same question.
- Do **NOT** call `editor project-info` to set a fabricated description. The endpoint enforces this — it returns `409 project_description_already_set` for any overwrite without `"allowOverwrite": true`, and `allowOverwrite` is only legitimate when the user has *explicitly* asked you to rename the project. Fabricating wastes a round-trip and confuses the user when they see the rejected POST in logs.
- When you later need the project's display **title** (its brand / product name), read it from this same file: prefer `projectTitle`, and fall back to the legacy `projectName` key (older projects carry only that). Never search the codebase (components, layouts, logos) for it. If neither key is present, ask the user; do not fabricate one.

Only proceed past step 1 once `projectDescription` is a real, multi-word description provided by the user.

## CRITICAL: How This Works

You MUST follow a step-by-step workflow driven by `codeyam-editor-dev editor step` commands. Each command tells you exactly what to do next. **You do NOT have all the instructions upfront** — the commands provide them incrementally.

**Your first action:** Run `codeyam-editor-dev editor step 1`.

**The rule:** After completing what a command tells you to do, run the NEXT command it specifies. The commands are your instructions — follow them one at a time.

## Task Tracking

Steps 2+ include `━━━ TASK ━━━` directives with exact task titles and procedures. Follow what each directive says: create the task, do the work, mark it completed before advancing. Step 1 has no task.

The advance gate reads `.codeyam/editor-task-tracking.json` (populated by the PostToolUse hook from your TaskCreate / TaskUpdate calls) and will `BLOCKED` if the current-step task is missing or not marked completed. Do NOT edit that JSON directly — go through TaskCreate/TaskUpdate so the hook records the state.

## The Cycle

Each feature flows through plan → confirm → prepare → prototype → demo → deconstruct → present → reconcile → finalize → journal → commit → push → feature-complete. Run `codeyam-editor-dev editor step 1` to start; subsequent commands tell you the next slug. UI flow = 23 steps, backend flow = 18 steps.

User confirmation is required at the `ui-confirm-plan` / `backend-confirm-plan`, `present-live` / `backend-confirm`, and `ui-present` / `backend-present` slugs. All others auto-advance — run the next step command immediately, do not wait for the user to prompt you.

## Scenario Coverage and Audit

At the **reconcile** step, `codeyam-editor-dev editor audit` is run to verify project integrity.
- **Visual Components**: Captured component scenarios automatically satisfy the `missingTests` check. No `testFile` is required in the glossary if a matching scenario exists.
- **Entry-Point Pages**: Application scenarios satisfy `missingTests` for pages.
- **Pure Logic**: Still requires a `testFile` pointing to a unit test.

## Handling User Feedback / Changes

When the user asks for changes mid-workflow, always:
1. Make the requested changes
2. Re-register any affected scenarios. Use a per-invocation scratch path (unique filename per call — e.g. `.codeyam/tmp/register-<batch-tag>.json`); `register` auto-deletes the file on success, so do NOT reuse a shared path.
3. Update the journal if needed
4. Resume from the current step

## Key Rules

- **Run the commands** — they ARE your instructions, not suggestions
- **One step at a time** — run each step command, read its FULL output, complete every checklist item, then advance
- **NEVER batch-run steps** — each step has unique instructions you must read and follow
- **Every feature gets scenarios** — this is the core value of CodeYam. Create at least one scenario that drives the Live Preview *during the build loop*, not as a Demo-step afterthought. A component with no top-level route (buried in a flow, or a self-hosting editor change) is shown via an isolated-component scenario at `/isolated-components/<Component>?s=<Scenario>` — that is the normal path, not a reason to skip the demo.
- **Keep the preview moving** — refresh it frequently so the user sees progress. The Demo step (`present-live`) requires a NAVIGABLE preview: its advance gate blocks until a verified capture exists for the feature, or a structural exception is recorded with `codeyam-editor-dev editor demo-skip --reason "..."`. Test evidence alone never advances the Demo step.
- **Run `codeyam-editor-dev editor advance` bare — do NOT pipe it through `tail` or `head`.** The command prints the next step's full instructions plus a tail-safe trailer (`━━━ BEGIN STEP N: <label> ━━━`) that carries the `EXACT_TASK_TITLE` and the immediate next actions. Slicing it strips the task hand-off body and the workflow stalls.
- **After `advance` succeeds, keep working in the same turn.** Read the trailer, create the next step's task, run its checklist. Do NOT announce the advance and stop — that forces the user to send "Ok continue" every step. The only exception is the `(CONFIRMATION GATE)` trailer variant, which redirects you to `AskUserQuestion` and forbids auto-advance.
- **Wait on the completion sentinel, never on a success-string regex.** The long commands (`pre-commit-sync`, `refresh-tests`, `session-checkpoint`) print a stable final stdout line — a JSON object carrying the token `CODEYAM_CMD_COMPLETE` plus the command name and a terminal `status` (`ok` | `error`) — on BOTH success and failure. If the harness auto-backgrounds one, wait on the token (`until grep -q "CODEYAM_CMD_COMPLETE" <taskfile>; do sleep 3; done`) and then read `status`. Do NOT guess at `HEAD ACQUIRED`/`recovered`/`pulled`-style English regexes.
- **Recover a bailed `pre-commit-sync` in one shot.** When `pre-commit-sync` bails on a dirty-tree rebase refusal or a duplicate plan slug, run `codeyam-editor-dev editor pre-commit-sync --recover`. It runs `git pull --rebase --autostash` → `post-merge-drift-sweep` → `plan-cleanup-duplicates` and re-attempts the sync in a single command — do NOT hand-stitch those three steps across multiple runs, and do NOT `git add` a deleted queue-plan copy by hand (`plan-cleanup-duplicates` now stages that deletion for you).

## Quick Reference

Most commands are shown in context by the step that needs them. A few non-obvious ones:

```bash
# Find scenarios for a specific component (avoids a whole-repo grep)
codeyam-editor-dev editor scenarios --component PreviewPanel
# Filter by name or slug substring (case-insensitive); flags AND together
codeyam-editor-dev editor scenarios --name "Loading" --slug previewpanel

# Look up glossary entries — do NOT Read glossary.json directly (~71k tokens)
codeyam-editor-dev editor glossary-find <name>
# Flags: --prefix, --substring, --feature <name>, --format json|pretty

# Diagnose an empty section in the Working Session Results panel
codeyam-editor-dev editor explain-results
```
