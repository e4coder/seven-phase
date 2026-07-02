---
description: Merge the final phase PR into the integration branch on Forgejo, then print the manual origin step (never pushes origin)
argument-hint: [feature-slug]
allowed-tools: Read, Bash
model: claude-sonnet-4-6
disable-model-invocation: true
---
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Feature: **$ARGUMENTS**. All phases are done and their PRs approved. This command squash-merges
the LAST open phase PR into `feat/$ARGUMENTS` on Forgejo, then STOPS. It never touches `origin`.

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" merge-final $ARGUMENTS`

The feature is now fully assembled on the Forgejo integration branch `feat/$ARGUMENTS`.
The final integration to your real remote is a MANUAL step you run by hand (the plugin will
NOT push `origin`):

    git checkout main && git merge --squash feat/$ARGUMENTS && git commit && git push origin main

STOP. Do not run the command above; print it for me and wait.
