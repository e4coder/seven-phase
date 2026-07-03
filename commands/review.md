---
description: Read the current phase's Forgejo PR review comments and address them within the current phase (STOPs if no phase PR is open, and posts one summary reply; never opens, merges, closes, resolves, or advances a phase)
argument-hint: [feature-slug]
allowed-tools: Read, Edit, Grep, Glob, Bash, mcp__plugin_seven-phase_forgejo__list_pull_requests, mcp__plugin_seven-phase_forgejo__pull_request_read, mcp__plugin_seven-phase_forgejo__issue_read, mcp__plugin_seven-phase_forgejo__issue_write
model: claude-opus-4-8
disable-model-invocation: true
---
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Forgejo target (read `owner=`, `repo=`, and `default_branch=` from here):
!`cat .llm/forgejo 2>/dev/null || echo "MISSING - run /seven-phase:init after adding a 'forgejo' git remote"`

Feature: **$ARGUMENTS**. Recent commits (derive the CURRENT phase from the latest `phaseN($ARGUMENTS)` subject):
!`git log -8 --pretty=format:'%h %s'`

You are reading the CURRENT phase's Forgejo PR and consuming my review feedback via the
`forgejo` MCP server (gitea-mcp). Its write tools are COARSE: `issue_write` can also close/edit -
the tool whitelist CANNOT stop that, so the limit is on YOU. Use EXACTLY this one write action
and nothing else:
  - `issue_write` with `method:"add_comment"` ONLY     (to post one summary reply)
NEVER call `issue_write` with method update / edit_comment / *label*. NEVER open, merge, close,
resolve a thread, or advance a phase - I do all of that by hand (phases open and merge their own
PRs; /review only reads and comments).

1. Push the branch so Forgejo has it: `git push forgejo HEAD` (current phase branch =
   `feat/$ARGUMENTS-p<N>`).
2. Find the CURRENT phase's PR: derive the current phase N from the latest `phaseN($ARGUMENTS)`
   commit above, then `list_pull_requests` {owner, repo, state:"open"} and match the one whose
   head branch is `feat/$ARGUMENTS-p<N>`. If none is open, STOP and tell me to run
   `/seven-phase:phase<N>` first (phases open their own PR; /review never opens or merges one).
3. Read every piece of feedback for that PR number (a PR's number == its issue number):
   - conversation comments: `issue_read` {method:"get_comments", owner, repo, issue_number:<n>}
   - reviews: `pull_request_read` {method:"get_reviews", owner, repo, pull_number:<n>}
   - inline comments per review: `pull_request_read` {method:"get_review_comments", owner, repo,
     pull_number:<n>, review_id:<id>}
   - PR details/diff if needed: `pull_request_read` {method:"get" | "get_diff" | "get_files", ...}
   List what you found before acting.
4. Address each comment STRICTLY within the current phase's contract (phase 0 plan text;
   phase 1 structs; phase 2 signatures/stubs; phase 3 TODO markers; phase 5 invariants;
   phase 6 real code only). A comment demanding out-of-phase work is a REWIND signal, not
   license to improvise: do NOT do it - record it as Deferred and name the earlier phase I
   must change.
5. If feedback changes the recorded plan, update the matching `## Phase N` of `.llm/$ARGUMENTS/plan.md`.
6. If the current phase runs code (4 or 6), re-run validation and keep it green:
   !`cat .llm/validation 2>/dev/null || echo "no validation set - run /seven-phase:init"`
   Never weaken tests or invariants to pass.
7. Commit: `git add -A && git commit -m "review($ARGUMENTS): address PR feedback (phaseN)"`
   then `git push forgejo HEAD` so the PR updates.
8. Post ONE summary reply: `issue_write` {method:"add_comment", owner, repo, issue_number:<n>,
   body:<markdown>} listing what you **Addressed** (comment -> sha) and what is **Deferred**
   (comment -> phase to rewind to). gitea-mcp has no per-thread reply or thread-resolve tool, so
   this single conversation comment is the whole reply.

STOP. Print the same Addressed / Deferred lists here and wait for my re-review - you resolve
nothing, merge nothing, close nothing, and advance nothing.
