# Task 2: SMF, timeline, Tick, rescale

## Context

Consumes Task 1’s parse bound. Adds `Tick` / `kNoTick` / `kMaxTick` and narrows SMF/timeline storage. Producer for Task 3 (`Tick` vocabulary) and Task 4 (`SmfEvent::tick`, `TempoPoint::tick`, `MidiTimeline` length/loop ticks, `sampleForTick` param).

## Exact write set

- `src/core/timedefaults.h`
- `src/core/smf.h`
- `src/core/smf.cpp`
- `src/core/miditimeline.h`
- `src/core/miditimeline.cpp`
- `src/core/midiimport.h`
- `src/core/midiimport.cpp`
- `src/core/tempo.h`
- `src/ui/newsongwizard.h`
- `src/ui/newsongwizard.cpp`
- `src/ui/workspaceui_samples.cpp`
- `src/checks/onboardcheck/import.cpp`

## Prerequisites

1.

## Interface contract

`using Tick = uint32_t` at global scope in `timedefaults.h` (same footing as `NoteId`). `CoreTimeDefaults::kNoTick` / `kMaxTick` as in spec.md. Include `<limits>` if missing.

`SmfEvent::tick`, `SmfTrack::endTick`, `TempoPoint::tick`, `TempoMapPoint::tick`, `TimeSigPoint::tick`, `OtherEvent::tick`, `MidiTimeline::{lengthTicks,loopStartTick,loopEndTick}` are `Tick`. Loop-absent initializers and comparisons in this write set use `kNoTick`. `loop*Sample` stay `uint64_t` / `UINT64_MAX`. `hasLoop()` stays sample-based.

`sampleForTick(Tick tick) const` still returns `uint64_t` (samples). `tickForSample` unchanged. File-local `RawEvent` / `RawOther` / `NoteEdge` ticks are `Tick`. `parseTrack` accumulator stays `uint64_t`; the Task 1 bound may now read `kNoTick` instead of `UINT32_MAX`.

`bool rescaleDivision(SmfFile *smf, uint16_t newDivision, QString *error);` per spec.md.

`bool NewSongWizard::songFile(SmfFile *out, QString *error) const;` per spec.md. `WorkspaceUi::submitCreateSong` shows the warning and does not create on failure.

`static_assert(sizeof(TempoPoint) == 8)` and `sizeof(TimeSigPoint) == 8`. Do not reorder `TempoMapPoint` / `OtherEvent`. `TimelineEvent::tick` becomes `Tick`. Miditimeline `static_cast<uint32_t>(…tick)` on SMF ticks become assignments.

`OnboardingTest`: existing `songFile()` callers use the bool out-param. New coverage: (1) in-memory SMF, division 24, one event at `kMaxTick`, `rescaleDivision(..., 48, ...)` returns false, that tick unchanged, error contains `Tick rescale to division %1 exceeds 32-bit tick range`; (2) `NewSongWizard` on that SMF, rescale checkbox checked, the `-X` / 48-clocks checkbox checked, `songFile` returns false and the error contains the same text. Do not add a checked-in `.mid`.

## Implementation steps

1. Add `Tick` / `kNoTick` / `kMaxTick`. Flip the named storage/params to `Tick` and tick-domain sentinels in this write set to `kNoTick`. Apply the two sizeof asserts. Leave `SmfEvent` / `SmfTrack` / `TempoMapPoint` / `OtherEvent` order.
2. Replace `rescaleDivision` with the bool+error contract; keep uint64 intermediates.
3. Change `songFile` and `submitCreateSong` to fail closed. Update onboardcheck callers and add the two overflow assertions.

## Acceptance predicate

Overlong parse still fails; valid SMF still loads; loop-absent in this write set is `kNoTick`; rescale overflow fails closed without mutation; wizard `songFile` fails on that overflow; existing onboard rescale-success assertions pass. Named checks: `deno task verify --filter smfcheck --filter onboardcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: narrowing `loopStartTick` while leaving a `UINT64_MAX` compare in `miditimeline.cpp` makes `hasLoop`-adjacent tick logic silently skip — flip those literals here. `loopcheck` sources convert in Task 7; do not edit them.
