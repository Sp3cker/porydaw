# Task 15 — Shared header/support deletion + engine reachability gate

## Context

After Tasks 2-14, every retiring editcheck C++ original is deleted. Three
shared check files remain whose only consumers were those originals
(verified: spec §7 — `tst_songdocument.h` included only by the seven
originals; `tst_songdocument_support.cpp/.h` included only by originals +
each other; Swift never references them). Separately, the legacy
song-document engine gate (spec §8) must be executed and recorded against
the exact closed candidate set. A **known blocker exists today**:
`src/project/projectworkspace.h:13-14` includes `core/smf.h` and
`core/songdocument.h` — dormant but unretired production source — so the
engine family is expected to be KEPT with a recorded blocker chain, unless
that set was retired by a separate decision in the meantime.

## Exact write set

- Delete: `src/checks/editcheck/tst_songdocument.h`,
  `src/checks/editcheck/tst_songdocument_support.cpp`,
  `src/checks/editcheck/tst_songdocument_support.h`
- New: `docs/plans/editcheck-proof-retirement/engine-reachability.md`
  (report)
- Conditional (only for §8 candidate files that pass ALL gates): delete
  those files; one-line `Native engine status` updates in the affected
  certificates via `deno task proof:edit`.

## Prerequisites

Tasks 2, 4, 6, 8, 12, 13, 14 ALL accepted (certificates recorded).

## Interface contract

1. Shared check-file deletion: after deleting the three files, a harness
   `grep` for `tst_songdocument\.h|tst_songdocument_support` scoped to
   `src/` returns zero code references (proof/plan docs excluded), and
   `lsp references` (where the LSP sees the headers) confirms no
   remaining includers.
2. Engine gate — exact candidate set (spec §8, nothing else):
   `src/core/songdocument.cpp`, `songdocument.h`,
   `songdocument_range.cpp`, `songdocument_tempo.cpp`,
   `songdocument_timeeditor.cpp`, `songdocument_timeeditor.hpp`,
   `songdocument_timeeditor_insert.cpp`,
   `songdocument_timeeditor_xcmd.cpp`, `songdocument_xcmd.cpp`,
   `songhistory.cpp`, `songhistory.h`. Per file, all three gates must
   pass: (a) zero CMake references — harness `grep` over every
   `CMakeLists.txt` outside build/external, re-run fresh; (b) every proof
   naming the file under `Covered native implementation` is a terminal
   certificate (naming alone never proves value; the conjunction does);
   (c) zero remaining on-disk includers that are themselves unretired
   source — harness `grep` for the include across `src/` + `lsp
   references`, with each hit classified (compiled / dormant-production /
   unretired original of another area). ANY failure = keep the file and
   record the blocker. Explicitly NOT candidates: `smf.*`,
   `miditimeline.*`, `xcmd.*`, `timelineplayer.*`, `midiimport.*`,
   `m4asemantics.*`, `mid2agbtables.*`, `velocitymodel.*`,
   `lanemoveplan.*`, `noteid.h` (referenced by other areas' unretired
   originals).
3. `engine-reachability.md` records per candidate file: gate results with
   evidence, the blocker chain (expected: `projectworkspace.h` → dormant
   widget UI set), and the future decision that would unblock it. No
   dead-code-bypass workarounds, no stub headers, no deleting around an
   includer.

## Implementation steps

1. Delete the three shared check files; verify per Interface contract 1.
2. Run the §8 gate fresh per Interface contract 2; write the report.
3. Delete gate-passing engine files only; update affected certificates'
   `Native engine status` lines via `deno task proof:edit`.
4. Report kept-file blockers with the exact owning references.

## Acceptance predicate

- Harness `grep` sweeps return zero code references for every deleted
  file; `deno task proof list --area editcheck` shows the seven retired
  proofs terminal (scale accounted per spec §5.1).
- Controller: full `deno task verify --verbose` PASS (build succeeding
  after any engine deletions is the deletion proof); report reviewed.

## Task-specific constraints

- NEVER delete an engine file whose gate fails; the report is the
  deliverable for blocked files.
- If deleting a gate-passing file breaks compilation of an unexpected
  on-disk consumer, restore the file, record the consumer in the report,
  and finish with the reduced deletion set — do not "fix" unrelated files.
- No edits to `src/project/projectworkspace.h` or the dormant widget UI:
  their retirement is a separate decision, not this task's.
