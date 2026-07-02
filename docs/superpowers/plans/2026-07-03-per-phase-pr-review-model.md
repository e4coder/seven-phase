# Per-phase-PR Review Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each phase its own PR into a per-feature integration branch on Forgejo, so phases are reviewed discretely, with a scripted (non-MCP) prior-phase merge on advance and a manual, origin-off-limits final squash.

**Architecture:** A new `scripts/phase-flow.sh` does all git + Forgejo-API (`curl`) plumbing — `start` (merge the open phase PR, sync the integration branch, cut the phase branch) and `finish` (push the phase branch, open its PR). Phase commands call it around Claude's phase work. `review.md` targets the current phase PR; a new `finish.md` merges the last PR on Forgejo and prints the manual origin step. The script is inert without Forgejo, preserving the original flow.

**Tech Stack:** Bash, `curl`, `git`, `python3` (JSON parse), Forgejo REST API v1. No new runtime deps.

## Global Constraints

- The plugin **only ever pushes/fetches the `forgejo` remote — never `origin`.** Any origin push is a defect.
- Secrets (`FORGEJO_HOST`, `FORGEJO_TOKEN`) come only from the environment; token never in argv (use `curl -K -` stdin), never in the repo or `.git/config`.
- `scripts/phase-flow.sh` is **inert (exit 0)** when there is no `forgejo` remote, or `FORGEJO_HOST`/`FORGEJO_TOKEN` unset, or no `.llm/forgejo` — phase commands then behave as the original commit-only flow.
- Integration branch = `feat/<f>`; phase branches = `feat/<f>-p<N>` (hyphen, no ref nesting).
- Phase PRs exist for phases 0,1,2,3,5,6. Phase 4 is a throwaway: it merges the open PR onto `feat/<f>`, works there, discards via `git stash -u && git stash drop`, commits only its report onto `feat/<f>`, opens NO PR.
- Merges are scripted via the Forgejo merge API (squash), triggered only by a human-invoked phase/finish command. `review.md` never merges.
- Spec: `docs/superpowers/specs/2026-07-03-per-phase-pr-review-model-design.md`.

---

## File Structure

- `scripts/phase-flow.sh` (new) — the plumbing: `start`/`finish`/`merge-final` subcommands.
- `tests/phase-flow.test.sh` (new) — live integration test against Forgejo, with teardown.
- `commands/phase0.md`…`phase6.md` (modify) — wrap Claude's phase work with `phase-flow.sh` calls.
- `commands/review.md` (modify) — target the current phase PR; drop `pull_request_write`.
- `commands/finish.md` (new) — merge the final phase PR on Forgejo + print the manual origin step.
- `PROTOCOL.md`, `README.md` (modify) — document the model.

---

## Task 1: `scripts/phase-flow.sh` + integration test

**Files:**
- Create: `scripts/phase-flow.sh`
- Test: `tests/phase-flow.test.sh`

**Interfaces:**
- Consumes: `.llm/forgejo` (`owner`/`repo`/`default_branch`), env `FORGEJO_HOST`/`FORGEJO_TOKEN`, the `forgejo` git remote (all from the existing auto-provision feature).
- Produces: CLI `phase-flow.sh start|finish|merge-final <feature> [N]`; creates `feat/<f>` + `feat/<f>-p<N>` branches on Forgejo and PRs `feat/<f>-p<N> → feat/<f>`. Later tasks (phase commands, finish.md) call these subcommands.

- [ ] **Step 1: Write the failing integration test**

Create `tests/phase-flow.test.sh`:

