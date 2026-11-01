# shellcheck shell=bash
# rdev — remote jobs: run detached commands, wait with network retries, fetch artifacts,
# switch the remote to another branch.
#
# A job lives in ~/rdev-jobs/<name>/ on the remote, outside the repo so it never dirties git:
#   script.ps1|script.sh  job body           out.log  stdout + stderr
#   pid                   launcher pid       exit     exit code, written last
#   started               start time         run.cmd|run.sh  launcher
#
# Jobs outlive the ssh session: Windows sshd kills its session's process tree on disconnect, so
# Windows jobs are created through WMI (Win32_Process.Create); Linux jobs use setsid + nohup.
#
# Exit codes (on top of the ones in rdev):
#   40 wait timed out, job still running     43 job with this name already running
#   41 job died without writing an exit code 44 job finished with a non-zero exit code
#   42 job not found

RDEV_SSH_RETRIES="${RDEV_SSH_RETRIES:-6}"
RDEV_SSH_OPTS=(-A -n -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15
               -o ServerAliveCountMax=4)

# Seconds to wait before retry N: 5, 10, 20, 40, 60, 60...
rdev_backoff() {
    local attempt="$1" seconds=5
    while [[ $attempt -gt 1 ]]; do seconds=$((seconds * 2)); attempt=$((attempt - 1)); done
    [[ $seconds -gt 60 ]] && seconds=60
    echo "$seconds"
}

rdev_fmt_secs() {
    local secs="${1:-0}"
    printf '%dm%02ds' $((secs / 60)) $((secs % 60))
}

# Value of `key=value` in a block of lines.
rdev_kv() {
    printf '%s\n' "$2" | sed -n "s/^$1=//p" | head -1
}

# Single-quote a value for PowerShell ('' escapes ') or bash ('\'' escapes ').
rdev_ps_quote()   { local value="${1//\'/\'\'}"; printf "'%s'" "$value"; }
rdev_bash_quote() { local value="${1//\'/\'\\\'\'}"; printf "'%s'" "$value"; }

# Run a script on the remote, retrying while ssh itself fails (exit 255 = connection error).
# PowerShell on Windows, bash on Linux. Prints the remote stdout; returns its exit code, or 20.
# Args: host os script
rdev_remote_exec() {
    local host="$1" os="$2" script="$3"
    local encoded remote_cmd out rc attempt=1 delay errf
    errf="$(mktemp "${TMPDIR:-/tmp}/rdev-err.XXXXXX")"
    if [[ "$os" == "windows" ]]; then
        # UTF-8 back over ssh; the console default (OEM code page) mangles non-ASCII output.
        script='[Console]::OutputEncoding = [Text.Encoding]::UTF8'$'\n'"$script"
        encoded="$(printf '%s' "$script" | /usr/bin/iconv -t UTF-16LE | /usr/bin/base64 | tr -d '\n')"
        remote_cmd="powershell -NoProfile -NonInteractive -EncodedCommand $encoded"
    else
        encoded="$(printf '%s' "$script" | /usr/bin/base64 | tr -d '\n')"
        remote_cmd="echo $encoded | base64 -d | bash"
    fi
    while :; do
        out="$(/usr/bin/ssh "${RDEV_SSH_OPTS[@]}" "$host" "$remote_cmd" 2>"$errf")"
        rc=$?
        [[ $rc -ne 255 ]] && break
        if [[ $attempt -ge $RDEV_SSH_RETRIES ]]; then
            echo "rdev: ssh to $host failed after $attempt attempts: $(tail -1 "$errf")" >&2
            rm -f "$errf"
            return 20
        fi
        delay="$(rdev_backoff "$attempt")"
        echo "rdev: ssh to $host failed (attempt $attempt/$RDEV_SSH_RETRIES), retrying in ${delay}s" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
    done
    out="${out//$'\r'/}"
    [[ -n "$out" ]] && printf '%s\n' "$out"
    # -EncodedCommand writes CLIXML progress records to stderr; only real errors are shown.
    [[ $rc -ne 0 ]] && sed '/^#< CLIXML/d;/^<Objs/d' "$errf" >&2
    rm -f "$errf"
    return $rc
}

