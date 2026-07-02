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
