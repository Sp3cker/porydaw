# Task 4: Range mutation arithmetic

## Context

Consume Task 1's shift helper and close the mixed-edit callers of note insertion. `applyRangeEdit` reaches `appendNoteInsertOps` independently of `addNotes`, so fixing only Task 3 would leave clipboard/range writes unprotected. The complete operation contract is in [spec.md](spec.md#note-and-range-mutation-policy).

## Exact write set

- `src/core/songdocument_range.cpp`
- `src/checks/editcheck/tst_songdocument_songranges.cpp`

## Prerequisites

1: `CoreTimeDefaults::shiftTickClamped`. No dependency on Task 3's implementation: private insertion and public mutation signatures are preserved by that task.

## Interface contract

`SongDocument::applyRangeEdit` and `moveRange` remain void atomic operations. Invalid upper destinations leave notes, lanes, tempo, track layout, and history untouched. Preserve their existing scope, invalid-track filtering, collision, xcmd rewrite, and lower-clamp behavior. The private insertion helper may rely on this caller preflight; it must not be used as a per-note skip mechanism.

## Implementation steps

1. At `applyRangeEdit` admission, validate every eligible added note's normalized span and every added lane/tempo position, including writes to tracks that the edit proposes to create. Reject before planning removals or expanding tracks; keep the existing target-track eligibility rules.
2. At `moveRange` admission, check upper headroom for all participating note-on/note-off destinations, ordinary lane points, descriptor points, and tempo points. Check requested shifts before saturation and validate wide terminated-note ends. A single invalid member rejects the complete mixed move.
3. Replace the four scalar shift sites in `moveRange`: descriptor `writes`, overlap-plan `newTick`, reinserted raw `op.event.tick`, and tempo `shifted.tick`. Use `std::set<Tick>` for the tempo-position `moving` set; keep xcmd candidate identities and indices uint64_t. Remove the identity `Tick(point.tick)` in `applyRangeEdit` while retaining necessary checked-end conversions.
4. Extend the existing `rangeEdit` and `rangeMove` slots with synthetic exact-ceiling success and upper-overflow rejection. Include a replacement that also removes an existing note, writes a lane/tempo point, and requests track expansion; one invalid added note must leave all of it unapplied. Cover a mixed move where only its note-off or one lane/tempo destination exceeds the ceiling, plus undo/redo of a valid boundary move.

## Acceptance predicate

The range paths cannot bypass note-end admission or partially apply an invalid mixed edit; valid range edits preserve existing results and undo/redo. Position containers and shifted destinations use the canonical type without changing identity domains. Named checks:

```sh
deno task verify --filter editcheck --filter savecheck --filter selectionkey-core --filter clipcheck --filter clipmimecheck --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not change public signatures, add a second note insertion API, move xcmd work to a new module, or modify `rangeedit.cpp`. Do not duplicate Task 3's mutation implementation here; this task owns only the independent range admission boundary and its local shift sites.
