# Swift backend Wave 4 — writable seam (`sgc_`) and its first two consumers

> Historical dispatch plan — do not execute or resume these tasks.
> Commit `fe1ff4df` closed a re-scoped grid milestone, not this original
> five-task acceptance set. T5's C++ presenter mirror was canceled.
> Retained legacy behavior is recorded in [spec.md](spec.md); the
> [current charter](../swift-backend-charter.md) governs maintenance.
> New work requires the [ownership design](../swift-ownership-cutover/design.md)
> gates and approved replacement briefs. Commands below may refer to retired
> harnesses or the removed standalone demo lane; they are historical evidence,
> not the current verification recipe.

The read-only roll becomes an editor, and TrackHeaders becomes the second
consumer of the same seams. Four new C-ABI surfaces, all values:

- `sgc_` — intent pipe, Swift → C++. Document intents execute as undoable
  `SongDocument` commands; session intents route to `SongView` state.
- `sgs_` — session-state push, C++ → Swift: selection transitions
  (`NoteId` tokens), primary track, track scope, mute/solo masks.
- `sgk_` — host-arbitrated key delivery, C++ → Swift: registry-matched
  command ids, never QKeyEvents.
- `sgd_` amendment — `SgdNote` gains its `NoteId` token (additive).

Both waves' contracts live in [spec.md](spec.md); the charter binds
everything. **Dispatch gate: Wave 3 final gate green, perf bar accepted
(§ below), and the user has authorized the Wave 3 checkpoint commits.**

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [`sgc_` intent pipe + executor + `swiftcommands` harness](task-1-brief.md) | SDD-track / sdd-implementer | New contract surface: undoability routing (S-3) and intent validation are judgment, not mechanics | Wave 3 gate |
| 2 | [`sgs_` session seam + `sgd_` NoteId amendment](task-2-brief.md) | SDD-track / sdd-implementer | Selection/session push contract with reconciliation semantics (`reconcileNoteSelection`, `applyRemap`) — contract work | Wave 3 gate |
| 3 | [`sgk_` key seam + `SwiftRollBand` adapter](task-3-brief.md) | SDD-track / qt-cpp-reviewer | Swift surface joins `TimelineBandInteraction`; input forwarding, gesture-active gating, fallback order — Qt contract heavy | 1, 2 |
| 4 | [Grid editing: gestures → intents](task-4-brief.md) | SDD-track / sdd-implementer | Gesture-to-intent mapping with one-undo-per-gesture granularity; behavior boundaries | 1, 2, 3 |
| 5 | [TrackHeaders Swift presenter](task-5-brief.md) | SDD-track / sdd-implementer | Second consumer of both seams behind its own flag; presenter surface mirror of `TrackHeaderModel` | 1, 2, 3 |

Execution order: **{1 ∥ 2} → 3 → {4 ∥ 5}.** 1 and 2 are file-disjoint
(1: `swiftgrid/command_*` + `swiftcommands` harness; 2: `swiftgrid/session_*`
+ `swiftdocfeed` extension + `SgdDocument.swift` — single writer enforced by
the Task-2 seam). 4 and 5 are file-disjoint (grid files vs
`trackheaderswift.*` + its QML). Task 3 is single-writer on
`timelinequickview` band wiring and the adapter files.

## Perf precondition (decided before Task 4 dispatch)

Wave 3's evidence sets the bar; default, adjustable by the user at the
Wave 3 gate review: Swift roll scroll/zoom frame cost within 2× of the
C++ roll on the largest checked-in fixture song, no sustained dropped
frames. Failing the bar re-routes Task 4 into a raster-performance task
first; it does not silently proceed.

## Global Constraints

- Every brief inherits this section, [spec.md](spec.md), and
  [swift-backend-charter.md](../swift-backend-charter.md); the charter
  wins conflicts. The charter's Swift implementation policy (6.4,
  checked concurrency, owned storage, no invented fallbacks) applies.
