---
name: fixup
description: >
  MANDATORY when the user says "fixup", "fix up", "fixup commits", "fixup the
  changes", "absorb into commits", "fold these changes into the right commits",
  or otherwise asks to distribute working-dir changes into existing branch
  commits. Reads the diff (staged + unstaged + untracked), matches each hunk to
  the branch commit it belongs to, and creates UNSIGNED `fixup!` commits via
  `scripts/fixup-hunks`. Changes that fit no commit stay in the working dir,
  each with a reason. Never rebases, pushes, or signs.
---

# Fixup

**Always go through `scripts/fixup-hunks`. Never run `git commit --fixup`, `git add -p`,
`git apply`, or `git absorb` inline for this job.**

Script: `~/.config/opencode/skills/fixup/scripts/fixup-hunks`

```bash
fixup-hunks range   [--base REF]                 # base, commits C1..Cn, upstream
fixup-hunks list    [--base REF] [-U N] [--max-lines N]   # items H*/U* + blame hints
fixup-hunks execute PLAN.json | -                # one unsigned fixup! per target
fixup-hunks check-autosquash [--base REF]        # in-memory autosquash dry run
```

## Hard rules

1. **Never sign fixup commits.** The script forces `-c commit.gpgsign=false --no-gpg-sign` and
   verifies no `gpgsig` header. Never pass `-S`/`--gpg-sign`, never re-commit them yourself.
2. Only create `fixup!` commits. No rebase, no `--autosquash`, no push, no `--no-verify`, no
   amend. The user squashes.
3. Never edit working-tree files to make a hunk fit. The script only writes the index.
4. Unsure → leave it. A leftover the user re-homes is cheap; a hunk in the wrong commit is not.

## Workflow

1. `fixup-hunks list`. It prints base (PR base via `gh`, else `origin/HEAD`), commits `C1..Cn`
   oldest first, then every item:
   - `H<n>` — a hunk of `git diff HEAD`. New/deleted/binary/mode-change files are one whole item.
   - `U<n>` — an untracked file (always whole).
   - `blame:` which commit last touched the lines the hunk removes or sits between (`base` =
     older than the branch). `touched by:` commits that touched the file (or dir, for `U*`).
   Fixup commits already on the branch are shown as `[-> Ck]`; blame and targets resolve to Ck.
   If the base looks wrong (stacked PR), re-run with `--base <ref>`.
2. **Read every candidate target**: `git show --stat <sha>` and the relevant part of
   `git show <sha> -- <path>`. Matching on file names alone is not enough.
3. Assign each item (see "Matching"). If one `-U3` hunk mixes concerns, re-run `list -U0`
   (finest split; ids change, so plan against the new listing).
4. Write the plan and execute:
   ```bash
   cat > /tmp/fixup-plan.json <<'EOF'
   {"H1": "C2", "H2": "leave", "H3": "C1", "U1": "C2"}
   EOF
   fixup-hunks execute /tmp/fixup-plan.json
   ```
   Values: `Cn`, a sha in range, or `leave`. Omitted ids are left too (with a warning). Execute
   refuses if HEAD or the working dir changed since `list`. No confirmation step needed —
   fixup commits rewrite nothing and undo is one command.
5. Read the autosquash dry run execute prints at the end (exit 5 = conflict). On conflict, a
   hunk was given to a commit older than the one introducing its context: undo
   (`git reset <orig>` from the output), fix the plan, run again.
6. Report (format below).

## Matching

Assign to commit C when **either**:
- blame points only to C (or C plus `base` context the same change obviously belongs to) and
  C's diff confirms the hunk fixes/finishes what C did; or
- by meaning, the hunk completes C's concern — same feature, a follow-up C forgot (test for C's
  code, call site of C's new function, review fix on C's lines). Untracked files match this way.

**Leave** in the working dir when:
- it is a new concern: changes `base` code no branch commit was about, or a feature none of the
  commits introduced;
- it fits two or more commits about equally;
- blame and meaning disagree and the diff of the blamed commit does not settle it;
- it cannot be split from a part that belongs elsewhere, even at `-U0` (adjacent lines);
- the target would be a merge commit, or blame points to a commit that is not in range.

Never assign to a commit just because it is the newest or touched the file.

## Hook failures

Pre-commit hooks run on each fixup commit (normal). If one fails, the script stops (exit 3),
keeps fixups already made, resets the index; it never touches the working tree.
- Formatter rewrote files (clang-format, qmlformat, black, end-of-file-fixer…): **retry once** —
  `list` again (the reformatted lines now appear in the hunks), re-plan, execute.
- Fails again, or a non-formatting failure (lint, region-metadata bump): stop and report the hook
  output. Do not bypass the hook.

## Report to the user

- Table: fixup commit sha → target `Cn sha subject` → items/files.
- Leftovers: `H<n> path — <one-line reason>` for each.
- Autosquash dry run result.
- Undo: `git reset <orig-head>` (changes come back unstaged; original index+worktree also kept
  at `refs/fixup-hunks/backup`). Staged/unstaged split is not preserved.
- Next step for the user: `git rebase -i --autosquash [--autostash] <base>`; if upstream says
  `published`, a force-push follows. Do not run either.