```bash
#!/usr/bin/env bash
# Integration test for scripts/phase-flow.sh against the real Forgejo instance.
# Requires FORGEJO_HOST, FORGEJO_TOKEN, FORGEJO_REVIEWER. Creates a throwaway repo + deletes it.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/scripts/forgejo-setup.sh"; FLOW="$ROOT/scripts/phase-flow.sh"
FAILED=0; check(){ if eval "$2"; then echo "ok  - $1"; else echo "FAIL - $1"; FAILED=1; fi; }
[ -n "${FORGEJO_HOST:-}" ] && [ -n "${FORGEJO_TOKEN:-}" ] && [ -n "${FORGEJO_REVIEWER:-}" ] \
  || { echo "SKIP: set FORGEJO_HOST/FORGEJO_TOKEN/FORGEJO_REVIEWER"; exit 0; }
HOST="${FORGEJO_HOST%/}"; API="$HOST/api/v1"
authcfg(){ printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN"; }
gstatus(){ authcfg | curl -sS -K - -o /dev/null -w '%{http_code}' "$1"; }
gbody(){ authcfg | curl -sS -K - "$1"; }

WORK="$(mktemp -d)"; NAME="$(basename "$WORK")"
cd "$WORK"; git init -q; git checkout -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
OWNER="$(gbody "$API/user" | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)"
teardown(){ authcfg | curl -sS -K - -o /dev/null -X DELETE "$API/repos/$OWNER/$NAME"; rm -rf "$WORK"; }
trap teardown EXIT
FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SETUP" >/dev/null    # provision repo + forgejo remote + .llm/forgejo
F=demo

echo '--- inert without forgejo config: run from a bare repo, expect skip + exit 0 ---'
( d2="$(mktemp -d)"; cd "$d2"; git init -q; git checkout -qb main
  env -u FORGEJO_TOKEN bash "$FLOW" start "$F" 0 >/dev/null 2>&1; rc=$?; rm -rf "$d2"; exit $rc )
check "inert exit 0 when unconfigured" "[ $? -eq 0 ]"

echo '--- phase 0: creates integration branch ---'
bash "$FLOW" start "$F" 0 >/dev/null
check "integration branch feat/demo on forgejo" "[ \"\$(gstatus $API/repos/$OWNER/$NAME/branches/feat%2Fdemo)\" = 200 ]"
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m 'phase0(demo): plan'
bash "$FLOW" finish "$F" 0 >/dev/null
P0="$(gbody "$API/repos/$OWNER/$NAME/pulls?state=open" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)"
check "phase 0 PR opened" "[ -n \"$P0\" ]"

echo '--- phase 1: merges p0 PR into feat/demo, cuts p1 branch ---'
bash "$FLOW" start "$F" 1 >/dev/null
check "p0 PR merged (now closed)" "[ \"\$(gstatus $API/repos/$OWNER/$NAME/pulls/$P0)\" = 200 ] && [ \"\$(gbody $API/repos/$OWNER/$NAME/pulls/$P0 | grep -o '\"merged\":true')\" = '\"merged\":true' ]"
check "on phase branch feat/demo-p1" "[ \"\$(git branch --show-current)\" = 'feat/demo-p1' ]"

echo '--- origin is never touched ---'
check "no origin remote created" "! git remote get-url origin >/dev/null 2>&1"
check "only forgejo remote present" "[ \"\$(git remote)\" = forgejo ]"

echo '--- idempotency: re-run phase 1 start must not error ---'
bash "$FLOW" start "$F" 1 >/dev/null; check "re-run start exit 0" "[ $? -eq 0 ]"

[ "$FAILED" -eq 0 ] && echo ALL PASS || echo SOME FAILED
exit "$FAILED"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `source ~/.config/bunyad/forgejo.env && bash tests/phase-flow.test.sh`
Expected: FAIL — `scripts/phase-flow.sh` doesn't exist yet (bash "No such file or directory"); checks fail / non-zero exit. (If it prints `SKIP`, load the env first.)

- [ ] **Step 3: Write the script**

Create `scripts/phase-flow.sh`:

```bash
#!/usr/bin/env bash
# Per-phase-PR plumbing for the seven-phase Forgejo review model.
#   phase-flow.sh start  <feature> <N>   merge the open phase PR into feat/<f>, sync, cut feat/<f>-pN
#   phase-flow.sh finish <feature> <N>   push feat/<f>-pN, open PR feat/<f>-pN -> feat/<f>
#   phase-flow.sh merge-final <feature>  squash-merge the last open phase PR into feat/<f> (for /finish)
# Reads .llm/forgejo (owner/repo/default_branch) + env FORGEJO_HOST/FORGEJO_TOKEN.
# Inert (exit 0) when Forgejo is not configured. Only ever touches the `forgejo` remote - never `origin`.
set -uo pipefail
msg(){ printf 'phase-flow: %s\n' "$*"; }
die(){ printf 'phase-flow: ERROR: %s\n' "$*" >&2; exit 1; }

CMD="${1:-}"; FEATURE="${2:-}"; N="${3:-}"
[ -n "$CMD" ] && [ -n "$FEATURE" ] || die "usage: phase-flow.sh start|finish|merge-final <feature> [N]"

