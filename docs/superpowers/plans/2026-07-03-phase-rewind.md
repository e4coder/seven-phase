# Phase Rewind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/seven-phase:rewind <feature> <K>` so the human can discard phases K…current and replay forward, carrying a "rewind note" into the redone phase.

**Architecture:** `phase-flow.sh` gains (a) anchor **tagging** of each phase's squash commit at merge time and (b) a `rewind` subcommand that resets the integration branch to the phase-(K−1) tag and force-pushes **forgejo only**. A new `commands/rewind.md` captures *why* (before the reset), runs the reset, then writes the note into `plan.md`'s now-blank `## Phase K`.

**Tech Stack:** Bash, `git`, `curl`, Forgejo REST API. No new deps.

## Global Constraints

- The plugin ONLY pushes/fetches the `forgejo` remote — **NEVER `origin`**. The rewind force-push targets `forgejo`; any `origin` reference is a defect.
- Rewind is destructive and **human-invoked only** (`disable-model-invocation: true`); Claude never self-rewinds.
- Anchors are git tags named `seven-phase/<feature>/phase<N>`. Rewind resets to `seven-phase/<feature>/phase<K-1>`; refuse to reset if that tag is missing (never guess a reset point).
- Valid `K` ∈ {1, 2, 3, 5} and `K < current`. Never rewind *to* phase 4 (throwaway) or phase 0 (out of scope — start over by hand).
- `phase-flow.sh` stays **inert (exit 0)** without Forgejo.
- Token via `curl -K -` stdin only, never argv (existing pattern).
- Spec: `docs/superpowers/specs/2026-07-03-phase-rewind-design.md`.

---

## File Structure

- `scripts/phase-flow.sh` (modify) — add anchor tagging in `sync_integration`; add the `rewind` subcommand.
- `tests/phase-flow.test.sh` (modify) — add a rewind leg (build phases → assert tags → rewind → assert reset + cleanup + origin-untouched).
- `commands/rewind.md` (new) — the human-facing command.
- `PROTOCOL.md`, `README.md` (modify) — document rewind.

---

## Task 1: `phase-flow.sh` anchor tagging + `rewind` subcommand + test

**Files:**
- Modify: `scripts/phase-flow.sh`
- Modify: `tests/phase-flow.test.sh`

**Interfaces:**
- Consumes: existing `phase-flow.sh` globals `$FEATURE`, `$N`, `$INT` (=`feat/$FEATURE`), `$OWNER`, `$REPO`, and the `sync_integration`/`open_phase_pr`/`squash_merge`/`api` helpers; the `forgejo` remote; `.llm/forgejo`.
- Produces: tags `seven-phase/<feature>/phase<N>` on the integration branch; CLI `phase-flow.sh rewind <feature> <K>` that resets `feat/<feature>` to the phase-(K−1) tag, force-pushes `forgejo`, and deletes orphaned phase branches + stale tags. Consumed by `commands/rewind.md` (Task 2).

- [ ] **Step 1: Read the current script + test**

Read `scripts/phase-flow.sh` and `tests/phase-flow.test.sh` in full so you match the existing helper names, quoting, and the `case "$CMD"` structure exactly. In particular note `sync_integration`, `open_phase_pr`, `squash_merge`, the `api()` helper, and the test's helper functions (e.g. `check`, the status/body curl helpers, the `gwait`/poll helper, `work.txt` commit pattern, and the teardown trap).

- [ ] **Step 2: Write the failing test leg**

