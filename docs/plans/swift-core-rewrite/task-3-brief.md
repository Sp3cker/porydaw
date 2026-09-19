# Task 3 — Tracks, raw events and value streams

## Context

Complete the event-oriented document API and import semantics used by time
transforms and future editors. This does not construct those editors.
See [plan.md](plan.md#global-constraints) and [spec.md](spec.md#editing-behavior).

## Exact write set

Create `src/swift/core/EventEditing.swift`, `src/swift/core/Xcmd.swift`,
`src/swift/core/MidiImport.swift`, `src/checks/swiftcore/EventChecks.swift`.
Modify `src/swift/core/CMakeLists.txt`, `src/checks/CMakeLists.txt`,
`src/checks/swiftcore/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp}`.
Read-only oracle: `src/core/{songdocument.cpp,songdocument_tempo.cpp,songdocument_xcmd.cpp,xcmd.h,xcmd.cpp,lanemoveplan.h,lanemoveplan.cpp,midiimport.h,midiimport.cpp}`;
`src/checks/editcheck/`, `src/checks/playback/{tst_xcmd.h,projection.cpp,rewrites.cpp}`,
`src/checks/automation/domain/`, `src/checks/midi/tst_midismf.cpp`.

## Prerequisites

Task 2's state, transaction and history interfaces accepted; task 1's codec and
musical classification are the only storage/semantic foundations.

## Interface contract

Implement spec.md's track, raw-event, tempo, signature/loop, lane and import API
families. `Xcmd.project`, `assess`, `rewrite`, `reconcile`, and
`canonicalizeForExport` operate on ordered event values. They are reusable by
task 4, not a lane-specific secondary document. Keep the pure lane-move planner
internal to `EventEditing.swift`.

`MidiImport` implements full analysis, division rescaling and eligible setter
reduction, including XCMD verdicts. Export canonicalization remains detached
from live state. `editRawAndTempo` handles raw deletion/tempo replacement and
tempo-to-raw replacement in one history transaction.

## Implementation steps

1. Implement track creation/duplication/deletion/reorder/name and EOT operations,
   preserving chunk-zero globals, loop-marker rescue and unused-channel seeding.
2. Implement raw events, intra-tick ordering/bounds, tempo, signatures and loops
   through the existing transaction helper. No independent tempo undo stack.
3. Implement XCMD epoch projection/rewrite/reconciliation, known-lane operations,
   and opaque preservation. Share collision/value rules across ordinary lanes.
4. Implement complete import analysis/rescaling/redundant-setter behavior. Import
   reports remain plain values/strings; do not add UI or diagnostic features.
5. Implement `eventEdits`, `xcmdEdits` and `midiImport` in `EventChecks.swift`.
   Swift owns musical-output, raw-order, undo and preserved-byte assertions;
   C++ changes are limited to suite invocation and temporary oracle access.

## Acceptance predicate

Track/event/value edits and import transforms match existing outcomes, save to
valid equivalent MIDI, preserve opaque traffic, and undo as single operations.
Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt eventEdits xcmdEdits midiImport
deno task verify --filter editcheck --filter xcmdcheck --filter smfcheck --filter automation-domain --verbose
```

Coverage comes from editcheck raw/tracks/logic cases, XCMD epoch/rewrite cases,
automation-domain collisions/span replacement, and smfcheck import verdicts.
The original event-list GUI is not required to test these domain operations.
Use its raw/tempo behavioral cases as reference, not a reason to port the view.

## Task-specific constraints

Do not mint permanent lane/row identities solely to replace valid short-lived raw
event positions. Do not normalize unknown traffic or move save normalization into
live editing. A failed user operation leaves the prior state intact through the
transaction mechanism, not per-field rollback code.
