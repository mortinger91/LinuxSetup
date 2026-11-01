# shellcheck shell=bash
# rdev — file transfer with "synced from pia_desktop mac repo" marker.
#
# Files copied to remote get a marker comment as the first line (after any
# shebang/XML/PHP prolog). Comment syntax is chosen by file extension.
# On subsequent syncs, any remote dirty file bearing the marker is safe to
# overwrite or drop. Remote dirty files WITHOUT the marker (and not dirty
# locally) cause a hard STOP — they may represent uncommitted user work.
#
# Exit codes propagated from callers; this lib returns 0/1 from checkers.

# Canonical marker body. Comment prefix is added by rdev_marker_line.
RDEV_MARKER_BODY="file synced from pia_desktop mac repo"

# Print the marker line (with comment prefix) for a file path. Returns 1 if
# the file type has no safe inline comment syntax (binary/json/lock/etc).
rdev_marker_line() {
    local f="$1"
    local base="${f##*/}" ext=""
    if [[ "$base" == *.* ]]; then
        ext="${base##*.}"
    else
        ext="$base"   # e.g. Dockerfile, Makefile, Rakefile
    fi
    local lower
    lower="$(printf '%s' "$ext" | tr 'A-Z' 'a-z')"

    # File types where adding any comment would corrupt the file.
    case "$lower" in
        json|lock|map|\
        png|jpg|jpeg|gif|webp|ico|bmp|tiff|heic|\
        pdf|zip|tar|gz|tgz|bz2|7z|rar|xz|\
        exe|dll|so|dylib|bin|dat|db|sqlite|class|jar|war|wasm|\
        o|a|lib|obj|pdb|\
        otf|ttf|woff|woff2|eot|\
        mp3|mp4|avi|mov|webm|wav|flac|ogg|aac|\
        min)
            return 1 ;;
    esac

    case "$lower" in
        sh|bash|zsh|fish|py|rb|pl|ps1|yaml|yml|toml|conf|cfg|properties|\
        ini|dockerfile|makefile|gitignore|dockerignore|md|rst|txt|hs|cabal|\
        gradle|rake|gemspec|gemfile|env|tf|hcl|nix|props|sample|awk|sed|\
        vimrc|screenrc|editorconfig|cmake|service|snippets|desktop|appdata|manifest)
            echo "# $RDEV_MARKER_BODY" ;;
        c|cc|cpp|cxx|h|hh|hpp|hxx|java|kt|js|jsx|ts|tsx|go|rs|swift|scala|\
        groovy|m|mm|cs|php|dart|proto|ktm|kts|v|sv|vala|glsl|vert|frag|\
        qml|scss|sass|less|styl)
            echo "// $RDEV_MARKER_BODY" ;;
        sql|lua|ada|elm|sml|haskell)
            echo "-- $RDEV_MARKER_BODY" ;;
        vim|viml)
            echo "\" $RDEV_MARKER_BODY" ;;
        html|htm|xml|svg|xhtml|vue|rss|atom|owl|rdf|xul|tsd|dtd|xsig|resx)
            echo "<!-- $RDEV_MARKER_BODY -->" ;;
        lisp|scm|clj|cljs|cljc|edn|rkt|el|elc)
            echo ";; $RDEV_MARKER_BODY" ;;
        erl|hrl)
            echo "%% $RDEV_MARKER_BODY" ;;
        *)
            # Unknown text-like file — default to `#` (POSIX-friendly).
            echo "# $RDEV_MARKER_BODY" ;;
    esac
}

# Build a marked copy of $1 at $2. Preserves shebang/XML declaration/PHP open
# tag on line 1 by inserting the marker as line 2. Falls back to a plain copy
# (no marker) for files whose type doesn't support comments.
rdev_make_marked_copy() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || { echo "rdev_make_marked_copy: source missing: $src" >&2; return 22; }

    local marker first
    marker="$(rdev_marker_line "$src")" || {
        # No safe comment syntax — copy as-is (no marker; treated as "unknown"
        # if found dirty on remote without local counterpart).
        cp "$src" "$dst" || return 22
        return 0
    }
    first="$(head -1 "$src")"
    {
        if [[ "$first" == "#!"* || "$first" == "<?xml"* || "$first" == "<?php"* ]]; then
            printf '%s\n' "$first"
            printf '%s\n' "$marker"
            tail -n +2 "$src"
        else
            printf '%s\n' "$marker"
            cat "$src"
        fi
    } > "$dst"
}

