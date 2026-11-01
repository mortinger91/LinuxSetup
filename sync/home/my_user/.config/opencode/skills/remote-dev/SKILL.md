---
name: remote-dev
description: >
  MANDATORY skill for ANY mention of: syncing, building, installing, running
  tests, deploying, or checking status on remote build machines
  (proxmox-windows / proxmox-debian). Triggers on phrases like "sync repo on
  windows", "sync to debian", "build on linux", "build on windows", "run the
  headless tests on windows", "install the build on windows", "compare master
  and my branch on windows", "remote status", "what's the build status",
  "stop build", "watch files on remote", or any combination of
  (sync|build|install|test|run|status|push|deploy) + (windows|win|debian|linux|remote).
  NEVER run ssh, scp, rsync, or git directly for these operations — always
  delegate to scripts/rdev. Also use for read-only inspection of a remote
  ("check on windows", "why is the remote dirty", "look at the logs on
  debian"): direct ssh is allowed for that, under the "Read-only diagnostics"
  rules below.
---

# Remote Dev

**ALWAYS run `scripts/rdev` for anything that writes to a remote: sync, branch switch, builds,
installs, tests. Never invent ssh/git/scp/rsync commands for those.** The only exception is
read-only inspection — see "Read-only diagnostics".

## Location

`~/.config/opencode/skills/remote-dev/scripts/rdev`

## Usage

```bash
rdev sync     --machine <windows|debian> [--push|--bundle] [--dry-run]
rdev checkout --machine <windows|debian> --ref BRANCH        # remote to origin/BRANCH
rdev run      --machine <windows|debian> --name NAME (--cmd STRING | --file PATH|-) [--cwd DIR]
rdev wait     --machine <windows|debian> --name NAME [--timeout SEC] [--interval SEC] [--tail N]
rdev status   --machine <windows|debian> [--name NAME]      # no --name: list all jobs
rdev log      --machine <windows|debian> --name NAME [--tail N]
rdev stop     --machine <windows|debian> --name NAME
rdev get      --machine <windows|debian> --name NAME --file FILE --to LOCAL_PATH
```

Every command takes `-h` for details.

## SSH hosts

The Windows box has two ssh config entries:

- `proxmox-windows` — interactive only. Sets `RemoteCommand pwsh -NoLogo`, so
  ssh **refuses** an explicit remote command. Never use it from a script.
- `proxmox-windows-cmd` — same machine, server default shell (cmd.exe). What
  `--machine windows` resolves to and the only host scripts may use.

## Modes: what you may run without asking

**Plan / read-only mode** (or the user only asked to look): read-only diagnostics,
`rdev sync --dry-run`, `rdev status`, `rdev log`. Propose any write as the exact `rdev` command
and wait.

**Build mode**: run the remote work the user asked for without asking at each step, chained as
long as the task needs — including repeated cycles (build → install → test → collect, then the
same on another branch):

- `rdev sync` (without `--push`/`--bundle`), `rdev checkout`.
- `rdev run` jobs that build (`rake stage|windeploy|installer|build_all_tests|test`), install the
  build just made, stop/start the brand's own client and service, run unit or headless tests,
  copy results into `$RDEV_JOB_DIR`.
- `rdev wait`, `rdev status`, `rdev log`, `rdev get`, `rdev stop` on jobs you started.

**Ask first, even in build mode:**

- `rdev sync --push` (irreversible push) or `--bundle`.
- Anything destructive outside a job's own output: `git reset --hard|clean|stash` on the remote,
  deleting files outside `out/`, `rdev-jobs/` and test-result files, uninstalling anything other
  than the brand under test, registry or system settings, reboots, `rdev stop` on a job you
  did not start.
- Fixing code because a build or test failed. Report, don't fix, unless asked.

Writes never go over ad-hoc ssh, even in build mode: `rdev run` is what gives a log, an exit
code, survival across disconnects and the retry behavior below.

## Jobs

`rdev run` starts a detached job and returns at once. It lives in `~/rdev-jobs/<name>/` on the
remote (outside the repo, so git stays clean) with `out.log`, `exit`, `pid`, `started`, and
outlives the ssh session (Windows: launched through WMI; Linux: setsid + nohup).

- **Body:** PowerShell 5.1 on Windows, bash on Linux. Working dir defaults to the remote repo
  root. Windows jobs run elevated, without a desktop (same as ssh).
- **Exit code:** the script's last native exit code, or its explicit `exit N`. On Linux add
  `set -e` (or check `$?`) when a middle step must stop the job.
- **Artifacts:** copy files to `$RDEV_JOB_DIR` (`$env:RDEV_JOB_DIR` on Windows), then
  `rdev get --file <name> --to <local path>`. Fetch into a scratch dir (the session's temp dir),
  never into the repo.
- **One job per name at a time** (exit 43). Reusing a finished name wipes its old dir. Use
  descriptive names that keep runs apart: `build-branch`, `install-master`, `headless-branch`.
- **Branch switches:** `rdev checkout` refuses while any job runs (43) or the remote repo is dirty
  (10). Afterwards `rdev sync` switches back to the local branch; if sync refuses with 11 (local
  ahead of origin), `rdev checkout --ref <local branch>` restores origin's tip of it instead —
  say so in the report.

### Waiting

`rdev wait` polls every 30 s and prints a progress line every ~2 min. Exit 0 = job exit 0,
44 = non-zero (code printed), 41 = died, 40 = still running when `--timeout` hit. Give the Bash
tool a timeout at least 120 s longer than `--timeout`, and call `wait` again while it returns 40.
Builds take 15–60 min, headless suites anywhere from minutes to hours: prefer
`--timeout 1500` with a 1700000 ms tool timeout. Do not poll with `status` in a loop.

## Retries

- **ssh/scp connection failures** are retried inside rdev (6 attempts, backoff 5–60 s), and
  `wait` keeps polling through outages until its own timeout. `checkout` also retries a failed
  `git fetch`.
- **`rdev sync` is not retried internally.** On exit 20, rerun it up to 3 times, 30 s apart.
- **A job failed (44 or 41): read the log tail before anything else.**
  - Network failure — DNS, connection reset/refused/timed out, TLS handshake, failed download,
    `bundle install`/gem fetch, `git fetch`, the VPN API unreachable, a connect that timed out
    before the tunnel came up: rerun the same job, up to 3 attempts total, 60 s apart. For test
    jobs rerun only the failed examples (`rspec file.rb:LINE` or `-e "name"`), not the suite.
  - Anything else (compile error, assertion failure, crash): stop the cycle there and report.
  - Report what needed a retry: a test that only passes on retry is flaky, say so.

## Recipes

Take brand, variant, arch, Qt root and cores from the remote `.vscode/settings.json` (read it
with a read-only diagnostic). Windows values at the time of writing: `BRAND=xvn VARIANT=debug
ARCHITECTURE=x86_64 QTROOT=C:/Qt/Qt6.5.9-mod/6.5.9 -j10`.

**Windows: build the installer**
```powershell
rake installer QTROOT=C:/Qt/Qt6.5.9-mod/6.5.9 -j10 BRAND=xvn VARIANT=debug ARCHITECTURE=x86_64
```

**Windows: install it** (the installer takes `/SILENT`; jobs are already elevated)
```powershell
Get-Process expressvpn-client -ErrorAction SilentlyContinue | Stop-Process -Force
$installer = Get-ChildItem out\xvn_debug_x86_64\installer -Filter *.exe |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
$process = Start-Process -FilePath $installer.FullName -ArgumentList '/SILENT' -Wait -PassThru
exit $process.ExitCode
```

**Headless specs, keeping the results**
```powershell
Set-Location headless_tests
bundle exec rspec splittunnel_spec.rb monitor_spec.rb
$rspecExit = $LASTEXITCODE
Copy-Item test_results.json, test_results.xml $env:RDEV_JOB_DIR
exit $rspecExit
```
Headless specs need an admin shell (jobs are) and a logged-in app; feature flags gate some
contexts, so check the log for skips before calling a result a regression.

**Comparing a branch against master** — one cycle per ref, distinct job names:
1. `rdev sync` → `run build-branch` → `wait` → `run install-branch` → `wait` →
   `run headless-branch` → `wait` → `get test_results.json`.
2. `rdev checkout --ref master` → the same three jobs as `*-master` → `get`.
3. `rdev sync` back to the branch (see "Branch switches" if it refuses).
4. Compare the two JSON files example by example: passed on master and failing on the branch =
   regression; new examples reported separately; skips that differ called out.

## Rules

1. Run the script verbatim. Report stdout/stderr verbatim.
2. On non-zero exit, show the exit code and the script's last message. Retry only as described
   under "Retries"; otherwise no interpretation, suggestions or fix attempts unless asked.
3. Do not run `git`, `ssh`, `scp`, or `rsync` directly for anything that writes — go through
   `rdev`. Direct `ssh` is allowed only for read-only diagnostics.
4. Do not modify the local repo to "prepare" a sync or a run. If sync refuses, surface the
   refusal and wait (or use `checkout` as described above when restoring after a comparison).
5. One build or test job per machine at a time unless the user asks otherwise; they share
   `out/`, the installed app and the VPN connection.

## Read-only diagnostics (direct ssh allowed)

For investigating a remote (git state, logs, config, files, event logs) you may ssh directly,
without asking. Only these hosts and repo paths:

| Machine | Host | Repo |
|---|---|---|
| windows | `proxmox-windows-cmd` | `$HOME\dev\pia_desktop` |
| debian | `proxmox-debian` | `~/dev/pia_desktop` |

**Allowed** — anything that only reads:
- `git --no-optional-locks status|log|reflog|diff|show|ls-files|branch|rev-parse|merge-base`,
  `git config --get*`/`--list`, `git lfs status|ls-files|env`. Always pass
  `--no-optional-locks` so `status` doesn't rewrite the index.
- Listing and reading files (`Get-ChildItem`, `Get-Content`, `Select-String`, `ls`, `cat`, `rg`),
  disk usage, process lists, app/daemon logs, `Get-WinEvent`/`journalctl`, shell history.

**Forbidden over direct ssh** — anything that writes: `git fetch|pull|checkout|switch|reset|
stash|clean|commit|config <set>`, `git lfs pull|fetch`, creating/deleting/moving files, builds,
service start/stop, installs, registry writes. Those go through `rdev` (see "Modes").

**Windows invocation.** The server shell is cmd.exe, and nesting PowerShell quotes inside it
breaks on `'`, `|`, `\` and `$`. Send the script base64-encoded instead:

```bash
PS=$(cat <<'EOF'
Set-Location $HOME\dev\pia_desktop
git --no-optional-locks status --porcelain=v1 | Select-Object -First 30
EOF
)
ENC=$(printf '%s' "$PS" | iconv -t UTF-16LE | base64)
ssh -o ConnectTimeout=10 proxmox-windows-cmd "powershell -NoProfile -EncodedCommand $ENC" 2>&1 \
  | sed '/^#< CLIXML/d;/^<Objs/d'
```

The `sed` drops the CLIXML progress noise `-EncodedCommand` emits on stderr. For wide tables add
`| Out-String -Width 250`, or PowerShell truncates columns.

**Debian invocation:** `ssh -o ConnectTimeout=10 proxmox-debian 'cd ~/dev/pia_desktop && ...'`.

**Secrets.** Config and env output can hold credentials (e.g. a token embedded in `lfs.url` or a
remote URL). Never echo them back: filter those keys out, or redact `user:token@` before showing
output. If one turns up, tell the user it is there and that it should be revoked.

## Exit codes (script-defined)

```
 0  success
10  remote dirty with files not safe to overwrite
11  local has unpushed commits (use --push or --bundle)
12  local branch not on origin
14  remote pull --ff-only failed / remote git fetch failed
15  remote diverged (HEAD not ancestor of origin/branch)
20  ssh failure (after retries)
21  local git error / remote command failed
22  file transfer failed (after retries)
30  usage error
40  wait timed out, job still running
41  job died without writing an exit code
42  job not found
43  job already running
44  job finished with a non-zero exit code
```

## Validation

- `scripts/tests/test_sync.sh` — 19 tests, 47 assertions. Run after any change to `lib/sync.sh`,
  `lib/state.sh`, `lib/transfer.sh`.
- After a change to `lib/jobs.sh`, smoke-test on both machines: `run --cmd` a job that prints,
  sleeps and exits 3 → `wait` returns 44 with the log tail; a second `run` with the same name
  while it runs returns 43; `stop` a long job; `get` an artifact; remove the smoke job dirs.
