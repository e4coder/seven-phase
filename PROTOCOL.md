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
  dependencies, no MCP servers unless the plan says so.
- Each phase ends by committing its own work:
  `git add -A && git commit -m "phaseN(<feature>): <summary>"`.
  Phase 4 commits only its report.
- Validate with the command in `.llm/validation` (set once per repo via
  /seven-phase:init). Never weaken tests or invariants to make validation pass.
- Be terse. No preamble. Show diffs, not essays.

## Phase contract
0  RESEARCH+PLAN  Research the codebase + problem; write plan.md (file-level breakdown of phases 1-6). No code.
1  STRUCTS        Data structures only - types, fields, enums. No bodies, no logic.
2  INTERFACES     Function/method signatures + interface types only. Bodies are stubs (panic/unimplemented/throw/revert "phase6").
3  TODO MAP       Insert `// TODO(<feature>): ...` at every site phase 6 will change. No real code.
4  DRY-RUN        Implement -> run validation -> THROW THE CODE AWAY -> report every deviation from structs/interfaces/TODOs.
5  INVARIANTS     Assertions / invariant checks only. Narrow, verifiable. No feature logic.
6  IMPLEMENT      Implement for real per the TODOs/structs/interfaces/invariants; run validation. The only real code.
