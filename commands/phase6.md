---
description: Phase 6 - real implementation
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 6 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Feature: **$ARGUMENTS**. Read `.llm/$ARGUMENTS/plan.md` end to end.

Phase 6 - IMPLEMENT FOR REAL:
1. Implement every phase-3 TODO using the phase-1 structs, phase-2 interfaces, and phase-5 invariants. Apply corrections from the Phase 4 report.
2. Replace all phase-2 stubs. Remove the `TODO($ARGUMENTS)` markers as you complete them.
3. Run the validation command until it passes:
   !`cat .llm/validation 2>/dev/null || echo "MISSING - run /seven-phase:init"`
   Do NOT weaken tests or invariants to pass. If you cannot satisfy them, STOP and report.
4. Record an implementation summary under `## Phase 6` in the plan.
5. Commit: `git add -A && git commit -m "phase6($ARGUMENTS): implementation"`.

STOP. The feature is ready for my final review / PR.
