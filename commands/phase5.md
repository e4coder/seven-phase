---
description: Phase 5 - invariants / assertions only
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 5 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 5`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md` (including the Phase 4 report).

Phase 5 - INVARIANTS ONLY:
1. Add assertions / invariant checks that must always hold for this feature (preconditions, postconditions, state invariants). Use the project's assertion mechanism.
2. Each invariant must be narrow and verifiable. No feature logic, no control flow beyond the checks.
3. List each invariant and where it is enforced under `## Phase 5` in the plan.
4. Commit: `git add -A && git commit -m "phase5($ARGUMENTS): invariants"`, then open/refresh this phase's PR by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 5`.

STOP and wait for review. Do not start Phase 6.
