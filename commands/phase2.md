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

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Phase 2 - INTERFACES ONLY:
1. Add/modify the function and method signatures and any interface/trait types from the plan.
2. Bodies are stubs only: `panic("phase6")` (Go), `unimplemented!()` (Rust), `throw new Error("phase6")` (TS), `revert("phase6")` (Solidity).
3. Record the final signatures under `## Phase 2` in the plan.
4. Commit: `git add -A && git commit -m "phase2($ARGUMENTS): interfaces"`.

STOP and wait for review. Do not start Phase 3.