# scp with retries on any failure. Remote paths are relative to the remote home.
# Args: src dst
rdev_scp_retry() {
    local src="$1" dst="$2" attempt=1 delay errf
    errf="$(mktemp "${TMPDIR:-/tmp}/rdev-err.XXXXXX")"
    while ! /usr/bin/scp -q -T -o BatchMode=yes -o ConnectTimeout=15 "$src" "$dst" 2>"$errf"; do
        if [[ $attempt -ge $RDEV_SSH_RETRIES ]]; then
            echo "rdev: scp $src -> $dst failed after $attempt attempts: $(tail -1 "$errf")" >&2
            rm -f "$errf"
            return 22
        fi
        delay="$(rdev_backoff "$attempt")"
        echo "rdev: scp failed (attempt $attempt/$RDEV_SSH_RETRIES), retrying in ${delay}s" >&2
        sleep "$delay"
        attempt=$((attempt + 1))
    done
    rm -f "$errf"
}

# Resolve --machine into "host<TAB>os". Returns 30 on an unknown machine.
rdev_jobs_target() {
    local cmd="$1" machine="$2" host
    [[ -n "$machine" ]] || { echo "rdev $cmd: --machine is required" >&2; return 30; }
    host="$(rdev_resolve_host "$machine")" || {
        echo "rdev $cmd: unknown machine '$machine'" >&2; return 30; }
    printf '%s\t%s\n' "$host" "$(rdev_host_os "$host")"
}

rdev_check_name() {
    local cmd="$1" name="$2"
    [[ -n "$name" ]] || { echo "rdev $cmd: --name is required" >&2; return 30; }
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "rdev $cmd: job name may only use letters, digits, '.', '_' and '-'" >&2; return 30; }
}

# --- Remote scripts --------------------------------------------------------------------------
# Each one is prefixed with a prelude that sets $rdevName / $rdevCwd / ... (PowerShell) or
# RDEV_NAME / RDEV_CWD / ... (bash), so values never go through pattern substitution.

# Shared status function. Prints key=value lines for one job.
read -r -d '' RDEV_PS_STATUS_FN <<'EOF'
function Get-RdevJob($job) {
    if (-not (Test-Path $job)) { return @('state=missing') }
    $exitCode = ''; if (Test-Path "$job\exit") { $exitCode = (Get-Content "$job\exit" -Raw).Trim() }
    $jobPid = ''; if (Test-Path "$job\pid") { $jobPid = (Get-Content "$job\pid" -Raw).Trim() }
    $startedAt = Get-Date; if (Test-Path "$job\started") { $startedAt = (Get-Item "$job\started").LastWriteTime }
    if ($exitCode -ne '') { $state = 'done'; $end = (Get-Item "$job\exit").LastWriteTime }
    elseif ($jobPid -and (Get-Process -Id $jobPid -ErrorAction SilentlyContinue)) { $state = 'running'; $end = Get-Date }
    else { $state = 'died'; $end = Get-Date }
    $last = ''
    if (Test-Path "$job\out.log") { $last = "$(Get-Content "$job\out.log" -Tail 1 -Encoding UTF8)" }
    if ($last.Length -gt 200) { $last = $last.Substring(0, 200) }
    @("state=$state", "exit=$exitCode", "pid=$jobPid", "started=$($startedAt.ToString('s'))",
      "elapsed=$([int]($end - $startedAt).TotalSeconds)", "last=$last")
}
EOF

read -r -d '' RDEV_SH_STATUS_FN <<'EOF'
rdev_job_status() {
    local job="$1" exit_code="" pid="" state end start last
    [ -d "$job" ] || { echo state=missing; return; }
    [ -f "$job/exit" ] && exit_code="$(cat "$job/exit")"
    [ -f "$job/pid" ] && pid="$(cat "$job/pid")"
    if [ -n "$exit_code" ]; then state=done; end="$(stat -c %Y "$job/exit")"
    elif [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then state=running; end="$(date +%s)"
    else state=died; end="$(date +%s)"; fi
    start="$(stat -c %Y "$job/started" 2>/dev/null || echo "$end")"
    last="$(tail -n 1 "$job/out.log" 2>/dev/null | cut -c1-200)"
    echo "state=$state"; echo "exit=$exit_code"; echo "pid=$pid"
    echo "started=$(cat "$job/started" 2>/dev/null)"; echo "elapsed=$((end - start))"; echo "last=$last"
}
EOF

# --- run -------------------------------------------------------------------------------------

rdev_run_usage() {
    cat <<EOF
Usage: rdev run --machine <windows|debian> --name NAME (--cmd STRING | --file PATH|-) [--cwd DIR]

Starts NAME as a detached job on the remote and returns. Windows jobs are PowerShell,
Linux jobs are bash. The job exit code is the script's last native exit code (or its
explicit 'exit N'). \$RDEV_JOB_DIR (env) is the job dir: copy artifacts there for 'rdev get'.

  --cmd STRING   Job body inline
  --file PATH    Job body from a local file ('-' = stdin)
  --cwd DIR      Remote working dir (default: the remote repo root)
EOF
}

