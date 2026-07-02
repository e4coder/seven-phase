#!/usr/bin/env bash
# PreToolUse gate. During phase 0 (plan-only) block any edit outside .llm/.
# Extracts the edited path with python3, then jq, then sed - whichever exists.
# Inert (exit 0) in repos with no .llm/.phase marker, and fails open if no
# extractor is available, so it can never wedge normal editing.
phase="$(cat .llm/.phase 2>/dev/null)"
[ "$phase" = "0" ] || exit 0
input="$(cat)"

extract() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c "import json,sys
try:
  t=json.load(sys.stdin).get('tool_input',{})
  print(t.get('file_path') or t.get('path') or '')
except Exception:
  print('')" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null
  else
    printf '%s' "$1" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
  fi
}

path="$(extract "$input")"
[ -n "$path" ] || exit 0
rel="${path#"$PWD"/}"
case "$rel" in
  .llm/*) exit 0 ;;
esac
echo "seven-phase: Phase 0 is plan-only. Edit to '$rel' blocked - write only under .llm/ or advance the phase." >&2
exit 2
