# Editcheck C++ check retirement — task plan

Spec: `docs/plans/editcheck-proof-retirement/spec.md` (read first; it owns
disposition semantics, certificate format, suite map, verification
commands, reachability evidence). Route: SDD-track (`sdd-execution-loop`,
seat `sdd-implementer`) for every task except Task 14 (Direct — mechanical,
single-file proof edit with pre-decided dispositions). This is judgment
work on observable-contract equivalence, not mechanical migration.

Scale (`tst_scale.cpp`) is NOT on the retirement path: Task 1 only records
reachability evidence (KEEP-NATIVE default; retirement solely on a future
explicit user decision, outside this plan's success criteria).

## File-ownership policy (AGENTS file-size discipline)

`TimeChecks.swift` (2,042 lines), `EventChecks.swift` (1,231), and
`NoteChecks.swift` (526) are at or beyond review-cohesion limits; new
assertions do NOT append to them. New work lands in coherent new check
files (150-400 lines, one C++ original-family concept each, no <80-line
fragments); existing suite entrypoints are touched only to wire calls
(1-2 lines); each new file is registered in `src/checks/CMakeLists.txt`
by its own task. Extraction of an existing family (Task 7) moves
functions verbatim — behavior and proof citations preserved (the owning
certificate task refreshes SHAs/citations). `src/checks/CMakeLists.txt`
has one writer at a time: tasks 5 → 7 → 9 → 10 → 11 → 13 serialize on it.

## Dispatch table

| # | Task | Brief | Write set (files) | Depends | Narrow check (controller) |
|---|------|-------|-------------------|---------|---------------------------|
| 1 | Scale keep-native reachability record (no deletion) | task-1-brief.md | `proof.tst_scale.txt` (Scope only) | — | `--filter scalecheck` (lane unaffected) |
| 2 | Timerange: A154 RETIRED-REPRESENTATION + certificate + delete (proof-only) | task-2-brief.md | `proof.tst_songdocument_timerange.txt`, delete `tst_songdocument_timerange.cpp` | — | full swiftcore |
| 3 | Metadata: wire 2 contracts, assert saved bytes/format-0 reload and nine history sites | task-3-brief.md | `EventChecks.swift` (existing contracts) | — | `--qt eventEdits` |
| 4 | Metadata certificate + delete | task-4-brief.md | `proof.tst_songdocument_metadata.txt`, delete `tst_songdocument_metadata.cpp` | 3 | full swiftcore |
| 5 | Track corpus complete: CMake source + driver + all 7 row families + 2 marker assertions | task-5-brief.md | new `TrackCorpusChecks.swift`, `EventChecks.swift` (1 call), `src/checks/CMakeLists.txt` (1 line) | 3 + C1 | `--qt eventEdits` (build covers CMake) |
| 6 | Songtracks certificate + delete | task-6-brief.md | `proof.tst_songdocument_songtracks.txt`, delete `tst_songdocument_songtracks.cpp` | 5 | full swiftcore |
| 7 | Songtime corpus extraction + completion: move `coreTimeCorpusChecks` family into new file, close all four families' gaps | task-7-brief.md | new `TimeCorpusChecks.swift`, `TimeChecks.swift` (extraction removal only), `src/checks/CMakeLists.txt` (1 line) | 5 (CMake serialization; runs parallel with 6) | `--qt timeEdits` |
| 8 | Songtime certificate + delete | task-8-brief.md | `proof.tst_songdocument_songtime.txt`, delete `tst_songdocument_songtime.cpp` | 7 | full swiftcore |
| 9 | Document history-suite file: loadPublication, savedIdentity, netZero, crossingIdentities, mergedOverlapPublication | task-9-brief.md | new `DocumentHistoryChecks.swift`, `NoteChecks.swift` (1-2 calls), `src/checks/CMakeLists.txt` (1 line) | 7 (CMake chain) | `--qt documentHistory` |
| 10 | Document edit-suite file: velocityAtomic, velocityRejects, duplicateIdentities, tempoEmpty | task-10-brief.md | new `DocumentEditChecks.swift`, `NoteChecks.swift` (1 call), `src/checks/CMakeLists.txt` (1 line) | 9 + C2 (NoteChecks reuse) | `--qt noteEdits` |
| 11 | Document track-suite file: duplicationOwnership, trackRemap publication + full globalMetadata contract (A145-A158) | task-11-brief.md | new `DocumentTrackChecks.swift`, `EventChecks.swift` (1 call), `src/checks/CMakeLists.txt` (1 line), `proof.tst_songdocument_document.txt` (A145-A158 only) | 10 (CMake chain) + C2 (EventChecks reuse) | `--qt eventEdits` |
| 12 | Document certificate + delete | task-12-brief.md | `proof.tst_songdocument_document.txt`, delete `tst_songdocument_document.cpp` | 9, 10, 11 | full swiftcore |
| 13 | Logic: NoteIdentity file + assertions + certificate + delete | task-13-brief.md | new `NoteIdentityChecks.swift`, `NoteChecks.swift` (1 call), `src/checks/CMakeLists.txt` (1 line), `proof.tst_songdocument_logic.txt`, delete `tst_songdocument_logic.cpp` | C3 (NoteChecks reuse + CMake chain) | `--qt noteEdits`; full swiftcore |
| 14 | Runner certificate + delete (Direct) | inline below | `proof.tst_songdocument_runner.txt`, delete `tst_songdocument_runner.cpp` | — | full swiftcore |
| 15 | Shared header/support deletion + engine reachability gate (spec §8) | task-15-brief.md | delete `tst_songdocument.h`, `tst_songdocument_support.cpp/.h`; `engine-reachability.md`; conditional §8-only deletions | 2, 4, 6, 8, 12, 13, 14 | full `deno task verify` |

## Parallel waves and file-reuse checkpoints

First parallel wave (disjoint write sets): **1, 2, 3, 14** — proofs
(1, 2, 14) / `EventChecks.swift` (3). No two wave-1 tasks share a file.

After C1, Task 5 runs (sole CMake writer); after 5 settles, **6 and 7 run
in parallel** (proof/delete vs new-file+TimeChecks — disjoint). Tasks
9 → 10 → 11 serialize on the CMake chain and on `NoteChecks.swift` reuse;
12 follows; 13 after C3.

Checkpoint milestones (authorize later reuse of an accepted writer's
files; the execution loop owns staging/diff packaging):

- **C1 — first certificates** (after 1, 2, 3, 4, 14 accepted): timerange,
  metadata, runner retired; scale recorded. Commits Task 3's
  `EventChecks.swift` work → authorizes Task 5's reuse of it.
- **C2 — corpus families** (after 5, 6, 7, 8, 9 accepted): songtracks and
  songtime retired; document history-suite landed. Commits the two corpus
  files, the TimeChecks extraction, Task 9's `NoteChecks.swift` wiring →
  authorizes Task 10 (NoteChecks reuse) and Task 11 (EventChecks reuse).
- **C3 — document complete** (after 10, 11, 12 accepted): document
  retired. Commits Task 10's `NoteChecks.swift` wiring → authorizes
  Task 13's reuse of it (and frees the CMake chain).
- **C4 — final handoff** (after 13, 15 accepted): full
  `deno task verify` and terminal proof tallies at that milestone.
  Subsequent completed-ledger cleanup may remove the wholly `MATCHED`
  certificates, leaving only non-MATCHED inventories in `proof list`.
  No empty checkpoints; serial same-file tasks never force extra commits
  between C1-C4 beyond these boundaries.

## Global constraints (once — briefs carry deltas only)

- Read `spec.md` §2-§4 before starting any task. Disposition semantics
  (including the hard rules: no argument echo, non-throwing construction
  never MATCHes staging/null sites, revision ≠ history depth), the
  STALE→REPRESENTATION→RETIRED-REPRESENTATION→BEHAVIOR-GAP test, the
  certificate format, the public history API, the revision-pinning
  protocol (§2.2 — keep the proof's existing `Reference revision`; verify
  `Original SHA-256` against the on-disk file; no placeholders), and the
  corpus-dimension rule live there and are not repeated in briefs.
- Implementers do NOT run `deno task verify`, `build:*`, `format`, or
  `lsp:swift`; the controller runs the recorded commands after the task
  settles. Read-only `deno task proof show|list` and `shasum` are
  implementer-available; `deno task proof:edit … --apply` is the sanctioned
  disposition-change mechanism.
- Acceptance searches use the harness `grep` tool scoped to named paths
  and `lsp references` for symbols — never shell `grep -rn` (AGENTS.md
  search discipline).
- Never relabel a site without either an executing Swift predicate under
  the original `cppID` or the named no-ingress proof (spec §2.1/§7).
  Never add a test-only accessor, production test hook, or new C++ support
  code. When in doubt between MATCHED and RETIRED-REPRESENTATION, the
  honest weaker label wins; a site may stay GAP and the file stay
  unretired rather than be forced green.
- The earlier four retired certificates (songmoves/songnotes/songranges/
  songraw) were immutable during this migration plan. Once their mapped
  Swift predicates have executed successfully and every site is `MATCHED`,
  the approved proof-retirement policy deletes the finished ledgers; the
  historical versions are recoverable at Git revision
  `4c52acd8c1193d27167c301002c67f18165938b8`.
- The controller commits the accepted prior migration work before plan
  execution; tasks start from that clean baseline checkpoint (pushed per
  AGENTS Git synchronization). If concurrent work reappears in shared
  files (`EventChecks.swift`, `TimeChecks.swift`, `NoteChecks.swift`,
  `src/swift/**`), anchor edits by symbol, re-`read` immediately before
  editing, and never revert unrelated hunks.
- Swift edits follow existing file idioms (contract functions, `report`
  parameter threading, `cppID` comments). New check files per the
  file-ownership policy above; fixtures are defined locally per file
  (do not widen `NoteChecks.swift` visibility); no other new abstractions.
- After any Swift edit the task is done only when `deno task proof show
  <affected-proof>` still parses and — for tasks that also touch proofs —
  the affected tallies moved exactly as the brief's acceptance states.

## Direct task 14 (inline)

# Target
`src/checks/editcheck/proof.tst_songdocument_runner.txt` reclassified to a
deletion certificate; `src/checks/editcheck/tst_songdocument_runner.cpp`
deleted.

# Change
1. Reclassify A001 GAP→MATCHED citing S001 (`coreEditCorpusSongs` fails the
   suite on a missing staged root — the observable contract of "editcheck
   requires its staged project root").
2. Reclassify A002 PARTIAL→RETIRED-REPRESENTATION: the site asserts
   `DecompProject::open` — a project-database staging step with no Swift
   ingress in this suite (`coreEditCorpusSongs` stages via the Deno
   fixture staging and direct `sound/songs/midi` + `midi.cfg` enumeration;
   it never opens a project database) and the C++ file is uncompiled
   (spec §7). The surviving observable — unreadable staging fails the
   suite — is already asserted by the throwing loader catch
   (S001/S003/S004/S007); do NOT claim the database-open step MATCHED.
3. Rewrite the preamble to the certificate format (spec §3, §2.2 revision
   pinning) with `Covered native implementation: src/core/songdocument.cpp
   :: SongDocument::load` and the run path `suite 4 ::
   coreEditCorpusLoadCheck`.
4. Delete `tst_songdocument_runner.cpp`. Do NOT touch
   `tst_songdocument_runner.swift` (live shared corpus loader).

# Acceptance
`deno task proof show tst_songdocument_runner` parses with 4 sites
terminal (3 MATCHED + 1 RETIRED-REPRESENTATION); `deno task proof list
--area editcheck` shows runner PARTIAL 0, GAP 0; file deleted. Controller
runs `deno task verify --filter swiftcore --verbose` and records the
Result line.
