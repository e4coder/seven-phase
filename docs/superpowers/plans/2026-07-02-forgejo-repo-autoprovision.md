# Forgejo Repo Auto-Provision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/seven-phase:init` auto-create this repo's Forgejo dev-cycle mirror, grant the developer admin access, wire the `forgejo` remote, and record config — so the review loop needs zero manual Forgejo setup.

**Architecture:** A dependency-free `scripts/forgejo-setup.sh` drives the Forgejo REST API with `curl` (gitea-mcp has no add-collaborator tool, and this keeps `init` independent of a live MCP session). `init.md` calls it; `review.md` reads the recorded default branch for the PR base. Verification is a shell integration test that provisions a throwaway repo against the real instance and tears it down.

**Tech Stack:** Bash, `curl`, `git`, Forgejo REST API v1. No new runtime dependencies.

## Global Constraints

- Token + host come only from the environment (`FORGEJO_HOST`, `FORGEJO_TOKEN`, `FORGEJO_REVIEWER`); never write secrets into the repo or `.git/config`.
- Never modify the `origin` remote.
- Every operation is idempotent — re-running `init` converges without error.
- Repos are created **private**, under the token's own account (owner derived from `GET /user`, never hardcoded).
- If `FORGEJO_HOST`/`FORGEJO_TOKEN` are unset, provisioning is skipped cleanly (exit 0) and the rest of `init` still runs.
- Spec: `docs/superpowers/specs/2026-07-02-forgejo-repo-autoprovision-design.md`.

---

## File Structure

- `scripts/forgejo-setup.sh` (new) — the provisioning script. Sole responsibility: bring the Forgejo mirror + remote + config to the desired state from the environment.
- `tests/forgejo-setup.test.sh` (new) — shell integration test against the live instance, with teardown.
- `commands/init.md` (modify) — call the script after validation setup.
- `commands/review.md` (modify) — use `default_branch` from `.llm/forgejo` as the PR base.
- `README.md` (modify) — document `FORGEJO_REVIEWER`, auto-provision, dev-cycle model.

---

## Task 1: Provisioning script + integration test

**Files:**
- Create: `scripts/forgejo-setup.sh`
- Test: `tests/forgejo-setup.test.sh`

**Interfaces:**
- Consumes: env `FORGEJO_HOST`, `FORGEJO_TOKEN`, `FORGEJO_REVIEWER`; the current git repo.
- Produces: a Forgejo repo `<owner>/<basename>` (private), the `forgejo` git remote, repo-scoped git credential config, and `.llm/forgejo` with keys `owner`, `repo`, `default_branch`, `reviewer`. Later tasks (review.md) rely on the `default_branch=` line.

- [ ] **Step 1: Write the failing integration test**

Create `tests/forgejo-setup.test.sh`:

```bash
#!/usr/bin/env bash
# Integration test for scripts/forgejo-setup.sh against the real Forgejo instance.
# Requires FORGEJO_HOST, FORGEJO_TOKEN, FORGEJO_REVIEWER in the environment.
# Creates a throwaway repo and deletes it at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/scripts/forgejo-setup.sh"
FAILED=0
check() { if eval "$2"; then echo "ok  - $1"; else echo "FAIL - $1"; FAILED=1; fi; }

[ -n "${FORGEJO_HOST:-}" ] && [ -n "${FORGEJO_TOKEN:-}" ] && [ -n "${FORGEJO_REVIEWER:-}" ] \
  || { echo "SKIP: set FORGEJO_HOST/FORGEJO_TOKEN/FORGEJO_REVIEWER to run"; exit 0; }
HOST="${FORGEJO_HOST%/}"; API="$HOST/api/v1"
OWNER="$(curl -sS -H "Authorization: token $FORGEJO_TOKEN" "$API/user" | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; git init -q; git checkout -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
NAME="$(basename "$WORK")"
teardown() { curl -sS -o /dev/null -X DELETE -H "Authorization: token $FORGEJO_TOKEN" "$API/repos/$OWNER/$NAME"; }
trap 'teardown; rm -rf "$WORK"' EXIT

FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT"

status() { curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: token $FORGEJO_TOKEN" "$1"; }
check "repo created"        "[ \"\$(status $API/repos/$OWNER/$NAME)\" = 200 ]"
check "reviewer collaborator" "[ \"\$(status $API/repos/$OWNER/$NAME/collaborators/$FORGEJO_REVIEWER)\" = 204 ]"
check "base branch pushed"  "[ \"\$(status $API/repos/$OWNER/$NAME/branches/main)\" = 200 ]"
check "forgejo remote set"  "git remote get-url forgejo >/dev/null 2>&1"
check "origin untouched"    "! git remote get-url origin >/dev/null 2>&1"
check "no token in config"  "! grep -q \"$FORGEJO_TOKEN\" .git/config"
check ".llm/forgejo owner"  "grep -q '^owner=$OWNER$' .llm/forgejo"
check ".llm/forgejo branch" "grep -q '^default_branch=main$' .llm/forgejo"

echo '--- idempotency: second run must not error ---'
FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT"; check "second run exit 0" "[ \$? -eq 0 ]"

[ "$FAILED" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAILED"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash tests/forgejo-setup.test.sh`
Expected: FAIL — `scripts/forgejo-setup.sh` does not exist yet (bash reports "No such file or directory"), so checks fail / non-zero exit. (If env vars are unset it prints SKIP; set them first from `~/.config/bunyad/forgejo.env` plus `FORGEJO_REVIEWER=e4coder`.)

