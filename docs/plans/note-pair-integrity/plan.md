# Note-pair integrity during ordinary editing

Status: audited implementation plan; not implemented. Findings are source-derived, not runtime reproductions. See [spec.md](spec.md) for behavior and [audit.md](audit.md) for corrections to the planning-agent proposal.

## Task list

1. [Preserve note-pair integrity in document edits](task-1-brief.md) — SDD-track / sdd-implementer: independently capped grouped extension, optional planning results, realized-output undo merging and ripple semantics require judgment across one document-editing surface.
2. [Keep rejected edits truthful in the UI](task-2-brief.md) — SDD-track / qt-cpp-reviewer: consumes Task 1's rejection contract; selection/cursor effects and shown Quick interactions require UI verification.

Both belong to the single workstream **ordinary-edit note integrity**. Task 1 owns document mutation and its regressions. Task 2 owns consumer-side acceptance handling and user documentation. Execute 1 → 2; the dependency is the mutation/rejection contract, not implementation detail.

Task 1 intentionally exceeds the three-file default: its eleven files close one document invariant over all existing producers and one editcheck surface. Splitting the planner's proposed core/range/ripple packages would leave callers temporarily ignoring rejection, omit shared test ownership, and repeat the same build. Task 2's four files close the consumer contract. These are cohesive-behavior exceptions, not mechanical exceptions.

## Global Constraints

- Scope is prevention in a clean new song through semantic editing. Do not sanitize imported MIDI, change raw Event List freedoms, alter MIDI pairing/export interpretation, or add orphan cleanup UI. Existing debris is not repaired by this work.
- The spec owns collision policy. Keep the existing SongDocument overlap planner, EditOp application/reversion, history and publication owners. No global post-edit scrubber, parallel note store, new dispatcher, or generic transaction framework.
- Closed write sets; preserve unrelated changes. Use LSP references before changing the named interfaces and migrate every production caller. Inspect current source before execution: line references in this plan are navigation aids, not edit coordinates.
- Preserve existing accepted-edit note identity behavior. In particular, ordinary moves/resize retain IDs; the current per-pitch move builder remints rewritten notes. Identity modernization is not included. Rejection must preserve all IDs and velocities exactly.
- Implementers reuse the commands recorded in their briefs. Reassess only if scope changes or a command is stale/unavailable; record the mismatch and replacement, never silently narrow verification.
- Implementers perform local inspection and focused validation when owning the settled tree. If another writer shares the build tree, defer builds/tests/formatters to the controller; read-only inspection remains allowed. The controller owns final settled-tree formatting, regression runs and native smoke. Use `deno task`, never direct CMake.
- Tests defend observable notes/events, atomic rejection, undo and consumer state—not helper wiring or message wording. Use existing synthetic-document/clipboard support. No new harness or production test access.
- No assertion/check failure may be handed off unresolved. Apply the repository's single-baseline failure policy; do not repeatedly stress native input while the user uses the desktop.

## Verification and checkpoints

Task 1 supplies fail-before/pass-after regression evidence for the concrete new-song defects. Task 2 supplies shown-UI evidence; a passing core test does not establish cursor/selection correctness. Exact commands and smoke scenarios are in the briefs.

The tasks have disjoint write sets, so no intermediate Git checkpoint is required. Final milestone: both task review gates accepted, scoped checks and native smoke pass, changed code formatted, manual updated, temporary smoke artifacts removed, then checkpoint all accepted work. Execution commits require authorization under the execution session; the present request authorizes committing this plan only.

## Source basis

- `src/core/songdocument.cpp`: `notesForTrack`, `resolveNoteOverlaps`, note builders, three mergeable commands.
- `src/core/songdocument_range.cpp`: `applyRangeEdit`, `moveRange`.
- `src/core/songdocument_timeeditor.cpp`: `TimeEditor::remove`.
- `src/core/songdocument_timeeditor_insert.cpp`: `insertBlank`, `duplicate` preserve disjoint clean-note geometry by splitting at insertion seams.
- `src/ui/songview/pianoroll_commands.cpp`, `pianoroll_gestures_active.cpp`: real keyboard/drag callers.
- `src/ui/songview/rangeedit.cpp`: range mutation and clipboard consumers.
- `src/checks/checkcatalog.cpp`: editcheck covers document editing; rollcheck covers shown piano-roll commands/gestures. `tools/checks_options.ts` confirms `--qt` targets one selected harness.
