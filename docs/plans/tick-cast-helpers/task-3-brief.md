# Task 3: Note mutation arithmetic and undo

## Context

Consume Task 1's shift helper. Repair the loss of implicit widening in note ends and add admission checks before note transactions. Task 6 consumes the resulting no-mutation rejection behavior. Range callers of the private insertion helper are covered separately by Task 4, not by silently dropping an invalid individual insert here.

## Exact write set

- `src/core/songdocument.cpp`
- `src/checks/editcheck/tst_songdocument_songnotes.cpp`
- `src/checks/editcheck/tst_songdocument_songmoves.cpp`

## Prerequisites

1: `CoreTimeDefaults::shiftTickClamped`.

## Interface contract

Implement [Note and range mutation policy](spec.md#note-and-range-mutation-policy) for `addNote`, `addNotes`, `moveNotes`, `moveNotesToPitches`, and `resizeNotes`. `noteEndTick(const DocNote&)` keeps its uint64_t return and reports a genuinely wide sum for terminated notes. Existing public signatures, command IDs, note IDs, and normal merge behavior remain unchanged. `resizeNotesLeft` remains outside this task's mutation changes.

## Implementation steps

1. Widen before addition in `noteEndTick`. Make `appendNoteInsertOps`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`, and right-resize storage writes consume a proven in-range end. Reuse the existing planned-end arithmetic where appropriate; do not add a generic conversion layer or return after emitting half of a note.
2. Preflight complete eligible batches in the named public mutations before overlap planning or history push. Check normalized insertion durations, requested upper start shifts, and terminated end headroom. Evaluate right-resize deltas against duration headroom before adding or narrowing. Follow the spec's existing lower-bound behavior and rejection return conventions.
3. Replace scalar shift casts in `MoveNotesCommand::movesMyOutputs`, `MoveNotesToPitchesCommand::movesMyOutputs`, the `moveNotes` change predicate, `collectMovePlans`, and both move-ops builders with the shared helper. Preserve the builders' existing invalid-track and unterminated-note filters; do not reject a note that an operation intentionally skips.
4. Guard accumulated tick deltas in both move-command `mergeWith` implementations before any rewind or addition. An unrepresentable accumulated delta declines the merge without undoing either already-applied command. Keep output-identity checks and inverse-merge obsolescence consistent with the admitted shift policy.
5. Extend `noteEditingBasic`/`noteEditingBatch` and `noteMoveRejects`/`noteMoveMerge` with isolated synthetic boundary cases: wide synthetic `noteEndTick`, accepted exact-ceiling end, rejected sentinel/wrapping end for add/move/right-resize, a mixed valid/invalid batch, the pitched-move rejection return, extreme signed duration/movement deltas, and an unrepresentable merge accumulation. Verify observable atomicity and valid-operation undo/redo; do not serialize/reparse a synthetic overlarge single MIDI delta.

## Acceptance predicate

Every named valid note operation preserves its existing musical and history behavior; invalid upper writes reject the whole operation without side effects, and no covered end or accumulated delta wraps before validation. The new boundary regressions fail the old arithmetic and pass the repaired paths. Named checks:

```sh
deno task verify --filter editcheck --filter savecheck --filter selectionkey-core --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Keep checks file-local rather than adding public validation APIs. A clamp of the note start is not an end preflight. Do not narrow `PlannedNote` ends, change variable-bound left-resize logic, alter key/value clamping, or replace the existing command/history design. Necessary checked storage conversions are allowed.
