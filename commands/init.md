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
3. Ensure `.gitignore` contains the line `.llm/.phase` (append if missing; create .gitignore if absent). This keeps the phase marker out of git.
4. Show me the contents of `.llm/validation` and confirm `.gitignore` was updated.
5. Forgejo review loop (optional). If a git remote named `forgejo` exists
   (`git remote get-url forgejo`), parse `<owner>/<repo>` from its URL and write
   `.llm/forgejo` as two lines: `owner=<owner>` and `repo=<repo>`. If there is no
   `forgejo` remote, write `.llm/forgejo` with blank `owner=` / `repo=` and tell me to
   run `git remote add forgejo <url>` then re-run init. This file is committed and holds
   NO secrets - it only tells /seven-phase:review which repo to read PR comments from.
   The host and the read-only token live in the FORGEJO_HOST / FORGEJO_TOKEN environment
   variables, never in the repo.

Create only `.llm/validation` and `.llm/forgejo`.