# Inert unless Forgejo is fully wired up
if ! git remote get-url forgejo >/dev/null 2>&1 || [ -z "${FORGEJO_HOST:-}" ] || [ -z "${FORGEJO_TOKEN:-}" ] || [ ! -f .llm/forgejo ]; then
  msg "Forgejo not configured - skipping PR plumbing (original flow applies)."; exit 0
fi

HOST="${FORGEJO_HOST%/}"; API="$HOST/api/v1"
OWNER="$(grep -E '^owner='          .llm/forgejo | cut -d= -f2)"
REPO="$( grep -E '^repo='           .llm/forgejo | cut -d= -f2)"
BASE="$( grep -E '^default_branch=' .llm/forgejo | cut -d= -f2)"
[ -n "$OWNER" ] && [ -n "$REPO" ] && [ -n "$BASE" ] || die ".llm/forgejo missing owner/repo/default_branch"
INT="feat/$FEATURE"; PB="feat/$FEATURE-p$N"

api(){ # api METHOD PATH [JSON] -> body then final line = HTTP status; token via stdin config (not argv)
  local m="$1" p="$2" d="${3:-}"
  if [ -n "$d" ]; then
    printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN" \
      | curl -sS -K - -X "$m" -H "Content-Type: application/json" -w '\n%{http_code}' -d "$d" "$API$p"
  else
    printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN" \
      | curl -sS -K - -X "$m" -w '\n%{http_code}' "$API$p"
  fi
}

open_phase_pr(){ # prints the open phase PR number for this feature, or empty
  api GET "/repos/$OWNER/$REPO/pulls?state=open&limit=50" | sed '$d' | python3 - "$FEATURE" <<'PY'
import json,sys
feat=sys.argv[1]
try: prs=json.load(sys.stdin)
except Exception: prs=[]
for pr in prs if isinstance(prs,list) else []:
    if ((pr.get("head") or {}).get("ref","")).startswith(f"feat/{feat}-p"):
        print(pr["number"]); break
PY
}

squash_merge(){ # squash_merge <number>
  local code; code="$(api POST "/repos/$OWNER/$REPO/pulls/$1/merge" '{"Do":"squash"}' | tail -1)"
  case "$code" in
    200) msg "squash-merged PR #$1 into $INT" ;;
    405|409) msg "PR #$1 not mergeable (already merged?) - skipping" ;;
    *) die "merge of PR #$1 failed (status $code)" ;;
  esac
}

sync_integration(){ # merge the open phase PR (if any) then fast-forward local INT to forgejo
  local num; num="$(open_phase_pr)"
  if [ -n "$num" ]; then squash_merge "$num"; else msg "no open phase PR to merge"; fi
  git checkout "$INT" 2>/dev/null || die "local $INT missing - run phase 0 first"
  git fetch forgejo "$INT" >/dev/null 2>&1 || die "fetch forgejo/$INT failed"
  git merge --ff-only "forgejo/$INT" >/dev/null 2>&1 || die "local $INT diverged from forgejo/$INT - resolve by hand"
}

case "$CMD" in
  start)
    [ -n "$N" ] || die "start needs <N>"
    if [ "$N" = "0" ]; then
      git show-ref --verify --quiet "refs/heads/$INT" || git branch "$INT" "$BASE" || die "cannot create $INT"
      git checkout "$INT" || die "cannot checkout $INT"
      git push -u forgejo "$INT" >/dev/null 2>&1 || msg "WARNING: could not push $INT"
      msg "created integration branch $INT"
    else
      sync_integration
    fi
    if [ "$N" = "4" ]; then
      msg "phase 4: staying on $INT (throwaway dry-run, no phase branch, no PR)"
    else
      git show-ref --verify --quiet "refs/heads/$PB" && git branch -D "$PB" >/dev/null 2>&1
      git checkout -b "$PB" "$INT" || die "cannot create $PB"
      msg "on phase branch $PB"
    fi
    ;;
  finish)
    [ -n "$N" ] || die "finish needs <N>"
    if [ "$N" = "4" ]; then
      msg "phase 4 opens no PR - pushing $INT"; git push forgejo "$INT" >/dev/null 2>&1 || msg "WARNING: push $INT failed"; exit 0
    fi
    git push -u forgejo "$PB" >/dev/null 2>&1 || die "could not push $PB"
    local_body="$(printf '{"head":"%s","base":"%s","title":"phase %s: %s","body":"Opened by /seven-phase:phase%s. Review this phase in isolation."}' "$PB" "$INT" "$N" "$FEATURE" "$N")"
    code="$(api POST "/repos/$OWNER/$REPO/pulls" "$local_body" | tail -1)"
    case "$code" in
      201) msg "opened PR $PB -> $INT" ;;
      409) msg "PR for $PB already open (updated by push)" ;;
      *) msg "WARNING: could not open PR (status $code)" ;;
    esac
    ;;
  merge-final)
    num="$(open_phase_pr)"
    if [ -n "$num" ]; then squash_merge "$num"; git fetch forgejo "$INT" >/dev/null 2>&1 || true
    else msg "no open phase PR to merge"; fi
    ;;
  *) die "unknown command: $CMD" ;;
