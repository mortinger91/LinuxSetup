# shellcheck shell=bash
# rdev — machine map, paths, cache helpers
# bash 3.2 compatible (no associative arrays).

# Canonical SSH host for a machine alias.
#
# Windows resolves to proxmox-windows-cmd, NOT proxmox-windows: the latter sets
# `RemoteCommand pwsh -NoLogo` in ~/.ssh/config for interactive use, and ssh
# refuses an explicit command when RemoteCommand is set. proxmox-windows-cmd is
# the same machine with the server default shell (cmd.exe), which every
# `ssh ... powershell -NoProfile -Command "..."` call in this skill relies on.
rdev_resolve_host() {
    case "$1" in
        windows|win)        echo "proxmox-windows-cmd" ;;
        debian|linux)       echo "proxmox-debian" ;;
        *)                  return 1 ;;
    esac
}

# OS family for a canonical host.
rdev_host_os() {
    case "$1" in
        proxmox-windows-cmd) echo "windows" ;;
        proxmox-debian)     echo "linux" ;;
        *)                  return 1 ;;
    esac
}

# Remote repo path. For Windows: relative (scp-friendly, no drive letter).
# For Linux: ~-relative.
rdev_remote_path() {
    case "$1" in
        proxmox-windows-cmd) echo "dev/pia_desktop" ;;
        proxmox-debian)     echo "~/dev/pia_desktop" ;;
        *)                  return 1 ;;
    esac
}

# Remote repo path as used by SSH `cd` (absolute or ~-relative).
rdev_remote_cd() {
    case "$1" in
        proxmox-windows-cmd) echo "\$HOME/dev/pia_desktop" ;;
        proxmox-debian)     echo "~/dev/pia_desktop" ;;
        *)                  return 1 ;;
    esac
}

# Cache dir for resolved build commands / state snapshots.
RDEV_CACHE_DIR="${RDEV_CACHE_DIR:-$HOME/.cache/rdev}"
rdev_cache_dir() { echo "$RDEV_CACHE_DIR/$1"; }

# Markers for build status on remote.
rdev_build_exit_marker() { echo "build.exit"; }
rdev_build_log_marker()  { echo "build.log"; }
rdev_build_err_marker()  { echo "build.err"; }
