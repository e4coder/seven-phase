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
