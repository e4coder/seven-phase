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
4. Commit: `git add -A && git commit -m "phase3($ARGUMENTS): todo map"`, then open/refresh this phase's PR by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 3`.

STOP and wait for review. Do not start Phase 4.
