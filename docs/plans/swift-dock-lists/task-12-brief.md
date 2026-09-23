# Context

Port the sample project/editor lifecycle predicates to the Swift service and QML editor. This is the lifecycle half of sample support and consumes task 11's `SampleProcessingBackend`; task 10 supplies the end-user New/Edit workflow. The source oracles are `src/checks/samplecheck/{editor,integration,project}.cpp` and their three `proof.*.txt` ledgers: 264 assertion sites in 32 named source methods.

# Exact write set

- `src/checks/workspace/sample_lifecycle.swift` — new SwiftCore project/document lifecycle and headless audio-engine predicates.
- `src/checks/workspace/SessionChecks.swift` and `src/checks/CMakeLists.txt` — register the SwiftCore predicates and SwiftRollGated source/slot.
- `src/checks/swiftrollgated/samplechecks.cpp` and `src/checks/swiftrollgated/tst_swiftrollgated.h` — add real QML editor interactions for source methods that observe dialog interaction, layout, keyboard, or audio behavior.

Read-only inputs: `src/checks/samplecheck/{editor.cpp,integration.cpp,project.cpp}`, the three samplecheck proof ledgers and fixture files, task 10's `ProjectService.swift`/`ProjectServiceCallbacks.swift` and worker sample operations, task 11's `SampleProcessingBackend`, and task 10's `SampleEditorController.swift`/`SampleEditorDialog.qml`. This task edits no production service/editor code.

# Prerequisites

Tasks 10 and 11. Task 10 creates the production `SampleEditorDialog.qml`, sample actions, and baseline workflows. Task 11's typed `SampleProcessingBackend` owns decoding, SF2 extraction, document rendering, and export. Run this after both at the shared `ProjectService.swift`, C ABI service, SwiftCore dispatcher, and `samplechecks.cpp` boundaries.

# Interface contract

- Project mutation stays on task 10's `pd_service_probe_samples`, `pd_service_read_sample`, and `pd_service_commit_sample` C ABI operations on the existing compiled `PdProjectService` serial worker. Those bridges call the compiled `SampleRegistrar` and sidecar helpers; do not use uncompiled `ProjectWorkspace`/`ProjectIo` command types or write project files from Swift/QML.
- `probeSamples()` returns pipeline and refusal data. `readSample(name:)` returns the probe, canonical committed `.wav` bytes/path, and validated sidecar-loaded state. `commitSample` returns committed status plus `sidecarSaved`/`sidecarError`; a failed auxiliary sidecar save does not turn a committed `.wav` into a failed operation.
- New sample registration validates `[a-z0-9_]+` and collisions against project symbols/files, writes the rendered WAV then exactly one registration block using compiled `SampleRegistrar`'s CRLF/style-preserving `QSaveFile` behavior, and handles the sidecar. Edit only updates an existing registered `.wav`; it does not rewrite the `.inc` entry. Refresh the task 5 sample/catalog projection after commit and surface native refusal text.
- `SampleSidecar` retains version 1, absolute source path, SHA-256 of exact source bytes, `leftOnly`, `sf2Zone`, and complete `SampleEditParams`. Edit re-imports the original source only when its hash still matches. Missing/changed/unreadable sources fall back to the committed `.wav`; a fallback commit removes stale sidecar data. Do not restore stale parameters from a mismatched sidecar.
- The editor's `SampleDocument` remains non-destructive and dialog-local until commit. Param changes use `SampleProcessingBackend`; a drag creates one undo entry; local cancel leaves the project unchanged. Audition closes/stops on every dismissal. QML interactions remain in the real `SampleEditorDialog.qml`, not the retired `SampleEditorDialog` QWidget.
- A successful sample commit and a slot assignment are distinct outcomes. After New succeeds, refresh the catalog. If an initiating slot exists, preserve its full voice when its macro is `DirectSound`, `DirectSoundNoResample`, or `DirectSoundAlt` except for changing the sample symbol; otherwise create the native default DirectSound voice (key 60, pan 0), deriving ADSR from `catalog.typicalAdsr` as `VoiceListAdsrDefaults` through `VoiceListSemantics.defaultAdsr(_:macro:symbol:)` with `macro: BankVoiceMacro.directSound` and `symbol: "DirectSoundWaveData_" + name`. Call `VoiceListController.applyVoiceEdit`/`DocumentSession.applyBankEdit` once. With no initiating slot, do not assign. If bank assignment fails, keep the committed sample and surface that failure. Edit updates the existing sample file/sidecar only and never mutates its bank slot.
- If `pd_service_commit_sample` reports a failure after a file write, report it accurately and do not assign the slot. Do not promise multi-file rollback that the compiled `SampleRegistrar::registerSample`/`updateSample` path does not implement.
- Identity is one-to-one with each original `SampleProcessingTest::<method>`: each SwiftCore predicate reports `cppID` `samplecheck/SampleProcessingTest::<method>`, while each SwiftRollGated check uses that exact method name as its QML slot and records the same source-method identity in its check evidence. Headless engine/model/service checks run in SwiftCore; live dialog interactions run against production QML in SwiftRollGated.

# Implementation steps

