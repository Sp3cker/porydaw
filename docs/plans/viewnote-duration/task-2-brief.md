# Task 2: Cut over consumers and skip empty spans

## Context

Consumes Task 1: `ViewNote::duration` and `ViewNote::endTick()`. Musical time
stays on the struct; pixels stay in `noteRect` / the camera. The property list
holds for ratify (verify + repair) and re-land (implement) alike.

## Exact write set

- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/pianoroll_gestures.cpp`
- `src/ui/songview/quick/timelinequickview_pianoroll.cpp`
- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/ui/songview/trackvoiceops.cpp`
- `src/checks/rollcheck/identity.cpp`
- `src/checks/rollcheck/keyboard.cpp`
- `src/checks/rollcheck/timemenu.cpp`
- `src/checks/host/tst_rulergridmenu.cpp`

Mechanical exception: every `ViewNote` `.endTick` data-member use in this list
becomes `endTick()`.

## Prerequisites

Task 1 interface: `duration` field, `endTick()` method, unpaired duration 0.

## Interface contract

`PianoRoll::noteRect(const ViewNote &)` returns a null `QRectF` when
`note.duration == 0`. Other `noteRect` overloads unchanged.

Draw-pending `ViewNote` sets `duration` to the existing draw length
(`m_drawDur`), not an end field.

`announceNote` reports `note.duration` as the tick length.

Note borders are solid: no `unterminated` parameter anywhere in note-border
painting; `noteBorderDashLength` / `noteBorderDashGap` absent from
`pianoroll.h`. `addDashedFrame` itself remains for the time-selection edge.

## Required tree properties

1. Every `ViewNote` end-field read/write in the write set uses `endTick()` or
   `duration` (`armNoteDrag` grips, time-range overlap, occupancy
   `emptyTick < note.endTick()`, identity expected end 288).
2. `noteRect(const ViewNote &)`: `duration == 0` returns `{}` before
   `pianoRollNoteMinimumWidth` is applied; otherwise
   `displayX(startTick)` / `displayX(endTick())`.
3. `beginDraw` pending note: `duration = m_drawDur`. Zero-duration notes are
   unreachable via hit-test; `displayedNoteRect` need not handle them.
4. Quick view: `addNoteBorder` draws solid frames with no unterminated branch
   (the `addFrame` signature may shed its return value).

## Acceptance predicate

Zero-duration ViewNotes produce a null `noteRect` and are not hit; paired notes
still resolve `endTick()` as start+duration; dashed unterminated borders remain
absent. Named checks: file-local diagnostics on the write set; focused
`rollcheck` deferred to parent SHARED_TREE.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk:
`pianoRollNoteMinimumWidth` on a zero-duration note makes it hittable; the
null-rect return must happen before that max. Do not edit `songviewmodel.*`.
