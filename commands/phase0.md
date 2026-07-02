---
description: Phase 0 - research the problem + codebase and write the durable plan
argument-hint: [feature-slug]
allowed-tools: Read, Write, Edit, Grep, Glob, WebSearch, WebFetch, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
!`mkdir -p .llm && echo 0 > .llm/.phase`
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS 0`

Feature: **$ARGUMENTS**. Phase 0: research only, no code.

1. Investigate the codebase and problem space for `$ARGUMENTS` (Grep/Glob/Read; web search only if external facts are needed).
2. Create `.llm/$ARGUMENTS/plan.md` containing:
   - `# Feature: $ARGUMENTS`
   - `Status: phase-0`
   - `## Phase 0 - Plan`: the concrete, file-level breakdown of how phases 1-6 will be executed for THIS feature - which structs, which interfaces, which call sites, what the dry-run will exercise, what invariants must hold.
   - Empty headers `## Phase 1` ... `## Phase 6`.
3. No feature code, structs, or signatures yet - only the plan.
4. Commit: `git add -A && git commit -m "phase0($ARGUMENTS): research + plan"`, then open/refresh this phase's PR by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 0`.

STOP and wait for my review. Do not start Phase 1.
