# Task 5 — Extract PorydawSampleUI (library model, arbiter, PCM audition player)

## Context

Fifth task of the Split Studio plan; creates the shared UI module both
studios sit on. Consumers: task 6 adds the marker-list waveform into this
module; tasks 7–9 build KitStudio's library pane, source session and
audition on `SampleLibraryModel` + `PcmAuditionPlayer`; task 10 mounts
them in the Split
Studio window. This task is behavior-preserving: Sample Studio keeps its
exact public surface, QML behavior and check outcomes; only the module
boundary and the audition playback seam change. Module rule (AGENTS.md): a
new module must measurably lower the one-file edit floor; the controller
measures and records it in `docs/BUILDING.md` (this brief does not write
that file).

## Exact write set

- Create `src/swift/sampleui/SampleLibraryModel.swift` (moved verbatim from
  `src/swift/app/samplestudio/SampleLibraryModel.swift`)
- Create `src/swift/sampleui/SampleAuditionArbiter.swift` (moved verbatim)
- Create `src/swift/sampleui/PcmAuditionPlayer.swift` (new; playback core
  extracted from `SampleStudioAudition`)
- Create `src/swift/sampleui/CMakeLists.txt`
- Edit `src/swift/app/samplestudio/SampleStudioAudition.swift` (delegate
  playback to `PcmAuditionPlayer`; keep its public surface identical)
- Edit `src/swift/app/samplestudio/SampleStudioWorkflow.swift` (import +
  construction-site updates only — the lane calls the same initializers)
- Edit `src/swift/app/NativeAudio.swift` (keep the
  `SampleAuditionOutput` conformance; import the module)
- Edit `src/swift/app/shell/PorydawQmlTypes.swift` (module alias
  `PorydawSampleUI → PorydawApp`; the moved types stay in `uncreatableTypes`)
- Delete `src/swift/app/samplestudio/SampleLibraryModel.swift` and
  `src/swift/app/samplestudio/SampleAuditionArbiter.swift` (moved, not
  copied)
- Edit `src/checks/samplecheck/AuditionStripChecks.swift` and
  `src/checks/samplecheck/LibraryModelChecks.swift` (imports only)

Controller-owned: `src/swift/app/CMakeLists.txt` (drop moved sources, link
`PorydawSampleUI`), root/module CMake wiring order, `checks:bridge` /
`qml-aot` baselines, and the `docs/BUILDING.md` edit-floor rows.

## Prerequisites

None (parallel with tasks 1–2). Tasks 6–9 consume this module's interface.

## Interface contract

`spec.md → PorydawSampleUI (tasks 5–6)`. Signatures unchanged for moved
types (`SampleLibraryModel` + rows, `SampleAuditionArbiter`). New:

```swift
@MainActor
public final class PcmAuditionPlayer {
    public init(lane: SampleAuditionArbiter?)
    public func play(owner: AnyObject, rendered: ProcessedSample,
                     looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8)
    public func restart(looped: Bool)
    public func stop(owner: AnyObject)
    public func close()
    public var playing: Bool
    public var onPlayhead: ((Int?) -> Void)?
    /// Position advance driven by the holder's tick timer.
    public func advance(bySeconds dt: Double)
}
```

Behavior split from `SampleStudioAudition` (`SampleStudioAudition.swift`
`start/advance/close`, lines 101–165): the player owns publish/re-publish
pending, gap-repeat, loop math and playhead mapping; `SampleStudioAudition`
keeps the presenter coupling (render observer, destination ADSR, audition
key, play label/text state) and delegates. The loop-position and gap
arithmetic must be the existing code moved, not rewritten — `advance`
reproduces the current `advance(bySeconds:)` semantics exactly (looped
wrap, 0.5 s one-shot gap, crop-relative playhead).

