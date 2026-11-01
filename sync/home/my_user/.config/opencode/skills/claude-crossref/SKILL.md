---
name: claude-crossref
description: >
  Cross-reference the current question with Claude Code (claude-fable-5).
  Trigger when the user says "also ask claude", "check with claude",
  "cross-reference with claude", or any similar phrasing asking for a
  second opinion from Claude Code on the same question opencode is
  already answering. Runs the script `scripts/claude-crossref` which
  calls `claude -p` read-only on the current repo and writes a merged
  cross-reference file to /tmp.
---

# Claude Cross-Reference

**Run `scripts/claude-crossref`. Never invoke `claude` directly.**

## Location

`~/.config/opencode/skills/claude-crossref/scripts/claude-crossref`

## When to trigger

User appends "also ask claude" (or close variant) to any question to
opencode. Examples:

- "Is the sun yellow? also ask claude"
- "How do I fix this bug? check with claude"
- "cross-reference with claude: should I use approach A or B?"

## Workflow (do exactly this, in order)

1. Answer the user's question yourself, as you normally would, using the
   active opencode model. Hold this answer — do not print it yet.
2. Run the script, passing your own answer and the user's question:

   ```bash
   ~/.config/opencode/skills/claude-crossref/scripts/claude-crossref \
     --question "<the user's verbatim question>" \
     --opencode-answer "<your answer, as plain text>"
   ```

   The script prints a file path on its last stdout line
   (e.g. `/tmp/opencode-claude-cross-0`). It never overwrites existing
   files; nonce increments for each call in the session.

   If a question or answer is long, multiline, or contains shell-unsafe
   characters, write each to a temp file first and use the `-file`
   variants instead:

   ```bash
   ~/.config/opencode/skills/claude-crossref/scripts/claude-crossref \
     --question-file /tmp/opencode-q.txt \
     --opencode-answer-file /tmp/opencode-a.txt
   ```

3. Read the cross-reference file the script returned. It contains four
   sections, in order:

   ```
   question: <user's question>
   opencode answer: <your original answer>
   claude answer: <claude code's answer>
   claude opinion on opencode answer: <claude's comparison>
   ```

4. Produce the **final merged answer** to the user, taking into account:
   - Your original answer
   - Claude's answer
   - Claude's opinion on your answer

   The final answer must:
   - Clearly state whether the two answers are **similar** or
     **different**.
   - If they differ, identify which one is correct (or more correct) and
     why, and flag the one that went off track if either did.
   - Enhance your original answer with anything Claude's answer added
     that yours missed.
   - Briefly attribute which agent/model produced which part, e.g.
     "Opencode (glm-5.2) found X; Claude (claude-fable-5) found Y."
     Use the model names you actually know are in use; do not invent
     model IDs.
   - Keep the attribution terse — one short clause per contribution, not
     a running commentary.

5. Do not show the raw /tmp file to the user unless they ask. Show only
   your final merged answer.

## Rules

1. Run the script verbatim. Report script failures verbatim with the
   exit code; do not paper over them.
2. Never call `claude` yourself — always go through the script. The
   script enforces read-only tool access (--allowed-tools "Read Grep
   Glob") so Claude Code cannot edit the repo.
3. Do not modify the /tmp cross-reference file after the script writes
   it. It is the audit trail for the exchange.
4. If the script's exit code is non-zero, surface the error and stop; do
   not fall back to calling `claude` inline.
5. The script picks the next free nonce automatically; you do not need
   to compute it.