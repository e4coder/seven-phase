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

Do not create any other files.
