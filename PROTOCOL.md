# 7-Phase Human-Gated Programming Protocol

Build every feature in seven phases. The HUMAN advances phases by invoking the next
/seven-phase:phaseN command. Never advance on your own. Never invoke another phase
command yourself.

Source of truth per feature: `.llm/<feature>/plan.md`. Read it at the start of every
phase; update only the current phase's section.

## Rules
- Phases 0-3 produce NO runnable feature logic (structs, signatures, TODO markers,
  plan text only). Phase 4 is a throwaway dry-run. Phase 5 adds only invariants.
  Phase 6 is the ONLY phase that writes real implementation.
- If a phase cannot be completed within the artifacts from earlier phases
  (structs / interfaces / TODOs), STOP. Do not improvise. State exactly what is missing
  and which earlier phase must change; the human will rewind.
- Touch only what the phase allows. No drive-by edits, no extra files, no new
  dependencies, no MCP servers. The sole sanctioned MCP surface is the Forgejo server used
  by /seven-phase:review: it reads PR comments, may open the feature's PR and post one
  summary reply, but never resolves threads, merges, closes, or advances a phase. That
  server's write tools are coarse, so this restraint is a rule /seven-phase:review must
  self-enforce, not a limit the tool whitelist can impose.
- Each phase ends by committing its own work:
  `git add -A && git commit -m "phaseN(<feature>): <summary>"`, then, if a `forgejo`
  remote exists, `git push forgejo HEAD` so the open PR reflects this phase.
  Phase 4 commits only its report.
- Validate with the command in `.llm/validation` (set once per repo via
  /seven-phase:init). Never weaken tests or invariants to make validation pass.
- Human review lives on the feature's Forgejo PR (one PR per `feat/<feature>` branch,
  open across every code-writing phase). Consume PR comments ONLY via
  /seven-phase:review, which addresses them within the current phase and NEVER advances a
  phase. Reading a comment is not permission to self-advance.
- Be terse. No preamble. Show diffs, not essays.

## Phase contract
0  RESEARCH+PLAN  Research the codebase + problem; write plan.md (file-level breakdown of phases 1-6). No code.
1  STRUCTS        Data structures only - types, fields, enums. No bodies, no logic.
2  INTERFACES     Function/method signatures + interface types only. Bodies are stubs (panic/unimplemented/throw/revert "phase6").
3  TODO MAP       Insert `// TODO(<feature>): ...` at every site phase 6 will change. No real code.
4  DRY-RUN        Implement -> run validation -> THROW THE CODE AWAY -> report every deviation from structs/interfaces/TODOs.
5  INVARIANTS     Assertions / invariant checks only. Narrow, verifiable. No feature logic.
6  IMPLEMENT      Implement for real per the TODOs/structs/interfaces/invariants; run validation. The only real code.
