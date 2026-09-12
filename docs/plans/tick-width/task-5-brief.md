# Task 5: Songview positions

## Context

Consumes Task 4’s document tick API. Producer for Task 7 (roll/clipboard checks). Mechanical same-shape cutover of songview positions to `Tick`. Named roll/clipboard checks run after Task 7 (their sources are in Task 7’s write set).

## Exact write set

- `src/ui/songviewmodel.h`
- `src/ui/songviewmodel.cpp`
- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/ui/songview/camera.cpp`
- `src/ui/songview/timecamera.h`
- `src/ui/songview/timecamera.cpp`
- `src/ui/songview/timeaxis.h`
- `src/ui/songview/timeaxis.cpp`
- `src/ui/songview/grid.h`
- `src/ui/songview/grid.cpp`
- `src/ui/songview/detail.h`
- `src/ui/songview/detail.cpp`
- `src/ui/songview/editorselectionmodel.h`
- `src/ui/songview/editorselectionmodel.cpp`
- `src/ui/songview/clip.h`
- `src/ui/songview/clipmime.h`
- `src/ui/songview/clipmime.cpp`
- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll.cpp`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/ui/songview/pianoroll_geometry.cpp`
- `src/ui/songview/pianoroll_gestures.cpp`
- `src/ui/songview/pianoroll_gestures_active.cpp`
- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler.cpp`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/ui/songview/otherstrip.cpp`
- `src/ui/songview/trackvoiceops.cpp`
- `src/ui/songview/viewstate.cpp`
- `src/ui/songview/drawercoordination.cpp`
- `src/ui/songview/quick/timelinequickview.h`
- `src/ui/songview/quick/timelinequickview.cpp`
- `src/ui/songview/quick/timelinequickview_pianoroll.cpp`
- `src/ui/songview/quick/timelinequickscene.cpp`
- `src/ui/songview/quick/timerulerquick.cpp`
- `src/ui/songview/quick/otherstripquick.cpp`
- `src/ui/songview/quick/automationquick.cpp`
- `src/ui/songview/quick/automationnodelanequick.h`
- `src/ui/songview/quick/automationnodelanequick.cpp`
- `src/ui/songview/quick/velocityquick.cpp`
- `src/ui/songview/quick/voicechangequick.cpp`
- `src/ui/songview/quick/eventlistcontroller.h`
- `src/ui/songview/quick/eventlistcontroller.cpp`

## Prerequisites

4.

## Interface contract

Musical positions in this write set are `Tick`: `StripItem::tick`, `Clip::span`, `ClipNote::relTick` (already 32-bit), `ViewNote::startTick` (already 32-bit), `LanePoint::tick` / `VoiceChange::tick` (already 32-bit), `TimeSelection` / `TrackTimeSelection` start/end, `ViewState::editCursorTick`, `SongView` / `TimeCamera` / `Grid` / `TimeAxis` tick params and loop accessors, `GridSegment::{start,next}` (`beatTicks` / `beatsPerBar` are `uint32_t`), hover/publish tick params.

`ViewNote::endTick()` stays `uint64_t`. `scaleTick` internals stay uint64; its clamp maximum is `kMaxTick`. `TimeAxis` loop accessors return `Tick`; absent is `kNoTick` (`GridSegment::next` too). No new `hasLoop*` helpers.

`static_assert(sizeof(songview::TimeAxis::GridSegment) == 16)`. Keep field order.

`songview.cpp` `documentRevision` stays `uint64_t`. Playhead sample APIs stay `uint64_t`.

## Implementation steps

1. Replace musical-position `uint64_t` (and already-`uint32_t` position fields) with `Tick` in the listed files only.
2. Flip tick-domain sentinels and `scaleTick` / span clamps to `kNoTick` / `kMaxTick` as specified.
3. Apply the `GridSegment` sizeof assert. Do not change `ViewNote::endTick()`’s return type.

## Acceptance predicate

Songview positions compile as `Tick`; loop-absent and grid `next` use `kNoTick`; clipboard rescale cannot clamp above `kMaxTick`. Named checks: `deno task build:app` (roll / clip harnesses run in Task 7).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: leaving `scaleTick(..., UINT64_MAX)` after `Clip::span` is `Tick` wraps the clamp. Grid loops that use `UINT64_MAX` as “open end” must become `kNoTick`.
