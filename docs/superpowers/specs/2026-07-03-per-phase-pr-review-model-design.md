# Design: Per-phase-PR review model

**Date:** 2026-07-03
**Status:** Approved (design), pending implementation plan
**Component:** seven-phase plugin — all `commands/phaseN.md`, `commands/review.md`, `PROTOCOL.md`, new `scripts/phase-flow.sh`, new `commands/finish.md`, `commands/init.md`/`scripts/forgejo-setup.sh`

## Purpose

Replace the single-feature-PR review loop with **one PR per phase** into a feature
integration branch, so each phase is reviewed and validated as a discrete unit (fixing
"I can't tell what I've already reviewed in one big accumulating PR"). The final squash to
the developer's real `main` is a **manual human step** — the plugin operates entirely on the
Forgejo dev-cycle mirror and **never touches `origin`**.

## Context

- Today: `/seven-phase:review` opens/updates one PR per `feat/<f>` branch that accumulates
  every phase. Review progress is hard to track.
- Forgejo is a dev-cycle mirror; the developer's real remote (`origin`) is the source of
  truth. **The plugin must never push to `origin`** — final integration is manual.
- Hard gate: the human invokes each `/phaseN`; Claude never self-advances
  (`disable-model-invocation: true` on every phase command). This is preserved.
- Backward compatibility: the plugin must still work for users **without** Forgejo
  configured (the original inline-diff, commit-only flow).

## Design

### Branch model (all on Forgejo; `origin` untouched)

```
main (seeded on Forgejo) ──●
                            ╲  feat/<f> = integration branch (created off main at phase 0)
        feat/<f> ────────────●────────●────────●─ ...     each ● = one squashed phase
                             ▲        ▲        ▲
    phase branches:   feat/<f>-p0  -p1      -p2  ...       each → PR into feat/<f>
```

- **Integration branch:** `feat/<f>`, created off `main` at phase 0, lives on Forgejo.
- **Phase branches:** `feat/<f>-pN` (hyphen — avoids the `feat/<f>` vs `feat/<f>/…` ref
  nesting conflict). Each opens a PR `feat/<f>-pN → feat/<f>`.
- **Phase PRs for phases 0, 1, 2, 3, 5, 6.** Phase 4 (throwaway dry-run) has **no PR**: it
  runs locally, is discarded, and commits only its deviation report **directly onto
  `feat/<f>`** (no review PR for a report).

### `scripts/phase-flow.sh` (plumbing: git + Forgejo API via `curl`, no MCP)

The merge/branch/PR mechanics are a shell script using `git` + `curl` against the Forgejo
API — the same pattern as `forgejo-setup.sh`. **Claude is never given a merge-capable MCP
tool;** the merge is a deterministic scripted step, triggered only by a human-invoked phase
command. The script is **inert (exit 0) when no `forgejo` remote / env is configured**, so
non-Forgejo users fall back to the original flow.

Two entry points, called by the phase commands:

- `phase-flow.sh start <feature> <N>`:
  1. Phase 0 only: create `feat/<f>` off `main`, push to `forgejo`.
  2. Squash-merge the **currently-open phase PR** (there is at most one, since phases are
     sequential) into `feat/<f>` via the Forgejo merge API, so this phase branches off a
     `feat/<f>` that contains all prior phases. Idempotent: skip if none is open / already
     merged. (Walk-through: phase 1 merges p0; phase 2 merges p1; phase 3 merges p2; phase 4
     merges p3 so the dry-run has the full codebase; phase 5 finds nothing open — phase 4
     opened no PR; phase 6 merges p5. Phase 6's own PR is merged by `/seven-phase:finish`.)
  3. `git fetch forgejo` + fast-forward local `feat/<f>`.
  4. Create `feat/<f>-pN` off `feat/<f>`, check it out.
- `phase-flow.sh finish <feature> <N>`:
  1. Push `feat/<f>-pN` to `forgejo`.
  2. Open PR `feat/<f>-pN → feat/<f>` via the Forgejo API (idempotent: skip if one is open).

All pushes target the `forgejo` remote only. The script **must never reference or push
`origin`** (guarded/asserted).

### Phase commands (`commands/phase0.md` … `phase6.md`)

Each `/seven-phase:phaseN <f>` becomes: inline PROTOCOL → `phase-flow.sh start <f> N` →
Claude does phase N's work per the existing contract (structs/interfaces/TODOs/invariants/
impl) → commit → `phase-flow.sh finish <f> N` → STOP for review. Phase 0 also creates the
integration branch (handled inside `start`).