rdev_run() {
    local machine="" name="" cwd="" file="" cmd_str="" have_cmd=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --name)    name="$2";    shift 2 ;;
            --cwd)     cwd="$2";     shift 2 ;;
            --file)    file="$2";    shift 2 ;;
            --cmd)     cmd_str="$2"; have_cmd=1; shift 2 ;;
            -h|--help) rdev_run_usage; return 0 ;;
            *) echo "rdev run: unknown option: $1" >&2; rdev_run_usage >&2; return 30 ;;
        esac
    done
    local target host os
    target="$(rdev_jobs_target run "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    rdev_check_name run "$name" || return $?
    if [[ $have_cmd -eq 1 && -n "$file" ]] || [[ $have_cmd -eq 0 && -z "$file" ]]; then
        echo "rdev run: pass exactly one of --cmd or --file" >&2; return 30
    fi

    local body
    if [[ $have_cmd -eq 1 ]]; then
        body="$cmd_str"
    elif [[ "$file" == "-" ]]; then
        body="$(cat)"
    else
        [[ -f "$file" ]] || { echo "rdev run: no such file: $file" >&2; return 30; }
        body="$(cat "$file")"
    fi

    # 1. Refuse if the same job is still running, otherwise reset its dir.
    local prelude prepare launch ext out rc
    if [[ "$os" == "windows" ]]; then
        ext="ps1"
        prelude="\$rdevName = $(rdev_ps_quote "$name"); \$rdevCwd = $(rdev_ps_quote "$cwd")"
        read -r -d '' prepare <<'EOF'
$job = Join-Path $HOME "rdev-jobs\$rdevName"
if ((Test-Path "$job\pid") -and -not (Test-Path "$job\exit")) {
    $jobPid = (Get-Content "$job\pid" -Raw).Trim()
    if (Get-Process -Id $jobPid -ErrorAction SilentlyContinue) { 'RUNNING'; exit 0 }
}
if (Test-Path $job) { Remove-Item -LiteralPath $job -Recurse -Force }
New-Item -ItemType Directory -Force -Path $job | Out-Null
'READY'
EOF
        # run.cmd: cmd redirection streams the log unbuffered; '(echo N)>' avoids 'echo 7>'
        # being parsed as a handle-7 redirect. exit.tmp + move makes the exit file atomic.
        read -r -d '' launch <<'EOF'
