# Preserve note-pair integrity in document edits

## 1. Context

Implement [spec.md](spec.md) at SongDocument's existing planning seam. Inherit [Global Constraints](plan.md#global-constraints). Task 2 consumes atomic rejection through unchanged document revision and the existing per-pitch boolean result. This package owns every document producer plus the shared editcheck evidence; it is one cohesive-behavior exception to the three-file default.

## 2. Exact write set

- `src/core/songdocument.h`
- `src/core/songdocument.cpp`
- `src/core/songdocument_range.cpp`
- `src/core/songdocument_timeeditor.cpp`
- `src/checks/editcheck/tst_songdocument.h`
- `src/checks/editcheck/tst_songdocument_support.h`
- `src/checks/editcheck/tst_songdocument_support.cpp`
- `src/checks/editcheck/tst_songdocument_songnotes.cpp`
- `src/checks/editcheck/tst_songdocument_songmoves.cpp`
- `src/checks/editcheck/tst_songdocument_songranges.cpp`
- `src/checks/editcheck/tst_songdocument_timerange.cpp`

## 3. Prerequisites

None beyond the frozen spec and current repository. No separate extraction task or new harness is needed.

## 4. Interface contract

Preserve public mutation signatures and the declarations/roles of `PlannedNote`, `EditOp`, the three command classes, `appendRemoveOps`, `appendNoteInsertOps`, `applyOps`, `revertOps`, and `notesForTrack`.

Change the existing private resolver to:

```cpp
bool resolveNoteOverlaps(const std::vector<PlannedNote> &written,
                         const std::vector<DocNote> &editNotes,
                         std::vector<std::vector<size_t>> &removals,
                         std::vector<EditOp> &trims) const;
```

`written` describes final participant spans, including deliberately protected unchanged participants where necessary. `editNotes` exempts those source notes (and explicitly deleted sources) from stationary trimming. False means the final participant set contains an empty or overlapping same-track/same-pitch span; output vectors remain exactly as supplied. True permits the existing stationary trim/remove plan. Empty input succeeds. Group by engine track and pitch; compare wide ticks; no quadratic all-pairs scan or whole-song copy for admission. Preserve chronological processing within each track/pitch when reusing the sorted spans for stationary resolution.

Change only the return types of `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`, and `buildResizeNotesOps` to `std::optional<std::vector<EditOp>>`, retaining arguments. `nullopt` means refusal; an empty vector is not a collision sentinel. Builders remain side-effect-free. Public callers build once, reject before history/publication, and move accepted ops into their command constructors. The constructors no longer redundantly rebuild the initial ops.

