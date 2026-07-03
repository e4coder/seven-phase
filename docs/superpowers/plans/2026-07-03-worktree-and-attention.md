# Worktree safety + per-phase attention digest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `phase-flow.sh` safe to run per-feature git worktrees, and post a prioritized "review-first" digest as a comment on each phase PR.

**Architecture:** Two additive, backward-compatible changes to `scripts/phase-flow.sh` — a fail-safe worktree guard that only `die`s on a *positively confirmed* cross-worktree branch collision, and an optional 4th `digest-file` arg to `finish` that posts the file as a PR comment after opening the PR. Phase commands write the digest and pass it; docs describe the worktree workflow. Everything degrades to today's behavior when the arg is absent or Forgejo is unconfigured.

**Tech Stack:** Bash, `curl` against Forgejo REST API, `python3` for JSON, git worktrees.

## Global Constraints

- The plugin NEVER touches `origin` — all pushes target the `forgejo` remote only. (Unchanged; do not add any `origin` operation.)
- `phase-flow.sh` stays inert (exit 0) when Forgejo is not configured (the existing guard at the top).
- The worktree guard must be **fail-safe**: it may `die` ONLY when it can positively confirm the branch is checked out at a path different from the current worktree root; on any ambiguity/parse failure it must return 0 and let the existing `git checkout` run unchanged.
- `finish` with no 4th arg must behave byte-for-byte as today.
- No MCP — the digest comment is posted via `curl`, like the rest of the script.
- The digest file is transient; the phase commands write it under `/tmp`, never committed.
- `python3` is already required by `phase-flow.sh` (guaranteed available where the guard/comment run).

---

### Task 1: Worktree guard in `phase-flow.sh`

**Files:**
- Modify: `scripts/phase-flow.sh` (add `assert_branch_free` helper; call it before the four in-place checkouts)
- Test: `tests/phase-flow.test.sh` (new guard leg)

**Interfaces:**
- Produces: `assert_branch_free <branch>` — `die`s iff `<branch>` is checked out in a worktree whose realpath differs from `git rev-parse --show-toplevel`; otherwise returns 0. Uses `$FEATURE` for the message.

- [ ] **Step 1: Add the failing test leg** to `tests/phase-flow.test.sh`, before the final `[ "$FAILED" -eq 0 ]` line. At this point `WORK` is checked out on `feat/demo` (from the rewind-to-5 section), so move it off first, then create a second worktree that holds `feat/demo`:

```bash
echo '--- worktree guard: a feature branch checked out elsewhere blocks in-place ops ---'
git checkout -q main
WT="$(mktemp -d)"; git worktree add -q "$WT" feat/demo
guard_out="$(bash "$FLOW" start demo 7 2>&1)"; guard_rc=$?
check "guard blocks start when feat/demo lives in another worktree" "[ $guard_rc -ne 0 ]"
check "guard names the other worktree path" "printf '%s' \"\$guard_out\" | grep -q 'checked out at'"
git worktree remove --force "$WT" 2>/dev/null; rm -rf "$WT"
git checkout -q feat/demo
```

- [ ] **Step 2: Run the test, expect the new leg to FAIL** (guard not implemented yet — `start demo 7` currently proceeds/errs differently, not with "checked out at"):

Run: `bash tests/phase-flow.test.sh 2>&1 | grep -E 'guard'`
Expected: `FAIL - guard blocks ...` and/or `FAIL - guard names ...`

- [ ] **Step 3: Add the `assert_branch_free` helper** to `scripts/phase-flow.sh`, immediately after the `api()` helper (after line 37):

```bash
# Fail-safe worktree guard. die ONLY when <branch> is positively confirmed checked
# out in a worktree whose realpath differs from the current one. Any ambiguity or
# parse failure -> return 0 (let the subsequent git checkout run exactly as before,
# so this can never be worse than today's behavior).
assert_branch_free(){ # assert_branch_free <branch>
  local branch="$1" here other
  here="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  other="$(git worktree list --porcelain 2>/dev/null | python3 -c '
import os, sys
here = os.path.realpath(sys.argv[1]); want = "refs/heads/" + sys.argv[2]
path = None
for line in sys.stdin:
    line = line.rstrip("\n")
    if line.startswith("worktree "):
        path = line[9:]
    elif line.startswith("branch ") and line[7:] == want:
        if path and os.path.realpath(path) != here:
            print(path); break
' "$here" "$branch" 2>/dev/null)" || return 0
  [ -n "$other" ] && die "feature '$FEATURE' (branch $branch) is checked out at $other - run this command from there"
  return 0
}
```

- [ ] **Step 4: Insert guard calls** at the four in-place checkouts:

In `sync_integration()`, make it the FIRST line of the function body (before `local num`):
```bash
  assert_branch_free "$INT"
```

In the `start` case, at the top of the `if [ "$N" = "0" ]; then` block (before `git show-ref ... || git branch "$INT" "$BASE"`):
```bash
      assert_branch_free "$INT"
```

