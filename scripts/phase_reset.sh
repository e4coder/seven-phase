#!/usr/bin/env bash
# Stop hook. Clear the phase marker at the end of every turn so the gate is only
# ever active during a live phase-0 turn (no stale-marker false positives).
[ -d .llm ] && printf 'idle\n' > .llm/.phase 2>/dev/null
exit 0
