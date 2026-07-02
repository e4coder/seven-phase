#!/usr/bin/env bash
# Integration test for scripts/forgejo-setup.sh against the real Forgejo instance.
# Requires FORGEJO_HOST, FORGEJO_TOKEN, FORGEJO_REVIEWER in the environment.
# Creates a throwaway repo and deletes it at the end.
#
# The token is never passed on the curl command line (it would be visible in
# ps / /proc/<pid>/cmdline); every authenticated call feeds the Authorization
# header via a curl config on stdin (curl -K -).
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$HERE/scripts/forgejo-setup.sh"
FAILED=0
check() { if eval "$2"; then echo "ok  - $1"; else echo "FAIL - $1"; FAILED=1; fi; }

[ -n "${FORGEJO_HOST:-}" ] && [ -n "${FORGEJO_TOKEN:-}" ] && [ -n "${FORGEJO_REVIEWER:-}" ] \
  || { echo "SKIP: set FORGEJO_HOST/FORGEJO_TOKEN/FORGEJO_REVIEWER to run"; exit 0; }
HOST="${FORGEJO_HOST%/}"; API="$HOST/api/v1"

# Authenticated curl helpers: auth header via stdin config, token never in argv.
authcfg() { printf 'header = "Authorization: token %s"\n' "$FORGEJO_TOKEN"; }
body()    { authcfg | curl -sS -K - "$1"; }                                # -> response body
status()  { authcfg | curl -sS -o /dev/null -w '%{http_code}' -K - "$1"; } # -> HTTP status
# Forgejo indexes a freshly pushed branch asynchronously; poll for the expected
# status for up to ~10s so the base-branch check isn't a race.
wait_status() { local url="$1" want="$2" i=0
  while [ "$i" -lt 20 ]; do [ "$(status "$url")" = "$want" ] && return 0; sleep 0.5; i=$((i+1)); done
  return 1; }

OWNER="$(body "$API/user" | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"; git init -q; git checkout -q -b main
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
git remote add origin https://example.invalid/x.git   # dummy origin: must survive untouched
NAME="$(basename "$WORK")"
teardown() { authcfg | curl -sS -o /dev/null -X DELETE -K - "$API/repos/$OWNER/$NAME"; }
trap 'teardown; rm -rf "$WORK"' EXIT

FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT"

check "repo created"          "[ \"\$(status $API/repos/$OWNER/$NAME)\" = 200 ]"
check "repo is private"       "body $API/repos/$OWNER/$NAME | grep -q '\"private\":true'"
check "reviewer collaborator" "[ \"\$(status $API/repos/$OWNER/$NAME/collaborators/$FORGEJO_REVIEWER)\" = 204 ]"
check "base branch pushed"    "wait_status $API/repos/$OWNER/$NAME/branches/main 200"
check "forgejo remote set"    "git remote get-url forgejo >/dev/null 2>&1"
check "origin untouched"      "[ \"\$(git remote get-url origin)\" = 'https://example.invalid/x.git' ]"
check "no token in config"    "! grep -q \"$FORGEJO_TOKEN\" .git/config"
check ".llm/forgejo owner"    "grep -q '^owner=$OWNER$' .llm/forgejo"
check ".llm/forgejo branch"   "grep -q '^default_branch=main$' .llm/forgejo"

echo '--- unset env: script must skip cleanly and write nothing ---'
WORK2="$(mktemp -d)"
( cd "$WORK2" && git init -q && git checkout -q -b main \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init" \
    && env -u FORGEJO_HOST -u FORGEJO_TOKEN bash "$SCRIPT" )
skip_rc=$?
check "unset-env exit 0"      "[ $skip_rc -eq 0 ]"
check "unset-env no .llm"     "[ ! -e \"$WORK2/.llm/forgejo\" ]"
rm -rf "$WORK2"

echo '--- idempotency: second run must not error ---'
FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT"; check "second run exit 0" "[ \$? -eq 0 ]"

echo '--- exists path must record the REPO default_branch, not whatever branch this run is on ---'
git checkout -q -b throwaway
FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT"; check "third run (from throwaway) exit 0" "[ \$? -eq 0 ]"
check "default_branch unchanged after run from throwaway" "grep -q '^default_branch=main$' .llm/forgejo"

echo '--- feature-branch guard: fresh repo whose only branch is feat/x must be rejected ---'
WORK3="$(mktemp -d)"
( cd "$WORK3" && git init -q && git checkout -q -b feat/x \
    && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init" \
    && FORGEJO_REVIEWER="$FORGEJO_REVIEWER" bash "$SCRIPT" )
guard_rc=$?
check "feature-branch guard exits non-zero" "[ $guard_rc -ne 0 ]"
check "feature-branch guard writes no .llm/forgejo" "[ ! -e \"$WORK3/.llm/forgejo\" ]"
rm -rf "$WORK3"

[ "$FAILED" -eq 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit "$FAILED"