In the `start` case, before cutting the phase branch — immediately before `git show-ref --verify --quiet "refs/heads/$PB" && git branch -D "$PB"` (the `else` of the phase-4 check):
```bash
      assert_branch_free "$PB"
```

In the `rewind` case, immediately before `git checkout "$INT" 2>/dev/null || die "local $INT missing"`:
```bash
    assert_branch_free "$INT"
```

- [ ] **Step 5: Run the full test, expect ALL PASS** (new guard leg passes; every existing leg unaffected because the harness runs in a single worktree):

Run: `bash tests/phase-flow.test.sh`
Expected: `ALL PASS` (exit 0)

- [ ] **Step 6: Commit**

```bash
git add scripts/phase-flow.sh tests/phase-flow.test.sh
git commit -m "feat(phase-flow): fail-safe worktree guard on in-place checkouts"
```

---

### Task 2: `finish` posts the attention digest

**Files:**
- Modify: `scripts/phase-flow.sh` (add `post_pr_comment` helper; capture PR number in `finish`; post the digest)
- Test: `tests/phase-flow.test.sh` (assert the digest comment appears)

**Interfaces:**
- Consumes: `open_phase_pr` (existing), `api` (existing).
- Produces: `finish <feature> <N> [digest-file]` — after opening the PR, if `digest-file` is given and non-empty and a PR number is known, posts the file's content as an issue/PR comment. Phase 4 returns before this (no PR). Never fails the phase.

- [ ] **Step 1: Add the failing test assertions.** In `tests/phase-flow.test.sh`, in the phase-1 section, write a digest file and pass it to `finish`, then assert the comment lands. Replace the existing line `bash "$FLOW" finish "$F" 1 >/dev/null` (the one just before `P1=...`) with:

```bash
printf '### \342\232\240\357\270\217 Needs your attention\n- confirm the Ledger struct shape\n\n### What this phase did\n- added structs\n' > "$WORK/digest1.md"
bash "$FLOW" finish "$F" 1 "$WORK/digest1.md" >/dev/null
```

Then, immediately after the existing `check "phase 1 PR opened" ...` line, add:

```bash
check "attention digest posted as a comment on the phase-1 PR" "gbody \"$API/repos/$OWNER/$NAME/issues/$P1/comments\" | grep -q 'Needs your attention'"
```

- [ ] **Step 2: Run the test, expect the new assertion to FAIL** (digest posting not implemented):

Run: `bash tests/phase-flow.test.sh 2>&1 | grep -i 'attention digest'`
Expected: `FAIL - attention digest posted ...`

- [ ] **Step 3: Add the `post_pr_comment` helper** to `scripts/phase-flow.sh`, right after `open_phase_pr()` (after its closing `}`):

```bash
post_pr_comment(){ # post_pr_comment <pr-number> <file>
  local num="$1" file="$2" body
  body="$(python3 -c 'import json,sys; print(json.dumps({"body": open(sys.argv[1], encoding="utf-8").read()}))' "$file" 2>/dev/null)" \
    || { msg "WARNING: could not read digest $file - skipping comment"; return 0; }
  local code; code="$(api POST "/repos/$OWNER/$REPO/issues/$num/comments" "$body" | tail -1)"
  case "$code" in
    201) msg "posted attention digest to PR #$num" ;;
    *)   msg "WARNING: could not post attention digest (status $code)" ;;
  esac
}
```

- [ ] **Step 4: Wire it into `finish`.** In the `finish` case, capture the optional arg and rework the PR-open block to keep the PR number. Replace:

```bash
    code="$(api POST "/repos/$OWNER/$REPO/pulls" "$local_body" | tail -1)"
    case "$code" in
      201) msg "opened PR $PB -> $INT" ;;
      409) msg "PR for $PB already open (updated by push)" ;;
      *) msg "WARNING: could not open PR (status $code)" ;;
    esac
```

with:

```bash
    DIGEST="${4:-}"
    resp="$(api POST "/repos/$OWNER/$REPO/pulls" "$local_body")"
    code="$(printf '%s' "$resp" | tail -1)"; num=""
    case "$code" in
      201) msg "opened PR $PB -> $INT"
           num="$(printf '%s' "$resp" | sed '$d' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("number",""))' 2>/dev/null)" ;;
      409) msg "PR for $PB already open (updated by push)"; num="$(open_phase_pr)" ;;
      *)   msg "WARNING: could not open PR (status $code)" ;;
    esac
    if [ -n "$DIGEST" ] && [ -s "$DIGEST" ] && [ -n "$num" ]; then post_pr_comment "$num" "$DIGEST"; fi
```

- [ ] **Step 5: Run the full test, expect ALL PASS:**

Run: `bash tests/phase-flow.test.sh`
Expected: `ALL PASS` (exit 0)

- [ ] **Step 6: Commit**

