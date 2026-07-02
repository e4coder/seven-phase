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
command -v python3 >/dev/null || die "python3 is required"

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
  api GET "/repos/$OWNER/$REPO/pulls?state=open&limit=50" | sed '$d' | python3 -c "
import json,re,sys
feat=sys.argv[1]
pat=re.compile(r'^feat/' + re.escape(feat) + r'-p[0-9]+\$')
try: prs=json.load(sys.stdin)
except Exception: prs=[]
for pr in prs if isinstance(prs,list) else []:
    ref=(pr.get('head') or {}).get('ref','')
    if pat.match(ref):
        print(pr['number']); break
" "$FEATURE"
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
    grep -qxF '.llm/.pluginroot' .gitignore 2>/dev/null || echo '.llm/.pluginroot' >> .gitignore
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
    local_body="$(python3 -c '
import json, sys
pb, base, n, feat = sys.argv[1:5]
print(json.dumps({
    "head": pb,
    "base": base,
    "title": f"phase {n}: {feat}",
    "body": f"Opened by /seven-phase:phase{n}. Review this phase in isolation.",
}))
' "$PB" "$INT" "$N" "$FEATURE")"
    code="$(api POST "/repos/$OWNER/$REPO/pulls" "$local_body" | tail -1)"
    case "$code" in
      201) msg "opened PR $PB -> $INT" ;;
      409) msg "PR for $PB already open (updated by push)" ;;
      *) msg "WARNING: could not open PR (status $code)" ;;
    esac
    ;;
  merge-final)
    # Squash-merge the last open phase PR on Forgejo, then fast-forward LOCAL feat/<f>
    # to match - identical to what sync_integration does for every other phase advance.
    # Without this, /finish's printed `git merge --squash feat/<f>` integrates the
    # feature WITHOUT the final phase's work (it was only merged on Forgejo, not locally).
    sync_integration
    ;;
  *) die "unknown command: $CMD" ;;
esac
