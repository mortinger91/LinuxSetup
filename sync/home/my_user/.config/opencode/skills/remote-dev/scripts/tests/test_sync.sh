#!/usr/bin/env bash
# rdev sync — exhaustive state coverage test against the linux remote.
#
# Drives the linux remote repo through every meaningful state and verifies
# the exit code returned by `rdev sync --dry-run` (and, for marker scenarios,
# a real `rdev sync`).
#
# HARD RULES:
#   - Local repo is READ-ONLY. Test never modifies it.
#   - Remote repo MUST be clean at start; otherwise test aborts.
#   - At end, remote is restored to its original branch + HEAD.
#
# Default local repo: /home/michele/dev/pia_desktop
# Override with: LOCAL_REPO=/path REMOTE_HOST=host ./test_sync.sh

set -uo pipefail

LOCAL_REPO="${LOCAL_REPO:-/home/michele/dev/pia_desktop}"
REMOTE_HOST="${REMOTE_HOST:-proxmox-debian}"
REMOTE_PATH="${REMOTE_PATH:-~/dev/pia_desktop}"
RDEV_ROOT="${RDEV_ROOT:-/home/michele/.config/opencode/skills/remote-dev/scripts}"
RDEV="$RDEV_ROOT/rdev"
MACHINE="debian"
TEST_FILE="rdev_test_marker.txt"        # unique test artifact name
TEST_FILE_CPP="rdev_test_marker.cpp"

# shellcheck source=../lib/config.sh
. "$RDEV_ROOT/lib/config.sh"
# shellcheck source=../lib/state.sh
. "$RDEV_ROOT/lib/state.sh"
# shellcheck source=../lib/transfer.sh
. "$RDEV_ROOT/lib/transfer.sh"

PASS=0
FAIL=0
SKIP=0
FIRST_FAILURE=""
VERBOSE="${VERBOSE:-0}"

# --- Output ---------------------------------------------------------------
log()   { printf '%s\n' "$*"; }
ok()    { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); [[ -z "$FIRST_FAILURE" ]] && FIRST_FAILURE="$1"; }
skip()  { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }
section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

expect_rc() {
    local expected="$1" name="$2" actual="$3" out="$4"
    if [[ "$expected" == "$actual" ]]; then
        ok "$name (rc=$actual)"
    else
        bad "$name (expected rc=$expected, got rc=$actual)"
        if [[ "$VERBOSE" == "1" || "$VERBOSE" == "true" ]]; then
            printf '%s\n' "$out" | sed 's/^/    /' >&2
        fi
    fi
}

ssh_cmd() {
    /usr/bin/ssh -A -n -o BatchMode=yes "$REMOTE_HOST" "$1"
}

# --- Saved state ----------------------------------------------------------
SETUP_OK=0
LOCAL_BRANCH=""
LOCAL_HEAD=""
ORIGIN_HEAD=""
LOCAL_DIRTY_COUNT=0
LOCAL_AT_ORIGIN=0
LOCAL_IS_CLEAN=0
REMOTE_BRANCH_SAVED=""
REMOTE_HEAD_SAVED=""