Module declaration shape: `add_library(PorydawSampleUI STATIC …)` +
`porydaw_swift_module` + `porydaw_swift_qt_interop`, linking exactly
`PorydawSample PorydawAppAudio PorydawAppPresentation QtBridge` (R2 —
`PorydawSample`: `ProcessedSample`/`SamplePeakPyramid`;
`PorydawAppAudio`: `AudioADSR`; `PorydawAppPresentation`:
`PreferencesStore` (moved model's init) and, from task 6,
`GridPalette`/`DisplayListWriter`; no `PorydawDocument`, no `PorydawCore`
— the moved files import neither: the model's Document/Core imports are
vestigial and stay behind with the presenter code; the scene's
`NativeDisplayList` import needs the render module-map include the
controller wires, mirroring `PorydawAppPresentation`'s block at
`src/swift/app/CMakeLists.txt:299-305`). Same shape as
`PorydawAppHistory`'s block (`src/swift/app/CMakeLists.txt:311-322`);
`add_dependencies(PorydawSampleUI QtBridgeMacros)`; the
PORYDAW_BUILD_CHECKS `-enable-testing` loop at
`src/swift/app/CMakeLists.txt:328-333` gains the new leaf.

## Implementation steps

1. Create `src/swift/sampleui/CMakeLists.txt` per the contract (the
   controller enrolls it in the build; you write the file).
2. Move the two files verbatim (import fixups only: `PorydawAppPresentation`
   and `QtBridge` were already the only non-Foundation imports of
   `SampleLibraryModel`; the arbiter imports `PorydawAppAudio`).
3. Extract `PcmAuditionPlayer`: move the playback state machine out of
   `SampleStudioAudition` (publish parameters, republishPending, size/
   loopStart/rate/ratio/crop/position/gap, playhead callback), leaving the
   presenter-facing wrapper delegating to it. `SampleStudioAudition`'s
   `available`, `playing`, `playText`, `auditionKey`, `hasDestinationAdsr`,
   `useDestinationAdsr`, `toggle`, `tick`, `advance`, `close` public members
   and their observable behavior are unchanged.
4. Update construction sites and imports in `SampleStudioWorkflow` and
   `NativeAudio` (the `extension NativeAudio: SampleAuditionOutput` stays in
   PorydawApp — `NativeAudio` must not move).
5. Update `PorydawQmlTypes`: alias entry + keep the existing
   `uncreatableTypes` rows (types now resolve from the new module through
   the alias). No extension conformances.
6. Fix check imports (`@testable import PorydawSampleUI` where the moved
   types are named). No row changes.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter samplecheck-editor`
  — all Sample Studio Swift suites (library model, audition strip,
    lifecycle, waveform, loop tools) pass unchanged after the move.
  Covers: behavior preservation of both moved types and the audition seam.
- `uv run --no-sync dev checks:shell --filter shell-sample-studio` and
  `uv run --no-sync dev checks:shell --filter shell-sample-studio-voice`
  — production QML lanes prove QML resolution through the module alias and
  the library pane's interaction contract.
- `uv run --no-sync dev checks:bridge`
  — moved bridged declarations still legal; zero findings expected (the
  surface did not change), so no baseline rewrite.
- `uv run --no-sync dev checks:qml-aot`
  — QML cache compilation unaffected by the alias.

Runtime prerequisites: none; no new rows are added (budget-neutral).

## Task-specific constraints

- Behavior-preserving: no renamed, widened, or removed public members; the
  two check files change imports only. Any compile-required signature
  adjustment beyond imports is a report-first event.
- `SampleStudioPresenter`, `SampleLoopTools`, `SampleWaveformModel`,
  `SampleWaveformScene` stay in `PorydawApp` (task 6 handles them).
- The moved files keep their internal structure; this is a move plus one
  extraction, not a rewrite.

## Controller verification

1. Wire CMake: move the two source lines into `src/swift/sampleui/
   CMakeLists.txt`, link `PorydawSampleUI` from `PorydawApp`, extend the
   `-enable-testing` leaf loop.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter samplecheck-editor`
3. `uv run --no-sync dev checks:shell --filter shell-sample-studio`
4. `uv run --no-sync dev checks:shell --filter shell-sample-studio-voice`
5. `uv run --no-sync dev checks:bridge`
6. `uv run --no-sync dev checks:qml-aot`
7. Edit-floor measurement per `docs/BUILDING.md`
   "Verifying a build-system change": touch
   `src/swift/sampleui/SampleLibraryModel.swift`, warm `build:app`, record
   before (PorydawApp 6.4 s documented) / after rows in
   `docs/BUILDING.md` under a `PorydawSampleUI` heading.
8. `uv run --no-sync dev format --check` on changed lines.
