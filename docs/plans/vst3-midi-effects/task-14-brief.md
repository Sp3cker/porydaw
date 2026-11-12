# Context
Align the accepted VST engine/host seams and the unaccepted editor/controller drafts with fork-main `ff15770a` before continuing feature work. Upstream `AudioControl` owns the device, renderer and bank on its serial executor; MainActor owns intent, presentation and asynchronous helper IPC. Consumers: tasks 8–12. Read plan.md Global Constraints and spec.md audio ownership/lifecycle contracts.

# Exact write set
- `src/swift/app/NativeAudio.swift`
- `src/swift/app/audio/AudioControl.swift`
- `src/swift/app/audio/AudioRenderEngine.swift`
- `src/swift/pluginhost/PluginInstance.swift`
- `src/swift/pluginhost/{BridgeChannel.swift,CaptureDriver.swift,HelperProcess.swift}` and `src/checks/pluginhost/BridgeChecks.swift`: observed Render-timeout ownership/classification race only.
- `src/checks/pluginhost/PluginHostChecks.swift`
- `src/checks/pluginhost/PluginHostEditorChecks.swift`
- Task 9's existing controller, renderer, store, workspace/session/catalog composition and check files, including `src/checks/workspace/SessionChecks.swift` and `src/checks/support/WorkspacePresenterFixture.swift`.
- Import-conflict resolution only: `src/swift/playback/audition/AudioSampleAudition.swift`, `src/swift/playback/audition/SampleAuditionPcm.swift`, `src/checks/samplecheck/PcmAuditionPlayerChecks.swift`, `docs/BUILDING.md`.
- Shared registration: `src/swift/app/CMakeLists.txt`, `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`, `src/checks/support/corecheck/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp,CoreCheckDispatch.swift}`.
- `plan.md`, `spec.md` and affected task briefs in this plan directory.

# Prerequisites
Tasks 4 and 7, and the upstream `ff15770a` audio ownership contract. Existing task 8 editor and task 9 controller behavior remains required.

# Interface contract
- `NativeAudio.attachLiveInsert(track: Int, insert: LiveInsert) -> AudioOperation<Void>` and `detachLiveInsert(track: Int, insert: LiveInsert) -> AudioOperation<Void>` synchronously enqueue cold commands. Receipts resolve only after rendering exclusion and renderer mutation complete.
- Commands carry the existing Sendable owner, not unchecked raw slot pointers. Control retains installed owners; detach compares exact installed identity so stale cleanup cannot remove a replacement on the same track.
- Host owns bridge producer transitions. `armLive(input:sampleRate:periodFrames:attach:detach:)` preserves its `EffectInput`, `Double` and `UInt32` setup parameters; its two callbacks are escaping `@MainActor (LiveInsert) async -> Void`. Detach acknowledgement precedes `LiveInsert.detach()`, Render reservation, slot/channel reclamation and helper shutdown.
- State restore stays attached when no producer transfer is required: await a pending handoff, use the existing helper-side state serialization, then flag input discontinuity. Do not introduce a detach/rearm cycle solely for restoring plugin state.
- Failure cleanup is owned and asynchronous; shutdown awaits it. Workspace suspension enqueues detach before stop/unload/new bind and retains receipts through cleanup. Attach rejects retired generations; detach always addresses its supplied immutable old owner.
- Render exchange timeout is typed data, not permission for a worker to kill the helper. The MainActor helper owner commits stopped-responding before termination and before asynchronous Render cleanup; subsequent EOF must not replace that cause. Genuine abrupt crashes still report stopped-working.
- Telemetry is generation-matched cached data; requested transport is intent. Checks wait for applied callback/telemetry evidence, never assume submission is completion.
- Preserve upstream sample leases, value-note identities and control-owned retired-storage reclamation; remove superseded branch executor/token code rather than compatibility shims.

# Implementation steps
1. Import upstream without rewriting pushed history and preserve unaccepted work while resolving ownership conflicts. Preserve both the upstream control model and VST slot/take behavior.
2. Extend the existing cold command/completion route. Retain installed owners until the renderer borrow is cleared or device shutdown joins callbacks; keep hot producer handover and startup behavior unchanged.
3. Migrate Host and every caller to acknowledged attachment. Cover restore, Render, reload, failure, disarm and shutdown without MainActor waits.
4. Migrate workspace/controller cleanup and checks to receipts and cached telemetry. Preserve all prior assertions, including the unresolved range fallback/deadline observations; do not repin or suppress them.
5. Retain real-editor checks in explicit macOS windowing lanes. Headless project-session checks must never construct native editor views under an offscreen backend.

# Acceptance predicate
The complete prior VST behavior survives, MainActor stays responsive while cold audio work completes, exact-owner detach cannot remove a successor, and Render/reclamation cannot overtake callback detachment. Native editor execution requires desktop approval and remains mandatory at final acceptance, not an implementation-checkpoint prerequisite under the user-approved plan gate timing. NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-playback`
- `uv run --no-sync dev checks --filter swiftcore-pluginhost --no-windowing-checks`
- `uv run --no-sync dev checks --filter swiftcore-pluginbridge`
- `uv run --no-sync dev checks --filter swiftcore-projectsession`
- `uv run --no-sync dev checks --filter samplecheck-editor`
- `uv run --no-sync dev checks:bridge`
- `uv run --no-sync dev checks --asan --filter swiftcore-pluginhost --no-windowing-checks`
- `uv run --no-sync dev checks --asan --filter swiftcore-pluginbridge`
- Audio-controller and audition coverage is included by `swiftcore-playback`'s prefix; the sample-editor lane executes the lease-backed PCM player checks. Actual async attachment/Render/cleanup consumer smoke supplements these checks.

# Task-specific constraints
No VST changes to upstream `AudioDevice`; reuse `withRenderingExcluded` on control. Never restore stop/restart-based cold edits, direct MainActor renderer access, old audition retirement infrastructure, a second bridge producer, or a new pointer Sendable wrapper. Every build/check invocation has a timeout no greater than 180 seconds. The merge checkpoint follows review and covering Debug/ASAN headless verification of the combined alignment and task 8/9 milestone, not conflict-marker removal; native execution remains explicitly pending for final acceptance.