esac
```

Then: `chmod +x scripts/phase-flow.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `source ~/.config/bunyad/forgejo.env && bash tests/phase-flow.test.sh`
Expected: every `ok - …`, then `ALL PASS`, exit 0. The throwaway repo is deleted by the teardown trap. Confirm the `no origin remote created` and `only forgejo remote present` checks pass (the origin-off-limits guarantee).

- [ ] **Step 5: Commit**

```bash
git add scripts/phase-flow.sh tests/phase-flow.test.sh
git commit -m "feat(phase-flow): per-phase-PR plumbing (start/finish/merge-final) + integration test"
```

---

## Task 2: Wire the phase commands to `phase-flow.sh`

**Files:**
- Modify: `commands/phase0.md`, `phase1.md`, `phase2.md`, `phase3.md`, `phase4.md`, `phase5.md`, `phase6.md`, `commands/init.md`

**Interfaces:**
- Consumes: `phase-flow.sh start|finish` (Task 1).
- Produces: phase commands that branch/PR per phase.

**Timing rule (critical, verified against Claude Code docs):** EVERY `` !`...` `` line in a command runs at command-EXPANSION time, BEFORE the model does any work. So `start` (pre-work: merge the prior PR, cut the branch) is a `` !`...` `` line, but `finish` (post-work: push the branch, open its PR) MUST be a plain instruction the model runs AFTER committing — a `` !`finish` `` would push an empty branch. Also `${CLAUDE_PLUGIN_ROOT}` is NOT reliably set in the model's Bash env, so the `start` `` !`...` `` line records the plugin root to `.llm/.pluginroot` (where `${CLAUDE_PLUGIN_ROOT}` does expand), and the `finish` instruction reads it back via `$(cat .llm/.pluginroot)`.

- [ ] **Step 1: Capture the plugin root + call `start` (all 7 phase files)**

In every `commands/phaseN.md`, immediately AFTER the PROTOCOL inline line (`` !`cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"` ``), insert this single `` !`...` `` line (inert without Forgejo, so the original flow is unchanged for non-Forgejo users):

```markdown
!`mkdir -p .llm; echo "${CLAUDE_PLUGIN_ROOT}" > .llm/.pluginroot; bash "${CLAUDE_PLUGIN_ROOT}/scripts/phase-flow.sh" start $ARGUMENTS N`
```

Replace `N` with that file's phase number (0 in phase0.md … 6 in phase6.md). This runs BEFORE the model acts: it records the plugin root to `.llm/.pluginroot` for Step 2, and runs `start` (with Forgejo: squash-merge the open phase PR into `feat/<f>` and cut `feat/<f>-pN`; phase 0 creates `feat/<f>`; phase 4 stays on `feat/<f>`).

- [ ] **Step 2: Replace the raw push with a post-commit `finish` INSTRUCTION (phases 0,1,2,3,5,6)**

Each of `phase0.md`, `phase1.md`, `phase2.md`, `phase3.md`, `phase5.md`, `phase6.md` currently ends its commit step with a `git push forgejo HEAD` clause (added by a prior feature). `finish` supersedes that raw push (it pushes the phase branch AND opens/refreshes the phase PR), so REPLACE that clause with a finish instruction the MODEL runs after committing. Example — phase1.md's commit step becomes:

```markdown
4. Commit: `git add -A && git commit -m "phase1($ARGUMENTS): data structures"`, then open/refresh this phase's PR by running `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 1`.
```

Do the same in each of the six files, keeping that file's existing commit-message text and using its phase number. This is a plain instruction (NOT a `` !`...` `` line — those run before the commit exists); it reads the plugin root from `.llm/.pluginroot`. No `git push forgejo HEAD` may remain in any phase file.

