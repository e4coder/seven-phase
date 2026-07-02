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

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md`.

Phase 1 - STRUCTS ONLY:
1. Add/modify the data structures named in the plan. Types, fields, enums only.
2. No function bodies, no logic, no signatures beyond what a type needs.
3. Record the final structures under `## Phase 1` in the plan.
4. Commit: `git add -A && git commit -m "phase1($ARGUMENTS): data structures"`.

STOP and wait for review. Do not start Phase 2.
