---
description: Phase 1 - data structures only
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 1 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 1`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Phase 1 - STRUCTS ONLY:
1. Add/modify the data structures named in the plan. Types, fields, enums only.
2. No function bodies, no logic, no signatures beyond what a type needs.
3. Record the final structures under `## Phase 1` in the plan.
4. Commit: `git add -A && git commit -m "phase1($ARGUMENTS): data structures"`. Then write a concise review-first digest to `/tmp/seven-phase-digest-$ARGUMENTS-1.md`: a `### ⚠️ Needs your attention` section FIRST - decisions to confirm, risks/uncertainties, deviations from the plan, and open questions, most-important-first (or `Nothing flagged - routine phase.` when there is nothing) - then a brief `### What this phase did`. Open/refresh this phase's PR and attach the digest by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 1 /tmp/seven-phase-digest-$ARGUMENTS-1.md`.

STOP and wait for review. Do not start Phase 2.