$job = Join-Path $HOME "rdev-jobs\$rdevName"
$cwd = $rdevCwd
if (-not $cwd) { $cwd = Join-Path $HOME 'dev\pia_desktop' }
$runCmd = @"
@echo off
chcp 65001 >nul
set "RDEV_JOB_DIR=%~dp0"
cd /d "$cwd" || ((echo rdev: cannot cd to $cwd)> "%~dp0out.log" & (echo 99)> "%~dp0exit" & exit /b 99)
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "[Console]::OutputEncoding = [Text.Encoding]::UTF8; & '%~dp0script.ps1'; exit `$LASTEXITCODE" > "%~dp0out.log" 2>&1
(echo %ERRORLEVEL%)> "%~dp0exit.tmp"
move /y "%~dp0exit.tmp" "%~dp0exit" >nul
"@
Set-Content -LiteralPath "$job\run.cmd" -Value $runCmd -Encoding Ascii
Set-Content -LiteralPath "$job\started" -Value (Get-Date -Format o)
$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine = "cmd.exe /d /c `"$job\run.cmd`""; CurrentDirectory = $HOME }
if ($result.ReturnValue -ne 0) { "LAUNCH_FAILED rv=$($result.ReturnValue)"; exit 1 }
Set-Content -LiteralPath "$job\pid" -Value $result.ProcessId
"pid=$($result.ProcessId)"
EOF
    else
        ext="sh"
        prelude="RDEV_NAME=$(rdev_bash_quote "$name"); RDEV_CWD=$(rdev_bash_quote "$cwd")"
        read -r -d '' prepare <<'EOF'
job="$HOME/rdev-jobs/$RDEV_NAME"
if [ -f "$job/pid" ] && [ ! -f "$job/exit" ] && kill -0 "$(cat "$job/pid")" 2>/dev/null; then
    echo RUNNING; exit 0
fi
rm -rf "$job"; mkdir -p "$job"; echo READY
EOF
        read -r -d '' launch <<'EOF'
job="$HOME/rdev-jobs/$RDEV_NAME"
cwd="${RDEV_CWD:-$HOME/dev/pia_desktop}"
cat > "$job/run.sh" <<RUN
#!/usr/bin/env bash
export RDEV_JOB_DIR="$job"
cd "$cwd" || { echo "rdev: cannot cd to $cwd" > "$job/out.log"; echo 99 > "$job/exit"; exit 99; }
bash "$job/script.sh" > "$job/out.log" 2>&1
echo \$? > "$job/exit.tmp"; mv "$job/exit.tmp" "$job/exit"
RUN
date -Iseconds > "$job/started"
setsid nohup bash "$job/run.sh" > /dev/null 2>&1 < /dev/null &
echo $! > "$job/pid"; echo "pid=$!"
EOF
    fi

    out="$(rdev_remote_exec "$host" "$os" "$prelude"$'\n'"$prepare")"; rc=$?
    [[ $rc -eq 20 ]] && return 20
    [[ $rc -eq 0 ]] || { echo "rdev run: could not prepare the job dir on $machine: $out" >&2; return 21; }
    if [[ "$out" == *RUNNING* ]]; then
        echo "STOP: job '$name' is still running on $machine. Wait for it or 'rdev stop' it." >&2
        return 43
    fi

    # 2. Upload the body. PowerShell 5.1 reads BOM-less UTF-8 as ANSI, so add a BOM.
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/rdev-job.XXXXXX")"
    if [[ "$os" == "windows" ]]; then
        { printf '\xEF\xBB\xBF'; printf '%s\n' "$body"; } > "$tmp"
    else
        printf '%s\n' "$body" > "$tmp"
    fi
    rdev_scp_retry "$tmp" "$host:rdev-jobs/$name/script.$ext" || { rm -f "$tmp"; return 22; }
    rm -f "$tmp"

    # 3. Launch detached.
    out="$(rdev_remote_exec "$host" "$os" "$prelude"$'\n'"$launch")"; rc=$?
    if [[ $rc -ne 0 || "$out" != *pid=* ]]; then
        echo "rdev run: launch failed on $machine: $out" >&2
        return 21
    fi
    echo "started job=$name machine=$machine pid=$(rdev_kv pid "$out")"
}

# --- status / log / wait / stop / get ---------------------------------------------------------

# Status of one job (key=value lines), or of every job ("name state exit elapsed" rows) when
# name is empty. Args: host os name
rdev_job_status_raw() {
    local host="$1" os="$2" name="$3" script
    if [[ "$os" == "windows" ]]; then
        script="\$rdevName = $(rdev_ps_quote "$name")"$'\n'"$RDEV_PS_STATUS_FN"$'\n'
        script+='if ($rdevName) { Get-RdevJob (Join-Path $HOME "rdev-jobs\$rdevName"); exit 0 }
Get-ChildItem (Join-Path $HOME "rdev-jobs") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $lines = Get-RdevJob $_.FullName
    $kv = @{}; foreach ($line in $lines) { $k, $v = $line -split "=", 2; $kv[$k] = $v }
    "{0}`t{1}`t{2}`t{3}" -f $_.Name, $kv["state"], $kv["exit"], $kv["elapsed"]
}'
    else
        script="RDEV_NAME=$(rdev_bash_quote "$name")"$'\n'"$RDEV_SH_STATUS_FN"$'\n'
        script+='if [ -n "$RDEV_NAME" ]; then rdev_job_status "$HOME/rdev-jobs/$RDEV_NAME"; exit 0; fi