- [ ] **Step 3: Write the provisioning script**

Create `scripts/forgejo-setup.sh`:

```bash
#!/usr/bin/env bash
# Provision this repo's Forgejo dev-cycle mirror from the environment:
# create the repo (private, under the token's own account) if missing, add
# FORGEJO_REVIEWER as an admin collaborator, wire the `forgejo` remote,
# configure non-interactive push auth, seed the base branch, write .llm/forgejo.
# Inert (exit 0) when FORGEJO_HOST/FORGEJO_TOKEN are not set. Never touches origin.
set -uo pipefail
msg() { printf 'forgejo-setup: %s\n' "$*"; }
die() { printf 'forgejo-setup: ERROR: %s\n' "$*" >&2; exit 1; }

# 1. Preflight
[ -n "${FORGEJO_HOST:-}" ] && [ -n "${FORGEJO_TOKEN:-}" ] || {
  msg "FORGEJO_HOST / FORGEJO_TOKEN not set - skipping Forgejo provisioning."; exit 0; }
command -v curl >/dev/null 2>&1 || { msg "curl not found - skipping."; exit 0; }
command -v git  >/dev/null 2>&1 || die "git not found"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repo"

HOST="${FORGEJO_HOST%/}"; API="$HOST/api/v1"
api() { # api METHOD PATH [JSON] -> prints body then a final line with HTTP status
  local m="$1" p="$2" d="${3:-}"
  if [ -n "$d" ]; then
    curl -sS -X "$m" -H "Authorization: token $FORGEJO_TOKEN" -H "Content-Type: application/json" \
      -w '\n%{http_code}' -d "$d" "$API$p"
  else
    curl -sS -X "$m" -H "Authorization: token $FORGEJO_TOKEN" -w '\n%{http_code}' "$API$p"
  fi
}

# 2. Owner from the token
resp="$(api GET /user)"; code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
[ "$code" = "200" ] || die "token auth failed (GET /user -> $code): $body"
OWNER="$(printf '%s' "$body" | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)"
[ -n "$OWNER" ] || die "could not determine owner login from /user"

# 3-4. repo name + default branch
NAME="$(basename "$(git rev-parse --show-toplevel)")"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "detached HEAD - checkout a branch first"

# 5. Create repo if missing
lcode="$(api GET "/repos/$OWNER/$NAME" | tail -1)"
if [ "$lcode" = "404" ]; then
  payload="$(printf '{"name":"%s","private":true,"auto_init":false,"default_branch":"%s"}' "$NAME" "$BRANCH")"
  cre="$(api POST /user/repos "$payload")"; ccode="${cre##*$'\n'}"
  [ "$ccode" = "201" ] || die "repo create failed ($ccode): ${cre%$'\n'*}"
  msg "created $OWNER/$NAME (private)"
elif [ "$lcode" = "200" ]; then
  msg "repo $OWNER/$NAME already exists"
else
  die "unexpected status checking repo ($lcode)"
fi

# 6. Reviewer as admin collaborator
if [ -n "${FORGEJO_REVIEWER:-}" ]; then
  ccode="$(api PUT "/repos/$OWNER/$NAME/collaborators/$FORGEJO_REVIEWER" '{"permission":"admin"}' | tail -1)"
  case "$ccode" in
    201|204) msg "reviewer '$FORGEJO_REVIEWER' is an admin collaborator" ;;
    404)     msg "WARNING: reviewer '$FORGEJO_REVIEWER' not found - skipped" ;;
    *)       msg "WARNING: could not add collaborator (status $ccode)" ;;
  esac
else
  msg "FORGEJO_REVIEWER not set - skipping collaborator step"
fi

# 7. Wire remote (leave origin alone)
if git remote get-url forgejo >/dev/null 2>&1; then
  msg "remote forgejo already set"
else
  git remote add forgejo "$HOST/$OWNER/$NAME.git"; msg "added remote forgejo"
fi

# 8. Non-interactive push auth (token read from env at push time, not stored)
git config "credential.$HOST.username" oauth2
git config "credential.$HOST.helper" '!f() { echo "password=${FORGEJO_TOKEN}"; }; f'

# 9. Seed base branch so PRs have a base
if git rev-parse HEAD >/dev/null 2>&1; then
  if git push forgejo "$BRANCH"; then msg "seeded base branch '$BRANCH'"
  else msg "WARNING: could not push base branch '$BRANCH'"; fi
else
  msg "no commits yet - skipping base-branch push"
fi

# 10. Record config (no secrets)
mkdir -p .llm
printf 'owner=%s\nrepo=%s\ndefault_branch=%s\nreviewer=%s\n' \
  "$OWNER" "$NAME" "$BRANCH" "${FORGEJO_REVIEWER:-}" > .llm/forgejo
msg "wrote .llm/forgejo"
```