Append a rewind leg to `tests/phase-flow.test.sh`, BEFORE the final `[ "$FAILED" -eq 0 ] && echo ALL PASS …` line. Adapt the helper names to the ones already in the file (shown here as `status`/`gbody`/`check` — use the file's actual names). It builds phases 0→2, starts phase 3, then rewinds to 2:

```bash
echo '--- rewind: build phases 0,1,2, start 3, then rewind to 2 ---'
# phase 2: commit real work on the current phase branch, open its PR
echo p2 >> work.txt && git add work.txt && git -c user.email=t@t -c user.name=t commit -q -m "phase2(demo): interfaces"
bash "$FLOW" finish demo 2 >/dev/null
# phase 3 start: merges p2 into feat/demo (creating the phase2 tag) and cuts feat/demo-p3
bash "$FLOW" start demo 3 >/dev/null
check "phase2 anchor tag exists"        "git rev-parse -q --verify refs/tags/seven-phase/demo/phase2 >/dev/null"
check "phase1 anchor tag exists"        "git rev-parse -q --verify refs/tags/seven-phase/demo/phase1 >/dev/null"
P1_TIP="$(git rev-parse seven-phase/demo/phase1)"
# rewind to phase 2 (redo interfaces): reset feat/demo to phase1 anchor
bash "$FLOW" rewind demo 2 >/dev/null
git checkout -q feat/demo
check "feat/demo reset to phase1 anchor" "[ \"\$(git rev-parse feat/demo)\" = \"$P1_TIP\" ]"
check "phase-2 work gone from feat/demo" "! git show feat/demo:work.txt | grep -qx p2"
check "phase2 tag deleted"               "! git rev-parse -q --verify refs/tags/seven-phase/demo/phase2 >/dev/null"
check "feat/demo-p3 branch deleted"      "! git rev-parse -q --verify refs/heads/feat/demo-p3 >/dev/null"
check "rewind never created origin"      "! git remote get-url origin >/dev/null 2>&1"
```

- [ ] **Step 3: Run the test to verify the new leg fails**

Run: `source ~/.config/bunyad/forgejo.env && bash tests/phase-flow.test.sh`
Expected: the earlier checks pass, but the new `rewind` leg fails — `bash "$FLOW" rewind demo 2` errors ("unknown command: rewind") since tagging + the subcommand don't exist yet, so the `feat/demo reset to phase1 anchor` and tag/branch-deletion checks FAIL.

- [ ] **Step 4: Add anchor tagging to `sync_integration`**

In `scripts/phase-flow.sh`, at the END of the `sync_integration` function (after it checks out `$INT`, fetches, and `merge --ff-only`s), append these two lines so every phase advance records an anchor for the phase that was just merged (`$N` is the phase being started; `$((N-1))` is the one just merged onto `feat/<f>`):

```bash
  git tag -f "seven-phase/$FEATURE/phase$((N-1))" >/dev/null 2>&1
  git push -f forgejo "seven-phase/$FEATURE/phase$((N-1))" >/dev/null 2>&1 || msg "WARNING: could not push anchor tag phase$((N-1))"
```

- [ ] **Step 5: Add the `rewind` subcommand**

In the `case "$CMD" in` block of `scripts/phase-flow.sh`, add a new `rewind)` arm (place it before the final `*)` catch-all):

```bash
  rewind)
    [ -n "$N" ] || die "rewind needs <K> (the phase to rewind to)"
    case "$N" in 1|2|3|5) ;; *) die "rewind target must be phase 1, 2, 3, or 5 (got '$N')";; esac
    # current phase = highest existing anchor tag + 1
    top="$(git tag -l "seven-phase/$FEATURE/phase*" | sed 's#.*/phase##' | grep -E '^[0-9]+$' | sort -n | tail -1)"
    [ -n "$top" ] || die "no anchor tags for $FEATURE - nothing to rewind"
    cur=$((top + 1))
    [ "$N" -lt "$cur" ] || die "cannot rewind to phase $N; current phase is ~$cur (must go backward)"
    anchor="seven-phase/$FEATURE/phase$((N-1))"
    git rev-parse -q --verify "refs/tags/$anchor" >/dev/null || die "anchor tag $anchor missing - refusing to reset to a guessed point"
    git checkout "$INT" 2>/dev/null || die "local $INT missing"
    git reset --hard "$anchor" || die "reset $INT to $anchor failed"
    git push --force-with-lease forgejo "$INT" || die "force-push $INT to forgejo failed"
    msg "reset $INT to $anchor (phase $((N-1)) state); force-pushed forgejo"
    # discard the orphaned phase branches + stale tags for phases N..cur
    m="$N"
    while [ "$m" -le "$cur" ]; do
      git branch -D "feat/$FEATURE-p$m" >/dev/null 2>&1 && msg "deleted local branch feat/$FEATURE-p$m"
      git push forgejo --delete "feat/$FEATURE-p$m" >/dev/null 2>&1
      git tag -d "seven-phase/$FEATURE/phase$m" >/dev/null 2>&1
      git push forgejo --delete "seven-phase/$FEATURE/phase$m" >/dev/null 2>&1
      m=$((m + 1))
    done
    msg "rewound $FEATURE to phase $N - run /seven-phase:phase$N to redo it"
    ;;
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `source ~/.config/bunyad/forgejo.env && bash tests/phase-flow.test.sh`
Expected: every `ok - …`, `ALL PASS`, exit 0 — including the new rewind checks (`feat/demo reset to phase1 anchor`, `phase-2 work gone`, `phase2 tag deleted`, `feat/demo-p3 branch deleted`, `rewind never created origin`). Throwaway repo cleaned up by teardown.

- [ ] **Step 7: Commit**

```bash
git add scripts/phase-flow.sh tests/phase-flow.test.sh
git commit -m "feat(phase-flow): anchor tags + rewind subcommand (reset to phase K-1, forgejo-only force-push)"
```

---

## Task 2: `commands/rewind.md`

**Files:**
- Create: `commands/rewind.md`

**Interfaces:**
- Consumes: `phase-flow.sh rewind <feature> <K>` (Task 1); `.llm/.pluginroot` capture pattern (same as the phase commands).
- Produces: the `/seven-phase:rewind` command.

- [ ] **Step 1: Create the command**

Create `commands/rewind.md`:

```markdown
---
description: Rewind a feature to an earlier phase - discard the phases built after it and replay, carrying a note of why (destructive; forgejo only, never origin; you invoke it, never Claude)
argument-hint: [feature-slug] [phase-number-K]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
model: claude-opus-4-8
disable-model-invocation: true
---
Rules (always follow):
!`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`

Forgejo target:
!`cat .llm/forgejo 2>/dev/null || echo "MISSING - run /seven-phase:init"`

Capture the plugin root for the reset step:
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot`

Arguments: **$ARGUMENTS** = `<feature-slug> <K>` (e.g. `treasury 2`). Recent commits:
!`git log -8 --pretty=format:'%h %s'`

You are REWINDING feature `<f>` to phase `<K>`: discard phases K..current and replay, carrying
a note of WHY so the redo avoids the same mistake. Destructive on the `forgejo` mirror ONLY -
NEVER `origin`. Order matters (the reset wipes `plan.md`, so capture the reason FIRST):

1. Parse `<f>` and `<K>` from $ARGUMENTS. K must be 1, 2, 3, or 5.
2. **Capture the rationale FIRST**, before any reset: read `.llm/<f>/plan.md` - especially
   `## Phase 4` (the dry-run deviation report) - plus any deferred review comments I gave you,
   and write yourself a concise summary: what was wrong, which artifact/phase K must change,
   and what to do differently. Hold it for step 4.
3. Run the reset (resets `feat/<f>` to the phase-(K-1) anchor tag, force-pushes `forgejo` only,
   deletes the orphaned phase branches + stale tags):
   !`echo "run: bash \"$(cat .llm/.pluginroot)/scripts/phase-flow.sh\" rewind $ARGUMENTS"`
   Run that command via Bash. If it errors (missing anchor tag, K out of range, not configured),
   STOP and report exactly what it said - do NOT improvise a reset by hand.
4. The reset reverted `.llm/<f>/plan.md` to its phase-(K-1) state (`## Phase K..` blank). Write
   the rationale from step 2 into `## Phase K` as a `### Rewind note` (what was wrong + what to
   change this time). Commit: `git add .llm/<f>/plan.md && git commit -m "rewind(<f>): note for phase <K> redo"`,
   then `git push --force-with-lease forgejo HEAD`. NEVER push `origin`.
5. STOP. Report: "Rewound `<f>` to phase `<K>`; the plan's Rewind note is in place. Run
   /seven-phase:phase<K> to redo it." Do NOT run the next phase yourself.
```

- [ ] **Step 2: Verify the command is well-formed and origin-safe**

Run: `grep -n 'push origin\|disable-model-invocation\|phase-flow.sh" rewind' commands/rewind.md`
Expected: `disable-model-invocation: true` present; the `phase-flow.sh … rewind` invocation present; NO `push origin` anywhere (only `--force-with-lease forgejo`).

- [ ] **Step 3: Commit**

```bash
git add commands/rewind.md
git commit -m "feat(rewind): /seven-phase:rewind command (capture reason, reset, write rewind note)"
```

---

## Task 3: Document rewind (PROTOCOL + README)

**Files:**
- Modify: `PROTOCOL.md`, `README.md`

**Interfaces:**
- Consumes: behavior from Tasks 1-2.
- Produces: accurate protocol + operator docs.

- [ ] **Step 1: Update PROTOCOL.md**

Read `PROTOCOL.md`. After the existing per-phase / review-loop rules, add a rule describing rewind (adapt wording to fit the surrounding bullet style):

```markdown
- Rewind is supported and human-invoked only. Phase 4's dry-run report is the canonical trigger:
  if it shows an earlier struct/interface/TODO was insufficient, run `/seven-phase:rewind <feature> <K>`
  to discard phases K..current and replay from K. Rewind resets the integration branch to the
  phase-(K-1) anchor and force-pushes the `forgejo` remote ONLY (never `origin`); it records a
  `### Rewind note` under `## Phase K` in the plan so the redo avoids the same mistake. Claude
  never rewinds on its own.
```

- [ ] **Step 2: Update README.md**

Read `README.md`. In the Forgejo review-loop section, after the per-feature recipe, add a short "Rewinding" subsection:

```markdown
### Rewinding a phase

Phase 4 is a throwaway dry-run whose report exists to reveal that an earlier phase's
struct/interface/TODO was wrong. When it does, rewind:

       /seven-phase:rewind <f> 2     # discard phases 2..current, reset feat/<f> to the phase-1
                                     # anchor, force-push forgejo (never origin), and record a
                                     # Rewind note under ## Phase 2 of the plan
       /seven-phase:phase2 <f>       # redo phase 2 - the Rewind note tells you what to change

Valid targets are phases 1, 2, 3, and 5 (below the current phase). It's destructive on the
Forgejo mirror only; `origin` is never touched. Redoing the whole plan (phase 0) means starting
the feature over by hand.
```

- [ ] **Step 3: Verify docs mention rewind + origin-safety**

Run: `grep -n 'rewind\|Rewind note\|origin' PROTOCOL.md README.md | grep -i rewind`
Expected: both files document `/seven-phase:rewind`, phase 4 as the trigger, the Rewind note, and forgejo-only/origin-untouched.

- [ ] **Step 4: Commit**

```bash
git add PROTOCOL.md README.md
git commit -m "docs: document /seven-phase:rewind (phase-4-triggered, forgejo-only, rewind note)"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** anchor tags (T1 Step 4), `rewind` subcommand with validate/reset/force-push-forgejo/cleanup (T1 Step 5), the K∈{1,2,3,5}/K<current/anchor-must-exist guards (T1 Step 5), capture-then-reset-then-write-note ordering (T2 command steps 2-4), origin-never-touched (T1 force-push targets forgejo + test asserts no origin; T2 grep), replay via existing `/phaseK` (T2 step 5), tests (T1 Steps 2/6), PROTOCOL+README (T3). K=0 excluded per spec. No gaps.
- **Placeholder scan:** none — full shell for the tagging + `rewind` case + test leg + command file; doc blocks are concrete (implementer adapts wording to surrounding style, which is explicit, not a placeholder).
- **Name consistency:** tag format `seven-phase/<feature>/phase<N>`, branch format `feat/<feature>-p<N>`, subcommand `rewind`, and `.llm/.pluginroot` capture are used identically across tasks and match the existing `phase-flow.sh` conventions.
