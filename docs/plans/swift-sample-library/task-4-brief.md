# Task 4: Bounded background sample preparation

## Context

The measured 8.32-second source renders in about 108 ms Release / 1,366 ms Debug. Preview and load currently block the Qt main thread. Preserve the existing transactional source and audition semantics while preparing off the main actor. Task 5 independently removes pitch analysis from source-install observers.

## Exact write set

- `src/swift/sample/SampleDocument.swift`
- `src/swift/sample/SampleRender.swift`
- `src/swift/sample/SampleResampler.swift`
- `src/swift/sample/SampleReopen.swift`
- `src/swift/app/samplestudio/SampleStudioPresenter.swift`
- `src/swift/app/samplestudio/SampleStudioWorkflow.swift`
- `src/swift/app/samplestudio/SampleSourcePreparation.swift` (new only if needed for coherent preparation ownership)
- `src/checks/samplecheck/AuditionStripChecks.swift`
- `src/checks/samplecheck/EditorPresenterChecks.swift`
- `src/checks/samplecheck/StudioLifecycleChecks.swift`
- `src/checks/samplecheck/WaveformChecks.swift`

Task 5 owns constructor/replacement migration in `LoopToolsChecks.swift` and `SourceReplacementChecks.swift`; do not edit them.

## Prerequisites

Existing sample-library spec and plan Global Constraints. No dependency on task 5 implementation; its frozen interface supplies `SampleLoopTools.cancelAnalysis()`.

## Interface contract

- `SampleStudioPresenter.init(document: SampleDocument, validateName: @escaping (String) -> String?)` replaces the source-only initializer. Retain the passed document's prepared render cache. Derive source/name/readouts from it. No legacy initializer.
- `SampleStudioPresenter.replaceSource(_ document: SampleDocument)` replaces the ImportedSample/restoredParams signature. Parameters are already in the document. Preserve registered identity, history reset, sourceRevision-before-observers, and all source-readout behavior. No legacy overload.
- `SampleDocument.prepare(checkpoint: () throws -> Void) rethrows` fills the canonical cached render only when absent. `processed` keeps its ordinary synchronous behavior for existing parameter editing, but source preparation explicitly warms that cache on the worker.
- Preserve non-cancellable synchronous DSP entry points because ordinary editor operations and numerical consumers still use them. Add explicit `checkpoint: () throws -> Void` rethrows overloads to `SampleRender.render` and `SampleDsp.resampleSinc`; synchronous entry points delegate to the same implementation with a nonthrowing checkpoint. No default throwing checkpoint: a compiler probe verified omitted default rethrows callbacks still require try.
- `SampleLoopTools.cancelAnalysis()` is called on studio close/release. Task 5 implements it.
- QML-visible method signatures remain unchanged. No new QML properties are required. Preserve source error destinations and existing stereo/SF2 dialogs.
- `SampleReopen.resolve` remains the canonical provenance/hash/SF2/fallback policy. Its `Result` carries the exact selected source bytes so preparation and later provenance recording use one read; do not duplicate that policy in the app layer.
- Temporary internal settling hooks may observe worker completion for the controller's harness without starting work. Remove observation-only hooks with the harness once they have no other consumers.

## Implementation steps

1. Add cooperative render cancellation at phase boundaries and inside long sinc output loops, without changing numerical iteration/arithmetic or filter settings. Cancellation throws through the explicit checkpoint interface, never returns fake empty audio.
2. Create one bounded preview/load preparation owner: at most one running CPU job plus one newest pending request. A superseding request cancels the worker; do not launch another CPU job until the old one completes. Immutable source/document values cross isolation, not QObject/presenter/audio state. Stop/close/session changes invalidate pending work and late completion, including failures.
3. Read/decode/render ordinary file preview/load requests off the main actor. Preserve SF2 zone selection and phase-cancellation questions; source/provenance/history commit occurs only after successful current preparation. While preparing, retain the valid old editor; do not assign a new loaded-path label before installation succeeds. Revalidate session/editor/request identity after every await. A selection followed by Stop must never start audio later; a preview following a pending load supersedes it. Explicit source-load requests stop prior preview preparation but must not accidentally cancel themselves through the stop helper.
4. Pass the prepared document into creation/replacement. Apply restored parameters before worker rendering, not after installation. Avoid a second render during sync/readout/observer access. Preview remains default GBA rendering with loopOn=false. Keep only the current immutable preparation snapshot; reuse its cache for a subsequent load only when decoded source identity and exact parameters match. Do not introduce a path-only/unbounded cache or share a preview render across differing loop parameters. Existing reopen/import routes must also use prepared documents instead of reintroducing main-thread source rendering.
5. Migrate owned constructor callsites to document arguments. Preserve their behavior assertions. Do not add tests of forwarding/defaults/source text. Keep errors visible and no @unchecked Sendable, force unwraps, try!, new audio thread work, or actor Task masquerading as a background worker.

## Acceptance predicate

Current source requests prepare outside the main actor, rapid A/B/C/Stop/Close sequences never publish obsolete results, and valid installation retains the worker cache while preserving transaction/stereo/SF2/provenance behavior. NAMED CHECKS: controller runs `uv run --no-sync dev build:checks`, `uv run --no-sync dev checks --filter samplecheck-processing --filter samplecheck-render --filter samplecheck-editor --pool=1`, and `uv run --no-sync dev checks:bridge`. Controller's temporary production-slice harness exercises actual loading, cache retention, event-loop progress during DSP and latest-request-wins/stop/close transitions.

## Task-specific constraints

Over-cap write set is one cohesive source-preparation behavior crossing existing document/presenter/workflow ownership; four check files are mechanical constructor migration only. No new permanent integration suites. Shared-tree builds, lint, tests, format and index refresh are controller-owned. Report inspection gaps rather than rebuilding to hide them.