Then: `chmod +x scripts/forgejo-setup.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/forgejo-setup.test.sh`
Expected: every line `ok - ...`, then `ALL PASS`, exit 0. The throwaway repo is deleted by the teardown trap.

- [ ] **Step 5: Commit**

```bash
git add scripts/forgejo-setup.sh tests/forgejo-setup.test.sh
git commit -m "feat(forgejo): add repo auto-provision script + integration test"
```

---

## Task 2: Call the script from init

**Files:**
- Modify: `commands/init.md`

**Interfaces:**
- Consumes: `scripts/forgejo-setup.sh` (Task 1) via `${CLAUDE_PLUGIN_ROOT}`.
- Produces: nothing new; wires provisioning into the init command.

- [ ] **Step 1: Add the provisioning step to init.md**

In `commands/init.md`, replace the current step 5 (the "Forgejo review loop (optional)" paragraph that only writes `.llm/forgejo`) with:

```markdown
5. Provision Forgejo (optional). Run the setup script, which is inert if
   `FORGEJO_HOST`/`FORGEJO_TOKEN` are unset:
   !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/forgejo-setup.sh"`
   It creates the private dev-cycle repo under the token's account (if missing),
   adds `FORGEJO_REVIEWER` as an admin collaborator, wires the `forgejo` remote
   (leaving `origin` untouched), seeds the base branch, and writes `.llm/forgejo`
   (`owner`, `repo`, `default_branch`, `reviewer`). Report what it printed. The host,
   token, and reviewer come from the environment, never the repo.
```

Also update the closing line from `Create only \`.llm/validation\` and \`.llm/forgejo\`.` to:

```markdown
Do not create files beyond `.llm/validation`, `.llm/forgejo`, the `.gitignore` entry, and what the setup script manages.
```

- [ ] **Step 2: Verify init wires the script (manual integration)**

Run in a throwaway repo with the env set:
```bash
d=$(mktemp -d); cd "$d"; git init -q; git checkout -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
CLAUDE_PLUGIN_ROOT=/home/nomi/Desktop/bunyad/seven-phase \
  bash "$CLAUDE_PLUGIN_ROOT/scripts/forgejo-setup.sh"
cat .llm/forgejo; git remote -v
# cleanup:
OWNER=$(grep ^owner= .llm/forgejo|cut -d= -f2); N=$(basename "$d")
curl -sS -X DELETE -H "Authorization: token $FORGEJO_TOKEN" "${FORGEJO_HOST%/}/api/v1/repos/$OWNER/$N" >/dev/null
cd - >/dev/null; rm -rf "$d"
```
Expected: `.llm/forgejo` has all four keys; `git remote -v` shows `forgejo` and no `origin`.

