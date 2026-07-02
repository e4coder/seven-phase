# seven-phase

A human-gated, 7-phase LLM programming pipeline for Claude Code, packaged as a plugin.
You drive each phase by hand; Claude cannot advance on its own.

    0  research + plan        4  dry-run (implement, validate, THROW AWAY, report deviations)
    1  data structures        5  invariants
    2  interfaces / stubs     6  implement for real
    3  in-place TODO map

Every phase is a separate command you invoke explicitly. Each carries
`disable-model-invocation: true`, so Claude will never chain to the next phase itself.

## Install

Local test (no install):

    claude --plugin-dir /path/to/seven-phase
    # then, in the session:
    /reload-plugins

From a marketplace (this repo is its own marketplace):

    /plugin marketplace add <your-org>/seven-phase
    /plugin install seven-phase@nomi-tools

Team-wide: commit `.claude/settings.json` in the target repo with `extraKnownMarketplaces`
+ `enabledPlugins` so collaborators are prompted to install automatically.

Edit `repository` in `.claude-plugin/plugin.json` (and the marketplace `name`/`owner`
if you like) before pushing.

## Per-repo setup

Run once inside each repo you want to use it in:

    /seven-phase:init "go test ./... && go vet ./..."

This writes `.llm/validation` (the command phases 4 and 6 run) and adds `.llm/.phase`
to `.gitignore`. Swap in `cargo test`, `pnpm test`, `forge test`, or a headless
sim/driver as appropriate.

## Workflow (per feature `<f>`)

    git worktree add ../wt-<f> -b feat/<f>      # isolate the feature; open in VS Code
    /seven-phase:phase0 <f>   # read .llm/<f>/plan.md, correct it, re-run if needed
    /seven-phase:phase1 <f>   # review the inline diff; advance only when happy
    /seven-phase:phase2 <f>
    /seven-phase:phase3 <f>
    /seven-phase:phase4 <f>   # read the deviation report; if a struct/interface is wrong,
                              #   /rewind (Esc Esc) or git reset to that phase, fix, replay
    /seven-phase:phase5 <f>
    /seven-phase:phase6 <f>   # validation must pass; then open the PR
    /seven-phase:inspect <f>  # read-only, hunk-by-hunk review at any point (Sonnet)

Any phase that reports "STOP - missing X" is the gate working: rewind to phase X,
fix it, and continue forward.

## How it fits together

- `PROTOCOL.md` holds the universal rules. Each command inlines it at runtime via
  `!` + `cat "${CLAUDE_PLUGIN_ROOT}/PROTOCOL.md"`, because a plugin's own CLAUDE.md is
  not loaded as project context.
- `.llm/validation` holds the per-repo test/build command (kept in the repo, not the
  plugin, since it is project-specific).
- `.llm/<feature>/plan.md` is the durable source of truth, carried across phases and
  across a phone/cloud handoff.
- Each phase commits its own work, so phase 4 always enters from a clean HEAD and its
  `git stash -u && git stash drop` revert only ever discards the throwaway implementation.

## Forgejo review loop (optional)

Review each phase on a Forgejo PR instead of only the inline VS Code diff, and let Claude
pull your comments back in before you advance.