- **The Wave 3 `sgd_` ABI is frozen except for the Task-2 amendment**
  (`noteId` field, additive; both sides compile in one binary, layout
  sync is compile-time). No other edits to `sgd_`.
- **Production C++ write set is closed:** new files under
  `src/ui/songview/quick/swiftgrid/`, `src/ui/songview/quick/timelinequickview.{h,cpp}`
  (band wiring, Task 3 only), new `src/ui/songview/trackheaderswift.{h,cpp}`
  (Task 5), new harness dirs + the three registration points. Everything
  else under `src/` is read-only. Unlisted file ⇒ brief defect; escalate.
- **Intent vocabulary is closed** in spec §2: implementers add no
  commands without a spec amendment. An interaction that cannot be
  expressed is an escalation, not a new verb.
- **One dispatcher.** Keys reach Swift only as registry-matched command
  ids through `sgk_`; QML never binds keyboard shortcuts (INV-1); Swift
  never sees QKeyEvents (INV-3). Text entry (rename, numeric fields)
  stays host-side per the charter's local-input exceptions.
- **Session vs document routing is C++-side and fixed** (spec §1):
  Swift submits intents without class knowledge beyond the enum.
- **Selection authority is the host.** `EditorSelectionModel` stays the
  single owner; Swift receives transitions and submits set/clear intents.
  No Swift-side selection state survives between pushes.
- Prototype lane must keep every existing smoke row green; new rows are
  additive. `PORYDAW_SWIFT_ROLL` gates the editable roll;
  `PORYDAW_SWIFT_HEADERS` gates the header presenter. Flags off =
  byte-identical behavior to Wave 3 ship state.
- No commit is authorized by this plan; checkpoints below.

## Verification policy

1. `swiftcommands` (Task 1): intent validation, undo granularity,
   revision round-trip, session routing.
2. `swiftdocfeed` extension (Task 2): selection transitions, mask pushes,
   reconciliation after undo/remap, stale-token behavior.
3. `swiftbandkeys` (Task 3): command-id delivery, eligibility gating via
   `sgp_` + `sgs_`, gesture-active blocking, autoRepeat, fallback order.
4. `swiftrollgated` extension (Task 4): end-to-end edit → undo → re-render
   through the production window with the flag on.
5. `swiftheadersgated` (Task 5): presenter surface, mute/solo round-trip,
   rename via host text entry, document track ops undoable.
6. Production canaries after any production-file edit: `deno task
  build:app`, `verify --filter selectionkey-core`, `--filter rollcheck-static`.
   Prototype regression: `deno task prototype:swift-grid --smoke`.

Controller final gate: all five harnesses + canaries + prototype smoke,
run once, whole plan.

## Checkpoints

No commit authorized yet. When the user approves:

- After Task 2 (Tasks 3–5 consume the amended `SgdDocument` and the
  session seam — checkpoint before file reuse).
- After Task 3 (Tasks 4–5 consume the adapter/band wiring).
- Wave close after the final gate.

## Source anchors

| Owner | Current |
| --- | --- |
| Intent execution backend | `SongDocument` command path + `QUndoStack` (src/core/songdocument.h); `SongView::setTrackMute`/`setTrackSolo`/track ops (src/ui/songview/trackvoiceops.cpp:78-122) |
| Selection authority | `songview::EditorSelectionModel` (src/ui/songview/editorselectionmodel.h), `NoteId` (src/core/noteid.h — opaque uint64 token, document-scoped) |
| Band contract | `TimelineBandInteraction` (src/ui/songview/quick/timelineinput.h), key routing (timelinequickview_keyrouting.cpp), cancel filter (native/window_cancel.cpp, `sgw_`) |
| Header presenter mirror | `TrackHeaderModel` (src/ui/songview/trackheadermodel.h) + `TrackHeaderBand.qml` |
| Seam conventions | `document_feed.h` (`sgd_`), corrected Wave-3 spec (raw SMF fields, normalization in `TimeAxis`) |