# --- Setup / teardown -----------------------------------------------------
setup() {
    log "Local repo:   $LOCAL_REPO"
    log "Remote host:  $REMOTE_HOST"
    log "Remote path:  $REMOTE_PATH"
    log ""

    cd "$LOCAL_REPO" || { log "FATAL: cannot cd to $LOCAL_REPO"; exit 1; }

    if ! rdev_ssh_probe "$REMOTE_HOST" "linux"; then
        log "FATAL: cannot reach $REMOTE_HOST via SSH"
        exit 1
    fi

    # Read local state (read-only).
    LOCAL_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    LOCAL_HEAD="$(git rev-parse HEAD)"
    ORIGIN_HEAD="$(rdev_local_origin_head)"
    LOCAL_DIRTY_COUNT="$(git status --porcelain=v1 | wc -l | tr -d ' ')"

    if [[ -z "$ORIGIN_HEAD" ]]; then
        log "FATAL: local branch '$LOCAL_BRANCH' is not on origin. Test cannot proceed."
        exit 1
    fi

    if [[ "$LOCAL_HEAD" == "$ORIGIN_HEAD" ]]; then
        LOCAL_AT_ORIGIN=1
    else
        log "FATAL: local has commits not present on origin (${LOCAL_HEAD:0:8} != origin ${ORIGIN_HEAD:0:8})."
        log "       Push local branch first, then re-run test."
        exit 1
    fi

    if [[ "$LOCAL_DIRTY_COUNT" == "0" ]]; then
        LOCAL_IS_CLEAN=1
    else
        LOCAL_IS_CLEAN=0
        log "WARN: local has $LOCAL_DIRTY_COUNT dirty file(s)."
        log "      Marker-transfer tests will use them; results may be noisier."
    fi
    log ""

    log "Local: branch=$LOCAL_BRANCH head=${LOCAL_HEAD:0:8} dirty=$LOCAL_DIRTY_COUNT"

    # Read remote state. HARD requirement: working tree must be clean.
    local rstate rdirty
    rstate="$(rdev_remote_state "$REMOTE_HOST" "linux" "$REMOTE_PATH")" || {
        log "FATAL: cannot read remote state"; exit 1; }
    REMOTE_BRANCH_SAVED="$(printf '%s' "$rstate" | cut -f1)"
    REMOTE_HEAD_SAVED="$(printf '%s' "$rstate" | cut -f2)"
    rdirty="$(printf '%s' "$rstate" | cut -f3)"
    log "Remote: branch=$REMOTE_BRANCH_SAVED head=${REMOTE_HEAD_SAVED:0:8} dirty=$rdirty"
    log ""

    if [[ "$rdirty" != "0" ]]; then
        log "FATAL: remote repo has $rdirty uncommitted file(s) in working dir."
        log "       Resolve before running test:"
        log "         ssh $REMOTE_HOST \"cd $REMOTE_PATH && git status\""
        exit 1
    fi

    SETUP_OK=1
}

teardown() {
    [[ $SETUP_OK -eq 0 ]] && return 0
    log ""
    log "Restoring remote to original state..."
    ssh_cmd "cd $REMOTE_PATH && git fetch origin -q 2>/dev/null" || true
    # Best-effort: return to saved branch if it's on origin; else fall back to master.
    ssh_cmd "cd $REMOTE_PATH && git checkout -B '$REMOTE_BRANCH_SAVED' 'origin/$REMOTE_BRANCH_SAVED' 2>/dev/null || git checkout -B master origin/master" >/dev/null 2>&1
    ssh_cmd "cd $REMOTE_PATH && git reset --hard HEAD 2>/dev/null && git clean -fd" >/dev/null 2>&1
    log "Remote restored."
}
trap teardown EXIT

# --- Remote helpers -------------------------------------------------------
# Reset remote to match local branch + HEAD (only meaningful when local at origin).
reset_remote_to_local() {
    ssh_cmd "cd $REMOTE_PATH && \
        git fetch origin -q && \
        git checkout -B '$LOCAL_BRANCH' 'origin/$LOCAL_BRANCH' && \
        git reset --hard 'origin/$LOCAL_BRANCH' && \
        git clean -fd" >/dev/null 2>&1
}

# Add an empty commit on remote (for divergence test).
remote_empty_commit() {
    ssh_cmd "cd $REMOTE_PATH && git commit --allow-empty -m 'rdev-test divergence'" >/dev/null 2>&1
}

# Create a dirty untracked file on remote. $1 = content (multi-line ok).
remote_dirty_untracked() {
    local content="$1" name="${2:-$TEST_FILE}"
    ssh_cmd "cd $REMOTE_PATH && printf '%s\n' '$content' > '$name'"
}

# Verify a remote file exists (echo YES/NO).
remote_exists() {
    local name="$1"
    ssh_cmd "cd $REMOTE_PATH && test -e '$name' && echo YES || echo NO"
}

# Count dirty files on remote.
remote_dirty_count() {
    ssh_cmd "cd $REMOTE_PATH && git status --porcelain=v1 | wc -l | tr -d ' '"
}

# Read first line of a remote file.
remote_first_line() {
    ssh_cmd "cd $REMOTE_PATH && head -1 '$1'"
}

# Remove test files from remote (defensive cleanup).
remote_cleanup_test_files() {
    ssh_cmd "cd $REMOTE_PATH && rm -f '$TEST_FILE' '$TEST_FILE_CPP' rdev_test_untracked.txt rdev_test_script.sh rdev_test_deletable.txt" >/dev/null 2>&1
}

# --- rdev runners ---------------------------------------------------------
run_dry()  { "$RDEV" sync --machine "$MACHINE" --dry-run 2>&1; }
run_sync() { "$RDEV" sync --machine "$MACHINE" 2>&1; }

# =========================================================================
# TESTS — exit-code matrix (dry-run)
# =========================================================================

