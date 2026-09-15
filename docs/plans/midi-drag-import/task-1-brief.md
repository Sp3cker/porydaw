# Task 1 — Selected-Track MIDI Projection

## Context

The stale source branch mixed reusable SMF selection behavior with obsolete UI assumptions. Put pure analysis and projection behind the current `midiimport` interface. Task 5 consumes these functions for both chooser destinations. Read [plan.md](plan.md) Global Constraints and [spec.md](spec.md) Pure Selection Projection.

## Exact write set

- `src/core/midiimport.h`
- `src/core/midiimport.cpp`
- `src/checks/onboardcheck/import.cpp`

## Prerequisites

None.

## Interface contract

- Add `std::vector<uint8_t> channels` to `ImportTrackInfo`, distinct and ordered by first channel-event occurrence.
- Add `std::vector<ImportTrackInfo> noteBearingImportTracks(const SmfFile &source)`.
- Add `SmfFile selectedMidiForNewSong(const SmfFile &source, const std::vector<int> &selectedTracks)`.
- Add `SmfFile selectedMidiForAppend(const SmfFile &source, const std::vector<int> &selectedTracks)`.
- `selectedTracks` is a unique set of valid source-chunk indices returned by `noteBearingImportTracks`; callers validate that precondition.
- Source selection, global classification, ordering, prefix context, end ticks, and outputs follow [spec.md](spec.md); inputs remain unchanged.

## Implementation steps

1. Extend `ImportTrackInfo` channel reporting and enumerate every note-bearing source chunk directly, independent of `mapSmfEngineTracks` and the hardware cap; keep the mapper canonical for projected result validation.
2. Implement the exact payload/name/prefix-aware global classifier in [spec.md](spec.md) by composing `isTempoMeta`, `smfMetaIsMarker`, and `SmfChannelPrefix` rather than duplicating unrelated SMF mapping.
3. Implement new-song projection with a tick/chunk/event-ordered conductor, self-contained prefixed markers, defined conductor end tick, and selected source-order note chunks stripped only of valid song-global events.
4. Implement append projection with selected source-order chunks and valid destination-owned globals removed while retaining malformed globals, names, scoped metadata, sysex/channel events, event order, and meaningful end ticks.
5. Extend `OnboardingTest::importAnalysis` for distinct channel order, a note chunk after 16 channel-only chunks, and 17 visible note chunks; extend `OnboardingTest::importDedup` for malformed globals, same-tick cross-chunk ties, out-of-tick source chunks, first unprefixed marker-looking names, prefixed marker names/context, exact end ticks, retained non-global data, unselected chunks, and source immutability.

## Acceptance predicate

`deno task verify --filter onboardcheck --verbose` passes. The named import cases demonstrate uncapped source enumeration, ordered distinct channels, deterministic valid projection, exact global-event classification/context/order, retained malformed/non-global data and end ticks, projected mapper validity, and unchanged source input.

## Task-specific constraints

- Do not add `earliestNoteTick`.
- Do not hard-code 16 tracks or infer capacity here; projection has no document policy.
- Do not broaden event removal beyond the global-event definition in [spec.md](spec.md).
