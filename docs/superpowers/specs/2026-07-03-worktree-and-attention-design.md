# Design: Worktree safety + per-phase attention digest

**Date:** 2026-07-03
**Status:** Approved (design), pending implementation plan
**Component:** seven-phase plugin — `scripts/phase-flow.sh`, `commands/phase0.md`…`phase6.md`, `PROTOCOL.md`/`README.md`

## Purpose

Two independent, small improvements to the per-phase-PR flow:
1. **Worktree safety** — let each feature run in its own git worktree (so multiple sessions
   work in parallel, and a session open in the main folder is never disrupted), instead of the
   plugin's in-place `git checkout` colliding across worktrees.
2. **Per-phase attention digest** — when a phase opens its PR, post a prioritized
   "review-first" comment so the human triages what matters first.

## Context

- The per-phase model (`scripts/phase-flow.sh`) drives branches with in-place `git checkout feat/<f>`
  / `git checkout -b feat/<f>-p<N>`. Git allows a branch to be checked out in only ONE worktree,
  so running a feature's phase command from the wrong directory (e.g. the main repo while
  `feat/<f>` is checked out in a worktree) collides — the failure seen on the "treasury" project.
- `finish` opens the phase PR via `curl` against the Forgejo API (no MCP). Forgejo is a dev-cycle
  mirror; `origin` is off-limits.
- Chosen approach (from design): **A** — the user creates the worktree; the plugin works cleanly
  inside it and guides if run from the wrong place. The attention digest is a **PR comment**
  (not the PR description), **folded into `finish`** (not a separate command).

## Design

### Part 1: Worktree safety

- **Wrong-worktree guard** in `phase-flow.sh`: a helper reads `git worktree list --porcelain`
  and, before any checkout of a feature branch (`feat/<f>` in `sync_integration`/phase-0, and
  `feat/<f>-p<N>` when cutting a phase branch), checks whether that branch is checked out in a
  worktree **other than the current one** (`git rev-parse --show-toplevel`). If so, it `die`s
  with: *"feature `<f>` (branch `<b>`) is checked out at `<path>` — run this command from
  there."* — instead of letting git's raw collision leave partial state.
- **Phase-0 robustness:** `start 0` already uses `feat/<f>` if it exists
  (`git show-ref … || git branch …`), so creating the worktree with
  `git worktree add ../wt-<f> -b feat/<f> main` (which pre-creates `feat/<f>`) works — verify the
  checkout is a clean no-op when already on it.
- **No new command.** The user creates the worktree; the README documents the exact
  `git worktree add` command and the one-worktree-per-feature workflow.
- **Main folder uninterrupted** is automatic: git worktrees are isolated working dirs, and the
  plugin only ever touches the current dir + that feature's own refs (`feat/<f>`, `feat/<f>-p<N>`,
  its tags) — never `main` or another feature's refs.

### Part 2: Per-phase attention digest

- **`finish <f> <N> [digest-file]`** gains an optional 3rd arg. After opening the phase PR (and
  determining its number), if `digest-file` is given and non-empty and a PR exists, `finish`
  posts the file's content as a **PR comment** — `POST /repos/<owner>/<repo>/issues/<n>/comments`
  with the body built via `python3` JSON (same escaping the PR-body build uses). Phase 4 (no PR)
  skips it. A failed comment post `warn`s; it never fails the phase.
- **Phase commands (0,1,2,3,5,6):** after committing, the model — which just did the work —
  writes a prioritized digest to `/tmp/seven-phase-digest-<f>-<N>.md` (outside the repo, so no
  `git add -A` ever sweeps it): a `### ⚠️ Needs your attention` section FIRST (decisions to
  confirm, risks/uncertainties, plan deviations, open questions — most-important-first; or
  *"Nothing flagged — routine phase."* when there's nothing), then a brief `### What this phase
  did`. It then calls `finish <f> <N> /tmp/seven-phase-digest-<f>-<N>.md`.
- Content is model-generated per phase (Claude has the phase context); the script only transports it.

## Files

- `scripts/phase-flow.sh` (modify) — worktree-guard helper + guard calls; `finish` digest-comment.
- `commands/phase0.md`…`phase6.md` (modify) — add the "write the digest, pass it to finish" step
  to the commit/finish step (phase 4 opens no PR, so it writes no digest).
- `PROTOCOL.md`, `README.md` (modify) — worktree workflow + the attention-comment behavior.
- `tests/phase-flow.test.sh` (modify) — a guard leg and a digest-comment leg.

## Error handling

| Condition | Behavior |
|---|---|
| Forgejo not configured | `phase-flow.sh` inert (exit 0) — the guard only matters when the script drives branches |
| Target feature branch checked out in another worktree | `die` with the worktree path; no partial checkout |
| `digest-file` missing/empty, or phase has no PR | `finish` skips the comment silently |
| Comment POST fails (network/API) | `warn`; the phase is not failed |
| Any push | targets the `forgejo` remote only — never `origin` (asserted, unchanged) |

## Testing

Extend `tests/phase-flow.test.sh` (live Forgejo, throwaway repo):
- **Guard:** after building a phase or two, add a second worktree that checks out `feat/demo`
  (`git worktree add <tmp> feat/demo`), then run `phase-flow.sh start demo <N>` from the original
  dir and assert it exits non-zero with a "checked out at" message and creates no new phase
  branch; remove the worktree.
- **Attention comment:** run a phase's `finish` with a digest file and assert the phase PR then
  has a comment containing the digest text (`GET /repos/<o>/<r>/issues/<n>/comments`).

## Out of scope (YAGNI)

- Plugin-managed worktree lifecycle (create/list/remove commands) — Approach A is user-creates.
- **Hotfix branches** — a separate feature (next brainstorm cycle).
- Making the attention digest the PR *description* instead of a comment — chosen: comment.

## Constraints

- `origin` never touched; all pushes target `forgejo`.
- The attention comment is posted via `curl` (no MCP), consistent with the rest of `phase-flow.sh`.
- The digest is transient (`/tmp`), never committed.