**Phase 4 is special** (throwaway dry-run): `start` still runs to squash-merge phase 3's
open PR into `feat/<f>` so the dry-run has the full phase-0–3 codebase, but phase 4 works on
`feat/<f>` **directly** (no phase branch), discards its implementation via the existing
`git stash -u && git stash drop` revert, commits only its deviation report onto `feat/<f>`,
and pushes `feat/<f>` to `forgejo`. It calls **no `finish`** and opens **no PR**.

### `commands/review.md`

Targets the **current phase's PR** (the open PR whose head is `feat/<f>-p<current>`, current
phase derived as today from the latest `phaseN(<f>)` commit). Reads that PR's comments,
addresses them **within the current phase**, commits, and pushes `feat/<f>-p<current>` so
that phase PR updates. **Never merges** (merging happens only in the next phase command's
`start`). No `pull_request_write` in its whitelist.

### The end: `/seven-phase:finish <f>`

Phase 6's PR is the last open phase PR, and no later phase exists to merge it. So a small
human-invoked `/seven-phase:finish <f>` closes the loop: it squash-merges phase 6's open PR
into `feat/<f>` **on Forgejo** (a Forgejo action — allowed), then STOPS and **prints** the
manual, origin-touching final step for the human to run by hand:

```
git checkout main && git merge --squash feat/<f> && git commit && git push origin main
```

`/seven-phase:finish` **never runs that** and never pushes `origin`. It is the only new
command; it exists solely because the last phase PR has no successor phase to merge it.

### `PROTOCOL.md` / `init.md` / `README.md`

- PROTOCOL: describe the per-phase-branch/PR model; the scripted prior-phase merge on
  advance; `/review` targets the current phase PR and never merges; `origin` is off-limits.
- `init.md` / `forgejo-setup.sh`: unchanged in the main; the integration branch is created
  at phase 0, not init. (Setup still creates the repo + seeds `main` on Forgejo.)
- README: document the per-phase-PR workflow and the manual finish step.

## Error handling

| Condition | Behavior |
|---|---|
| No `forgejo` remote / Forgejo env unset | `phase-flow.sh` inert (exit 0); phase commands behave as the original commit-only flow |
| Prior-phase PR already merged / absent | Skip the merge, continue (idempotent) |
| Prior-phase merge conflict | Report and STOP (should not happen in the sequential model) |
| Any attempt to touch `origin` | Structurally impossible — the script only ever pushes `forgejo`; asserted |

## Backward compatibility

With no Forgejo configured, every phase command falls back to today's behavior (do the phase
work, commit locally, STOP) — `phase-flow.sh` is a no-op. The Forgejo per-phase-PR flow is
strictly additive/opt-in.

## Testing

Shell integration test for `scripts/phase-flow.sh` against the live Forgejo instance: create
an integration branch, run `start`/`finish` for a couple of phases, assert the phase branches
+ PRs exist, assert the prior-phase PR is squash-merged into `feat/<f>` on the next `start`,
assert idempotency, and assert **no `origin` remote is ever created or pushed**. Teardown the
throwaway repo. (Same harness style as `tests/forgejo-setup.test.sh`.)

## Out of scope (YAGNI)

- Final squash to the real `main` + push to `origin` — manual human step; plugin only prints it.
- Parallel/stacked phase development — phases are strictly sequential (the protocol requires it).
- Rebasing an already-merged early phase — if an earlier phase must change, the existing
  "rewind" guidance applies; automatic stack rebasing is not built.

## Security / constraints

- The plugin never pushes `origin`; only the `forgejo` remote.
- Forgejo token/host from env only, never in the repo (unchanged from the current model).
- No MCP merge tool is exposed to Claude; merges are scripted + human-triggered.
