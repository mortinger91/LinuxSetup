## Project memory files — hard rule

When working inside a git repo (or any cwd that is a project root), ALWAYS
check for and read both of these files at the start of every session, before
doing any other work:

- `CLAUDE.md` (shared, committed project instructions)
- `CLAUDE.local.md` (personal, uncommitted; trumps the shared file)

If neither exists, skip silently. If only one exists, read that one.

**Conflict resolution:** when the two files disagree, `CLAUDE.local.md` wins.
Treat `CLAUDE.local.md` as the authoritative override on top of `CLAUDE.md`;
`CLAUDE.md` is the baseline, `CLAUDE.local.md` is the patch.

Note: opencode's built-in auto-loader only picks up `CLAUDE.md` (not
`CLAUDE.local.md`), and even then only as a fallback when `AGENTS.md` is
absent. This rule exists to guarantee `CLAUDE.local.md` is always read and
always takes precedence — regardless of what opencode auto-loads.

## Skill routing — hard rules

**remote-dev skill is MANDATORY** for any of these phrases or intents:

- "sync <repo/code/files> (to|on|with) <windows|win|debian|linux|remote>"
- "build on <windows|debian|linux>"
- "what's the build status", "remote status", "check the build"
- "stop the build", "kill the build"
- "watch files on remote", "continuous sync"
- ANY combination of (sync|build|deploy|push|status) + (windows|win|debian|linux|proxmox|remote)

**NEVER** run `ssh`, `scp`, `rsync`, or `git` directly for these operations.
**ALWAYS** invoke the skill first; the skill runs `scripts/rdev` which is the
only source of truth. Running ssh/git inline bypasses all safety checks,
marker logic, and divergence detection — it is forbidden for anything that
writes to the remote, however small.

**Exception — read-only diagnostics:** after loading the skill, direct `ssh`
is allowed for inspection that only reads (git state, logs, files, config), as
defined in the skill's "Read-only diagnostics" section. Any write still goes
through `rdev` or the user.

If the user mentions a remote machine keyword and the skill has not been
loaded yet, **load it before doing anything else**. Do not start probing SSH
or git state before the skill is loaded.

**fixup skill is MANDATORY** for any of these phrases or intents:

- "fixup", "fix up", "fixup commits", "fixup the changes", "fixup into commits"
- "absorb (these changes) into (the) commits", "fold changes into the right commits"
- ANY request to distribute working-dir changes into existing branch commits

**ALWAYS** load the skill and go through `scripts/fixup-hunks`. **NEVER** run
`git commit --fixup`, `git add -p`, `git apply`, or `git absorb` inline for
this. **NEVER sign fixup commits** (no `-S`/`--gpg-sign`; the script forces
signing off). Never rebase, autosquash, or push as part of a fixup — the user
squashes.
