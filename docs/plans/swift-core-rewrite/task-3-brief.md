# Task 3 — Tracks, raw events and value streams

## Context

Complete the event-oriented document API and import semantics used by time
transforms and future editors. This does not construct those editors.
See [plan.md](plan.md#global-constraints) and [spec.md](spec.md#editing-behavior).

## Exact write set

Create `src/swift/core/EventEditing.swift`, `src/swift/core/Xcmd.swift`,
`src/swift/core/MidiImport.swift`, `src/checks/swiftcore/EventChecks.swift`.
Modify `src/swift/core/{CMakeLists.txt,MidiFile.swift,SongDocument.swift}`,
`src/checks/CMakeLists.txt`,
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

`MidiFile.swift` owns an internal `TrackNameScan` value with
`mutating func consume(_ event: borrowing MidiEvent) -> Bool`. A fresh scanner
starts outside a channel-prefix span. A `0x20` meta event activates that span
when its payload is nonempty and clears it when empty; a channel event clears
it. Only `0x03` meta events outside the span return true. Other events preserve
the prefix state. This is the sole name-role rule, not a generic metadata engine.
`SongDocument.trackName`, `classifyEvents(in:)`, and `MidiImport.analyze` consume
it instead of maintaining separate prefix/name-selection logic. Preserve their
existing display length, import whitespace/empty-name handling, event order,
first-name versus subsequent-marker treatment, and rename marker rejection.
Correct the document query's prefixed-name selection; do not change opaque
payloads or unrelated conductor/loop classification.

## Implementation steps

1. Implement track creation/duplication/deletion/reorder/name and EOT operations,
   preserving chunk-zero globals, loop-marker rescue and unused-channel seeding.
   Centralize the name-role rule above and migrate all three consumers. Retain
   raw chunk/event addressing and the existing commit/history mechanism.
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
`eventEdits` and `midiImport` additionally exercise a prefixed name before a
global name, prefix reset by a channel event and by empty prefix payload,
multiple global names, and marker-looking names. Assert document/import name
selection under their existing formatting rules, rename targeting the global
name, preserved prefixed/opaque events, undo restoration, and save/decode
preservation. No duplicated scanner in the tests; use explicit expected values.
The first command below executes these new Swift regressions; the second
guards unrelated legacy metadata/marker behavior, not the corrected query.
Record the prefixed-name query correction explicitly in the task evidence;
do not label a differing legacy query result as unchanged parity.
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
