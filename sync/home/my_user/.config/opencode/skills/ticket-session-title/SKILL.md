---
name: ticket-session-title
description: Rename the opencode session to the Jira ticket it is about ("Review: KDT-1234 <summary>" or "Implement: KDT-1234 <summary>"). Use at the START of any session where the user asks to work on, implement, pick up, start, fix, or review a KDT ticket or its PR, e.g. "work on KDT-1234", "let's do KDT-1234", "review KDT-1234", "review the PR for KDT-1234", a polymoon.atlassian.net link, or "review this branch/PR" whose branch or PR title carries a KDT key. Runs alongside the jira / pr-review skills, not instead of them.
---

# Ticket session title

Put the ticket key and name in the session title, then carry on with the actual task.

## Steps

1. **Get the key.** In order: the user's message (`KDT-1234`, or `selectedIssue=` / `/browse/` in a
   URL), the PR title, the branch name (`git branch --show-current`). No key found: skip silently.
2. **Get the summary:**
   ```bash
   jira issue view KDT-1234 --raw | jq -r '.fields.summary'
   ```
   Strip leading bracket tags like `[Qt]`. If jira fails, use the PR title (minus the `KDT-XXXX:`
   prefix); if that is missing too, use the key alone.
3. **Rename** with the `session_title` tool:
   - review (ticket, PR, branch): `Review: KDT-1234 Add a CLI command to trigger an app auto-update`
   - do / implement / work on / fix: `Implement: KDT-1234 Add a CLI command to trigger an app auto-update`
   - Multiple tickets: `Implement: KDT-1234, KDT-1240 <first summary>`.
4. Don't mention the rename unless it failed. Do it once per session; re-run only if the session
   moves on to a different ticket.

If the `session_title` tool isn't available, the `session-title` plugin isn't loaded
(`~/.config/opencode/plugins/session-title/plugin.js`, listed in `opencode.json` `plugin`): tell
the user once and continue with the task.
