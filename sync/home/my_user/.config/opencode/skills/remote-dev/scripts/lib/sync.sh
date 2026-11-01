# shellcheck shell=bash
# rdev — sync subcommand
#
# Flow:
#   1. Probe SSH + local + remote state.
#   2. Validate remote dirty files (marker-or-dirty-locally rule):
#        - Remote dirty file also dirty locally           -> OK (overwrite)
#        - Remote dirty file bears the sync marker        -> OK (drop / overwrite)
#        - Remote dirty file without marker, clean locally -> STOP (exit 10)
#   3. Local branch missing on origin                     -> STOP (exit 12)
#   4. Local unpushed                                     -> STOP (exit 11, unless --push/--bundle)
#   5. Divergent remote HEAD (not ancestor of origin/br)  -> STOP (exit 15)
#   6. Align remote branch (fetch + checkout origin/branch).
#   7. Fast-forward remote HEAD (pull --ff-only).
#   8. Transfer dirty local files (marked), restore/delete stale remote files.
#
# --dry-run performs steps 1-5 only; exits 0 if syncable.
#
# Exit codes:
#   0  success (or dry-run syncable)
#   10 remote dirty with files not safe to overwrite (no marker, not local)
#   11 local has unpushed commits (use --push or --bundle)
#   12 local branch not on origin
#   14 remote pull --ff-only failed (post-divergence-check race)
#   15 remote diverged (HEAD not ancestor of origin/branch)
#   20 ssh failure
#   21 local git error
#   22 file transfer failed
#   30 usage error

rdev_sync_usage() {
    cat <<EOF
Usage: rdev sync --machine <windows|debian> [options]

Options:
  --push       Push unpushed local commits to origin, then sync (irreversible)
  --bundle     Transfer unpushed commits via git bundle (no push)
  --dry-run    Probe state and check syncability, do not modify remote
  --force      Reserved (no-op for now)
  -h, --help   Show this help
EOF
}

