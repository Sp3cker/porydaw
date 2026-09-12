# Task 1: Parse bound

## Context

Stop silent wrap of SMF ticks that do not fit `Tick`. Task 2 narrows `SmfEvent::tick` and reuses `smf.cpp`; this task only adds the bound. `kNoTick` does not exist yet — compare against `UINT32_MAX` (same value).

## Exact write set

- `src/core/smf.cpp`
- `src/checks/midi/tst_midismf.h`
- `src/checks/midi/tst_midismf.cpp`

## Prerequisites

None.

## Interface contract

`SmfFile::read` / `parseTrack`: after adding a VLQ delta, if the absolute tick is `>= UINT32_MAX`, return false with

`Track %1: tick position exceeds 32-bit tick range`

(`%1` is the existing track index used by neighboring parse errors). `SmfEvent::tick` remains `uint64_t`. `parseTrack` / `SmfFile::read` signatures unchanged.

`MidiSmfTest` gains one private slot whose body asserts that a well-formed SMF whose accumulated tick is `>= UINT32_MAX` fails `SmfFile::read` and that the error contains `tick position exceeds 32-bit tick range`. Existing slots stay.

## Implementation steps

1. Bound the accumulator in `parseTrack` only. Place the failure with the other per-track parse errors. Do not clamp, wrap, or store a truncated tick.
2. Add the new `MidiSmfTest` slot declaration and definition. Build the overlong file in the test (QByteArray / existing format helpers); do not add a checked-in `.mid` unless the suite already requires one for this case.
3. Do not edit `miditimeline.cpp`, `midiimport.cpp`, or any tick field type.

## Acceptance predicate

Overlong absolute ticks fail parse with the contracted error; current valid SMF fixtures still load. Named checks: `deno task verify --filter smfcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: bounding after a wrapping uint32 accumulator would hide the case — keep the existing uint64 accumulator and reject on magnitude. A tick of `UINT32_MAX - 1` must still parse.
