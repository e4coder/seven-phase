---
description: Phase 4 - implement, validate, THROW AWAY, report deviations
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 4 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 4`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Working tree status (must be clean; .llm/.phase is gitignored so ignore it):
!`git status --porcelain`

If the block above is non-empty, STOP and tell me to commit phases 1-3. Otherwise proceed.

Phase 4 - DRY RUN (throwaway):
1. Implement the feature for real, following the phase-3 TODOs, phase-1 structs, phase-2 interfaces.
2. Run the validation command for this repo:
   !`cat .llm/validation 2>/dev/null || echo "MISSING - run /seven-phase:init"`
   Execute it and record pass/fail. If it fails, still continue - the report is the point.
3. Identify EVERY place you had to deviate from the structs, interfaces, or TODOs (new field, changed signature, extra step, missing/insufficient TODO).
4. Write the report to `/tmp/phase4-$ARGUMENTS.md`: the deviation list + validation pass/fail.
5. Throw the implementation away (safe because the tree was clean at entry):
   `git stash -u || true` then `git stash drop || true`.
6. Append the contents of `/tmp/phase4-$ARGUMENTS.md` under `## Phase 4` in `.llm/$ARGUMENTS/plan.md`.
7. Commit only the report: `git add .llm/$ARGUMENTS/plan.md && git commit -m "phase4($ARGUMENTS): dry-run report"`, then run `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 4`.

STOP. If the report shows the structs/interfaces/TODOs were insufficient, rewind to the relevant phase before Phase 5 (with Forgejo configured, run `/seven-phase:rewind <feature> <K>`).