Each phase gets its own branch `feat/<f>-p<N>` off the integration branch `feat/<f>`, and its
own PR into `feat/<f>` - not one PR per feature. Invoking the next phase squash-merges the
previous phase's PR into `feat/<f>` (scripted against Forgejo's API, not an MCP tool) and cuts
the next phase branch. You leave line comments on the CURRENT phase's PR; `/seven-phase:review
<f>` reads them (via the MCP server) and addresses them **within the current phase**, then
commits and pushes `feat/<f>-p<N>`. On Forgejo it makes only one write: a single summary
comment ("Addressed X in `<sha>`, deferred Y"). It never opens, merges, closes, resolves a
thread, or advances a phase - phases open and merge their own PRs; you do the rest by hand. A
comment asking for out-of-phase work is reported as a rewind signal, not acted on.

> **Guardrail note.** `gitea-mcp` (v1.3.0) exposes coarse, mode-based write tools -
> `issue_write` also closes/edits, so the `allowed-tools` whitelist alone can't stop a
> comment call from also closing the issue. The "never merge/close/advance" rule is enforced
> by the `review.md` prompt, which restricts Claude to `issue_write` with
> `method:"add_comment"` only. Opening and squash-merging phase PRs is scripted directly
> against Forgejo's REST API by `phase-flow.sh` - it is never exposed to the model as an MCP
> tool at all. Keep claude-bot's token minimal and glance at its PR activity.

Setup:

> **Server prerequisite.** The Forgejo instance's `git` system user needs a git identity
> configured (`git config --global user.name`/`user.email` as that user on the server) -
> without it, squash-merges return 500 and the per-phase flow dies at the first phase advance.

1. Install the MCP server. The plugin bundles a `forgejo` server that runs the official
   `gitea-mcp` binary (it speaks Forgejo's API). Put `gitea-mcp` on your PATH, or swap
   `mcpServers.forgejo.command`/`args` in `.claude-plugin/plugin.json` for a
   `docker run -i ... docker.gitea.com/gitea-mcp-server` invocation.
2. Export the connection - the bot token needs **repository + issue write** (for PRs and
   comments) plus **`write:user`** (Forgejo gates repo creation via `POST /user/repos`
   under the user scope, which `/seven-phase:init` uses to auto-create the dev-cycle repo).
   It never merges, so it does not need admin scope:

       export FORGEJO_HOST=https://forgejo.bunyad.space
       export FORGEJO_TOKEN=<bot token: repo + issue write + write:user>
       export FORGEJO_REVIEWER=<your Forgejo username>   # added as admin collaborator

   Unset vars degrade gracefully in `forgejo-setup.sh` and the phase commands (they just
   skip Forgejo provisioning/pushes). The `forgejo` MCP server itself is a separate,
   non-fatal failure mode: if `gitea-mcp` isn't on your PATH or the vars aren't exported
   where Claude Code starts, the server shows as unavailable in the session (Claude just
   can't call `mcp__forgejo__*` tools) rather than crashing anything - but you do need the
   `gitea-mcp` binary installed for it to work at all.

   To disable Forgejo entirely, remove the `forgejo` entry from `mcpServers` in
   `.claude-plugin/plugin.json`.
3. Run init inside the repo. It provisions the Forgejo dev-cycle mirror for you:

       /seven-phase:init "go test ./..."     # creates the repo, adds you as admin
                                             # collaborator, wires the `forgejo` remote

   Forgejo is a dev-cycle mirror: feature and phase branches + PRs live there for review, but
   the source of truth is `origin` (see below for how the final merge to `origin` works).

Then, per feature (each phase = its own PR into the integration branch `feat/<f>`):

       /seven-phase:phase0 <f>   # creates feat/<f>, opens the phase-0 (plan) PR
       /seven-phase:review <f>   # read/address that phase's PR comments (never merges)
       /seven-phase:phase1 <f>   # merges the phase-0 PR into feat/<f>, opens the phase-1 PR
       ...                       # repeat review/advance through phase 6 (phase 4 = throwaway, no PR)
       /seven-phase:finish <f>   # merges the phase-6 PR on Forgejo, prints the manual origin step

Forgejo is a dev-cycle mirror; the plugin never pushes `origin`. When `/seven-phase:finish`
prints it, you run the final squash to your real main and push to `origin` yourself:

       git checkout main && git merge --squash feat/<f> && git commit && git push origin main

To use a Forgejo-native MCP server instead of `gitea-mcp`, keep the server key named
`forgejo` and update the `command`/`args` plus the `mcp__forgejo__*` tool names in
`commands/review.md` to match that server's tool set.

## Optional hard gate (hooks)

`hooks/hooks.json` wires two hooks:

- PreToolUse (`scripts/gate.sh`) blocks edits outside `.llm/` while phase 0 is running.
  Extracts the edited path with python3, jq, or sed (whichever exists); fails open if
  none are available, and is inert in repos with no `.llm/`.
- Stop (`scripts/phase_reset.sh`) clears the phase marker at the end of each turn, so the
  gate is only ever active during a live phase-0 turn.

To disable the hooks, remove the `"hooks"` line from `.claude-plugin/plugin.json`, or
install the plugin at project scope instead of user scope.

> Plugins run with your privileges and their hooks execute on tool use. Review before
> installing anyone else's.
