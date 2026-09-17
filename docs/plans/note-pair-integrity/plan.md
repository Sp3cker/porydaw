# Note-pair integrity during ordinary editing

Status: implemented and controller-verified in the isolated `note-integrity-refusal` worktree; uncommitted and unmerged, based at `71ac6b5212ac266d060e1c1937c0eca0487f2c0b`. This revision applies the final ruling — **uniform atomic refusal with stable NoteIds** — replacing the earlier cap/trim/duplicate policy; the correction history, including what the user explicitly released, is in [audit.md](audit.md). Behavior is specified in [spec.md](spec.md). Findings are source-derived, not runtime reproductions.

## Task list

| # | Task | Route | Prerequisites |
| --- | --- | --- | --- |
| 1 | [Test oracle support](task-1-brief.md) | SDD-track / sdd-implementer | — |
| 2 | [Core admission and stable identity](task-2-brief.md) | SDD-track / sdd-implementer | 1 |
| 3 | [Range producer](task-3-brief.md) | SDD-track / sdd-implementer | 2 |
| 4 | [Delete Time producer](task-4-brief.md) | SDD-track / sdd-implementer | 2 |
| 5 | [UI consumers and manual](task-5-brief.md) | SDD-track / qt-cpp-reviewer | 2 |
| 6 | Align downstream fixtures with refusal semantics — Direct, inline below | Direct | 2 |

Routing: tasks 1–4 are judgment work at the core planning seam — an event-level consistency oracle, one admission predicate replacing three policies, builder unification around stable identity, and two producer conversions with clamped-endpoint edge cases — so the seat is `sdd-implementer`. Task 5 is Qt Widgets/C++ truthfulness (selection, cursor and revision gating around model mutations) plus the user-facing manual, so the seat is `qt-cpp-reviewer`. Task 6 is genuinely Direct under triage — a mechanical, reversible fixture reroute across two check files with the single predicate that the named slots pass — so it carries no brief; its Target/Change/Acceptance is inline below and the dispatch quotes it.

All six belong to the single workstream **ordinary-edit note integrity**:

