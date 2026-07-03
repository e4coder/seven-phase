---
description: Phase 2 - interfaces / signatures only
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 2 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 2`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Phase 2 - INTERFACES ONLY:
1. Add/modify the function and method signatures and any interface/trait types from the plan.
2. Bodies are stubs only: `panic("phase6")` (Go), `unimplemented!()` (Rust), `throw new Error("phase6")` (TS), `revert("phase6")` (Solidity).
3. Record the final signatures under `## Phase 2` in the plan.
4. Commit: `git add -A && git commit -m "phase2($ARGUMENTS): interfaces"`. Then write a concise review-first digest to `/tmp/seven-phase-digest-$ARGUMENTS-2.md`: a `### ⚠️ Needs your attention` section FIRST - decisions to confirm, risks/uncertainties, deviations from the plan, and open questions, most-important-first (or `Nothing flagged - routine phase.` when there is nothing) - then a brief `### What this phase did`. Open/refresh this phase's PR and attach the digest by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 2 /tmp/seven-phase-digest-$ARGUMENTS-2.md`.

STOP and wait for review. Do not start Phase 3.
