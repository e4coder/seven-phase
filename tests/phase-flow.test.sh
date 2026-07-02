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

[ "$FAILED" -eq 0 ] && echo ALL PASS || echo SOME FAILED
exit "$FAILED"
