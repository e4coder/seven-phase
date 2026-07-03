---
description: Phase 3 - in-place TODO map of every change site
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 3 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 3`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Phase 3 - TODO MAP ONLY:
1. At every location phase 6 will change, insert `// TODO($ARGUMENTS): <precise description>` (use the language's comment syntax).
2. No real implementation - only TODO markers and the phase-2 stubs.
3. List every TODO (file:line + text) under `## Phase 3` in the plan.
4. Commit: `git add -A && git commit -m "phase3($ARGUMENTS): todo map"`. Then write a concise review-first digest to `/tmp/seven-phase-digest-$ARGUMENTS-3.md`: a `### ⚠️ Needs your attention` section FIRST - decisions to confirm, risks/uncertainties, deviations from the plan, and open questions, most-important-first (or `Nothing flagged - routine phase.` when there is nothing) - then a brief `### What this phase did`. Open/refresh this phase's PR and attach the digest by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 3 /tmp/seven-phase-digest-$ARGUMENTS-3.md`.

STOP and wait for review. Do not start Phase 4.
