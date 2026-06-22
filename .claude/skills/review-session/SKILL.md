---
name: review-session
autoApprove: true
description: |
  Review a previous Claude Code session to identify problems and inefficiencies.
  Analyzes the transcript, presents findings, asks the user what they noticed,
  and writes plans to address everything found.
---

# Review Session

Analyze a previous Claude Code session to surface **problems and inefficiencies** — things that went wrong, took too long, or could be done better. Output is actionable plans saved to `.codeyam/plans/`.

**IMPORTANT: Plans are always written to THIS repo's `.codeyam/plans/` directory (`/Users/jaredcosulich/workspace/codeyam/codeyam-editor/.codeyam/plans/`), not the client project being reviewed.** The plans describe improvements to the editor workflow itself.

## Workflow

### Step 0: Exit Plan Mode

If you are currently in Plan Mode, you MUST exit it before proceeding to ensure you have full tool access for the extraction and analysis scripts.

### Step 1: Choose the source — local or a cloud VM

Sessions can live on this laptop **or** on a running codeyam-editor cloud VM. First check whether any VMs are up:

```bash
node .claude/skills/review-session/scripts/vm-sessions.mjs --list-vms
```

- **Exits non-zero / "No running … VMs"** → there's nothing to review remotely. Skip the question and go straight to the **Local** path below.
- **Lists one or more VMs** → ask the user where to look with AskUserQuestion. Offer **"Local"** plus each VM by name as options. **Remember each VM's printed zone** — you need it for the remote commands. Then follow the matching path in Step 2.

### Step 2: Find the right session

#### Local source

Ask which project to review, then which session:

```bash
node .claude/skills/review-session/scripts/find-last-session.mjs --list-projects
```

Present the top 3-5 real projects (skip temp/test directories) and ask which one. Then list its sessions. **Always use `--exclude-current`** to skip the currently-running session (this one):

```bash
# Reviewing the current project (same working directory):
node .claude/skills/review-session/scripts/find-last-session.mjs --exclude-current --list-sessions

# Reviewing a different project:
node .claude/skills/review-session/scripts/find-last-session.mjs --project=<name> --list-sessions
```

Present the sessions (timestamps + sizes) and ask which one. Default to the most recent but let them choose. To get the chosen path:

```bash
node .claude/skills/review-session/scripts/find-last-session.mjs --exclude-current --project=<name> --nth=<N>
```

The chosen path is what you feed to Step 3.

#### Cloud VM source

List the VM's sessions (grouped by project, both Claude and Gemini, newest first). Pass the VM name and the zone you noted in Step 1:

```bash
node .claude/skills/review-session/scripts/vm-sessions.mjs --vm=<name> --zone=<zone> --list-sessions
```

A VM almost always has exactly one project (`/workspace`). If more than one project is listed, confirm which the user wants. Present the sessions (timestamps + sizes) and ask which one — each entry prints its own `--fetch=<remote-path>`.

Then copy the chosen transcript to a local temp file. **The command prints the local path on stdout** — that's what Step 3 reads:

```bash
node .claude/skills/review-session/scripts/vm-sessions.mjs --vm=<name> --zone=<zone> --fetch=<remote-path>
```

(If it reports "No codeyam-editor container is running", the editor isn't up on that VM — pick another VM or fall back to Local.)

**Do not skip sessions for being small** — local or remote. Short sessions often contain the exact problems worth reviewing.

### Step 3: Extract and analyze

From here the flow is identical for both sources — you have a local transcript path (either a real local session or the temp file fetched from the VM). Start with the decisions view for the best balance of context vs. size:

```bash
node .claude/skills/review-session/scripts/extract-session.mjs <path> --section=decisions
```

If the session is short, use `--section=full` to get everything. Other sections available: `user-only`, `errors`.

Also extract errors specifically:

```bash
node .claude/skills/review-session/scripts/extract-session.mjs <path> --section=errors
```

### Step 4: Present your findings

Analyze the transcript for **problems and inefficiencies only**:

1. **Problems** — bugs encountered, incorrect approaches taken, things that broke, user corrections, work that had to be redone
2. **Inefficiencies** — unnecessary steps, going in circles, over-engineering, missed shortcuts, slow approaches when faster ones existed

Present these as a concise bulleted list. Do NOT list what was accomplished or what features were built — focus exclusively on what went wrong or could be improved.

### Step 5: Ask the user what they noticed

After presenting your findings, **ask the user what they saw as problematic or inefficient**. Use AskUserQuestion with a free-text prompt like:

> "What problems or inefficiencies did you notice in this session? Anything I missed or that stood out to you?"

The user may have context you don't — they may have noticed the AI going in circles, making wrong assumptions, or taking an approach that caused downstream issues.

### Step 6: Write plans

Combine your findings with the user's input. For each actionable problem or inefficiency, create a plan file in the **codeyam-editor repo** (not the reviewed project):

```
/Users/jaredcosulich/workspace/codeyam/codeyam-editor/.codeyam/plans/<slug>.md
```

**Plan format:** Read `.claude/skills/codeyam-plan/SKILL.md` Step 4 for the canonical plan file format (frontmatter, sections, slug rules, and guidelines). Use that format exactly, mapping review-session content to the canonical sections:

| Canonical Section | Review-session content |
|---|---|
| **Summary** | The problem + evidence from the transcript (what went wrong and how you know) |
| **Key Decisions** | The chosen fix approach and why |
| **Implementation** | Concrete fix steps with real file paths |
| **Reused existing code** | Existing code to leverage for the fix (omit section if empty) |
| **Scenarios to Demonstrate** | How to verify the fix works |

**Frontmatter overrides** (these differ from codeyam-plan defaults):
- `title`: prefix with "Fix:" for bugs or "Improve:" for inefficiencies
- `source`: always `"session-review"` (not `"manual"`)

### Step 7: Verify

Run `codeyam-editor-dev editor plans` to verify the plans are parseable, then show the user what was created. Ask if they want to edit any.

### Step 8: Commit each plan

Commit each plan file as a standalone commit, one plan per commit, using the pathspec form so unrelated staged work isn't swept in. **Always append `[skip ci]` to the commit message** — plan files don't change source or tests, so CI must not be triggered. Same rule for amends.

```bash
git commit -m "plan: <short description from the plan title> [skip ci]" -- .codeyam/plans/<slug>.md
git show --stat --name-only HEAD   # verify only the plan file is in the commit
```

If anything other than the plan file appears in the commit, run `git reset --soft HEAD~1` and retry with the pathspec form.

## Managing Plans

```bash
# List all plans:
codeyam-editor-dev editor plans

# Delete a plan:
codeyam-editor-dev editor plan-delete <slug>
```

## Tips

- Start with `--section=decisions` — it shows what happened without overwhelming detail
- Use `--section=errors` to find explicit failures
- Short sessions are often the most interesting — they may have been abandoned due to a problem
- A single session can produce multiple plans
- Keep plan descriptions concrete — "the AI spent 5 tool calls searching for a file that was in the obvious location" is better than "search was inefficient"
- Cloud VM sessions require `gcloud` auth (`gcloud auth login`) and read transcripts via an IAP-tunneled SSH into the VM's editor container, so each `vm-sessions.mjs` call takes a few seconds. The plans you write still land in **this** repo's `.codeyam/plans/`, exactly as for local sessions.