All current resolver consumers must handle the boolean: `addNote`, `addNotes`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`, `buildResizeNotesOps`, `resizeNotesLeft`, `applyRangeEdit`, `moveRange`; `TimeEditor::remove` becomes a new consumer.

Test support adds `bool notePairsConsistent(const SongDocument &document, int engineTrack)` in `songdocument_test`. For the selected clean-fixture track/channel, verify all positive-velocity starts resolve to positive spans, each release belongs to exactly one projected note, all releases are claimed, and same-pitch spans are disjoint. Inspect events as well as the projection, so an extra release cannot hide behind correct-looking notes. This helper is used only on authored clean fixtures, never as a production/import validator.

## 5. Implementation steps

1. Add synthetic clean-song regressions before production changes using `songdocument_test::makeDocument`: an empty conductor plus program-bearing editable track(s), then semantic note creation. Declare the slots below in the existing test class and implement the shared invariant helper. Capture original bytes, tempos, track count, IDs/velocities, revision/save token, undo index/count/clean state and a usable redo branch where relevant. Run the focused defect slots pre-fix and retain their actual failures as reproduction evidence.
2. Add representability admission to `resolveNoteOverlaps` before modifying its outputs; integrate optional builders and prebuilt command ops across the core callers. In per-pitch moves, include unchanged selected paired notes in final participant spans even when their events are not rewritten; preserve the existing no-op emission behavior. Gate all participants, not merely the entries that emit new events. Do not change accepted per-pitch ID-reminting semantics. In each `mergeWith`, compute candidate accumulated fields and ops without replacing live command state. A refused candidate restores both already-applied commands in order, rebuilds track-map state as required, returns false and leaves both command records intact. Preserve successful merge, inverse/no-op and publication behavior; do not label refusal impossible.
3. Migrate range producers. `applyRangeEdit` validates all eligible destination notes together, including repeated TrackNotes groups and newly planned tracks, even when the original SMF has no tracks. Keep skipped invalid destinations out of admission, matching the emission loop. Any collision rejects track creation, removals, lane writes and tempo together. `moveRange` uses independently clamped original on/end ticks, exactly matching raw-event reinsertion, then gates them before assembling/pushing the mixed command. Keep raw payloads and non-note semantics unchanged.
4. Reconcile ripple removal with the resolver. In `TimeEditor::remove`, collect shifted paired spans for notes starting at or after range end; exempt notes starting at or after range start (removed or moved), not every `plan.notes` member. Let earlier notes remain stationary candidates. Add planner trims to the existing insert list without changing recorded XCMD relocation indices; reuse `xcmdAssembleOps` for all-removals-before-inserts ordering. Respect `taken` so an original note end cannot be shifted/removed again by the orphan pass. Keep lane-only scopes, raw orphan treatment, tempo, track-end and signature behavior unchanged. Do not edit insertion/duplication algorithms.
5. Complete the focused matrix below and run the named checks. Preserve existing behavioral tests unless the specified contract intentionally changes their expectation. Verify admitted state and undo/redo byte round trips, rejected state including redo availability, and no unmatched events after accepted sequences. Tests assert musical results and state transitions, not which helper was called.

## 6. Acceptance predicate

All spec document behaviors hold through the unchanged public mutations, demonstrated by these slots in the existing files:

| Slot / file | Required observable cases |
| --- | --- |
| `noteResizeCollisionRejects` / songnotes | Exact `[0,10)`, `[20,30)` +20 rejection; left-resize collision; adjacency accepted; a mergeable sequence accepts a safe lengthening, rejects crossing the next selected start without erasing redo/history, then accepts an inverse restoring the initial state. |
| `noteBatchCollisionRejects` / songnotes | Direct `addNotes` collision rejects; same starts/containment reject; disjoint and adjacent batches accept; separate pitches/tracks remain independent. No stationary victim changes on refusal. |
| `noteMoveCollisionRejects` / songmoves | Key clamp and tick-zero clamp collisions; convergent per-pitch destinations; one destination unchanged while another converges onto it; reverse input order gives the same admission; noncolliding per-pitch edits still work. Include accepted merged move/resize, rejected subsequent edit and subsequent undo/redo, plus boundary clamp/reversal to exercise accumulated rebuilding without assuming additive clamping. |
| `rangeEditCollisionRejects` / songranges | Combined same-destination groups reject atomically with simultaneous note removal, track expansion, lane/tempo writes; empty-document expansion also validates. `moveRange` zero-length collapse rejects with its mixed data untouched. Accepted partial clamping trims stationaries against actual emitted endpoints, not original duration. |
| `timeRangeRemoveRippleTrim` / timerange | A `[0,100)`, B `[110,120)`, remove `[20,50)` produces `[0,80)`, `[80,90)`; exact boundary and noncollision variants; scoped other track unchanged; undo/redo restore exact bytes. Clean same-pitch insertion and duplication seam cases still satisfy the invariant. |

Use the invariant helper after every accepted mutation and redo in this matrix, and verify unchanged original identity/state on refusal. Do not substitute imported corpus fixtures for the minimal new-song reproductions.

NAMED CHECKS (implementer on its settled tree; otherwise controller):

```sh
deno task verify --filter editcheck --qt noteResizeCollisionRejects noteBatchCollisionRejects noteMoveCollisionRejects rangeEditCollisionRejects timeRangeRemoveRippleTrim
deno task verify --filter editcheck --verbose
```

The first command is the new defect/invariant matrix; the second covers existing stationary overlap behavior, raw editing, tick limits, document publication, history, ranges and time edits. It does not prove UI rejection handling; that is Task 2.

## 7. Task-specific constraints

- No command may enter QUndoStack merely to discover admission failure in its initial redo. Initial planning and merged replanning must use the same gate without duplicate initial computation.
- The merge fallback is transactional for both document and command members; changing the accumulated delta before a refused rebuild is a bug. Do not add snapshots of the whole song to repair this.
- Existing shared-end/unterminated raw material is not the acceptance domain. Preserve existing handling outside directly touched notes; no whole-document cleanup/assertion pass.
- New-song creation itself, SMF pairing, selection ownership and audio playback code remain untouched. All behavioral evidence requested here runs through SongDocument.
