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
# Forgejo indexes a freshly pushed branch asynchronously; poll for the expected
# status for up to ~10s so branch-existence checks aren't a race.
gwait(){ local url="$1" want="$2" i=0
  while [ "$i" -lt 20 ]; do [ "$(gstatus "$url")" = "$want" ] && return 0; sleep 0.5; i=$((i+1)); done
  return 1; }

WORK="$(mktemp -d)"; NAME="$(basename "$WORK")"
cd "$WORK"; git init -q; git checkout -q -b main
echo init > work.txt; git add work.txt; git -c user.email=t@t -c user.name=t commit -q -m init
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
check "integration branch feat/demo on forgejo" "gwait $API/repos/$OWNER/$NAME/branches/feat%2Fdemo 200"
echo p0 >> work.txt; git add work.txt; git -c user.email=t@t -c user.name=t commit -q -m 'phase0(demo): plan'
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

echo '--- merge-final: must fast-forward LOCAL feat/demo, not just merge on Forgejo ---'
echo p1 >> work.txt; git add work.txt; git -c user.email=t@t -c user.name=t commit -q -m 'phase1(demo): work'
bash "$FLOW" finish "$F" 1 >/dev/null
P1="$(gbody "$API/repos/$OWNER/$NAME/pulls?state=open" | grep -o '"number":[0-9]*' | head -1 | cut -d: -f2)"
check "phase 1 PR opened" "[ -n \"$P1\" ]"
bash "$FLOW" merge-final "$F" >/dev/null
check "phase 1 PR merged (now closed)" "[ \"\$(gbody $API/repos/$OWNER/$NAME/pulls/$P1 | grep -o '\"merged\":true')\" = '\"merged\":true' ]"
check "local feat/demo fast-forwarded to include phase-1 work" "[ \"\$(git show feat/demo:work.txt | tail -1)\" = p1 ]"
# merge-final calls sync_integration with N unset; it must NOT tag a bogus phase-1.
check "merge-final creates no stray phase tag" "! git tag -l 'seven-phase/demo/phase-*' | grep -q . && ! git rev-parse -q --verify refs/tags/seven-phase/demo/phase-1 >/dev/null"

echo '--- rewind: build phases 0,1,2, start 3, then rewind to 2 ---'
# phase 2 start: merge-final already absorbed phase1's PR into feat/demo above, so there's
# no open PR here - sync_integration just ff's (no-op) and tags phase1, then cuts feat/demo-p2.
bash "$FLOW" start demo 2 >/dev/null
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

echo '--- rewind to 5: replay 2->6 (incl the no-PR phase 4), then rewind to 5 (phase4 anchor) ---'
# feat/demo is currently at the phase1 anchor (checked out above). Replay forward.
# redo p2
bash "$FLOW" start demo 2 >/dev/null
echo p2 >> work.txt && git add work.txt && git -c user.email=t@t -c user.name=t commit -q -m "phase2(demo): interfaces"
bash "$FLOW" finish demo 2 >/dev/null
# p3: start merges p2 (tags phase2), cut demo-p3, commit, open PR
bash "$FLOW" start demo 3 >/dev/null
echo p3 >> work.txt && git add work.txt && git -c user.email=t@t -c user.name=t commit -q -m "phase3(demo): todos"
bash "$FLOW" finish demo 3 >/dev/null
# p4 (special): start merges p3 (tags phase3) and STAYS on feat/demo (no phase branch);
# finish 4 pushes feat/demo and opens no PR. The dry-run "report" is committed onto feat/demo.
bash "$FLOW" start demo 4 >/dev/null
echo "phase4 dry-run report" >> work.txt && git add work.txt && git -c user.email=t@t -c user.name=t commit -q -m "phase4(demo): dry-run report"
bash "$FLOW" finish demo 4 >/dev/null
# p5: no open PR (phase 4 opened none) -> sync_integration ff's and tags phase4 at the
# post-phase-3+report state, then cuts demo-p5. This is the subtle phase-4-anchor case.
bash "$FLOW" start demo 5 >/dev/null
echo p5 >> work.txt && git add work.txt && git -c user.email=t@t -c user.name=t commit -q -m "phase5(demo): invariants"
bash "$FLOW" finish demo 5 >/dev/null
# p6: start merges p5 (tags phase5), cuts demo-p6
bash "$FLOW" start demo 6 >/dev/null
check "phase4 anchor tag exists"         "git rev-parse -q --verify refs/tags/seven-phase/demo/phase4 >/dev/null"
check "phase5 anchor tag exists"         "git rev-parse -q --verify refs/tags/seven-phase/demo/phase5 >/dev/null"
P4_TIP="$(git rev-parse seven-phase/demo/phase4)"
# rewind to phase 5: reset feat/demo to the phase4 anchor (post-phase-3 + dry-run report)
bash "$FLOW" rewind demo 5 >/dev/null
git checkout -q feat/demo
check "feat/demo reset to phase4 anchor" "[ \"\$(git rev-parse feat/demo)\" = \"$P4_TIP\" ]"
check "phase4 report present on feat/demo" "git show feat/demo:work.txt | grep -q 'phase4 dry-run report'"
check "phase-5 work gone from feat/demo" "! git show feat/demo:work.txt | grep -qx p5"
check "phase5 tag deleted"               "! git rev-parse -q --verify refs/tags/seven-phase/demo/phase5 >/dev/null"
check "phase4 anchor tag still exists"   "git rev-parse -q --verify refs/tags/seven-phase/demo/phase4 >/dev/null"
check "feat/demo-p6 branch deleted"      "! git rev-parse -q --verify refs/heads/feat/demo-p6 >/dev/null"
check "rewind-to-5 never created origin" "! git remote get-url origin >/dev/null 2>&1"

[ "$FAILED" -eq 0 ] && echo ALL PASS || echo SOME FAILED
exit "$FAILED"
