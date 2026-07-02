---
description: Read-only review of the latest change against the plan
argument-hint: [feature-slug]
allowed-tools: Read, Grep, Glob, Bash
model: claude-sonnet-4-6
disable-model-invocation: true
---
Rules for reference:
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Feature: **$ARGUMENTS**.

Uncommitted diff:
!`git diff`
Last commit:
!`git show HEAD --stat`
!`git diff HEAD~1 HEAD`

Against `.llm/$ARGUMENTS/plan.md`, review the changes hunk by hunk. For each hunk: does it match the current phase's contract? Flag anything out of scope (logic in phases 1-3, code left behind from phase 4, drive-by edits, new deps). Do NOT edit anything. Output a checklist: hunk -> verdict -> action.