- [ ] **Step 3: Phase 4 special-case (`phase4.md`)**

`phase4.md` gets the Step-1 `start 4` line (which merges phase 3's open PR onto `feat/<f>` and stays there — no phase branch). Its report-commit step (step 7) ends with the same raw push; REPLACE that clause with a `finish 4` instruction (pushes `feat/<f>`, opens no PR):

```markdown
7. Commit only the report: `git add .llm/$ARGUMENTS/plan.md && git commit -m "phase4($ARGUMENTS): dry-run report"`, then run `bash "$(cat .llm/.pluginroot)/scripts/phase-flow.sh" finish $ARGUMENTS 4`.
```

- [ ] **Step 4: Gitignore the captured path (`commands/init.md`)**

`.llm/.pluginroot` holds a machine-specific absolute path and must not be committed. In `commands/init.md` step 3 (which currently ensures the line `.llm/.phase` is in `.gitignore`), change it to ensure BOTH `.llm/.phase` and `.llm/.pluginroot` are present (each appended only if missing).

- [ ] **Step 5: Verify**

Run:
```bash
for n in 0 1 2 3 4 5 6; do printf "phase%s: start=%s finish=%s\n" "$n" \
  "$(grep -c "phase-flow.sh\" start \$ARGUMENTS $n" commands/phase$n.md)" \
  "$(grep -c "phase-flow.sh\" finish \$ARGUMENTS $n" commands/phase$n.md)"; done
grep -l 'git push forgejo HEAD' commands/phase*.md || echo "no raw push remains (good)"
grep -c 'pluginroot' commands/init.md
```
Expected: each phase file reports `start=1 finish=1` with its own number; the raw-push grep prints "no raw push remains (good)"; init.md references `pluginroot` at least once.

- [ ] **Step 6: Commit**

```bash
git add commands/phase0.md commands/phase1.md commands/phase2.md commands/phase3.md commands/phase4.md commands/phase5.md commands/phase6.md commands/init.md
git commit -m "feat(phases): per-phase branch + PR via phase-flow.sh (start !-line, post-commit finish)"
```

---

## Task 3: Point `review.md` at the current phase PR

**Files:**
- Modify: `commands/review.md`

**Interfaces:**
- Consumes: the phase branch/PR naming from Task 1 (`feat/<f>-p<N>`).
- Produces: a review command scoped to one phase PR that never merges.

- [ ] **Step 1: Retarget the PR the command reads, and drop the merge tool**

Two edits to `commands/review.md`:

(a) In the frontmatter `allowed-tools:` line, remove `mcp__forgejo__pull_request_write` (review must never merge/open/close). Keep the read tools + `mcp__forgejo__issue_write` (for the summary comment).

(b) In step 2 (currently "Find the PR … match the one whose head branch is `feat/$ARGUMENTS` … If none exists, open it"), replace with:

```markdown
2. Find the CURRENT phase's PR: derive the current phase N from the latest `phaseN($ARGUMENTS)`
   commit above, then `list_pull_requests` {owner, repo, state:"open"} and match the one whose
   head branch is `feat/$ARGUMENTS-p<N>`. If none is open, STOP and tell me to run
   `/seven-phase:phase<N>` first (phases open their own PR; /review never opens or merges one).
```

Also update the write-guardrail preamble so it no longer mentions `pull_request_write`/opening PRs — review's only Forgejo write is the one `issue_write` summary comment; it never opens, merges, or closes.

- [ ] **Step 2: Verify review no longer merges/opens**

Run: `grep -n 'pull_request_write\|open the PR\|open it once' commands/review.md`
Expected: no output (review neither merges nor opens PRs).

- [ ] **Step 3: Commit**

```bash
git add commands/review.md
git commit -m "feat(review): scope /review to the current phase PR; never merge/open"
```

---

## Task 4: `commands/finish.md`

**Files:**
- Create: `commands/finish.md`

**Interfaces:**
- Consumes: `phase-flow.sh merge-final` (Task 1).
- Produces: the terminal command that merges phase 6's PR on Forgejo and prints the manual origin step.

- [ ] **Step 1: Create the finish command**

Create `commands/finish.md`:

```markdown
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
```

- [ ] **Step 2: Verify finish never pushes origin**

Run: `grep -n 'push origin\|merge-final' commands/finish.md`
Expected: `merge-final` is invoked via the script; the only `push origin` occurrence is inside the printed-for-the-human code block (indented, not a `!`-executed line). Confirm there is no `!`…push origin…`` executable line.

- [ ] **Step 3: Commit**

```bash
git add commands/finish.md
git commit -m "feat(finish): merge final phase PR on Forgejo + print manual origin step"
```

---

## Task 5: Document the model (PROTOCOL + README)

**Files:**
- Modify: `PROTOCOL.md`, `README.md`

**Interfaces:**
- Consumes: behavior from Tasks 1-4.
- Produces: accurate protocol + operator docs.

- [ ] **Step 1: Update PROTOCOL.md**

Replace the existing review-loop bullets (the "Each phase ends by committing… push forgejo HEAD" bullet and the "Human review lives on the feature's Forgejo PR…" bullet) with the per-phase model:

```markdown
- With Forgejo configured, each phase runs on its own branch `feat/<feature>-p<N>` off the
  integration branch `feat/<feature>`, and opens ONE PR per phase (phases 0,1,2,3,5,6; phase 4
  is a throwaway with no PR). Invoking the next phase squash-merges the previous phase's PR into
  `feat/<feature>` (scripted, via Forgejo's API - not an MCP tool). All of this is `phase-flow.sh`,
  which is inert without Forgejo, so the original commit-only flow still applies otherwise.
- Human review happens on the CURRENT phase's PR. Consume its comments ONLY via
  /seven-phase:review, which addresses them within the current phase and NEVER merges, opens,
  closes, or advances. Reading a comment is not permission to self-advance.
- The plugin only ever pushes the `forgejo` remote. `origin` is OFF-LIMITS: the final squash of
  `feat/<feature>` to your real `main` and the push to `origin` are MANUAL steps you run by hand
  (see /seven-phase:finish, which does the Forgejo-side merge and prints the origin step).
```

- [ ] **Step 2: Update README.md Forgejo section**

In `README.md`, replace the "Then, per feature:" recipe block in the Forgejo section with the per-phase-PR flow:

```markdown
Then, per feature (each phase = its own PR into the integration branch `feat/<f>`):

       /seven-phase:phase0 <f>   # creates feat/<f>, opens the phase-0 (plan) PR
       /seven-phase:review <f>   # read/address that phase's PR comments (never merges)
       /seven-phase:phase1 <f>   # merges the phase-0 PR into feat/<f>, opens the phase-1 PR
       ...                       # repeat review/advance through phase 6 (phase 4 = throwaway, no PR)
       /seven-phase:finish <f>   # merges the phase-6 PR on Forgejo, prints the manual origin step

Forgejo is a dev-cycle mirror; the plugin never pushes `origin`. When `/seven-phase:finish`
prints it, you run the final squash to your real main and push to `origin` yourself:

       git checkout main && git merge --squash feat/<f> && git commit && git push origin main
```

- [ ] **Step 3: Verify docs mention the per-phase model + origin-off-limits**

Run: `grep -n 'per phase\|feat/<f>-p\|off-limits\|OFF-LIMITS\|seven-phase:finish' PROTOCOL.md README.md`
Expected: matches showing the per-phase PR model and the origin-off-limits / finish behavior are documented in both files.

- [ ] **Step 4: Commit**

```bash
git add PROTOCOL.md README.md
git commit -m "docs: per-phase-PR review model + origin-off-limits + /finish"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** integration + phase branches (T1 script), inert-without-forgejo (T1 script + test), prior-open-PR squash-merge on advance (T1 `sync_integration`), phase-branch cut (T1 `start`), phase PRs 0/1/2/3/5/6 (T2), phase 4 throwaway no-PR (T1 phase-4 branches, T2 Step 3), `/review` on current phase PR + no merge (T3), `/finish` merges last PR + prints origin step (T4), origin-off-limits (T1 guard + test asserts no origin, T4 prints-not-runs, T5 docs), backward-compat (T1 inert), PROTOCOL+README (T5). No gaps.
- **Placeholder scan:** none — full script + test code included; the per-phase edits give the exact inserted lines and the `N` substitution rule.
- **Name consistency:** `feat/$FEATURE` / `feat/$FEATURE-p$N`, `.llm/forgejo` keys `owner`/`repo`/`default_branch`, and subcommands `start`/`finish`/`merge-final` are used identically across Tasks 1-5.
