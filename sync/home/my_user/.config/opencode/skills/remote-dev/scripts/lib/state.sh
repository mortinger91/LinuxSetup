# shellcheck shell=bash
# rdev — local + remote git state probing.
#
# All probes return TSV on stdout:  branch<TAB>head<TAB>dirty_count
# Exit codes: 0 success, 20 ssh failure, 21 local git error.

# Probe local repo state. Prints: branch<TAB>head<TAB>dirty_count
rdev_local_state() {
    local branch head dirty
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || { echo "git error: not in a repo" >&2; return 21; }
    head="$(git rev-parse HEAD 2>/dev/null)"                 || { echo "git error: no HEAD" >&2;     return 21; }
    dirty="$(git status --porcelain=v1 | wc -l | tr -d ' ')"
    printf '%s\t%s\t%s\n' "$branch" "$head" "$dirty"
}

# Local dirty file paths, one per line, sorted unique.
# Strips the 3-char XY-status prefix from `git status --porcelain`.
rdev_local_dirty_files() {
    git status --porcelain=v1 | cut -c4- | sed 's/.* -> //' | sort -u
}

# Local dirty entries as TSV: STATUS<TAB>PATH
# STATUS ∈ {M=modified/untracked, D=deleted}. Rename reported against new path as M.
rdev_local_dirty_detail() {
    local line xy x y rest path status
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        xy="${line:0:2}"
        x="${xy:0:1}"
        y="${xy:1:1}"
        rest="${line:3}"
        # Rename: "old -> new"
        if [[ "$rest" == *" -> "* ]]; then
            path="${rest##* -> }"
        else
            path="$rest"
        fi
        # Strip surrounding quotes (git quotes paths with special chars).
        if [[ "$path" == \"*\" ]]; then
            path="${path#\"}"
            path="${path%\"}"
        fi
        status="M"
        if [[ "$y" == "D" ]] || { [[ "$x" == "D" ]] && [[ "$y" == " " ]]; }; then
            status="D"
        fi
        printf '%s\t%s\n' "$status" "$path"
    done < <(git status --porcelain=v1)
}

# Local origin HEAD for current branch (empty if no upstream).
rdev_local_origin_head() {
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    git rev-parse "origin/$branch" 2>/dev/null || true
}

# Remote dirty file paths, one per line, sorted unique.
# Args: host os cd_path
rdev_remote_dirty_files() {
    local host="$1" os="$2" cd_path="$3"
    local raw
    if [[ "$os" == "windows" ]]; then
        raw="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $cd_path; git status --porcelain=v1" 2>&1)"
        raw="${raw//$'\r'/}"
    else
        raw="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $cd_path && git status --porcelain=v1" 2>&1)"
    fi
    printf '%s\n' "$raw" | cut -c4- | sort -u
}

# Returns 0 if every remote dirty file is also dirty locally.
# Args: host os cd_path
rdev_remote_dirty_is_subset_of_local() {
    local host="$1" os="$2" cd_path="$3"
    local remote_files local_files
    remote_files="$(rdev_remote_dirty_files "$host" "$os" "$cd_path")"
    [[ -z "$remote_files" ]] && return 0
    local_files="$(rdev_local_dirty_files)"
    # For each remote dirty file, check it appears in local dirty set.
    local f found
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        found=0
        while IFS= read -r lf; do
            if [[ "$f" == "$lf" ]]; then found=1; break; fi
        done <<< "$local_files"
        [[ $found -eq 0 ]] && return 1
    done <<< "$remote_files"
    return 0
}

# Probe remote repo state. Prints: branch<TAB>head<TAB>dirty_count
rdev_remote_state() {
    local host="$1" os="$2" cd_path="$3"
    local raw line1 line2 line3
    if [[ "$os" == "windows" ]]; then
        # cmd.exe is the default shell on the remote — wrap in powershell.
        # Use `@()` to guarantee array context so .Count is reliable for 0..N dirty files.
        # Single-line PowerShell command separated by `;` — survives cmd.exe quoting.
        raw="$(/usr/bin/ssh -A -n -o ConnectTimeout=15 -o BatchMode=yes "$host" \
            powershell -NoProfile -Command \
            "Set-Location $cd_path; \$b=git rev-parse --abbrev-ref HEAD; \$h=git rev-parse HEAD; \$d=@(git status --porcelain=v1).Count; Write-Output \$b; Write-Output \$h; Write-Output \$d" \
            2>&1)"
        [[ $? -eq 0 ]] || { echo "ssh failed: $raw" >&2; return 20; }
        # Strip CR (CRLF from Windows) — bash parameter expansion, no external tr.
        raw="${raw//$'\r'/}"
        line1="${raw%%$'\n'*}"; raw="${raw#*$'\n'}"
        line2="${raw%%$'\n'*}"; raw="${raw#*$'\n'}"
        line3="${raw%%$'\n'*}"
        printf '%s\t%s\t%s\n' "$line1" "$line2" "$line3"
    else
        raw="$(/usr/bin/ssh -A -n -o ConnectTimeout=15 -o BatchMode=yes "$host" \
            "cd $cd_path && printf '%s\t%s\t%s\n' \"\$(git rev-parse --abbrev-ref HEAD)\" \"\$(git rev-parse HEAD)\" \"\$(git status --porcelain=v1 | wc -l | tr -d ' ')\"" 2>&1)"
        [[ $? -eq 0 ]] || { echo "ssh failed: $raw" >&2; return 20; }
        printf '%s\n' "$raw"
    fi
}

# Quick SSH reachability probe. Returns 0 if reachable.
rdev_ssh_probe() {
    local host="$1" os="$2"
    if [[ "$os" == "windows" ]]; then
        /usr/bin/ssh -A -n -o ConnectTimeout=10 -o BatchMode=yes "$host" powershell -NoProfile -Command "Write-Output OK" >/dev/null 2>&1
    else
        /usr/bin/ssh -A -n -o ConnectTimeout=10 -o BatchMode=yes "$host" "echo OK" >/dev/null 2>&1
    fi
}

# Parse a TSV line field by index (1-based).
rdev_field() {
    local line="$1" idx="$2"
    printf '%s' "$line" | cut -f"$idx"
}

# Check on remote whether $2 is an ancestor of $3 (after fetching origin).
# Returns 0 if ancestor, 1 if not, 2 on ssh error.
# Args: host os cd_path ancestor_commit descendant_ref
rdev_remote_is_ancestor() {
    local host="$1" os="$2" cd_path="$3" ancestor="$4" descendant="$5"
    local out
    if [[ "$os" == "windows" ]]; then
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $cd_path; git fetch origin -q; if (git merge-base --is-ancestor $ancestor $descendant) { Write-Output YES } else { Write-Output NO }" 2>&1)"
        out="${out//$'\r'/}"
    else
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $cd_path && git fetch origin -q && (git merge-base --is-ancestor $ancestor $descendant && echo YES || echo NO)" 2>&1)"
    fi
    [[ "$out" == *"YES"* ]] && return 0
    [[ "$out" == *"NO"* ]]  && return 1
    return 2
}
