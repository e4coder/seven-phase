---
description: Scaffold the 7-phase workflow into THIS repo (.llm/ + validation command)
argument-hint: [validation command, e.g. "go test ./..."]
allowed-tools: Read, Write, Edit, Bash
disable-model-invocation: true
---
Set up this repository for the 7-phase workflow.

1. `mkdir -p .llm`.
2. Write `.llm/validation` containing exactly this command on one line (no extra quoting):
   $ARGUMENTS
   If $ARGUMENTS is empty, write `echo "EDIT .llm/validation - set your test/build command"` and tell me to edit it.
3. Ensure `.gitignore` contains the lines `.llm/.phase` and `.llm/.pluginroot` (append each only if missing; create .gitignore if absent). This keeps the phase marker and the machine-specific plugin-root path out of git.
4. Show me the contents of `.llm/validation` and confirm `.gitignore` was updated.
5. Provision Forgejo (optional). Run the setup script, which is inert if
   `FORGEJO_HOST`/`FORGEJO_TOKEN` are unset:
   !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/forgejo-setup.sh"`
   It creates the private dev-cycle repo under the token's account (if missing),
   adds `FORGEJO_REVIEWER` as an admin collaborator, wires the `forgejo` remote
   (leaving `origin` untouched), seeds the base branch, and writes `.llm/forgejo`
   (`owner`, `repo`, `default_branch`, `reviewer`). Report what it printed. The host,
   token, and reviewer come from the environment, never the repo.

Do not create files beyond `.llm/validation`, `.llm/forgejo`, the `.gitignore` entry, and what the setup script manages.
