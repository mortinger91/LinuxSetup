# remote-dev skill

Sync local repo to a remote build machine and run the remote's `stop_all_and_stage_build` task. Built for the pia_desktop workflow with two remotes: `proxmox-windows` and `proxmox-debian`.

**Core invariant:** local and remote repos must always have the same branch checked out, the same commit at HEAD, and the same working-tree contents.

**Build runs async:** after launch, control returns to the user immediately. The agent announces the result when the build completes.

## Triggers

Any of:
- "test on windows" / "build on windows" / "move to windows"
- "test on linux" / "build on linux" / "move to linux"
- "sync to <machine>" / "deploy to <machine>"
- "try on the <windows|linux> box"
- "remote build"
- "develop on <machine>" / "work on <machine> for a bit" → activates continuous sync mode

## What it does

1. Probes SSH (≤10s). Aborts cleanly if unreachable.
2. Reads local git state: branch, HEAD, dirty file list, whether HEAD matches `origin/<branch>`.
3. Reads remote git state on `~/dev/pia_desktop` (Linux) or `%USERPROFILE%\dev\pia_desktop` (Windows): branch, HEAD, dirty status.
4. **Aborts** if remote has uncommitted changes the agent didn't make.
5. Reports and checks out the local branch on the remote if branches differ.
6. **Reconciles commits + working tree to match local**, via a 3-flag decision matrix:
   - `NEEDS_PULL`  = local HEAD ≠ remote HEAD
   - `NEEDS_RSYNC` = local has uncommitted working-tree changes
   - `UNPUSHED`   = local HEAD ≠ origin HEAD (commits not shared yet)

   | UNPUSHED | NEEDS_PULL | NEEDS_RSYNC | Action |
   |----------|------------|-------------|--------|
   | no       | no         | no          | nothing — already in sync |
   | no       | no         | yes         | rsync only |
   | no       | yes        | no          | `git pull --ff-only` on remote |
   | no       | yes        | yes         | **pull THEN rsync** (pull first so dirty files land on the right commit) |
   | yes      | *          | *           | STOP and ask: push+pull / git bundle transfer / abort |

7. Resolves the `stop_all_and_stage_build` task from remote `.vscode/tasks.json` — walks its `dependsOn` chain (`daemon_service_stop_impl` → `daemon_kill` → `client_kill` → `stage_build`), picks OS-specific commands, substitutes `${config:*}` from remote `.vscode/settings.json` and `${workspaceFolder}` = remote repo root.
8. Launches the resolved chain via the **Task tool** (general subagent) so it runs in background. Pre-steps run inline (fast); the long rake build runs async.
9. Returns control to the user with a one-liner: `Build launched on <machine> in background. I'll announce when it's done.`
10. When the subagent returns, announces a fixed-format block: branch, all three HEADs (local/remote/origin), sync method, pre-build step status, build result + exit code, elapsed, log path, error tail.

## Continuous sync mode

Activated by "develop on <machine>" or after the first successful build/sync. Once active:

- After **every** local Edit/Write tool call that touches a file under the repo root, the agent immediately rsyncs that single file to the remote (silent — only speaks on failure).
- Local commits are NOT auto-pushed to origin. They sit locally until the next sync trigger, at which point the UNPUSHED branch asks the user.
- Maintains the invariant: same branch, same HEAD, same working tree on both sides.
- Exit when user says "back to local", "stop syncing", or switches machines.

## Key implementation notes

- **Two SSH hosts for one Windows box.** `proxmox-windows` sets `RemoteCommand pwsh -NoLogo` (interactive use only — ssh rejects an explicit command when `RemoteCommand` is set). `proxmox-windows-cmd` is the same machine with no `RemoteCommand`; it is what `rdev_resolve_host windows` returns and the only one scripts may use.
- **Windows SSH default shell is cmd.exe** — every remote command must be `ssh proxmox-windows-cmd powershell -NoProfile -Command "..."`. Bare `ssh proxmox-windows-cmd "ls"` breaks.
- **tasks.json + settings.json are JSONC** (line comments, trailing commas). Strip before parsing.
- **Variables are resolved from the REMOTE settings.json**, never the local one. `${workspaceFolder}` = remote repo root. Unresolved `${config:*}` → STOP (never silently empty).
- **`git pull` is allowed** but only inside Step 4's NEEDS_PULL branch, with `--ff-only` to guard against accidental merges.
- **Never auto-push.** The push+pull path needs explicit user confirmation and a user-supplied commit message.
- **Build is async.** Always hand off the rake build via the Task tool. Only the fast stop/kill pre-steps run inline. Never block the main conversation on a long build.
- **One build per machine at a time.** Queue a second request, don't race.
- **No `sudo` on the build itself** — `rake stage` / `rake windeploy` runs as the user. The stop/kill/service pre-steps may need sudo for service control only.

## Files

- `SKILL.md` — full workflow loaded into the agent context when the skill triggers.

## Adding more remotes

Add a row to the host table in `SKILL.md` with: alias, SSH host, OS, repo path, shell wrapper. No other changes needed.
