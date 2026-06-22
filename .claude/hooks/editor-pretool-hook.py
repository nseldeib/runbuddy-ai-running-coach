#!/usr/bin/env python3
"""
PreToolUse hook for editor mode — blocks tool execution outside allowed slugs.

Reads `.codeyam/editor-step.json` for the active slug and
`.codeyam/cache/step-metadata.json` for the per-slug capability
allowlists, then blocks:
- Write/Edit to non-`.codeyam/`, non-`.claude/` files at slugs that
  don't carry the code-change capability.
- Bash `git commit` / `git add` outside slugs in `commitSlugs`.
- Bash `git push` outside slugs in `pushSlugs`.
- AskUserQuestion at slugs in `previewRequiredSlugs` unless
  `.codeyam/preview-shown.json` matches the current step.

The slug allowlists are projected into the cache by
`crates/codeyam-editor/src/commands/editor/slug_capabilities.rs` (the
single source of truth for per-slug capabilities), so a future
workflow renumbering never silently breaks a gate.

The Plan-tab PTY does not set `CODEYAM_EDITOR_ACTIVE`, so this hook is
silent there by design — Plan-tab commits are always allowed.

Returns exit code 2 to block, 0 to allow. Stderr is fed back to
Claude as feedback.
"""

import json
import os
import re
import subprocess
import sys

# `_step_metadata` lives next to this file; add the hook directory to
# `sys.path` so the import works regardless of the cwd the hook runner
# launches from.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _step_metadata import cli_command, load_step_metadata, resolve_mode_table  # noqa: E402

# Plan files live here and are always commitable regardless of current step.
PLAN_PATH_PREFIX = ".codeyam/plans/"


def staged_paths_are_plans_only(project_dir):
    """True iff `git diff --cached --name-only` is non-empty and every path
    starts with `.codeyam/plans/`. An empty staged set returns False — the
    commit would be a no-op and the existing error path is more useful."""
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            cwd=project_dir,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except Exception:
        return False
    if result.returncode != 0:
        return False
    lines = [l for l in result.stdout.splitlines() if l.strip()]
    if not lines:
        return False
    return all(l.startswith(PLAN_PATH_PREFIX) for l in lines)


def git_add_paths_are_plans_only(command):
    """True iff a `git add` command targets only paths under .codeyam/plans/.

    Conservatively rejects any flag-like arg (-A/--all, -p/--patch,
    -i/--interactive, etc.) and a bare "." pathspec, since we cannot infer
    the eventual staged set in those cases."""
    tokens = command.split()
    try:
        add_idx = tokens.index("add")
    except ValueError:
        return False
    args = tokens[add_idx + 1:]
    if not args:
        return False
    for tok in args:
        if tok.startswith("-") or tok == ".":
            return False
    return all(p.startswith(PLAN_PATH_PREFIX) for p in args)


def _slug_label(state, slug):
    """Human-readable identifier for BLOCKED messages. Slug is the
    primary handle; label is shown alongside when state carries it."""
    label = state.get("label", "") or ""
    if label:
        return f"{label} (slug={slug})"
    return f"slug={slug}"


def _preview_hint(mode, project_dir):
    """Hint shown when AskUserQuestion is blocked for missing preview.

    Backend mode never has a live preview — point at the results
    panel instead. UI mode points at `editor preview` with the
    user-configured default screen size."""
    cli = cli_command()
    if mode == "backend":
        return f"{cli} editor show-results"
    default_dim = "Desktop"
    editor_config_path = os.path.join(project_dir, ".codeyam", "editor.json")
    try:
        with open(editor_config_path, "r") as f:
            cfg = json.load(f)
        default_dim = cfg.get("defaultScreenSize", "Desktop")
    except Exception:
        pass
    return f'{cli} editor preview \'{{"dimension":"{default_dim}"}}\''