```bash
git add scripts/phase-flow.sh tests/phase-flow.test.sh
git commit -m "feat(phase-flow): finish posts a review-first attention digest as a PR comment"
```

---

### Task 3: Phase commands write and attach the digest

**Files:**
- Modify: `commands/phase0.md`, `commands/phase1.md`, `commands/phase2.md`, `commands/phase3.md`, `commands/phase5.md`, `commands/phase6.md` (extend the final commit/finish step). Phase 4 is untouched (no PR).

**Interfaces:**
- Consumes: `finish <feature> <N> [digest-file]` from Task 2.

- [ ] **Step 1: Edit each of the six phase commands.** In each, the final numbered step currently ends with:

> …then open/refresh this phase's PR by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS <N>`.

Replace the tail of that step (from "then open/refresh" onward) with, using the phase's own `<N>`:

> Then write a concise review-first digest to `/tmp/seven-phase-digest-$ARGUMENTS-<N>.md`: a `### ⚠️ Needs your attention` section FIRST — decisions to confirm, risks/uncertainties, deviations from the plan, and open questions, most-important-first (or `Nothing flagged - routine phase.` when there is nothing) — then a brief `### What this phase did`. Open/refresh this phase's PR and attach the digest by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS <N> /tmp/seven-phase-digest-$ARGUMENTS-<N>.md`.

Concretely the `<N>` per file: phase0.md → 0, phase1.md → 1, phase2.md → 2, phase3.md → 3, phase5.md → 5, phase6.md → 6.

- [ ] **Step 2: Verify no other step was disturbed** — the only change per file is the finish sentence; the `!`-lines, commit command, and STOP line are unchanged.

Run: `git diff --stat commands/`
Expected: only the six files above changed, small line deltas.

- [ ] **Step 3: Commit**

```bash
git add commands/phase0.md commands/phase1.md commands/phase2.md commands/phase3.md commands/phase5.md commands/phase6.md
git commit -m "feat(phases): write a review-first attention digest and attach it to each phase PR"
```

---

### Task 4: Documentation

**Files:**
- Modify: `PROTOCOL.md` (worktree + attention-digest bullets), `README.md` (worktree workflow + attention-digest note)

- [ ] **Step 1: PROTOCOL.md** — after the per-phase-PR bullet (the one ending "…the original commit-only flow still applies otherwise."), add:

```markdown
- Run each feature from its own git worktree (`git worktree add ../wt-<feature> -b feat/<feature> <base>`)
  so parallel sessions never collide; a session in the main folder is untouched. `phase-flow.sh`
  refuses to run if a feature's branch is checked out in a different worktree, naming where it lives.
- When a phase opens its PR, it attaches a review-first digest comment: a `### ⚠️ Needs your attention`
  section first (decisions to confirm, risks, plan deviations, open questions) so you triage what
  matters before reading the diff. Phase 4 opens no PR; its dry-run report serves the same purpose.
```

- [ ] **Step 2: README.md** — the Workflow block already shows `git worktree add ../wt-<f> -b feat/<f>`. Under the "Forgejo review loop" section, after the paragraph describing per-phase PRs (ending "…A comment asking for out-of-phase work is reported as a rewind signal, not acted on."), add:

```markdown
Each phase PR also gets a **review-first digest** comment when it opens — Claude's prioritized
`⚠️ Needs your attention` list (decisions to confirm, risks, plan deviations, open questions)
so you can focus on what matters before reading the diff. Run each feature from its own worktree
(`git worktree add ../wt-<f> -b feat/<f> <base>`); `phase-flow.sh` refuses to operate on a feature
whose branch is checked out in a different worktree and tells you where it lives, so parallel
sessions and the main folder never interfere.
```

- [ ] **Step 3: Commit**

```bash
git add PROTOCOL.md README.md
git commit -m "docs: document per-feature worktrees and the attention-digest comment"
```

---

## Self-Review

**Spec coverage:**
- Worktree guard (spec Part 1) → Task 1. ✓
- Phase-0 robustness → already present (`start 0` reuses `feat/<f>` at phase-flow.sh:84); no code change, noted. ✓
- Docs / worktree workflow → Task 4. ✓
- `finish` digest-comment (spec Part 2) → Task 2. ✓
- Phase commands write the prioritized digest → Task 3. ✓
- Phase 4 excluded (no PR) → honored in Tasks 2 (early return) & 3 (not edited). ✓
- Tests (guard leg + digest leg) → Tasks 1 & 2. ✓

**Placeholder scan:** none — all steps carry real code/commands.

**Type consistency:** `assert_branch_free`, `post_pr_comment`, `finish <f> <N> [digest-file]`, `open_phase_pr` used consistently across tasks. The digest path `/tmp/seven-phase-digest-$ARGUMENTS-<N>.md` matches the spec.

**Safety recheck:** every change is additive; `finish` with 3 args is unchanged; the guard is fail-safe (returns 0 on any doubt); the live test is the gate before anything reaches `main`.
