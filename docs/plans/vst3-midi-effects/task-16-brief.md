# Context
Repair confirmed render-preparation duplication and MainActor CPU work, independently of native helper repairs. Worktree /Users/spencer/dev/cProjects/porydaw/.worktrees/vst3-midi-effects; BASE 15933295bece3e2b10fb17d6718880685db9eade. Read plan.md Global Constraints and spec.md. Native isolation, per-effect lifecycle ownership and callback-excluded acknowledged transfers are fixed constraints, not simplification targets.

# Exact write set
Production: src/swift/pluginhost/CaptureTransport.swift; src/swift/pluginhost/CaptureDriver.swift; src/swift/app/miditools/PluginEffectRenderer.swift; src/swift/app/drawer/effectoutput/EffectOutputPage.swift; src/swift/app/DocumentWorkspace.swift only removal of obsolete EffectOutput playhead forwarding.
Consumers: src/checks/pluginhost/PluginHostChecks.swift; src/checks/editorqml/tst_ShellEffectOutput.qml for its existing Render predicate/diagnostics; src/checks/editorqml/ShellQmlTests.swift only a read-only ShellQmlBootstrap native-stop observation.
Documentation: README.md existing VST Render paragraph only.
Over-cap exception: one render request crosses UI timing metadata, private worker preparation, and pure output normalization; one render behavior and its existing consumers. No other files. Do not edit BridgeChecks/ABIChecks/EditorChecks/native files/spec.md; separate native owner. Controller owns CMake/registrations if absolutely required; prefer existing files and no new abstraction/module. No proof ledgers.

# Interface and preservation contract
- UI must not construct a full CaptureTransport merely for a duration caption. Add one cheap canonical timing query owned by existing CaptureTransport (preferred public static estimatedSeconds(for: CaptureRequest) throws -> Double) that shares validation/preroll/sample-bound calculations with full preparation and never enumerates, pairs or sorts note events. No second timing formula or duration approximation. Preserve existing sampleRate/blockFrames, timing boundaries, fractional meter behavior, errors and public transport accessors. Resolve exported-symbol references before changing them; unavailable SourceKit refs are not a pass.
- Exactly one full CaptureTransport input schedule is built for each actual capture, on the dedicated CaptureWorker thread or an explicit non-main executor, never in @MainActor CaptureDriver.render. Preferred: CaptureJob carries immutable Sendable CaptureRequest; worker validates/cancels/prepares the transport before its processing loop. Do not duplicate the schedule or dispatch per block. Cheap validation may run before reservation; no eager timeline-array copies.
- Render normalization (pair/sort/lattice/normalization report -> EffectOutput) runs away from MainActor using an explicit Swift6.4 @concurrent pure operation or equivalent explicit non-main execution. Merely making Task{} or async does not change isolation. Keep UI/helper IPC and publication on MainActor. Avoid an extra generic renderer/operation framework, new queues, per-record boxing, @unchecked Sendable or detached unowned work. Immutable Sendable snapshots and existing controller generation/revision guards stay authoritative.
- Preserve live/render exclusion, acquireRender/finishRender reservations, realtime restore, cancellation, awaited worker/control teardown, FIFO input IDs, preroll/latency endpoints, non-note counts and output provenance. Preserve synchronous Grab behavior and existing pairing semantics; do not broaden into a LiveTake/Core pairing refactor. Keep distinct helper/editor/setup/live epochs and cancelled-task join registries; previous broad deletion proposals were rejected as behavior-changing.
- EffectOutputPage keeps the same QML-facing surface, same exact Offline/Realtime captions, real accepted duration including preroll as currently defined, cancellation/availability behavior, and no new QtBridge declaration/baseline rewrite. Leave existing rendered-origin completion checks intact.
- Delete EffectOutputPage's duplicate playing cache, refreshPlayhead hook and Render guard, plus its two DocumentWorkspace forwarding sites. TrackEffectsController.render already owns requested/applied playback refusal with the same user-facing error. Preserve that authority and the native insert's processing guard; do not invent another cache or weaken the stop condition. The QML test must observe actual requested-stopped, applied-stopped and live-insert-not-playing state through its existing test bootstrap, rather than treating requested transport/playhead projections as an applied-stop acknowledgement. Preserve the playing refusal and Render-completion predicate/timeouts; this is observation, not retry/delay.

# Five implementation steps
1. Record declarations/diagnostics/references and inspect entire preparation/worker/normalization contexts plus real fixture capture consumers.
2. Factor canonical cheap timing metadata in CaptureTransport and replace drawer full-construction caption path without touching event scheduling or inventing duplicate formulas.
3. Move the single full input preparation into existing worker execution, preserving error/cancel/reservation cleanup; keep the immutable request snapshot as the job contract.
4. Run pure Render normalization explicitly off MainActor, retaining the controller's existing MainActor commit guards. Add/adjust only discriminating endpoint/cancellation/normalization/caption behavior cases needed; no source-text/thread-wiring/mock-echo tests or permanent microbench scaffolds. A throwaway runtime probe can verify non-main execution without new production hooks; report exact probe needed if controller-owned.
5. Update existing README Render description, complete local before/after structural inspection and return full result with verification deferred.

# Acceptance predicate
A Render request uses cheap canonical timing for presentation, one off-main input schedule and off-main normalization, preserving existing note results/endpoints/pacing/cancellation/live restoration and UI contracts through the real fixture path; no extra lifecycle abstraction or MainActor heavy preparation remains.

# Controller verification (each invocation <=180s, serialized configs)
uv run --no-sync dev build:checks
uv run --no-sync dev checks --filter swiftcore-pluginhost --no-windowing-checks --pool=1
uv run --no-sync dev checks --filter swiftcore-projectsession --no-windowing-checks --pool=1
uv run --no-sync dev checks:shell --filter shell-effect-output --pool=1
matching ASAN build/lanes; checks:bridge; checks:qml-aot; format --check; lsp:swift after edits
Actual helper scanner/capture smoke plus non-main execution evidence; native editor/window smoke remains separately mandatory after unlock.

# Execution and reports
SHARED_TREE no child builds/tests/formatters/linters/index/reconfigure/desktop/commits. Read-only file-local inspection remains required. Return status DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT, summary, implementation, tests(command+output, DEFERRED_TO_CONTROLLER for unrun), changedFiles, selfReviewFindings(tools/symbol scope/diagnostic deltas/permitted vs actual declaration changes/unavailable checks), concerns. No report/scratch files or subdelegation. No misleading completion while a real prerequisite is missing.