def main():
    # Only enforce in editor mode
    if not os.environ.get("CODEYAM_EDITOR_ACTIVE"):
        sys.exit(0)

    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    state_path = os.path.join(project_dir, ".codeyam", "editor-step.json")

    # No state file = not in editor mode, allow everything
    if not os.path.exists(state_path):
        sys.exit(0)

    try:
        with open(state_path, "r") as f:
            state = json.load(f)
    except (json.JSONDecodeError, IOError):
        sys.exit(0)  # Can't read state, don't block

    step = state.get("step", 0)
    slug = state.get("slug") or ""

    if not step:
        sys.exit(0)

    metadata = load_step_metadata(project_dir)
    mode, mode_table = resolve_mode_table(state, metadata)

    code_change_slugs = set(mode_table.get("codeChangeSlugs", []))
    commit_slugs = set(mode_table.get("commitSlugs", []))
    push_slugs = set(mode_table.get("pushSlugs", []))
    preview_required_slugs = set(mode_table.get("previewRequiredSlugs", []))

    # Read the tool use event from stdin
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            sys.exit(0)
        event = json.loads(raw)
    except Exception:
        sys.exit(0)

    tool_name = event.get("tool_name", "")
    tool_input = event.get("tool_input", {})

    # Always allow codeyam-editor commands. Match both the canonical
    # name and the local-dev wrapper so saved sessions emitted under
    # either spelling keep working after the canonical-name rollout.
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        if (
            "codeyam-editor-dev editor" in command
            or "codeyam-editor-dev:editor" in command
            or "codeyam-editor-dev editor" in command
            or "codeyam-editor-dev:editor" in command
        ):
            sys.exit(0)

    # Always allow reading
    if tool_name in ("Read", "Glob", "Grep", "WebFetch", "WebSearch", "Agent"):
        sys.exit(0)

    # Always allow task management
    if tool_name in ("TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "Skill", "ToolSearch"):
        sys.exit(0)

    # Gate AskUserQuestion at preview-required slugs — require preview marker first
    if tool_name == "AskUserQuestion":
        if slug and slug in preview_required_slugs:
            marker_path = os.path.join(project_dir, ".codeyam", "preview-shown.json")
            preview_ok = False
            if os.path.exists(marker_path):
                try:
                    with open(marker_path, "r") as f:
                        marker = json.load(f)
                    if marker.get("step") == step:
                        preview_ok = True
                except Exception:
                    pass

            if not preview_ok:
                hint = _preview_hint(mode, project_dir)
                print(
                    f"BLOCKED: This step ({_slug_label(state, slug)}) requires showing "
                    f"the live preview before asking the user for confirmation.\n"
                    f"Run `{hint}` first, then call AskUserQuestion.",
                    file=sys.stderr,
                )
                sys.exit(2)

        sys.exit(0)

    # Check Write/Edit to non-.codeyam files
    if tool_name in ("Write", "Edit"):
        file_path = tool_input.get("file_path", "")

        # `@import url(...)` in CSS is render-blocking and bypasses Next.js's
        # font pipeline. Webfonts belong in layout.tsx via next/font or a
        # <link rel="preconnect"> + <link href> — check BEFORE the .codeyam/
        # short-circuit so authored CSS is gated regardless of step.
        if file_path.endswith(".css"):
            content_str = tool_input.get("content", "") or tool_input.get("new_string", "")
            if "@import url" in content_str:
                print(
                    "BLOCKED: `@import url(...)` in CSS is render-blocking and "
                    "hurts LCP. Load webfonts via next/font in layout.tsx (or "
                    "a <link rel=\"preconnect\"> + <link href> pair) rather than "
                    "from the stylesheet.",
                    file=sys.stderr,
                )
                sys.exit(2)

        # Always allow .codeyam/ and .claude/ files (editor state)
        if "/.codeyam/" in file_path or "/.claude/" in file_path:
            sys.exit(0)
        # Empty allowlist means the cache is missing/stale (e.g. a v1
        # cache after a binary downgrade) — degrade to "allow" rather
        # than brick the session. An empty `slug` means the state file
        # predates the slug field; the next `editor step` invocation
        # will migrate it, so degrade to "allow" rather than block on
        # an unmatchable allowlist.
        if slug and code_change_slugs and slug not in code_change_slugs:
            allowed = ", ".join(sorted(code_change_slugs))
            print(
                f"BLOCKED: This step ({_slug_label(state, slug)}) does not allow code changes. "
                f"Code changes are only allowed at slugs: {allowed}. "
                f"If you need to make changes after a final-presentation gate, run "
                f"`{cli_command()} editor change` first.",
                file=sys.stderr,
            )
            sys.exit(2)

    # Check Bash commands for git commit/push
    if tool_name == "Bash":
        command = tool_input.get("command", "")

        # BSD grep on macOS lacks -P (PCRE). Fail loud so Claude switches to
        # the Grep tool (ripgrep-backed, PCRE-compatible) instead of seeing
        # a cryptic "grep: invalid option" at runtime.
        if re.search(r"\bgrep\s+-[A-Za-z]*P\b", command):
            print(
                "BLOCKED: `grep -P` is unsupported on macOS (BSD grep). "
                "Use the Grep tool instead — it wraps ripgrep and honors "
                "PCRE syntax portably.",
                file=sys.stderr,
            )
            sys.exit(2)

        if "git commit" in command:
            if slug and commit_slugs and slug not in commit_slugs and not staged_paths_are_plans_only(project_dir):
                allowed = ", ".join(sorted(commit_slugs))
                print(
                    f"BLOCKED: git commit/add is only allowed at slug(s): {allowed}. "
                    f"You are at {_slug_label(state, slug)}. "
                    f"Plan-file commits (.codeyam/plans/*.md) are allowed at any step. "
                    f"Follow the workflow — commits happen at the `commit` slug.",
                    file=sys.stderr,
                )
                sys.exit(2)
        elif "git add" in command:
            if slug and commit_slugs and slug not in commit_slugs and not git_add_paths_are_plans_only(command):
                allowed = ", ".join(sorted(commit_slugs))
                print(
                    f"BLOCKED: git commit/add is only allowed at slug(s): {allowed}. "
                    f"You are at {_slug_label(state, slug)}. "
                    f"Plan-file commits (.codeyam/plans/*.md) are allowed at any step. "
                    f"Follow the workflow — commits happen at the `commit` slug.",
                    file=sys.stderr,
                )
                sys.exit(2)

        if "git push" in command:
            if slug and push_slugs and slug not in push_slugs:
                allowed = ", ".join(sorted(push_slugs))
                print(
                    f"BLOCKED: git push is only allowed at slug(s): {allowed}. "
                    f"You are at {_slug_label(state, slug)}.",
                    file=sys.stderr,
                )
                sys.exit(2)

    # Allow everything else
    sys.exit(0)


if __name__ == "__main__":
    main()
