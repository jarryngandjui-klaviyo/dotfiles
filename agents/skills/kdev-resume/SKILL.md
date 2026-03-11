---
name: kdev-resume
description: Use when resuming a previously paused Klaviyo dev session — lists saved session files and restores context, repos, branches, and next steps.
user-invocable: true
disable-model-invocation: false
allowed-tools: Read, Glob, Bash
model: sonnet
---

## kdev-resume

Restore a previously saved session so you can pick up exactly where you left off.

---

### Steps

1. **List available sessions:**

   ```bash
   ls -lt ~/.claude/sessions/session-*.md
   ```

   Display each session with:
   - Filename (as the selectable option)
   - **Title** (from the `# Session:` heading)
   - **Saved date**
   - **Goal** (one-line summary)

   Example output to show the user:
   ```
   Available sessions:

   [1] session-msk-consumer-lag.md
       Goal: Add consumer lag metrics to MSK Kafka topic dashboards
       Saved: 2026-03-10

   [2] session-event-gateway-retry.md
       Goal: Implement retry logic for event gateway DLQ
       Saved: 2026-03-08
   ```

2. **Ask the user to pick one** — "Which session would you like to resume? (enter number or filename)"

3. **Load the session file** — Read the full contents of the chosen file.

4. **Restore context** — Present a structured summary:

   - Working directory and all repos with their branches
   - Goal and current status
   - Open questions / blockers
   - Next steps (numbered, ready to act on)
   - Key files and commands

5. **Offer to verify repo state** — Ask: "Would you like me to check the current branch and git status for each repo?"

   If yes, run:
   ```bash
   git -C {repo_path} status --short
   git -C {repo_path} branch --show-current
   ```
   For each repo listed in the session. Flag any drift (e.g. branch differs from what was saved, unexpected uncommitted changes).

6. **Confirm readiness** — End with: "Resuming session: {title}. Ready to continue from: {first next step}."