rdev_sync() {
    local machine="" do_push=0 do_bundle=0 dry_run=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --machine) machine="$2"; shift 2 ;;
            --push)    do_push=1;    shift ;;
            --bundle)  do_bundle=1;  shift ;;
            --dry-run) dry_run=1;    shift ;;
            --force)                   shift ;;
            -h|--help) rdev_sync_usage; return 0 ;;
            *) echo "rdev sync: unknown option: $1" >&2; rdev_sync_usage >&2; return 30 ;;
        esac
    done

    [[ -n "$machine" ]] || { echo "rdev sync: --machine is required" >&2; rdev_sync_usage >&2; return 30; }
    { [[ $do_push -eq 1 ]] && [[ $do_bundle -eq 1 ]]; } && {
        echo "rdev sync: --push and --bundle are mutually exclusive" >&2; return 30; }
    { [[ $dry_run -eq 1 ]] && { [[ $do_push -eq 1 ]] || [[ $do_bundle -eq 1 ]]; }; } && {
        echo "rdev sync: --dry-run cannot be combined with --push or --bundle" >&2; return 30; }

    local host os path rel_path
    host="$(rdev_resolve_host "$machine")" || { echo "rdev sync: unknown machine '$machine'" >&2; return 30; }
    os="$(rdev_host_os "$host")"
    path="$(rdev_remote_cd "$host")"
    rel_path="$(rdev_remote_path "$host")"

    local tag=""
    [[ $dry_run -eq 1 ]] && tag="[dry-run]"

    # --- Step 1: SSH probe -------------------------------------------------
    rdev_ssh_probe "$host" "$os" || {
        echo "STOP: cannot reach $host via SSH" >&2
        return 20
    }

    # --- Step 2: Probe local + remote state --------------------------------
    local local_state remote_state local_branch local_head local_dirty origin_head
    local_state="$(rdev_local_state)" || return 21
    local_branch="$(printf '%s' "$local_state" | cut -f1)"
    local_head="$(printf '%s'   "$local_state" | cut -f2)"
    local_dirty="$(printf '%s'  "$local_state" | cut -f3)"
    origin_head="$(rdev_local_origin_head)"

    remote_state="$(rdev_remote_state "$host" "$os" "$path")" || return 20
    local remote_branch remote_head remote_dirty
    remote_branch="$(printf '%s' "$remote_state" | cut -f1)"
    remote_head="$(printf '%s'  "$remote_state" | cut -f2)"
    remote_dirty="$(printf '%s' "$remote_state" | cut -f3)"

    echo "$tag local : branch=$local_branch head=${local_head:0:8} dirty=$local_dirty"
    echo "$tag remote: branch=$remote_branch head=${remote_head:0:8} dirty=$remote_dirty"

    # --- Step 3: Validate remote dirty files -------------------------------
    # Build local dirty set once.
    local local_dirty_set
    local_dirty_set="$(rdev_local_dirty_files)"

    if [[ "$remote_dirty" != "0" ]]; then
        local rfiles rfile safe
        local -a unknown=()
        rfiles="$(rdev_remote_dirty_files "$host" "$os" "$path")"
        while IFS= read -r rfile; do
            [[ -z "$rfile" ]] && continue
            if grep -Fxq -- "$rfile" <<< "$local_dirty_set"; then
                continue  # also dirty locally — will overwrite
            fi
            # Not dirty locally — must have marker.
            if rdev_remote_file_has_marker "$host" "$os" "$path" "$rfile"; then
                continue
            fi
            unknown+=("$rfile")
        done <<< "$rfiles"
        if [[ ${#unknown[@]} -gt 0 ]]; then
            echo "STOP: remote has dirty file(s) without sync marker and not dirty locally:" >&2
            printf '  %s\n' "${unknown[@]}" >&2
            echo "Inspect: ssh $host \"cd $path && git status\"" >&2
            return 10
        fi
    fi

    # --- Step 4: Local branch must exist on origin -------------------------
    if [[ -z "$origin_head" ]]; then
        echo "STOP: local branch '$local_branch' has no upstream on origin." >&2
        echo "Push first or use --bundle." >&2
        return 12
    fi

    # --- Step 5: Local unpushed commits ------------------------------------
    if [[ "$local_head" != "$origin_head" ]]; then
        if [[ $dry_run -eq 1 ]]; then
            echo "STOP: local has unpushed commits (head ${local_head:0:8} != origin ${origin_head:0:8})." >&2
            echo "Dry-run cannot resolve. Re-run without --dry-run with --push or --bundle." >&2
            return 11
        fi
        if [[ $do_push -eq 0 && $do_bundle -eq 0 ]]; then
            echo "STOP: local has unpushed commits (head ${local_head:0:8} != origin ${origin_head:0:8})." >&2
            echo "Re-run with --push (push to origin, irreversible) or --bundle (transfer via git bundle)." >&2
            return 11
        fi
        if [[ $do_push -eq 1 ]]; then
            echo "Pushing $local_branch to origin..."
            git push origin "$local_branch" || { echo "git push failed" >&2; return 21; }
            origin_head="$(rdev_local_origin_head)"
        elif [[ $do_bundle -eq 1 ]]; then
            rdev_bundle_transfer "$host" "$os" "$path" "$remote_head" "$local_branch" || return 22
            remote_head="$local_head"
        fi
    fi

    # --- Step 6: Branch alignment ------------------------------------------
    if [[ "$remote_branch" != "$local_branch" ]]; then
        if [[ $dry_run -eq 1 ]]; then
            echo "$tag would switch remote branch: $remote_branch -> $local_branch"
            remote_branch="$local_branch"
            # After checkout origin/$branch, remote head would equal origin head.
            remote_head="$origin_head"
        else
            echo "Switching remote branch: $remote_branch -> $local_branch"
            if [[ "$os" == "windows" ]]; then
                /usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
                    "Set-Location $path; git fetch origin -q; git checkout -B $local_branch origin/$local_branch" \
                    >/dev/null 2>&1 || { echo "remote checkout failed" >&2; return 21; }
            else
                /usr/bin/ssh -A -n -o BatchMode=yes "$host" \
                    "cd $path && git fetch origin -q && git checkout -B $local_branch origin/$local_branch" \
                    >/dev/null 2>&1 || { echo "remote checkout failed" >&2; return 21; }
            fi
            remote_head="$local_head"
        fi
    fi

    # --- Step 7: Divergence check + fast-forward ---------------------------
    if [[ "$remote_head" != "$local_head" ]]; then
        # All checks are LOCAL — avoids requiring the remote to have GitHub auth.
        # Refresh local origin ref first (best-effort).
        git fetch origin -q 2>/dev/null || true
        origin_head="$(rdev_local_origin_head)"

        # (a) If remote_head is not in local object store, remote has commits
        #     local doesn't know about → divergent.
        if ! git cat-file -e "$remote_head" 2>/dev/null; then
            echo "STOP: remote HEAD ${remote_head:0:8} is not present in local repo." >&2
            echo "Remote has commits local doesn't know about. Pull from remote or inspect." >&2
            return 15
        fi
        # (b) If remote_head is not an ancestor of origin/branch, histories
        #     diverged (likely local was rebased and force-pushed).
        if ! git merge-base --is-ancestor "$remote_head" "$origin_head" 2>/dev/null; then
            echo "STOP: remote HEAD ${remote_head:0:8} is NOT an ancestor of origin/$local_branch." >&2
            echo "Remote history diverged (likely local was rebased or remote has extra commits)." >&2
            echo "Resolve: ssh $host \"cd $path && git reset --hard origin/$local_branch\" (loses remote-only commits)," >&2
            echo "or merge manually on the remote." >&2
            return 15
        fi
        if [[ $dry_run -eq 1 ]]; then
            echo "$tag would pull --ff-only origin $local_branch on remote"
            remote_head="$local_head"
        else
            echo "Pulling on remote (ff-only)..."
            local pull_out
            if [[ "$os" == "windows" ]]; then
                pull_out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
                    "Set-Location $path; git fetch origin -q; git pull --ff-only origin $local_branch" 2>&1)"
            else
                pull_out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" \
                    "cd $path && git fetch origin -q && git pull --ff-only origin $local_branch" 2>&1)"
            fi
            if [[ $? -ne 0 ]]; then
                echo "STOP: remote pull --ff-only failed unexpectedly:" >&2
                echo "$pull_out" >&2
                return 14
            fi
        fi
    fi

    # --- Step 8: Transfer / restore ----------------------------------------
    # 8a. Restore remote dirty files that are not dirty locally (marker proved safe).
    if [[ "$remote_dirty" != "0" ]]; then
        local rfiles rfile
        rfiles="$(rdev_remote_dirty_files "$host" "$os" "$path")"
        while IFS= read -r rfile; do
            [[ -z "$rfile" ]] && continue
            if grep -Fxq -- "$rfile" <<< "$local_dirty_set"; then
                continue  # handled in 8b
            fi
            if [[ $dry_run -eq 1 ]]; then
                echo "$tag would restore on remote: $rfile"
            else
                rdev_remote_restore_file "$host" "$os" "$path" "$rfile" || {
                    echo "remote restore failed for $rfile" >&2; return 22; }
                echo "  restored: $rfile"
            fi
        done <<< "$rfiles"
    fi

    # 8b. Transfer local dirty files (with marker); delete on remote if gone locally.
    if [[ "$local_dirty" != "0" ]]; then
        local detail status lfile
        detail="$(rdev_local_dirty_detail)"
        while IFS=$'\t' read -r status lfile; do
            [[ -z "$lfile" ]] && continue
            if [[ "$status" == "D" ]]; then
                if [[ $dry_run -eq 1 ]]; then
                    echo "$tag would delete on remote: $lfile"
                else
                    rdev_remote_delete_file "$host" "$os" "$path" "$lfile" || {
                        echo "remote delete failed for $lfile" >&2; return 22; }
                    echo "  deleted: $lfile"
                fi
            else
                if [[ $dry_run -eq 1 ]]; then
                    echo "$tag would transfer marked: $lfile"
                else
                    rdev_transfer_file_marked "$host" "$os" "$rel_path" "$lfile" || return 22
                fi
            fi
        done <<< "$detail"
    fi

    # --- Step 9: Done ------------------------------------------------------
    if [[ "$local_dirty" == "0" && "$remote_branch" == "$local_branch" && "$remote_head" == "$local_head" && "$remote_dirty" == "0" ]]; then
        echo "$tag already in sync."
    else
        echo "$tag sync complete."
    fi
    return 0
}

# Transfer unpushed commits via git bundle. $1=host $2=os $3=remote_path
# $4=remote_head (merge-base-ish) $5=local_branch
rdev_bundle_transfer() {
    local host="$1" os="$2" path="$3" base="$4" branch="$5"
    local bundle="/tmp/rdev-${branch}-$$.bundle"
    echo "Creating bundle for $base..$branch..."
    git bundle create "$bundle" "${base}..${branch}" >/dev/null 2>&1 || {
        echo "git bundle create failed" >&2; return 22; }
    local remote_bundle="/tmp/$(basename "$bundle")"
    echo "Copying bundle to $host..."
    /usr/bin/scp -q "$bundle" "$host:$remote_bundle" >/dev/null 2>&1 || {
        echo "scp bundle failed" >&2; rm -f "$bundle"; return 22; }
    rm -f "$bundle"
    echo "Merging bundle on remote..."
    if [[ "$os" == "windows" ]]; then
        /usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $path; git fetch $remote_bundle $branch:refs/heads/rdev-bundle; git merge --ff-only rdev-bundle; git branch -D rdev-bundle" \
            >/dev/null 2>&1 || { echo "remote bundle merge failed" >&2; return 22; }
    else
        /usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $path && git fetch $remote_bundle $branch:refs/heads/rdev-bundle && git merge --ff-only rdev-bundle && git branch -D rdev-bundle" \
            >/dev/null 2>&1 || { echo "remote bundle merge failed" >&2; return 22; }
    fi
}