# Check whether a remote file contains the marker. Looks at first 2 lines so
# shebang/XML-prolog files are still recognised. Returns 0 if marker found.
# Args: host os cd_path file
rdev_remote_file_has_marker() {
    local host="$1" os="$2" cd_path="$3" file="$4"
    local out
    if [[ "$os" == "windows" ]]; then
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $cd_path; \$l = Get-Content -LiteralPath '$file' -TotalCount 2 -ErrorAction SilentlyContinue; if (\$l -match '$RDEV_MARKER_BODY') { 'YES' } else { 'NO' }" 2>&1)"
        out="${out//$'\r'/}"
    else
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $cd_path && head -2 '$file' 2>/dev/null | grep -q '$RDEV_MARKER_BODY' && echo YES || echo NO" 2>&1)"
    fi
    [[ "$out" == *"YES"* ]]
}

# Check whether a remote file is tracked by git. Returns 0 if tracked.
# Args: host os cd_path file
rdev_remote_file_is_tracked() {
    local host="$1" os="$2" cd_path="$3" file="$4"
    local out
    if [[ "$os" == "windows" ]]; then
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $cd_path; if (git ls-files --error-unmatch '$file' 2>\$null) { 'YES' } else { 'NO' }" 2>&1)"
        out="${out//$'\r'/}"
    else
        out="$(/usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $cd_path && git ls-files --error-unmatch '$file' >/dev/null 2>&1 && echo YES || echo NO" 2>&1)"
    fi
    [[ "$out" == *"YES"* ]]
}

# Restore a remote file to HEAD (tracked) or delete it (untracked).
# Args: host os cd_path file
rdev_remote_restore_file() {
    local host="$1" os="$2" cd_path="$3" file="$4"
    if rdev_remote_file_is_tracked "$host" "$os" "$cd_path" "$file"; then
        if [[ "$os" == "windows" ]]; then
            /usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
                "Set-Location $cd_path; git checkout HEAD -- '$file'" >/dev/null 2>&1
        else
            /usr/bin/ssh -A -n -o BatchMode=yes "$host" \
                "cd $cd_path && git checkout HEAD -- '$file'" >/dev/null 2>&1
        fi
    else
        if [[ "$os" == "windows" ]]; then
            /usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
                "Set-Location $cd_path; Remove-Item -LiteralPath '$file' -Force -ErrorAction SilentlyContinue" >/dev/null 2>&1
        else
            /usr/bin/ssh -A -n -o BatchMode=yes "$host" \
                "cd $cd_path && rm -f '$file'" >/dev/null 2>&1
        fi
    fi
}

# Delete a remote file (used when local has deleted the file).
# Args: host os cd_path file
rdev_remote_delete_file() {
    local host="$1" os="$2" cd_path="$3" file="$4"
    if [[ "$os" == "windows" ]]; then
        /usr/bin/ssh -A -n -o BatchMode=yes "$host" powershell -NoProfile -Command \
            "Set-Location $cd_path; Remove-Item -LiteralPath '$file' -Force -ErrorAction SilentlyContinue" >/dev/null 2>&1
    else
        /usr/bin/ssh -A -n -o BatchMode=yes "$host" \
            "cd $cd_path && rm -f '$file'" >/dev/null 2>&1
    fi
}

# Transfer a single local file to the remote, prepending the marker.
# Skips files that don't exist locally (caller should handle deletion).
# Args: host os rel_repo_path local_file
rdev_transfer_file_marked() {
    local host="$1" os="$2" rel_path="$3" file="$4"
    [[ -f "$file" ]] || { echo "skip (gone locally): $file"; return 0; }

    local tmpdir="/tmp/rdev-marked-$$"
    mkdir -p "$tmpdir"
    local marked="$tmpdir/marked"
    rdev_make_marked_copy "$file" "$marked" || { rm -rf "$tmpdir"; return 22; }

    /usr/bin/scp -q -T "$marked" "$host:$rel_path/$file"
    local rc=$?
    rm -rf "$tmpdir"
    [[ $rc -eq 0 ]] || { echo "scp failed for $file" >&2; return 22; }
    echo "  -> $file"
}
