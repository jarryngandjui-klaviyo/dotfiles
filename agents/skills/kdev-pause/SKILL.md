---
name: kdev-pause
description: Use when pausing a Klaviyo dev session to switch context — saves current work state, goals, open files, and next steps to a session file for later resumption.
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Glob, Grep, Bash, Write
model: sonnet
---

## kdev-pause

Snapshot the current session context to a markdown file so you can switch to another project and resume later without losing context.

---

### What to capture

Collect the following from the current conversation and working state:

1. **Working directory** — the directory where the session was started (`pwd`)
2. **Repos involved** — all repos touched during the session (name + local path); work may span multiple repos (e.g. k-repo + infrastructure-deployment)
3. **Goal** — what problem is being solved or feature being built
4. **Current status** — what has been done so far, what is in progress
5. **Open questions / blockers** — anything unresolved or uncertain
6. **Next steps** — the exact next actions to take when resuming
7. **Key files** — relevant file paths touched or referenced per repo (use `git status` in each repo if helpful)
8. **Key commands** — any commands needed to get back up to speed (e.g. test commands, pants targets, branch names per repo)

---

### File naming

Generate a short slug (2–4 words, hyphen-separated, lowercase) that describes what is being worked on.

Examples:
- `session-msk-consumer-lag.md`
- `session-event-gateway-retry.md`
- `session-prep-publisher-dlq.md`

Save the file to: `~/.claude/sessions/session-{context_name}.md`

---

### Session file format

```markdown
# Session: {Descriptive Title}

**Saved:** {date}
**Working Directory:** {absolute path where session started}

## Repos
| Repo | Local Path | Branch |
|------|-----------|--------|
| {repo name} | {local path} | {branch} |
| {repo name} | {local path} | {branch} |

## Goal
{What you're trying to accomplish}

## Status
{What's done, what's in progress}

## Open Questions / Blockers
- {item}

## Next Steps
1. {First action to take on resume}
2. {Second action}

## Key Files
- `{repo}/{path/to/file.py}` — {why it matters}

## Key Commands
```bash
{commands needed to resume — test commands, validation, appfile-cli, etc.}
```

## Notes
{Any other context worth preserving}
```

---

### Steps

1. Run `pwd` to capture the working directory.
2. For each repo involved, run `git -C {repo_path} branch --show-current` to capture the branch.
3. Collect context from the conversation (ask the user if anything critical is unclear).
4. Generate the `context_name` slug based on what's being worked on.
5. Write the session file to `~/.claude/sessions/session-{context_name}.md`.
6. Confirm to the user: "Session saved to `~/.claude/sessions/session-{context_name}.md`. Run `/kdev-resume` to pick up where you left off."
