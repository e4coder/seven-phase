---
description: Rewind a feature to an earlier phase - discard the phases built after it and replay, carrying a note of why (destructive; forgejo only, never origin; you invoke it, never Claude)
argument-hint: [feature-slug] [phase-number-K]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Forgejo target:
!`cat .llm/forgejo 2>/dev/null || echo "MISSING - run /seven-phase:init"`

Capture the plugin root for the reset step:
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot`

Arguments: **$ARGUMENTS** = `<feature-slug> <K>` (e.g. `treasury 2`). Recent commits:
!`git log -8 --pretty=format:'%h %s'`

You are REWINDING feature `<f>` to phase `<K>`: discard phases K..current and replay, carrying
a note of WHY so the redo avoids the same mistake. Destructive on the `forgejo` mirror ONLY -
NEVER `origin`. Order matters (the reset wipes `plan.md`, so capture the reason FIRST):

1. Parse `<f>` and `<K>` from $ARGUMENTS. K must be 1, 2, 3, or 5.
2. **Capture the rationale FIRST**, before any reset: read `.llm/<f>/plan.md` - especially
   `## Phase 4` (the dry-run deviation report) - plus any deferred review comments I gave you,
   and write yourself a concise summary: what was wrong, which artifact/phase K must change,
   and what to do differently. Hold it for step 4.
3. Run the reset (resets `feat/<f>` to the phase-(K-1) anchor tag, force-pushes `forgejo` only,
   deletes the orphaned phase branches + stale tags):
   !`echo "run: bash \"$(cat .llm/.pluginroot)/scripts/phase-flow.sh\" rewind $ARGUMENTS"`
   Run that command via Bash. If it errors (missing anchor tag, K out of range, not configured),
   STOP and report exactly what it said - do NOT improvise a reset by hand.
4. The reset reverted `.llm/<f>/plan.md` to its phase-(K-1) state (`## Phase K..` blank). Write
   the rationale from step 2 into `## Phase K` as a `### Rewind note` (what was wrong + what to
   change this time). Commit: `git add .llm/<f>/plan.md && git commit -m "rewind(<f>): note for phase <K> redo"`,
   then `git push --force-with-lease forgejo HEAD`. NEVER push `origin`.
5. STOP. Report: "Rewound `<f>` to phase `<K>`; the plan's Rewind note is in place. Run
   /seven-phase:phase<K> to redo it." Do NOT run the next phase yourself.
