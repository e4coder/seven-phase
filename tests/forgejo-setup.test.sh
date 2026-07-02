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
