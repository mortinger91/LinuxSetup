---
name: jira
description: Read and create Jira tickets in the KDT project (polymoon.atlassian.net, Desktop Team board 2336). Use when the user says "jira", "ticket", "KDT-1234", "make/create/open/file a ticket", "make a bug ticket", "what's in KDT-…", "show my tickets", or pastes a polymoon.atlassian.net link.
---

# Jira (KDT)

Tools: `jira` (jira-cli, already configured for KDT / board 2336) for reading;
`scripts/jira-create` (REST, uses `template.json`) for creating. Auth: `JIRA_API_TOKEN` env var.

## Reading

```bash
jira issue view KDT-1234 --plain                 # summary, status, description
jira issue view KDT-1234 --plain --comments 10   # with comments
jira issue view KDT-1234 --raw | jq '.fields'    # every field, for exact values
jira issue list --plain -a"$(jira me)" -s"Ready to Start"
jira issue list --plain -q 'project = KDT AND text ~ "force update"'
```

For a URL like `.../boards/2336?selectedIssue=KDT-1234` or `.../browse/KDT-1234`, read the key.

## Creating

Only create a ticket when the user asks for one. Run `scripts/jira-create` (path relative to this
skill dir) and **paste the printed ticket URL in the reply**. Every ticket is automatically:

- project KDT, assigned to Michele, no reviewer
- component Qt only (fixed, never changed), priority Normal, Brand ExpressVPN,
  Device and OS Desktop / <platform>
- moved to **Ready to Start** (shows in that board column)
- no epic/parent unless the user names one (`--parent KDT-XXXX`)

### Type: task or bug

Decide from the context of the request:

- **Bug** (`-t bug`): the user says "bug", or describes a defect: something broken, crashing, wrong
  behavior, a regression.
- **Task** (default): everything else, e.g. features, refactors, chores, investigations, follow-ups.

### Platform (`--os`, required)

Infer it from the ticket's context:

- `cross` (Core / Cross): the work or bug is in shared code, e.g. `daemon/`, `common/`,
  `client/`, `clientlib/`, `kapps_*`, `cli/`, or shared QML, and it isn't tied to one OS.
- `linux` / `windows` / `macos`: the work or bug is platform-specific. Signs: the user names the
  OS, the code lives in platform dirs (`*/linux/`, `*/win/`, `*/mac/`, `extras/installer/<os>`),
  or it touches OS mechanisms (systemd, iptables, WFP, SMJobBless, launchd, etc.).
- **Unsure? Ask the user before creating.** Don't guess.

### Bug-only fields

- **Severity** (`--severity`): infer it from the context. If you're unsure, use S3.
  - S1 Catastrophic: crash on launch, data loss, security issue, or a leak with the VPN down. No workaround.
  - S2 Severe: a core feature is broken (connect, login, updates) and there's no reasonable workaround.
  - S3 Moderate: a feature is broken or degraded but a workaround exists, or it only affects a limited path.
  - S4 Minor: a small functional issue with low impact.
  - S5 Cosmetics: visual or text-only.
- **Environment** (`--env`): Production by default. Use `--env during-dev` (Development / During
  Dev) only when the user says it was found during development.

### Other overrides

Set these only when the context clearly calls for them:

- `--label NAME`, `--priority NAME`.

### Writing the ticket

- Summary: imperative, concise, no `KDT-` prefix, e.g. "Relaunch the client after a Linux force update".
- Description: Jira wiki markup (`h3.`, `*`, `{code}`), short. For bugs, cover steps,
  expected vs actual, and platform/version if known. For tasks, cover the goal and the done
  criteria. If you have repo context (branch, diff), use it, but don't paste code dumps.
- Multi-line descriptions: pass them on stdin with `-d -` and a quoted heredoc.

```bash
scripts/jira-create --os linux -s "Relaunch the client after a Linux force update" -d - <<'EOF'
After a forced update on Linux the client stays closed.
h3. Done when
* Client relaunches automatically once the update finishes
EOF

scripts/jira-create -t bug --severity S2 --os cross -s "Connect hangs after resume from sleep" -d - <<'EOF'
...
EOF
```

`--dry-run` prints the payload without creating anything. If the create fails, show the error and
don't retry blindly. If you see a "no transition" warning, the ticket was still created: paste the
URL and mention that it's not in Ready to Start.
