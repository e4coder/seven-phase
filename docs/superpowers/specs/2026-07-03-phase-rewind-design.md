# Design: Phase rewind for the per-phase-PR model

**Date:** 2026-07-03
**Status:** Approved (design), pending implementation plan
**Component:** seven-phase plugin — new `commands/rewind.md`, additions to `scripts/phase-flow.sh`, `PROTOCOL.md`/`README.md`

## Purpose

Let the human **rewind to an earlier phase** — discard everything built after it and replay
forward — with a **rewind note** carried into the redone phase so the same mistake isn't
repeated. This restores a capability the 7-phase protocol is built around (phase 4 is a
throwaway dry-run whose entire purpose is to reveal that an earlier struct/interface/TODO is
wrong and trigger a rewind) that the per-phase-PR model removed by making the pipeline
strictly forward-only.

## Context

- The per-phase-PR model (`scripts/phase-flow.sh`) is forward-only: each phase's PR is
  **squash-merged** into the integration branch `feat/<f>` when the next phase's `start` runs,
  then a new phase branch `feat/<f>-p<N>` is cut. There is no reverse path.
- The original (pre-Forgejo) flow rewound trivially via `git reset` on the single feature
  branch. The per-phase model broke that: downstream phases are baked into `feat/<f>` as squash
  commits with no boundary to reset to.
- Forgejo is a **dev-cycle mirror**; the developer's real remote (`origin`) is the source of
  truth. **The plugin must never push `origin`** — force-pushing the integration branch is
  fine because it only ever targets `forgejo`.
- Hard gate: the human invokes each command; Claude never advances or rewinds on its own.

## Design

### New command: `/seven-phase:rewind <feature> <K>`

Human-invoked and explicit (a destructive reset must be deliberate — **never** auto-triggered
by re-running `/phaseK`). Valid `K` is an **artifact phase below the current one** (1, 2, 3, or
5 — you rewind *from* a phase-4 report or later *to* an earlier phase; never *to* the throwaway
phase 4). Rewinding to phase 0 (redo the whole plan) is out of scope — that's effectively
starting the feature over (see Out of scope). Inert (exit 0) without Forgejo, like the rest of
`phase-flow.sh`.

### Anchoring: git tags on each phase's squash commit

`scripts/phase-flow.sh` `sync_integration` (which merges the open phase PR and fast-forwards
local `feat/<f>` during `start N`) additionally **tags** the resulting integration tip:

```
git tag -f "seven-phase/<f>/phase<N-1>" feat/<f>
git push -f forgejo "seven-phase/<f>/phase<N-1>"      # forgejo only
```

So `seven-phase/<f>/phaseM` always points at `feat/<f>` as it was right after phase M was
merged. Rewind resets to `seven-phase/<f>/phase<K-1>` — an exact, self-owned anchor (chosen
over commit-message matching, which depends on Forgejo's squash-message format and is unsafe
for a destructive reset).

### `phase-flow.sh rewind <feature> <K>` — the mechanics

Ordered so the rewind note survives the reset:

1. **Preflight & validate.** Forgejo configured; derive the current phase (highest existing
   `seven-phase/<f>/phaseM` tag, +1 for any in-progress branch); require `1 ≤ K < current` and
   `K != 4`; require the `phase<K-1>` tag to exist — else `die`
   (never reset to a guessed point).
2. **Reset** `feat/<f>` hard to `seven-phase/<f>/phase<K-1>`. This
   also reverts the tracked `plan.md` to its phase-(K-1) state — `## Phase K..` become blank
   again automatically (no separate blanking needed).
3. **Force-push `forgejo` only** (`git push --force-with-lease forgejo feat/<f>`). Guarded so
   it can never target `origin`.
4. **Cleanup:** delete the orphaned phase branches `feat/<f>-pK … feat/<f>-p<current>` (local +
   Forgejo) and the stale tags `seven-phase/<f>/phaseK … phase<current>` (local + Forgejo).
   The already-merged phase PRs stay **closed** as review history.
5. Leave `feat/<f>` checked out at the anchor. STOP.

The **rewind note** itself is written by the command wrapper (below), not the script, because
it needs the model to synthesize it.

### `commands/rewind.md` — the human-facing flow

1. **Capture the rationale first** (before any reset): the model reads the phase-4 deviation
   report (`## Phase 4` in `plan.md`, still present pre-reset), any deferred review comments,
   and the human's stated reason, and holds a concise "why we're rewinding to phase K" summary.
2. Run `phase-flow.sh rewind <feature> K` (does steps 2-5 above).
3. **Write the captured rationale** into the now-blank `## Phase K` of `plan.md` as a
   `### Rewind note` (what was wrong, which artifact must change, what to do differently),
   commit it onto `feat/<f>`, and `git push --force-with-lease forgejo feat/<f>`.
4. STOP and tell the human to run `/seven-phase:phaseK` — the existing forward machinery
   replays from K, and `phaseK`'s "read plan.md at the start" step surfaces the Rewind note so
   the redo avoids the prior mistake.

### Replay

No new replay logic — after rewind, current-phase detection reads phase K-1 (the reset tip),
so `/seven-phase:phaseK` is the natural next step and `phase-flow.sh start K` cuts a fresh
`feat/<f>-pK` off the reset `feat/<f>`. Phases replay K, K+1, … normally (re-tagging as they
re-merge, via `git tag -f`).

### `PROTOCOL.md` / `README.md`

Document the rewind command, that phase 4's report is the canonical rewind trigger, the
force-push-`forgejo`-only / `origin`-off-limits guarantee, and the Rewind-note memory.

## Error handling

| Condition | Behavior |
|---|---|
| Forgejo not configured | `rewind` inert (exit 0) |
| `K` out of range / `K == 4` / `K ≥ current` | `die` with a clear message; no reset |
| `phase<K-1>` anchor tag missing | `die` (refuse to guess a reset point) |
| Any attempt to touch `origin` | Structurally impossible — force-push targets `forgejo` only; asserted |
| Local `feat/<f>` diverged unexpectedly | `--force-with-lease` fails safe rather than clobbering |

## Testing

Extend `tests/phase-flow.test.sh` against the live Forgejo: build up phases 0-2 (real diffs),
assert `seven-phase/<f>/phaseM` tags are created on merge; run `phase-flow.sh rewind <f> 2`;
assert `feat/<f>` is reset to the `phase1` tag, `plan.md` reverted (Phase-2 section blank
again), the `feat/<f>-p2` branch + `phase2` tag are gone (local + Forgejo), the phase-1 PR
remains closed, and **no `origin` remote exists / is pushed**. Teardown the throwaway repo.

## Out of scope (YAGNI)

- Iterating the *current, unmerged* phase — already handled by `/seven-phase:review` (address
  comments on the open phase PR).
- Non-destructive rewind (revert commits) — rejected during design.
- Cross-machine anchor sync beyond pushing tags to `forgejo`.
- Automatic reconciliation of downstream phases — rewind discards them by design.
- Rewinding to phase 0 (redo the whole plan) — effectively starting the feature over; do it by
  hand (delete `feat/<f>` and its `seven-phase/<f>/*` tags, re-run `/seven-phase:phase0`).

## Security / constraints

- The plugin never pushes `origin`; force-push targets `forgejo` only (asserted).
- Rewind is destructive and human-invoked only; Claude never self-rewinds.
- Refuse to reset without an exact anchor tag (no message-guessing).