for job in "$HOME"/rdev-jobs/*/; do
    [ -d "$job" ] || continue
    s="$(rdev_job_status "${job%/}")"
    printf "%s\t%s\t%s\t%s\n" "$(basename "$job")" "$(echo "$s" | sed -n "s/^state=//p")" \
        "$(echo "$s" | sed -n "s/^exit=//p")" "$(echo "$s" | sed -n "s/^elapsed=//p")"
done'
    fi
    rdev_remote_exec "$host" "$os" "$script"
}

rdev_job_log_raw() {
    local host="$1" os="$2" name="$3" lines="$4"
    if [[ "$os" == "windows" ]]; then
        rdev_remote_exec "$host" "$os" "\$rdevName = $(rdev_ps_quote "$name"); \$rdevLines = $lines"$'\n''
$log = Join-Path $HOME "rdev-jobs\$rdevName\out.log"
if (Test-Path $log) { Get-Content $log -Tail $rdevLines -Encoding UTF8 }'
    else
        rdev_remote_exec "$host" "$os" "tail -n $lines \"\$HOME/rdev-jobs/\"$(rdev_bash_quote "$name")/out.log 2>/dev/null"
    fi
}

rdev_status() {
    local machine="" name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --name)    name="$2";    shift 2 ;;
            -h|--help) echo "Usage: rdev status --machine <windows|debian> [--name NAME]"; return 0 ;;
            *) echo "rdev status: unknown option: $1" >&2; return 30 ;;
        esac
    done
    local target host os out
    target="$(rdev_jobs_target status "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    if [[ -z "$name" ]]; then
        out="$(rdev_job_status_raw "$host" "$os" "")" || return 20
        if [[ -z "$out" ]]; then echo "no jobs on $machine"; return 0; fi
        printf 'job\tstate\texit\telapsed\n%s\n' "$out" \
            | awk 'BEGIN { FS = OFS = "\t" } { for (i = 1; i <= 4; i++) if ($i == "") $i = "-"; print }' \
            | column -t -s $'\t'
        return 0
    fi
    rdev_check_name status "$name" || return $?
    out="$(rdev_job_status_raw "$host" "$os" "$name")" || return 20
    [[ "$(rdev_kv state "$out")" == "missing" ]] && { echo "job '$name' not found on $machine" >&2; return 42; }
    printf '%s\n' "$out"
}

rdev_log() {
    local machine="" name="" lines=100
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --name)    name="$2";    shift 2 ;;
            --tail)    lines="$2";   shift 2 ;;
            -h|--help) echo "Usage: rdev log --machine <windows|debian> --name NAME [--tail N]"; return 0 ;;
            *) echo "rdev log: unknown option: $1" >&2; return 30 ;;
        esac
    done
    local target host os
    target="$(rdev_jobs_target log "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    rdev_check_name log "$name" || return $?
    [[ "$lines" =~ ^[0-9]+$ ]] || { echo "rdev log: --tail takes a number" >&2; return 30; }
    rdev_job_log_raw "$host" "$os" "$name" "$lines" || return 20
}

rdev_wait_usage() {
    cat <<EOF
Usage: rdev wait --machine <windows|debian> --name NAME [--timeout SEC] [--interval SEC] [--tail N]

Polls until the job finishes. ssh outages are retried and do not end the wait.
  --timeout SEC   Give up after SEC seconds, job keeps running (default 1500, exit 40)
  --interval SEC  Seconds between polls (default 30)
  --tail N        Log lines shown when the job ends (default 40)
EOF
}

rdev_wait() {
    local machine="" name="" timeout=1500 interval=30 lines=40
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine)  machine="$2";  shift 2 ;;
            --name)     name="$2";     shift 2 ;;
            --timeout)  timeout="$2";  shift 2 ;;
            --interval) interval="$2"; shift 2 ;;
            --tail)     lines="$2";    shift 2 ;;
            -h|--help)  rdev_wait_usage; return 0 ;;
            *) echo "rdev wait: unknown option: $1" >&2; rdev_wait_usage >&2; return 30 ;;
        esac
    done
    local target host os
    target="$(rdev_jobs_target wait "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    rdev_check_name wait "$name" || return $?

    local start now out state exit_code elapsed polls=0
    start="$(date +%s)"
    while :; do
        if out="$(rdev_job_status_raw "$host" "$os" "$name")"; then
            state="$(rdev_kv state "$out")"
            exit_code="$(rdev_kv exit "$out")"
            elapsed="$(rdev_kv elapsed "$out")"
            case "$state" in
                missing)
                    echo "job '$name' not found on $machine" >&2; return 42 ;;
                done|died)
                    echo "--- last $lines log lines ---"
                    rdev_job_log_raw "$host" "$os" "$name" "$lines"
                    echo "---"
                    if [[ "$state" == "died" ]]; then
                        echo "RESULT: job=$name died without an exit code after $(rdev_fmt_secs "$elapsed")"
                        return 41
                    fi
                    echo "RESULT: job=$name exit=$exit_code elapsed=$(rdev_fmt_secs "$elapsed")"
                    [[ "$exit_code" == "0" ]] && return 0
                    return 44 ;;
                running)
                    # Progress every 4th poll keeps long waits readable.
                    if [[ $((polls % 4)) -eq 0 ]]; then
                        echo "[$(date +%H:%M:%S)] $name running $(rdev_fmt_secs "$elapsed") | $(rdev_kv last "$out" | cut -c1-140)"
                    fi ;;
            esac
        else
            echo "[$(date +%H:%M:%S)] $machine unreachable, still waiting" >&2
        fi
        polls=$((polls + 1))
        now="$(date +%s)"
        if [[ $((now - start)) -ge $timeout ]]; then
            echo "RESULT: job=$name still running after waiting $(rdev_fmt_secs $((now - start))); wait again"
            return 40
        fi
        sleep "$interval"
    done
}

rdev_stop() {
    local machine="" name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --name)    name="$2";    shift 2 ;;
            -h|--help) echo "Usage: rdev stop --machine <windows|debian> --name NAME"; return 0 ;;
            *) echo "rdev stop: unknown option: $1" >&2; return 30 ;;
        esac
    done
    local target host os script out
    target="$(rdev_jobs_target stop "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    rdev_check_name stop "$name" || return $?
    if [[ "$os" == "windows" ]]; then
        script="\$rdevName = $(rdev_ps_quote "$name")"$'\n''$job = Join-Path $HOME "rdev-jobs\$rdevName"
if (-not (Test-Path $job)) { "MISSING"; exit 0 }
if (Test-Path "$job\exit") { "ALREADY_DONE"; exit 0 }
$jobPid = (Get-Content "$job\pid" -Raw).Trim()
taskkill /T /F /PID $jobPid 2>&1 | Out-Null
Set-Content -LiteralPath "$job\exit" -Value "stopped"
"STOPPED"'
    else
        script="RDEV_NAME=$(rdev_bash_quote "$name")"$'\n''job="$HOME/rdev-jobs/$RDEV_NAME"
[ -d "$job" ] || { echo MISSING; exit 0; }
[ -f "$job/exit" ] && { echo ALREADY_DONE; exit 0; }
pid="$(cat "$job/pid")"
kill -TERM -- "-$pid" 2>/dev/null; sleep 3; kill -KILL -- "-$pid" 2>/dev/null
echo stopped > "$job/exit"; echo STOPPED'
    fi
    out="$(rdev_remote_exec "$host" "$os" "$script")" || return 20
    case "$out" in
        *MISSING*)      echo "job '$name' not found on $machine" >&2; return 42 ;;
        *ALREADY_DONE*) echo "job '$name' had already finished" ;;
        *)              echo "stopped job=$name on $machine" ;;
    esac
}

rdev_get() {
    local machine="" name="" file="" to=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --name)    name="$2";    shift 2 ;;
            --file)    file="$2";    shift 2 ;;
            --to)      to="$2";      shift 2 ;;
            -h|--help) echo "Usage: rdev get --machine <windows|debian> --name NAME --file FILE --to LOCAL_PATH"; return 0 ;;
            *) echo "rdev get: unknown option: $1" >&2; return 30 ;;
        esac
    done
    local target host
    target="$(rdev_jobs_target get "$machine")" || return $?
    host="${target%%$'\t'*}"
    rdev_check_name get "$name" || return $?
    [[ -n "$file" && -n "$to" ]] || { echo "rdev get: --file and --to are required" >&2; return 30; }
    [[ "$file" != *..* && "$file" != /* ]] || { echo "rdev get: --file must be inside the job dir" >&2; return 30; }
    rdev_scp_retry "$host:rdev-jobs/$name/$file" "$to" || return 22
    echo "fetched $file -> $to"
}

# --- checkout --------------------------------------------------------------------------------

rdev_checkout() {
    local machine="" ref=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --ref)     ref="$2";     shift 2 ;;
            -h|--help)
                echo "Usage: rdev checkout --machine <windows|debian> --ref BRANCH"
                echo "Switches the remote repo to origin/BRANCH (e.g. master for a baseline run)."
                echo "'rdev sync' switches it back to the local branch."
                return 0 ;;
            *) echo "rdev checkout: unknown option: $1" >&2; return 30 ;;
        esac
    done
    local target host os
    target="$(rdev_jobs_target checkout "$machine")" || return $?
    host="${target%%$'\t'*}"; os="${target#*$'\t'}"
    [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "rdev checkout: --ref must be a branch name" >&2; return 30; }

    # Refuse while any job runs (a build or test would see files change under it) or the
    # repo is dirty (the switch would carry or lose uncommitted work).
    local script
    if [[ "$os" == "windows" ]]; then
        script="\$rdevRef = $(rdev_ps_quote "$ref")"$'\n'"$RDEV_PS_STATUS_FN"$'\n''
Get-ChildItem (Join-Path $HOME "rdev-jobs") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ((Get-RdevJob $_.FullName) -contains "state=running") { "JOB_RUNNING " + $_.Name; exit 0 }
}
Set-Location (Join-Path $HOME "dev\pia_desktop")
$dirty = @(git status --porcelain=v1)
if ($dirty.Count -gt 0) { "DIRTY"; $dirty; exit 0 }
git fetch origin -q 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { "FETCH_FAILED"; exit 0 }
git checkout -q -B $rdevRef "origin/$rdevRef" 2>&1
if ($LASTEXITCODE -ne 0) { "CHECKOUT_FAILED"; exit 0 }
"OK " + (git rev-parse --short HEAD)'
    else
        script="RDEV_REF=$(rdev_bash_quote "$ref")"$'\n'"$RDEV_SH_STATUS_FN"$'\n''
for job in "$HOME"/rdev-jobs/*/; do
    [ -d "$job" ] || continue
    rdev_job_status "${job%/}" | grep -qx "state=running" && { echo "JOB_RUNNING $(basename "$job")"; exit 0; }