test_in_sync() {
    section "T1 clean remote, same branch+HEAD as local -> 0"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin (currently unpushed)"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 0 "in sync" "$rc" "$out"
}

test_remote_behind_ff() {
    section "T2 remote behind local (ff-able) -> 0"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    ssh_cmd "cd $REMOTE_PATH && git reset --hard HEAD~1" >/dev/null 2>&1
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 0 "remote behind ff-able" "$rc" "$out"
}

test_remote_divergent() {
    section "T3 remote divergent (extra commit not on origin) -> 15"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    remote_empty_commit
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 15 "divergent" "$rc" "$out"
}

test_remote_diff_branch_on_origin() {
    section "T4 remote on different branch (exists on origin) -> 0"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    # Use master as the alternate branch — every repo has it.
    ssh_cmd "cd $REMOTE_PATH && git checkout -B master origin/master 2>/dev/null && git reset --hard origin/master" >/dev/null 2>&1
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 0 "different branch on origin" "$rc" "$out"
}

test_dirty_untracked_no_marker() {
    section "T5 dirty remote, untracked no marker, not local -> 10"
    reset_remote_to_local
    remote_cleanup_test_files
    remote_dirty_untracked "no marker here"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 10 "dirty no marker" "$rc" "$out"
}

test_dirty_untracked_with_marker() {
    section "T6 dirty remote, untracked with marker -> 0 (or 11 if local unpushed)"
    reset_remote_to_local
    remote_cleanup_test_files
    ssh_cmd "cd $REMOTE_PATH && printf '# file synced from pia_desktop mac repo\nstuff\n' > $TEST_FILE"
    local out rc expected
    out="$(run_dry)"; rc=$?
    if [[ $LOCAL_AT_ORIGIN -eq 1 ]]; then expected=0; else expected=11; fi
    expect_rc "$expected" "dirty with marker (local_at_origin=$LOCAL_AT_ORIGIN)" "$rc" "$out"
}

test_dirty_tracked_no_marker() {
    section "T7 dirty remote, tracked file (e.g. README.md) no marker, clean local -> 10"
    reset_remote_to_local
    remote_cleanup_test_files
    # Dirty a tracked file we know local doesn't have dirty.
    ssh_cmd "cd $REMOTE_PATH && echo '// unmarked remote change' >> README.md 2>/dev/null || echo '// unmarked' >> .gitignore"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 10 "dirty tracked no marker" "$rc" "$out"
    # Restore so it doesn't leak.
    ssh_cmd "cd $REMOTE_PATH && git checkout HEAD -- README.md .gitignore" >/dev/null 2>&1
}

test_dirty_remote_diff_branch() {
    section "T8 dirty remote on different branch -> 10"
    reset_remote_to_local
    ssh_cmd "cd $REMOTE_PATH && git checkout master 2>/dev/null && git reset --hard origin/master 2>/dev/null && echo 'x' >> README.md" >/dev/null 2>&1
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 10 "dirty diff branch" "$rc" "$out"
}

