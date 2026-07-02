# Design: Auto-provision the Forgejo dev-cycle repo at init

**Date:** 2026-07-02
**Status:** Approved (design), pending implementation plan
**Component:** seven-phase plugin — `/seven-phase:init`, `commands/review.md`, new `scripts/forgejo-setup.sh`

## Purpose

Remove the manual Forgejo setup step. `/seven-phase:init` should create the per-project
Forgejo repository, grant the developer admin access, wire a `forgejo` git remote, seed the
base branch, and record config — so the seven-phase review loop works with **zero manual
Forgejo steps**.

## Context

- **Forgejo is a dev-cycle-only workspace.** Feature branches and their PRs live there for
  the 7-phase review. The source of truth is the `origin` remote. Final integration (merge to
  main, push to `origin`) is a **manual human step** and is out of scope.
- The MCP token belongs to the bot account (`claude-bot`), so repos are created in the bot's
  namespace. The developer is added as an **admin collaborator**.
- `gitea-mcp` has **no add-collaborator tool**, so provisioning uses the Forgejo REST API via
  `curl` rather than the MCP. This also keeps `init` independent of a live MCP session.
- Existing behavior: `init` writes `.llm/validation` and `.llm/forgejo`; `review.md` and
  `PROTOCOL.md` push to the `forgejo` remote.

## Requirements

- Idempotent — safe to re-run.
- No secrets in the repo; host + token come from the environment.
- Never touch the `origin` remote.
- Record the real default branch so PRs target the correct base (fixes code-review finding #1,
  the hardcoded `base:"main"`).
- Degrade gracefully when Forgejo env is unset (still perform the non-Forgejo parts of init).

## Design

### New: `scripts/forgejo-setup.sh`

Invoked by `init.md`. Provisions the repo via the Forgejo API.

**Inputs:** env `FORGEJO_HOST`, `FORGEJO_TOKEN`, `FORGEJO_REVIEWER` (developer's Forgejo
username). No positional args required.

**Steps:**
1. **Preflight** — if `FORGEJO_HOST` or `FORGEJO_TOKEN` unset, print a message and exit 0
   (init continues; Forgejo provisioning skipped). Require `curl`.
2. **Bot owner** — `GET {HOST}/api/v1/user` with the token → `.login` (never hardcode
   `claude-bot`).
3. **Repo name** — `basename "$(git rev-parse --show-toplevel)"`.
4. **Default branch** — `git rev-parse --abbrev-ref HEAD`.
5. **Create if missing** — `GET /api/v1/repos/{owner}/{name}`; on 404 → `POST /api/v1/user/repos`
   with `{name, private:true, auto_init:false, default_branch}`. Empty repo, so the seed push
   cannot conflict.
6. **Grant developer access** — `PUT /api/v1/repos/{owner}/{name}/collaborators/{FORGEJO_REVIEWER}`
   body `{permission:"admin"}` (idempotent). If `FORGEJO_REVIEWER` unset or the user 404s, warn
   and continue.
7. **Wire remote** — if `git remote get-url forgejo` fails, `git remote add forgejo
   {HOST}/{owner}/{name}.git` (plain HTTPS URL, **no token embedded**). `origin` is never modified.
8. **Configure non-interactive push auth** (see below) so `git push forgejo` never prompts.
9. **Seed base branch** — `git push forgejo {default_branch}` so PRs have a base. Tolerate
   "everything up-to-date" and "no commits yet" (warn on the latter).
10. **Write `.llm/forgejo`** — four lines: `owner=`, `repo=`, `default_branch=`, `reviewer=`.

### Push authentication (non-interactive)

Every `git push forgejo HEAD` (seed push here, and each phase push per `PROTOCOL.md`) runs
unattended in a Claude Code session, so it must authenticate without prompting. The token is
already in the environment as `FORGEJO_TOKEN`.

**Decision:** configure a **repo-scoped git credential helper that reads the token from the
environment** — the token is NOT written into `.git/config` or the remote URL. The script runs:

```
git config credential."${FORGEJO_HOST}".username oauth2
git config credential."${FORGEJO_HOST}".helper '!f() { echo "password=${FORGEJO_TOKEN}"; }; f'
```

Only the helper snippet (which references the env var by name) lands in `.git/config`; the
secret itself stays in the environment. Pushes transport-authenticate as the bot; commit
authorship is unaffected (preserved from the committer's git identity). *(Alternatives
considered: token embedded in the remote URL — rejected, leaks the token into `.git/config`
and `git remote -v`; SSH with the developer's key — rejected, needs extra Forgejo SSH setup.)*

### Modified: `commands/init.md`

After the existing validation + `.gitignore` steps, invoke
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/forgejo-setup.sh"`. Report what it did (repo created or
already present, remote wired, base seeded) or why it was skipped (env not set).

### Modified: `commands/review.md`

Read `default_branch=` from `.llm/forgejo` and use it as the PR `base` in the
`pull_request_write {method:"create"}` call, replacing the hardcoded `"main"`.

### Modified: `README.md`

Document: the new auto-provision behavior of `init`; the `FORGEJO_REVIEWER` env var (alongside
`FORGEJO_HOST`/`FORGEJO_TOKEN`); and that Forgejo is a dev-cycle mirror whose final
integration to `origin` is a manual human step.

### `.llm/forgejo` format (updated)

```
owner=<bot login>
repo=<repo name>
default_branch=<branch>
reviewer=<developer forgejo username>
```

## Error handling

| Condition | Behavior |
|---|---|
| `FORGEJO_HOST`/`FORGEJO_TOKEN` unset | Skip Forgejo provisioning, continue init, clear message |
| `curl` missing | Skip provisioning with a message |
| API 401 / 5xx | Print status + body; non-fatal to init; report clearly |
| Reviewer user 404 / `FORGEJO_REVIEWER` unset | Warn, skip collaborator step, continue |
| Seed push fails (no commits yet) | Warn; repo exists, base can be pushed later |

## Idempotency

Repo exists → skip create. Remote exists → skip add. Collaborator `PUT` and `git push` are
naturally idempotent. Re-running `init` converges without error.

## Testing

No unit framework (plugin = markdown + shell). Verification is an integration check against the
real instance (`forgejo.bunyad.space`):
1. In a scratch git repo with a commit, set the env vars and run the script.
2. Assert: repo created under the bot, developer is an admin collaborator, `forgejo` remote
   present, default branch pushed, `.llm/forgejo` has all four keys.
3. Re-run; assert no errors and no duplicate side effects (idempotency).
4. Unset `FORGEJO_TOKEN`; assert the script skips cleanly and init still writes `.llm/validation`.

## Out of scope (YAGNI)

- Final merge-to-main and push-to-`origin` (manual human step).
- Branch protection (the bot owns the repo, so it can't be constrained by protection — code
  review finding #2 stays prompt-enforced; acceptable because Forgejo is dev-cycle-only).
- Repo deletion / teardown / cleanup.

## Security

- Token and host only from the environment; never written to the repo.
- `.llm/forgejo` holds only non-secret metadata (owner, repo, branch, reviewer).
- Script runs with strict mode and guarded, individually-checked `curl` calls.