1. Exercise task 10's worker/Swift service value mapping at the Swift consumer boundary. Assert returned sample values after async completion and exact operation errors by sample name.
2. Exercise the complete editor lifecycle through task 10's production QML/controller: New/Edit, hash-verified re-import, canonical-WAV fallback, local cancel/undo/redo, registration/update, sidecar warning/removal, catalog refresh, and optional slot assignment.
3. Add SwiftCore predicates for the headless engine, model, service, file, and sidecar boundaries; add SwiftRollGated predicates for the production QML editor's gesture, scrolling, splitter, keyboard, audition, and commit observations. `engineLoop` is a headless engine check from `src/checks/samplecheck/integration.cpp:43-120` and belongs in SwiftCore, not QML. The original `pipelinePrefillCollision` and `pipelineRateCommit` assertions in `src/checks/samplecheck/editor.cpp:98-112,191-216` inspect `SampleEditorDialog` widgets and input behavior, so implement them only as SwiftRollGated production-QML slots, not as SwiftCore facade checks.
4. Preserve every behavior and branch represented by the following source methods:

   | Proof source | Runnable predicate names |
   |---|---|
   | `proof.editor.txt` | `editorAuditionStrip`, `editorCommit`, `editorCrossfade`, `editorDrag`, `editorLoopPopulate`, `editorLoopRefine`, `editorPitchAdoption`, `editorScroll`, `editorSplitter`, `editorUndo`, `pipelineCropNormalize`, `pipelineKeyOverride`, `pipelineLoopToggle`, `pipelinePrefillCollision`, `pipelinePreparedDefaults`, `pipelineRateCommit`, `spaceAudition` |
   | `proof.integration.txt` | `engineLoop`, `sampleUpdate`, `sampleUpdateRefusals`, `sidecarEditDialog`, `sidecarFallback`, `sidecarRemove`, `sidecarRerender`, `sidecarRoundtrip`, `sidecarTouchedSource` |
   | `proof.project.txt` | `projectCrlf`, `projectDuplicate`, `projectInspect`, `projectProbe`, `projectRegister`, `projectSanitizeValidate` |

5. Check service/history invariants at the actual Swift consumer boundary: all failed reads/commits preserve prior visible state; clean cancellation causes no file or bank mutation; successful update leaves registration bytes unchanged; sidecar mismatch chooses canonical WAV; successful sidecar failure remains a warning; catalog refresh publishes the new sample before assignment.

# Acceptance predicate

- `deno task build:app` and `deno task build:checks` succeed.
- `deno task verify --filter swiftcore --verbose` runs exactly these 18 headless engine/model/service/file predicates against isolated fixtures: `pipelineCropNormalize`, `pipelineKeyOverride`, `pipelineLoopToggle`, `pipelinePreparedDefaults`, `engineLoop`, `sampleUpdate`, `sampleUpdateRefusals`, `sidecarFallback`, `sidecarRemove`, `sidecarRerender`, `sidecarRoundtrip`, `sidecarTouchedSource`, `projectCrlf`, `projectDuplicate`, `projectInspect`, `projectProbe`, `projectRegister`, and `projectSanitizeValidate`. Each emits its exact `samplecheck/SampleProcessingTest::<method>` identity and proves headless engine behavior, returned consumer values, registration/update bytes, CRLF preservation, duplicate/invalid refusals, probe/inspect outcomes, and no-write/no-receipt cancellation/failure semantics.
- `deno task verify --filter swiftrollgated --verbose` runs exactly these 14 production QML/audio slots named after their source methods: `editorAuditionStrip`, `editorCommit`, `editorCrossfade`, `editorDrag`, `editorLoopPopulate`, `editorLoopRefine`, `editorPitchAdoption`, `editorScroll`, `editorSplitter`, `editorUndo`, `pipelinePrefillCollision`, `pipelineRateCommit`, `spaceAudition`, and `sidecarEditDialog`. Each slot records its exact `samplecheck/SampleProcessingTest::<method>` source identity and exercises the live QML editor/production audio path for audition, commit/cancel, gesture grouping, loop auto-population/refine/crossfade, resize/squeeze/scroll, and edit-sidecar presentation. `pipelinePrefillCollision` asserts imported-name prefill, collision/invalid-name status and disabled `sampleAddButton`, and valid-name re-enable; `pipelineRateCommit` asserts typing does not render per keystroke, Return commits `sampleRateCombo`'s target rate, and the source-rate preset restores the imported rate. `spaceAudition` must focus a child editor control, toggle production audition once without editing that control or triggering application transport, ignore auto-repeat, and consume the matching release as in `src/ui/sampleeditordialog.cpp:571-597`.
- Across both lanes, each of the 32 names in the implementation table is assigned exactly once; no original source method is left unmapped or represented only by a hidden QtWidgets dialog.
- Every task-12 predicate passes before tasks 13–16 proof/parity work; no C++ proof runner is a replacement for these Swift/QML checks.

# Task-specific constraints

- Reuse task 11's processing backend. Do not add decoder/DSP algorithms to this task or weaken its existing exact pins/tolerances.
- Do not alter native project-write order, sidecar auxiliary semantics, or sample-vs-bank command ownership. Do not add unrelated sample formats or a new-song wizard.
- Keep task 12 separate from proof-ledger edits; task 14 owns the seven samplecheck ledgers and sample-specific dialog visual mapping.
