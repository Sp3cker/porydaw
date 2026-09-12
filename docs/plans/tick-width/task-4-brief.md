# Task 4: SongDocument tick API

## Context

Consumes Task 2’s SMF/timeline ticks and Task 3’s xcmd tick fields. Producer for Tasks 5–6 (document tick API). Loop-sentinel check files listed here so `loopTick() == UINT64_MAX` cannot survive the return-type change. Time-editor overflow guards listed here so `Tick > UINT64_MAX - span` cannot go dead.

## Exact write set

- `src/core/songdocument.h`
- `src/core/songdocument.cpp`
- `src/core/songdocument_range.cpp`
- `src/core/songdocument_tempo.cpp`
- `src/core/songdocument_timeeditor.hpp`
- `src/core/songdocument_timeeditor.cpp`
- `src/core/songdocument_timeeditor_insert.cpp`
- `src/core/timelineplayer.h`
- `src/core/timelineplayer.cpp`
- `src/checks/editcheck/tst_songdocument_document.cpp`
- `src/checks/editcheck/tst_songdocument_songtracks.cpp`
- `src/checks/editcheck/tst_songdocument_timerange.cpp`
- `src/checks/project/save.cpp`
- `src/checks/selectionkey/corefixture.cpp`
- `src/checks/selectionkey/corefixture.h`

## Prerequisites

2, 3.

## Interface contract

`Tick` positions: `DocNote::tick`, `NewNote::tick`, `DocLanePoint::tick`, `LanePointValue::tick`, `LanePointMove::newTick`, `DocTimeSig::tick`, `TimeRange::{startTick,endTick}`, `TimeRange::span/contains/overlaps` params, `findNote` / `findLanePoint` / `addNote` / `addLanePoint` / `writeLanePoints` tick params, `setTrackEndTick`, `setTimeSig` / `moveTimeSig` / `deleteTimeSig` ticks, `makeChannelEvent` / `appendNoteInsertOps` / `makeLaneEvent` / `appendLaneInsertOps` ticks, time-editor `XcmdEventRecord::newTick` and move/insert tick params, `TimelinePlayer::PendingOff::tick`.

Stay `uint64_t`: durations, `noteEndTick` / `containsNoteSpan` expected end, `PendingOff::samplePos`, `revision`.

`loopTick(bool)` returns `Tick`; absent is `kNoTick`. Comment updated. `setLoopTick(int64_t)` signature unchanged; `-1` still removes; conversion to `kNoTick` lives in the setter body.

Time-editor overflow guards (`insertBlank`, `duplicate`, and any sibling in this write set that compares a tick to `UINT64_MAX - span`) compare against `kMaxTick`.

Listed checks: tick-domain `UINT64_MAX` / `numeric_limits<uint64_t>::max()` on loop ticks become `kNoTick`; `corefixture` tick params become `Tick`.

`tst_songdocument_timerange.cpp` gains a slot: `insertBlankTime` that would shift a track end or event past `kMaxTick` returns false and does not mutate (`smf().write()` unchanged). Build the overlong event in the test; do not add a fixture file.

`static_assert(sizeof(TimelinePlayer::PendingOff) == 16)`. `DocNote` stays 48, no reorder.

## Implementation steps

1. Flip the named document/player positions to `Tick` and loop sentinels to `kNoTick` in this write set, including the listed check files.
2. Retarget overflow guards to `kMaxTick`. Add the insert-overflow slot.
3. Apply the `PendingOff` sizeof assert. Do not change `setLoopTick`’s signature. Do not edit songview, drawer, or unlisted checks.

## Acceptance predicate

`loopTick` absent is `kNoTick`; insert that would exceed `kMaxTick` returns false without mutation; listed checks still pass. Named checks: `deno task verify --filter editcheck --filter savecheck --filter selectionkey-core --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: `corefixture` `tick != UINT64_MAX` after `loopTick` returns `Tick` never reserves loop markers — that compare must become `kNoTick` here. Do not start if time-editing is mutating `songdocument*`.