- Task 1 exports the test-only note-pair consistency oracle (`songdocument_test::notePairsConsistent`) in the shared support pair, and nothing else.
- Task 2 owns the SongDocument seam: the private admission predicate (grouped by `(engineTrack, key)`, no cross-pitch quadratic scan), unified stable-identity move builders, refusal-first resize planning, the prebuilt-ops command/undo discipline, plan-first merging that commits only when accumulated candidate geometry exactly equals the already-applied sequential geometry per `NoteId` (per-pitch destinations realigned to the incoming notes' `NoteId`s under reordered input), every new or renamed editcheck slot declaration, and the note/move regression matrix.
- Task 3 converts `applyRangeEdit` (combined-destination validation) and `moveRange` (exact clamped endpoints) to that contract, extending the existing slots in its own regression file — no test-header edits.
- Task 4 converts `TimeEditor::remove` to pure refusal detection, likewise extending existing slots in its own regression file.
- Task 5 owns consumer-side truthfulness (revision-gated paste/transpose/nudge effects including `PianoRoll::transposeSelection`'s reveal/audition/update gate, one neutral Delete Time no-change message covering both no-op and collision refusal, the rollcheck duplicate-expectation flip and rejection slot) and the manual.
- Task 6 realigns two downstream fixtures that uniform refusal would otherwise redden after task 2: the editcheck publication slots and the velocity-page stacked-node seeding.

Dependency graph: **1 → 2 → {3, 4, 5, 6}**. Task 2 consumes task 1's oracle helper. Tasks 3–6 consume task 2's private admission behavior and its public unchanged-revision rejection contract — interfaces only, never implementation detail. Tasks 3–6 have mutually disjoint write sets and are parallel-ready once task 2 is accepted.

Sizing: tasks 1, 3 and 4 sit within the three-file default. Task 2 exceeds it (core pair, the editcheck test header and two regression files): it closes one admission invariant over one seam — a recorded cohesive-behavior exception, not a mechanical one. Task 5 exceeds it (range consumer, the piano-roll transpose command file, rollcheck harness files and the manual): one consumer-truthfulness contract with one verification surface. Task 6 is a two-file Direct fixup defined inline below.

### Task 6 (Direct): Align downstream fixtures with refusal semantics

- **Target:** `src/checks/editcheck/tst_songdocument_document.cpp` (slots `documentPublicationNetZero`, `documentMergedOverlapPublication`) and `src/checks/drawerpresentation/velocity.cpp` (slot `transientBandAndStackedNodes`). Closed set; no other files.
- **Change:** Both editcheck slots move key 69 by +1 onto key 70, where a stationary note with the same start tick already lives — under task 2's uniform refusal those moves refuse and the slots go red. Reroute their merge/publication scenarios through free pitches (seed the stationary note on a free key such as 72) while keeping their actual contracts: revision counts, `documentChanged`/`tracksRemapped` ordering, net-zero inverse merge (undo count returns to baseline, no redo branch, bytes equal), and the clean-index barrier. In `transientBandAndStackedNodes`, seed the stacked same-pitch overlap through public `SongDocument::insertRawEvent` (note-on plus release) instead of semantic `addNote`, so arbitrary raw-stream drawer rendering stays covered — the playable projection is built defensively for exactly such raw material.
- **Acceptance:** `deno task verify --filter editcheck --qt documentPublicationNetZero documentMergedOverlapPublication` and `deno task verify --filter velocity-page --qt transientBandAndStackedNodes` pass on the implementer's settled tree (both need an available native desktop); the controller's final settled-tree runs keep both harnesses green.

## Global Constraints

- Scope is prevention in a clean new song through semantic editing. Do not sanitize imported MIDI, change raw Event List freedoms, alter MIDI pairing/export interpretation, or add orphan cleanup UI. Existing debris is not repaired by this work.
- The spec owns the single collision rule; admission, identity and refusal semantics come from [spec.md](spec.md). Do not introduce stationary trimming or removal, resize capping, realized-duration undo stores, duplicate-span admission, NoteId reminting, or any document preview API — resize preview stays the existing drag-delta UI arithmetic. Keep the existing SongDocument planning seam (builders produce ops or refusal), EditOp application/reversion, and the history/publication owners. No global post-edit scrubber, parallel note store, new dispatcher or generic transaction framework.
- NoteIds are stable through every semantic edit, including per-pitch/scale-fold moves. Rejection preserves all IDs, velocities and bytes exactly.
- Closed write sets; preserve unrelated changes. Use LSP references before changing the named interfaces and migrate every production caller. Inspect current source before execution: line references in this plan are navigation aids, not edit coordinates.
- Implementers reuse the commands recorded in their briefs. Reassess only if scope changes or a command is stale/unavailable; record the mismatch and replacement, never silently narrow verification.
- Implementers perform local inspection and focused validation when owning the settled tree. If another writer shares the build tree, defer builds/tests/formatters to the controller; read-only inspection remains allowed. The controller owns final settled-tree formatting, regression runs and native smoke. Use `deno task`, never direct CMake.
- Tests defend observable notes/events, atomic refusal, undo and consumer state — not helper wiring or message wording. Use existing synthetic-document/clipboard support. No new harness or production test access.
- No assertion/check failure may be handed off unresolved. Apply the repository's single-baseline failure policy; do not repeatedly stress native input while the user uses the desktop.

## Verification and checkpoints

Task 1 proves the oracle on deliberately corrupted fixtures. Task 2 supplies fail-before/pass-after regression evidence for admission, stable identity and the note/move matrix. Tasks 3 and 4 supply the same for their producers. Task 5 supplies shown-UI evidence; a passing core test does not establish cursor/selection correctness. Task 6 reroutes two downstream fixtures whose current geometry task 2's refusal reddens; its scoped checks are recorded inline with the task. Exact commands and smoke scenarios are in the briefs; rollcheck's and velocity-page's shown checks require an available native desktop.

Checkpoint milestones: after task 2's review gate, checkpoint all accepted work — the admission contract is the integration boundary the parallel wave builds on. Final milestone: tasks 3–6 accepted — SDD review gates for 3–5 and task 6's inline named checks — with scoped checks and native smoke passing, changed code formatted, manual updated, temporary smoke artifacts removed, then checkpoint the remaining accepted work. Execution commits require authorization under the execution session; the present request authorizes these plan documents only.

## Source basis

- `src/core/songdocument.cpp`, `songdocument.h`: `notesForTrack` (interpretation unchanged); fork-main's void `resolveNoteOverlaps` stationary-trim planner is replaced by a pure admission predicate with no duplicate carve-out; `buildMoveNotesOps`/`buildMoveNotesToPitchesOps` unified around one stable-identity event-rewrite discipline and returning `std::optional`; `buildResizeNotesOps` returning `std::optional` with admission and no capping; the three mergeable commands keep accumulated-delta merging, rebuilt plan-first with overflow guards.
- `src/core/songdocument_range.cpp`: `applyRangeEdit` combined-destination validation including empty-SMF track expansion; `moveRange` exact clamped-endpoint planning.
- `src/core/songdocument_timeeditor.cpp`: `TimeEditor::remove` written/edited collection with refusal instead of trims.
- `src/core/songdocument_timeeditor_insert.cpp`: `insertBlank`, `duplicate` — non-goals; seam-split construction already preserves disjointness.
- `src/ui/songview/pianoroll_gestures_active.cpp`: `updateResizeDrag`/`commitResizeDrag` — attempted-geometry preview and release-time commit; resize truthfulness follows from the unchanged revision.
- `src/ui/songview/rangeedit.cpp`: range mutation and clipboard consumers. `src/ui/songview/pianoroll_commands.cpp`: `PianoRoll::transposeSelection` — ordinary selected-note transpose; its reveal/audition/update effects are revision-gated on the accepted `moveNotes`.
- `src/checks/editcheck/tst_songdocument_support.*`: oracle home. `src/checks/rollcheck/identity.cpp`, `timemenu.cpp`: duplicate-expectation flip and rejection slot. `src/checks/editcheck/tst_songdocument_document.cpp`: publication/net-zero slots rerouted to free pitches (task 6). `src/checks/drawerpresentation/velocity.cpp`: `transientBandAndStackedNodes` overlap reseeded through public `SongDocument::insertRawEvent` (`songdocument.h`), keeping raw-stream drawer coverage.
- `src/checks/checkcatalog.cpp`: editcheck covers document editing; rollcheck covers shown piano-roll commands/gestures; `velocity-page` covers the velocity drawer surface. `tools/checks_options.ts` confirms `--qt` targets one selected harness.