done
cd "$HOME/dev/pia_desktop" || exit 1
dirty="$(git status --porcelain=v1)"
[ -n "$dirty" ] && { echo DIRTY; echo "$dirty"; exit 0; }
git fetch origin -q || { echo FETCH_FAILED; exit 0; }
git checkout -q -B "$RDEV_REF" "origin/$RDEV_REF" 2>&1 || { echo CHECKOUT_FAILED; exit 0; }
echo "OK $(git rev-parse --short HEAD)"'
    fi

    local out attempt=1 delay
    while :; do
        out="$(rdev_remote_exec "$host" "$os" "$script")" || return 20
        [[ "$out" != *FETCH_FAILED* ]] && break
        if [[ $attempt -ge $RDEV_SSH_RETRIES ]]; then
            echo "STOP: git fetch on $machine failed after $attempt attempts" >&2; return 14
        fi
        delay="$(rdev_backoff "$attempt")"
        echo "rdev: git fetch on $machine failed (attempt $attempt), retrying in ${delay}s" >&2
        sleep "$delay"; attempt=$((attempt + 1))
    done
    case "$out" in
        *JOB_RUNNING*)    echo "STOP: ${out#*JOB_RUNNING } is still running on $machine" >&2; return 43 ;;
        DIRTY*)           echo "STOP: remote repo has uncommitted changes:" >&2
                          printf '%s\n' "${out#DIRTY}" | sed '/^$/d;s/^/  /' >&2; return 10 ;;
        *CHECKOUT_FAILED*) echo "STOP: checkout of origin/$ref failed on $machine:" >&2
                          printf '%s\n' "$out" >&2; return 21 ;;
        *OK*)             echo "remote $machine now on $ref at ${out##*OK }" ;;
        *)                echo "rdev checkout: unexpected output: $out" >&2; return 21 ;;
    esac
}
