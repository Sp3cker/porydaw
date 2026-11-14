# Task 4 — Share the velocity gesture's note index with its scene snapshot

## Context
`VelocityGestureState` (VelocityTransactions.swift) already builds and owns a
validated private `noteIndices: [NoteID: Int]` over its frozen notes. Every
`VelocityInteractionSnapshot` (VelocityScene.swift) construction rebuilds the
identical dictionary from the same `frozenNotes` (via a mapped intermediate
array). Pass the gesture's existing index into the snapshot instead of
rebuilding it per scene input.

## Exact write set
- `src/swift/app/drawer/velocity/VelocityTransactions.swift`
- `src/swift/app/drawer/velocity/VelocityScene.swift`
- `src/swift/app/drawer/velocity/VelocityPublication.swift`

## Prerequisites
None.

## Interface contract
- `VelocityGestureState` exposes its index internally (e.g. an internal
  `func frozenIndices() -> [NoteID: Int]` or a snapshot-producing helper —
  implementer's choice, internal access only, no new public API).
- `VelocityInteractionSnapshot` gains an initializer path that accepts a
  prebuilt `frozenIndices` matching `frozenNotes` and does NOT rebuild the
  dictionary or map an intermediate array. The existing initializer keeps
  working unchanged for non-gesture callers.
- `VelocityPublication.sceneInput` (and any other constructor fed by a live
  gesture — grep all `VelocityInteractionSnapshot(` call sites in the write
  set folders) passes the gesture's index when the frozen notes come from
  that gesture.
- `frozenNote(_:)` results identical for all inputs. No behavior change.

## Implementation steps
1. Grep `VelocityInteractionSnapshot(` across `src/swift/app/` (scoped) and
   classify: gesture-fed vs standalone. Only gesture-fed sites change.
2. Add the index-sharing path; standalone init retains current build.
3. The shared dictionary must describe the exact `frozenNotes` array passed
   (gesture `notes` are `private(set)` and only appended via `append`, which
   maintains the index — rely on that, and state it in a ≤2-line comment at
   the sharing site if not obvious from types).

## Acceptance predicate
Velocity scenes, hit-testing, previews, and commits behave identically.
Controller: `build:checks` + `checks:qml` + `checks --filter swiftcore`.
SHARED_TREE: DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- `VelocityGestureState` is `public struct … Sendable` in a module with
  cross-module callers; keep the new accessor internal to the app target
  (same module as the other two files — verify, and if the accessor would
  need to be public, report NEEDS_CONTEXT instead of widening the API).
- Do not change preview storage (`[NoteID: UInt8]`) or selection ordering.
