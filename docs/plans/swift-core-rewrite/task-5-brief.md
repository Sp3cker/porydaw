# Task 5 — Swift timeline and realtime sequencer

## Context

Convert both timeline projection and `TimelinePlayer`; do not reclassify the
latter as native code to avoid the requested rewrite. The poryaaaa engine and
native device remain unchanged. Task 7 repoints AudioEngine and the render CLI
at this accepted implementation. See [plan.md](plan.md#global-constraints) and
[spec.md](spec.md#playback-and-native-services).

## Exact write set

Create `src/swift/core/PlaybackTimeline.swift`,
`src/swift/playback/Sequencer.swift`, `src/swift/playback/PlaybackBridge.swift`,
`src/swift/playback/module.modulemap`, `src/swift/playback/CMakeLists.txt`,
`src/audio/swift_playback.h`, `src/checks/swiftcore/PlaybackChecks.swift`.
Modify `CMakeLists.txt`, `src/swift/core/CMakeLists.txt`,
`src/checks/CMakeLists.txt`,
`src/checks/swiftcore/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp}`.
Read-only oracle: `src/core/{miditimeline,timelineplayer,mid2agbtables}.{h,cpp}`,
`src/audio/timeline_handoff.h`, `src/checks/playback/`,
`src/checks/audio/tst_trackactivity.cpp`, `src/checks/midi/tst_midiexport.cpp`.

## Prerequisites

Task 1's storage/tempo/track/mid2agb semantics accepted. Algorithm work is
independent of tasks 2–4; shared build integration remains serialized.

## Interface contract

Implement `PlaybackTimeline.build` and `Sequencer` per spec.md. Timeline building
accepts the canonical file and optional authoritative tempo stream; it does not
require a mutable document or Qt. `PorydawPlayback` owns the only engine import.

The internal C header declares `PdPlaybackEvent`, `PdPlaybackData`, and these
entry points (pointers are borrowed for the call unless explicitly owning):

- `pd_playback_data_retain(const PdPlaybackData*)` and
  `pd_playback_data_release(const PdPlaybackData*)` on the control thread.
- `pd_playback_data_load_file(const char* path, double sampleRate,
  PdPlaybackData** out, char* error, size_t errorCapacity) -> bool` creates one
  owned publication using the Swift codec/projection, or returns false with no
  publication and a diagnostic. The renderer uses this entry, not a native codec.
- `pd_player_create() -> void*`, `pd_player_destroy(void*)` on control thread.
- `pd_player_reset(void*)`, `pd_player_position(const void*) -> uint64_t`.
- `pd_player_seek(void*, uint64_t, const PdPlaybackData*)` and
  `pd_player_replace(void*, uint64_t, const PdPlaybackData*)`.
- `pd_player_chase(M4AEngine*, const PdPlaybackData*, uint64_t)` and
  `pd_player_prime(M4AEngine*, const PdPlaybackData*, uint64_t)`.
- `pd_player_render(void*, M4AEngine*, const PdPlaybackData*, float* left,
  float* right, size_t frames, bool looping, uint32_t muteMask)`.

`PdPlaybackEvent` carries sample position UInt64, tick UInt32, type/track/data
bytes and NoteID UInt64; use natural alignment. `PdPlaybackData` carries an
immutable event view and the actual timing/loop/track fields currently consumed
by AudioEngine/exports. `PlaybackBridge` owns conversion/storage on the control
thread; a retained publication owns all of its borrowed buffers. Native
`shared_ptr<const PdPlaybackData>` adopts one reference with
`pd_playback_data_release` as its deleter; additional native shared_ptr copies do
not retain Swift separately. Transfer or retain explicitly when Swift and native
owners both hold the publication. Callback consumers borrow only. Preserve the
existing current/retired-owner handoff and control-thread release points.
No per-field getter ABI or Swift object access in render.

## Implementation steps

1. Implement exact sample projection, tempo conversion and shared track mapping;
   preserve loop discovery, end times, settings and event ordering.
2. Implement the Swift sequencer with fixed preallocated state and borrowed
   buffers. Port seek, replace, chase, prime and render behavior as a unit.
3. Implement the narrow native entrypoints without actor hops, runtime allocation,
   ARC traffic or locks on the callback path. Do not use packed event structs.
4. Add `swiftcore` slot `playback` comparing events and rendered PCM against the
   existing C++ scheduler and real poryaaaa engine on existing loop/prime cases.
5. Inspect optimized callback code and run a bounded ordinary-render allocation
   probe. Remove the probe after recording evidence; do not add telemetry to
   production. Reuse existing fixtures and render sizes rather than inventing
   a concurrency torture suite.

## Acceptance predicate

Swift timeline/sample conversion and PCM agree with existing loop/chase/prime/
mute behavior; the ordinary render path allocates no storage and does not retain
or release Swift owners. Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt playback
deno task verify --filter loopcheck --filter primecheck --filter trackactivitycheck --filter exportcheck --verbose
```

The reference checks remain C++ at this stage. `swiftcore:playback` must exercise
production Swift render against the real engine, including a loop crossing and
replacement at the current playback position. Device/AudioEngine handoff and WAV
client migration are task 7's explicit remaining integration proof.

## Task-specific constraints

Do not alter DSP, resamplers or miniaudio. If the verified Swift toolchain cannot
produce the required callback without runtime work, report that concrete blocker;
do not silently keep the old sequencer or move it to another directory. No
hypothetical timing framework or new platform/toolchain work belongs here.
