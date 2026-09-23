# Task 2 — Timerange: A154 RETIRED-REPRESENTATION, certificate, deletion (proof-only)

## Context

`proof.tst_songdocument_timerange.txt` holds 193 sites: 192 MATCHED (nine
synthetic time-range families ported into `TimeChecks.swift ::
removalAndSeams / insertionAndBoundaries / duplicationAndGlobals`, suite 9)
and one NATIVE — `A154 | timeRangeAutomationSeamsAndDefaults |
tst_songdocument_timerange.cpp:468`: `QVERIFY(timeline)` on
`buildTimeline(44100.0)`, a C++ heap-pointer null check. Swift
`PlaybackTimeline.build(state:sampleRate:)` returns a non-optional value:
there is **no failure path to assert**, and a `sampleRate == 44_100`
predicate would merely echo the call argument (spec §2.1 hard rules). The
usable-timeline observable is already asserted by S145 (`tempoMap`
non-empty) and S146 (front 120 BPM). This task is proof-only: terminalize
A154 as RETIRED-REPRESENTATION, convert the proof to a deletion
certificate, delete the uncompiled original. **No Swift changes.**

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_timerange.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_timerange.cpp`

## Prerequisites

None.

## Interface contract

- A154 Disposition NATIVE→RETIRED-REPRESENTATION via
  `deno task proof:edit`. Mapping line states: the C++ site checked a
  nullable heap return; Swift `PlaybackTimeline.build` is non-optional so
  construction has no failure branch; the consumer-visible "usable
  timeline" outcome is asserted by S145/S146 (tempo map contents); the
  original C++ file is uncompiled in every target (spec §7).
- Certificate preamble per spec §3 with the proof's EXISTING
  `Reference revision` retained and `Original SHA-256` verified against
  the on-disk file (spec §2.2) before deletion.
- All 192 MATCHED entries and the `S###` trailer unchanged.

## Implementation steps

1. Reclassify A154 per Interface contract.
2. Rewrite the preamble to the certificate format:
   `Covered native implementation: src/core/songdocument_timeeditor*.cpp,
   src/core/songdocument.cpp :: SongDocument::removeTimeRange,
   insertBlankTime, duplicateTimeRange, tempo/signature paths,
   buildTimeline`; `Native engine status` per spec §3 item 7 (engine files
   remain on disk — Task 15 owns the §8 gate); `Fixture and execution`
   condenses the existing nine-case description; `History caveat` cites
   `coreEditHistoryCountAtTip`; `Registered run path: … TimeChecks.swift
   :: runTimeEditsSuite (removalAndSeams, insertionAndBoundaries,
   duplicationAndGlobals), swiftcore suite 9 via CoreCheckSupport.swift ::
   pdc_suite_run; counterpart compiled in src/checks/CMakeLists.txt ::
   swift_core_check`. Refresh `Swift counterpart` SHAs
   (`shasum -a 256 TimeChecks.swift tst_songdocument_runner.swift`).
3. Verify revision pinning (spec §2.2): existing `Reference revision` +
   `Original SHA-256` match `git show <rev>:src/checks/editcheck/
   tst_songdocument_timerange.cpp | shasum -a 256`. On mismatch, resolve
   per §2.2 or STOP and report.
4. Delete `tst_songdocument_timerange.cpp`. Header slot cleanup belongs
   to Task 15 (wholesale); do not edit `tst_songdocument.h`.

## Acceptance predicate

- `deno task proof show tst_songdocument_timerange` parses; 192 MATCHED +
  1 RETIRED-REPRESENTATION; `deno task proof list --area editcheck` shows
  timerange NATIVE 0, PARTIAL 0, GAP 0.
- Controller: `deno task verify --filter swiftcore --verbose` PASS
  recorded in the certificate Result line (no Swift change occurred;
  suite 9 must remain green and unchanged in assertion count).

## Task-specific constraints

- Zero Swift edits in this task; if any predicate seems missing, that is
  a different task's concern — A154 closes by classification only.
- Do not alter any of the 192 existing MATCHED mappings.
