# Task 2: TimeEditor position cutover

## Context

Consume Task 1's Tick span and saturating shift. Finish the endpoint/local migration while preserving the TimeEditor transaction contract in [spec.md](spec.md#timeeditor-behavior). No subsequent task writes these files.

## Exact write set

- `src/core/songdocument_timeeditor_insert.cpp`
- `src/core/songdocument_timeeditor.cpp`
- `src/checks/editcheck/tst_songdocument_timerange.cpp`

## Prerequisites

1: `TimeRange::span()` and `CoreTimeDefaults::shiftTickClamped`.

## Interface contract

Keep the public remove/insert/duplicate signatures, false/no-mutation failure contract, track/lane scopes, and tempo seam behavior. Working values that are bounded positions or spans use Tick. No new declarations in `songdocument_timeeditor.hpp`.

## Implementation steps

1. In `TimeEditor::insertBlank`, `duplicate`, and `remove`, reject reserved endpoints before headroom arithmetic. Convert `s`, `e`, and `span` to Tick. Convert source/end locals only when they come from stored positions or a range-clipped end; retain wide computed note ends until bounded.
2. Preserve complete insert/duplicate preflights for every affected event, tempo point, and track end. Use Tick headroom comparisons without identity `Tick(span)` casts. Apply the helper only after admission; map duplicate destinations as source plus the range span, and remove destinations as source minus that span.
3. Apply the same local-type and shift cutover to `time_edit_detail::removeTempoPoints`, `insertBlankTempoPoints`, and `duplicateTempoPoints`. Preserve seam winners, defaults, ordering, and clipping; remove identity endpoint casts rather than disguising them.
4. Update `timeEditCloseGapTrackEnds` and `timeEditShiftRightTrackEnds` to bounded Tick locals and the same admitted shifts. Keep untouched-track ends unchanged and preserve the current inserted-event maximum calculation.
5. Extend `timeRangeNoOps`, `timeRangeInsertBlankOverflow`, and `timeRangeDuplicateClippingAndOrder` with reserved-endpoint rejection, valid exact-ceiling movement, and duplicate overflow atomicity. Use isolated synthetic documents; cover a track-end-only overflow as well as a note/event destination. Preserve the existing ordinary seam and undo/redo assertions.

## Acceptance predicate

TimeEditor operations preserve normal results and reject every covered invalid endpoint/upper shift before mutation; exact-ceiling shifts remain accepted and undoable. Endpoint/span locals and guards no longer require widen-then-narrow scaffolding, while genuinely wide note ends remain wide. Named checks:

```sh
deno task verify --filter editcheck --filter savecheck --filter selectionkey-core --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not preserve unsigned-underflow behavior for sentinel ranges, delete preflight guards because the helper clamps, or change unrelated TimeEditor declarations. Do not impose a blanket zero-`uint64_t` or zero-cast acceptance rule on computed ends.