- [ ] **Step 3: Commit**

```bash
git add commands/init.md
git commit -m "feat(forgejo): provision repo + remote during /seven-phase:init"
```

---

## Task 3: review.md uses the recorded default branch as PR base

**Files:**
- Modify: `commands/review.md`

**Interfaces:**
- Consumes: `.llm/forgejo` `default_branch=` (Task 1).
- Produces: correct PR base for non-`main` repos (fixes code-review finding #1).

- [ ] **Step 1: Replace the hardcoded base branch**

In `commands/review.md` step 2 (PR creation), change:

```
`pull_request_write` {method:"create", owner, repo, base:"main", head:"feat/$ARGUMENTS",
```

to:

```
`pull_request_write` {method:"create", owner, repo, base:<default_branch from .llm/forgejo>, head:"feat/$ARGUMENTS",
```

And in the "Forgejo target" preamble line, note the extra keys:

```
Forgejo target (read `owner=`, `repo=`, and `default_branch=` from here):
```

- [ ] **Step 2: Verify the instruction is unambiguous**

Run: `grep -n 'base:' commands/review.md`
Expected: one match, referencing `default_branch from .llm/forgejo`, no remaining `base:"main"`.

- [ ] **Step 3: Commit**

```bash
git add commands/review.md
git commit -m "fix(forgejo): PR base uses recorded default_branch, not hardcoded main"
```

---

## Task 4: Document FORGEJO_REVIEWER, auto-provision, and the dev-cycle model

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: behavior from Tasks 1-3.
- Produces: accurate operator docs.

- [ ] **Step 1: Update the Forgejo setup section**

In `README.md`, in the "Forgejo review loop" setup list: (a) add `FORGEJO_REVIEWER` to the exported env block; (b) replace the manual `git remote add forgejo ... && /seven-phase:init` step with a note that `init` now auto-creates the repo, adds you as admin collaborator, and wires the `forgejo` remote. Add one sentence stating Forgejo is a **dev-cycle mirror**: the source of truth is `origin`, and the final merge-to-main + push-to-`origin` is a manual step.

Concretely, change the export block to:

```
       export FORGEJO_HOST=https://forgejo.bunyad.space
       export FORGEJO_TOKEN=<bot token: repo + issue write>
       export FORGEJO_REVIEWER=<your Forgejo username>   # added as admin collaborator
```

and replace step 3 ("Point the repo at Forgejo and record owner/repo") with:

```
3. Run init inside the repo. It provisions the Forgejo dev-cycle mirror for you:

       /seven-phase:init "go test ./..."     # creates the repo, adds you as admin
                                             # collaborator, wires the `forgejo` remote

   Forgejo is a dev-cycle mirror: feature branches + PRs live there for review, but the
   source of truth is `origin`. After phase 6, you merge to your main branch and push to
   `origin` by hand.
```

- [ ] **Step 2: Verify docs mention the new env var and behavior**

Run: `grep -n 'FORGEJO_REVIEWER\|dev-cycle\|auto' README.md`
Expected: matches showing `FORGEJO_REVIEWER` documented and the dev-cycle model described.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(forgejo): document FORGEJO_REVIEWER + auto-provision + dev-cycle model"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** create repo (T1 step 3 #5), owner from token (#2), private/empty (#5), collaborator (#6), remote leaving origin (#7), push auth (#8), seed base (#9), `.llm/forgejo` 4 keys (#10), init wiring (T2), review base fix (T3), README + `FORGEJO_REVIEWER` + dev-cycle (T4), idempotency + graceful skip + no-secret-in-config (T1 test asserts all three). No gaps.
- **Placeholder scan:** none — full script and test code included.
- **Type/name consistency:** `.llm/forgejo` keys (`owner`, `repo`, `default_branch`, `reviewer`) are written in T1 and read in T3; the `forgejo` remote name and `FORGEJO_REVIEWER` env var are consistent across all tasks.