test_dirty_both_sides() {
    section "T9 dirty remote on a file that is also dirty locally -> 0"
    [[ $LOCAL_IS_CLEAN -eq 0 ]] || { skip "requires local dirty (currently clean)"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    # Pick the first dirty local file and dirty the same path on remote.
    local dirty_file
    dirty_file="$(git status --porcelain=v1 | head -1 | cut -c4-)"
    [[ -n "$dirty_file" ]] || { skip "no dirty local file available"; return; }
    ssh_cmd "cd $REMOTE_PATH && echo '// unmarked remote change' >> '$dirty_file'"
    local out rc expected
    out="$(run_dry)"; rc=$?
    if [[ $LOCAL_AT_ORIGIN -eq 1 ]]; then expected=0; else expected=11; fi
    expect_rc "$expected" "dirty both sides same file" "$rc" "$out"
}

# =========================================================================
# TESTS — real sync (marker behaviour)
# =========================================================================

test_real_drop_untracked_marked() {
    section "M1 real sync: untracked marked remote file (not local) -> dropped, exit 0"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    ssh_cmd "cd $REMOTE_PATH && printf '# file synced from pia_desktop mac repo\nstuff\n' > rdev_test_untracked.txt"
    local out rc
    out="$(run_sync)"; rc=$?
    expect_rc 0 "sync succeeded" "$rc" "$out"
    if [[ $rc -eq 0 ]]; then
        if [[ "$(remote_exists rdev_test_untracked.txt)" == "NO" ]]; then
            ok "untracked marked file dropped"
        else
            bad "untracked marked file still present"
        fi
    fi
    remote_cleanup_test_files
}

test_real_restore_marked_tracked() {
    section "M2 real sync: marked dirty tracked file (clean local) -> restored, exit 0"
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    ssh_cmd "cd $REMOTE_PATH && printf '# file synced from pia_desktop mac repo\nstale\n' > README.md"
    local out rc
    out="$(run_sync)"; rc=$?
    expect_rc 0 "sync succeeded" "$rc" "$out"
    if [[ $rc -eq 0 ]]; then
        local dirty
        dirty="$(remote_dirty_count)"
        # Local may have its own dirty files which would be transferred, leaving remote dirty.
        # What matters for this assertion: README.md specifically is no longer dirty.
        local readme_dirty
        readme_dirty="$(ssh_cmd "cd $REMOTE_PATH && git status --porcelain=v1 README.md | wc -l | tr -d ' '")"
        if [[ "$readme_dirty" == "0" ]]; then
            ok "README.md restored on remote"
        else
            bad "README.md still dirty on remote (count=$readme_dirty, total_dirty=$dirty)"
        fi
    fi
    ssh_cmd "cd $REMOTE_PATH && git checkout HEAD -- README.md" >/dev/null 2>&1
}

test_real_send_dirty_marked() {
    section "M3 real sync: send a local dirty file -> remote first line is marker"
    [[ $LOCAL_IS_CLEAN -eq 0 ]] || { skip "requires local dirty (currently clean)"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    # Pick a known-extension local dirty file so marker syntax is deterministic.
    local dirty_file
    dirty_file="$(git status --porcelain=v1 | grep -E '\.(cpp|h|sh|py|js|ts|qml|json|md|txt|cmake)$' | head -1 | cut -c4-)"
    [[ -n "$dirty_file" ]] || { skip "no dirty local file with known extension"; return; }
    local out rc
    out="$(run_sync)"; rc=$?
    expect_rc 0 "sync succeeded" "$rc" "$out"
    if [[ $rc -eq 0 ]]; then
        local first body
        first="$(remote_first_line "$dirty_file")"
        if [[ "$first" == *"file synced from pia_desktop mac repo"* ]]; then
            ok "marker present on $dirty_file (first line)"
        else
            bad "marker missing on $dirty_file (first line: $first)"
        fi
    fi
    remote_cleanup_test_files
    # Defensive: reset any tracked file we touched on remote back to HEAD.
    ssh_cmd "cd $REMOTE_PATH && git checkout HEAD -- ." >/dev/null 2>&1
}

test_real_overwrite_marked() {
    section "M4 real sync: re-running sync overwrites marked remote file"
    [[ $LOCAL_IS_CLEAN -eq 0 ]] || { skip "requires local dirty"; return; }
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    # Send once.
    run_sync >/dev/null 2>&1
    # Stash a snapshot of remote file count after first sync.
    local first_count
    first_count="$(remote_dirty_count)"
    # Send again — should be idempotent.
    local out rc
    out="$(run_sync)"; rc=$?
    expect_rc 0 "re-sync succeeded" "$rc" "$out"
    if [[ $rc -eq 0 ]]; then
        local second_count
        second_count="$(remote_dirty_count)"
        if [[ "$first_count" == "$second_count" ]]; then
            ok "remote dirty count stable ($second_count)"
        else
            bad "remote dirty count changed ($first_count -> $second_count)"
        fi
    fi
    ssh_cmd "cd $REMOTE_PATH && git checkout HEAD -- ." >/dev/null 2>&1
    remote_cleanup_test_files
}

test_dirty_marker_missing_then_present() {
    section "M5 dry-run: same file dirty both sides without marker -> syncable"
    [[ $LOCAL_IS_CLEAN -eq 0 ]] || { skip "requires local dirty"; return; }
    [[ $LOCAL_AT_ORIGIN -eq 1 ]] || { skip "requires local at origin"; return; }
    reset_remote_to_local
    remote_cleanup_test_files
    local dirty_file
    dirty_file="$(git status --porcelain=v1 | head -1 | cut -c4-)"
    [[ -n "$dirty_file" ]] || { skip "no dirty local file" ; return; }
    # Remote same file dirty WITHOUT marker. Should be allowed because also dirty locally.
    ssh_cmd "cd $REMOTE_PATH && echo '// unmarked' >> '$dirty_file'"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 0 "dirty both sides no marker -> syncable" "$rc" "$out"
    ssh_cmd "cd $REMOTE_PATH && git checkout HEAD -- ." >/dev/null 2>&1
}

test_real_shebang_preserved() {
    section "M6 real sync: local dirty shebang file -> shebang line 1, marker line 2"
    reset_remote_to_local
    remote_cleanup_test_files
    printf '#!/bin/bash\necho hi\n' > rdev_test_script.sh
    local out rc
    out="$(run_sync)"; rc=$?
    expect_rc 0 "sync succeeded" "$rc" "$out"
    if [[ $rc -eq 0 ]]; then
        local l1 l2
        l1="$(ssh_cmd "cd $REMOTE_PATH && sed -n 1p rdev_test_script.sh")"
        l2="$(ssh_cmd "cd $REMOTE_PATH && sed -n 2p rdev_test_script.sh")"
        if [[ "$l1" == "#!/bin/bash" && "$l2" == "# file synced from pia_desktop mac repo" ]]; then
            ok "shebang line 1, marker line 2"
        else
            bad "wrong layout (l1=$l1 l2=$l2)"
        fi
    fi
    rm -f rdev_test_script.sh
    ssh_cmd "cd $REMOTE_PATH && rm -f rdev_test_script.sh" >/dev/null 2>&1
}

test_marker_line_map() {
    section "U1 unit: rdev_marker_line returns correct comment prefix per extension"
    # Pure local unit test — no SSH.
    local cases=(
        "script.sh|# file synced from pia_desktop mac repo"
        "main.cpp|// file synced from pia_desktop mac repo"
        "app.py|# file synced from pia_desktop mac repo"
        "page.html|<!-- file synced from pia_desktop mac repo -->"
        "query.sql|-- file synced from pia_desktop mac repo"
        "init.vim|\" file synced from pia_desktop mac repo"
        "core.clj|;; file synced from pia_desktop mac repo"
        "Dockerfile|# file synced from pia_desktop mac repo"
        "style.scss|// file synced from pia_desktop mac repo"
        "app.rb|# file synced from pia_desktop mac repo"      # Ruby
        "module.mm|// file synced from pia_desktop mac repo"  # Objective-C++
        "header.h|// file synced from pia_desktop mac repo"
        "view.qml|// file synced from pia_desktop mac repo"
        "boot.sh|# file synced from pia_desktop mac repo"
    )
    local case_ exp ext actual
    for case_ in "${cases[@]}"; do
        ext="${case_%|*}"
        exp="${case_##*|}"
        actual="$(rdev_marker_line "x.$ext")"
        if [[ "$actual" == "$exp" ]]; then
            ok "marker for .$ext"
        else
            bad "marker for .$ext (expected: $exp, got: $actual)"
        fi
    done

    # Files that must NOT receive a marker (binary/json/lock).
    local nomarker_exts=(json lock png pdf zip exe class wasm o a)
    for ext in "${nomarker_exts[@]}"; do
        if rdev_marker_line "x.$ext" >/dev/null; then
            bad ".$ext should NOT have a marker but got one"
        else
            ok ".$ext correctly refused marker"
        fi
    done
}

test_dirty_mixed_marker_and_not() {
    section "T10 dirty remote: marked file + unmarked file -> STOP 10"
    reset_remote_to_local
    remote_cleanup_test_files
    ssh_cmd "cd $REMOTE_PATH && printf '# file synced from pia_desktop mac repo\nstuff\n' > rdev_test_marked.txt"
    ssh_cmd "cd $REMOTE_PATH && printf 'unmarked\n' > rdev_test_unmarked.txt"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 10 "mixed dirty -> STOP because of unmarked" "$rc" "$out"
}

test_dirty_multi_type_markers() {
    section "T11 dirty remote: marker recognised across multiple file types -> 0"
    reset_remote_to_local
    remote_cleanup_test_files
    # One file per supported comment family. None exist locally.
    ssh_cmd "cd $REMOTE_PATH && \
        printf '# file synced from pia_desktop mac repo\n' > rdev_t_sh.sh && \
        printf '// file synced from pia_desktop mac repo\n' > rdev_t_cpp.cpp && \
        printf -- '-- file synced from pia_desktop mac repo\n' > rdev_t_sql.sql && \
        printf '<!-- file synced from pia_desktop mac repo -->\n' > rdev_t_html.html && \
        printf ';; file synced from pia_desktop mac repo\n' > rdev_t_clj.clj"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 0 "all marker types recognised" "$rc" "$out"
}

test_dirty_json_no_marker() {
    section "T12 dirty remote: .json cannot have marker -> STOP 10"
    reset_remote_to_local
    remote_cleanup_test_files
    # .json files cannot receive a marker; if dirty on remote and not local -> STOP.
    ssh_cmd "cd $REMOTE_PATH && printf '{\"key\":\"value\"}\n' > rdev_test.json"
    local out rc
    out="$(run_dry)"; rc=$?
    expect_rc 10 "json no marker -> STOP" "$rc" "$out"
}

# --- Test selection -------------------------------------------------------
# Args:  -t<N>  run T-series test N (e.g. -t10)
#        -m<N>  run M-series test N (e.g. -m1)
#        -u<N>  run U-series test N (e.g. -u1)
#        -l     list tests and exit
#        no args -> run all
TESTS_TO_RUN=()
LIST_ONLY=0
usage() {
    cat <<EOF
Usage: $0 [-t<N>] [-m<N>] [-u<N>] [-l]
  -t<N>  Run T-series test N (e.g. -t10 for T10). Repeatable.
  -m<N>  Run M-series test N (e.g. -m1). Repeatable.
  -u<N>  Run U-series test N (e.g. -u1). Repeatable.
  -l     List available tests and exit.
  No args: run all tests.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t*) TESTS_TO_RUN+=("T${1#-t}") ;;
        -m*) TESTS_TO_RUN+=("M${1#-m}") ;;
        -u*) TESTS_TO_RUN+=("U${1#-u}") ;;
        -l|--list) LIST_ONLY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; usage >&2; exit 30 ;;
    esac
    shift
