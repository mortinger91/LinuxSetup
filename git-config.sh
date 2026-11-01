#!/bin/bash

# Non-interactive global git config, shared by init-config.sh and update-config.sh.
# Idempotent: `git config --global` overwrites, so re-running only applies what changed.
function apply_git_config() {
  git config --global credential.usehttppath true
  git config --global pull.ff only
  git config --global pull.rebase false
  git config --global init.defaultBranch master
  touch /home/$USERNAME/.gitignore_global
  git config --global core.excludesfile /home/$USERNAME/.gitignore_global
  git config --global rerere.enabled true # Remembers git conflict resolution and apply them automatically
  git config --global column.ui auto
  git config --global branch.sort -committerdate
  git config --global alias.pushf "push --force-with-lease"  # does not force push the branch if remote does not match with local branch (e.g. someone pushed on that branch, you never fetched, you rebase and force push deleting all the new commits)
  git config --global alias.fixup "commit --no-gpg-sign --fixup" # git fixup <sha>: unsigned fixup! commit, squashed away by autorebase
  git config --global alias.autorebase "rebase --autostash --autosquash" # git autorebase <base>: fold fixup! commits into their targets, stashing local changes
  git config --global push.useForceIfIncludes true # Harden --force-with-lease: refuse if remote has commits not in your reflog. This means if you fetched but still your branch is not synced with the remote
  git config --global core.autocrlf input # Convert CRLF to LF on commit, never convert on checkout. Prevents Windows line endings from entering repos
  git config --global core.untrackedcache true
  git config --global core.fsmonitor true # This makes git status fast on large repos
}

# Applies apply_git_config and prints only the entries that changed.
function update_git_config() {
  if ! command -v git >/dev/null 2>&1; then
    print_color red "git not installed, skipping git config"
    return
  fi
  local before after
  before=$(git config --global --list 2>/dev/null)
  apply_git_config
  after=$(git config --global --list 2>/dev/null)
  if [ "$before" != "$after" ]; then
    print_color green "Updated global git config:"
    diff <(echo "$before") <(echo "$after") | grep '^[<>]'
  fi
}
