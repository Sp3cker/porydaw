# Task 4 — Range and time transforms

## Context

Complete the remaining document operations with one cross-stream transform
implementation. Absent ruler/drawer views do not justify dropping their existing
core semantics. See [plan.md](plan.md#global-constraints) and
[spec.md](spec.md#editing-behavior).

## Exact write set

Create `src/swift/core/TimeEditing.swift`, `src/checks/swiftcore/TimeChecks.swift`.
Modify `src/swift/core/CMakeLists.txt`, `src/checks/CMakeLists.txt`,
`src/checks/swiftcore/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp}`.
Read-only oracle: `src/core/songdocument_range.cpp`,
`src/core/songdocument_timeeditor{.hpp,.cpp,_insert.cpp,_xcmd.cpp}`,
`src/checks/editcheck/{tst_songdocument_timerange.cpp,tst_songdocument_songranges.cpp,tst_songdocument_songtime.cpp}`,
`src/checks/clipboard/`.

## Prerequisites

Task 3's ordered-event/value-stream/XCMD operations and task 2's transaction
interface accepted. Do not modify their ownership model to implement transforms.

## Interface contract

Implement `RangeEdit`, `TimeRange`, `TimeScope` and the five spec operations:
`applyRangeEdit`, `moveRange`, `removeTime`, `insertBlankTime`, `duplicateTime`.
They produce one candidate `SongState` and one history entry. They operate over
all stored streams, not merely visible notes. Internal helpers share event
insertion and XCMD reconciliation from task 3.

## Implementation steps

1. Implement grouped range insertion/removal/move, exact-byte note relocation,
   and required track expansion under the existing project/engine budget.
2. Implement scoped gap removal and whole-song closing, preserving effective
   value-stream state at seams and the existing global-marker/EOT behavior.
3. Implement blank insertion and duplication: crossing-note splits, new-half
   identity, signature/value seeding, opaque events and XCMD reconciliation.
4. Preserve ordinary boundary behavior at tick zero, empty selections and the
   maximum file tick; detect overflow before installing a candidate state.
5. Implement `timeEdits` in `TimeChecks.swift` from existing range/time/clipboard
   scenarios. Swift asserts final bytes, note identities and single-step undo;
   the C++ selector only invokes/reports the suite.

## Acceptance predicate

Existing scoped and whole-song time operations match reference results and
restore all affected streams in one undo. Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt timeEdits
deno task verify --filter editcheck --filter clipcheck --verbose
```

The Swift slot covers seam state, split notes, track expansion, globals/EOT,
unterminated notes and XCMD traffic. This proves core transforms, not the absent
time-ruler menus or automation interaction surface.

## Task-specific constraints

Do not recreate `TimeEditor` as a second command engine. Do not implement a
separate algorithm for each lane kind when ordered-stream transformation plus
existing lane/XCMD rules expresses the behavior. No new time-editing UI.