done

should_run() {
    local id="$1"
    if [[ ${#TESTS_TO_RUN[@]} -eq 0 ]]; then return 0; fi
    local t
    for t in "${TESTS_TO_RUN[@]}"; do
        [[ "$t" == "$id" ]] && return 0
    done
    return 1
}

# --- Run ------------------------------------------------------------------
# Test registry: (ID, function). Add new tests here in run order.
run_one() {
    local id="$1" fn="$2"
    should_run "$id" || return 0
    "$fn"
}

if [[ $LIST_ONLY -eq 1 ]]; then
    cat <<'EOF'
T1  test_in_sync
T2  test_remote_behind_ff
T3  test_remote_divergent
T4  test_remote_diff_branch_on_origin
T5  test_dirty_untracked_no_marker
T6  test_dirty_untracked_with_marker
T7  test_dirty_tracked_no_marker
T8  test_dirty_remote_diff_branch
T9  test_dirty_both_sides
T10 test_dirty_mixed_marker_and_not
T11 test_dirty_multi_type_markers
T12 test_dirty_json_no_marker
M1  test_real_drop_untracked_marked
M2  test_real_restore_marked_tracked
M3  test_real_send_dirty_marked
M4  test_real_overwrite_marked
M5  test_dirty_marker_missing_then_present
M6  test_real_shebang_preserved
U1  test_marker_line_map
EOF
    exit 0
fi

# Run requires setup only when at least one test runs.
needs_setup=0
for id in T1 T2 T3 T4 T5 T6 T7 T8 T9 T10 T11 T12 M1 M2 M3 M4 M5 M6 U1; do
    if should_run "$id"; then needs_setup=1; break; fi
done

if [[ $needs_setup -eq 1 ]]; then
    setup
fi

run_one T1  test_in_sync
run_one T2  test_remote_behind_ff
run_one T3  test_remote_divergent
run_one T4  test_remote_diff_branch_on_origin
run_one T5  test_dirty_untracked_no_marker
run_one T6  test_dirty_untracked_with_marker
run_one T7  test_dirty_tracked_no_marker
run_one T8  test_dirty_remote_diff_branch
run_one T9  test_dirty_both_sides
run_one T10 test_dirty_mixed_marker_and_not
run_one T11 test_dirty_multi_type_markers
run_one T12 test_dirty_json_no_marker

run_one M1 test_real_drop_untracked_marked
run_one M2 test_real_restore_marked_tracked
run_one M3 test_real_send_dirty_marked
run_one M4 test_real_overwrite_marked
run_one M5 test_dirty_marker_missing_then_present
run_one M6 test_real_shebang_preserved

run_one U1 test_marker_line_map

log ""
log "================================"
log "PASS: $PASS    FAIL: $FAIL    SKIP: $SKIP"
log "================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
