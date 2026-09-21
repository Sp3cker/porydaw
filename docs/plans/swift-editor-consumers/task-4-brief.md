# Task 4 — Restore the Velocity page

## Context

Follow [Global Constraints](plan.md#global-constraints), [Page transaction contract](spec.md#page-transaction-contract), [Velocity page](spec.md#velocity-page), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

Task 3 supplies the accepted shared playhead and expanded `EditorDrawerPage.interactionActive` seam. Restore the production Velocity section as a document-bound Swift owner plus production QML. Production behavior and scenario intent come from `src/ui/editordrawer/velocityarea/`, `velocityaxis.*`, `src/checks/drawerpresentation/velocity.cpp`, the existing roll velocity-prompt/local-input behavior, and sibling `velocity-lane`, `velocity-prompt`, and `editor-drawer` references.

Known capability boundary: Swift `BankSlotView` exposes top-level parsed `BankVoice` only. Exact per-note keysplit/drumkit subvoice/ToneData resolution is unavailable without a new native service API. Do not approximate it. Implement and review every independent Velocity behavior, report this exact residual blocker, and continue the later independent tasks as the milestone contract directs.

## Exact write set

Create:

- `src/swift/app/VelocityPage.swift`: one deep page owner containing projection, frozen gesture transaction, selection/readout, prompt transaction, diagnostics, page seam, and QML bridge.
- `src/ui/songview/quick/drawer/VelocityPage.qml`: production axis/handles/readout/input composition.
- `src/ui/songview/quick/drawer/VelocityPrompt.qml`: Swift-owned drawer-local modal value prompt; no legacy `QuickPopupSession` dependency.
- `src/checks/swiftcore/VelocityPageChecks.swift`: direct value-map, projection, transaction, prompt, history, cancellation, context, and diagnostics checks.

Modify:

- `src/swift/app/ApplicationSession.swift`: create/retain/attach the document-bound page after audio/document/grid/playhead setup; refresh it from camera/playback/document changes; route audition and prompt command callbacks; cancel while the Quick scene exists, request detach, and release the page only after the host acknowledges scene removal.
- `src/swift/app/SharedPlayhead.swift`: if needed, add one Swift-only presentation callback so `ApplicationSession` can fan shared clock updates into document-bound pages without QML calling back through transient bridge wrappers; preserve the existing QML-facing presenter contract.
- `src/swift/app/NoteCommands.swift`: make `EditCommand.setVelocity` availability/dispatch explicit without committing a value before prompt acceptance.
- `src/ui/songview/quick/swiftroll/PianoGrid.swift`: route the existing Set Velocity command to the page prompt through one Swift callback and preserve command availability publication.
- `src/swift/app/CMakeLists.txt`: compile `VelocityPage.swift`.
- `CMakeLists.txt`: add both production Velocity QML files to the existing `drawer_qml` resource.
- `src/checks/swiftcore/SessionChecks.swift` and `src/checks/CMakeLists.txt`: dispatch/compile direct checks.
- `src/checks/editorqml/EditorQmlTests.swift` and `src/checks/editorqml/tst_EditorDrawer.qml`: add production page mounting, real input, prompt, rendering, cancellation, and playhead-performance cases in the existing lane.

The implementer may modify `src/ui/songview/quick/drawer/EditorDrawer.qml` only if production page focus/modal containment requires a container-provided fact that cannot be expressed through the existing Loader/section rectangle. Any such change must preserve the generic container contract and be named in the result.

Read-only: legacy C++/QML prompt and velocity sources, existing `VelocityMap`, sibling references, native project/audio services. No native/C++/QtBridge expansion.

## Prerequisites

- Task 3 is accepted/checkpointed and exposes the shared camera/playhead plus `EditorDrawerPage.interactionActive`.
- `SongDocument` exposes stable note identity, note lookup, `setVelocities`, `nudgeVelocities`, selection reconciliation, and ordinary history.
- `DocumentSession` owns selected notes/track, edit cursor, bank slots, timeline, camera, and history.
- Existing `VelocityMap` is the exact continuous/PSG level conversion authority.
- `EditCommand.setVelocity` already has the canonical command identity.

If top-level voice mapping proves unavailable, stop. If only keysplit/drumkit subvoice resolution is missing as grounded, keep the top-level implementation exact, identify the blocked cases, and do not invent a fallback.

## Interface contract

### Page owner

`@MainActor @QtBridgeable public final class VelocityPage` implements `EditorDrawerPage` with `.velocity`, a fixed production QML URL, production preferred/max body policy, and `interactionActive` true for any pointer gesture, frozen preview, open prompt, or audition.

It retains `DocumentSession` weakly or under the bounded document-owner lifetime but never retains `ApplicationSession`/drawer. It publishes only QML primitives and stable row/handle models needed to render:

- shared plot facts derived from camera;
- selected-track note handles with stable NoteID, tick/x, displayed value/y, selected/hover/preview state, and label/readout;
- resolved axis kind/range/ticks/labels from `VelocityMap` and current voice context;
- prompt open/draft/error/bounds state; and
- `contentBuildCount` plus playhead-presentation diagnostics.

Horizontal projection is always the shared camera. The shared playhead remains the composition-owned segment; the page may consume its tick/playing state for voice context but creates no line/clock.

### Voice/value context

While playing, resolve the value map at the rounded shared playhead context tick; while stopped, use `DocumentSession.editCursor`. For top-level direct/square1/square2/wave/noise voices, use the existing `VelocityMap` exactly. If the active voice requires keysplit/drumkit per-note subvoice data not exposed by Swift, publish an explicit unsupported-context diagnostic and disable only the edits whose exact map is unknowable; never silently use continuous/direct mapping.

### Pointer transaction

A gesture captures document revision, track identity, stable selected NoteIDs, their original velocities, axis map, pointer origin, and detent/modifier policy. Selection changes caused by press occur before capture exactly as production. Motion updates preview only. Relative multi-note movement applies one clamped delta preserving relative offsets; absolute paint uses the captured map. Release calls the existing semantic document operation once, producing at most one history entry. No-op release produces none.

Cancellation from Escape, pointer ungrab, hide, track/document change, prompt replacement, window deactivation, or scene retirement clears preview/audition/follow suspension and commits nothing. A stale revision or missing captured note cancels instead of retargeting current selection.

### Prompt transaction

Set Velocity opens a Swift-owned transaction capturing document revision, selected track, stable selected NoteIDs, and before-values. Draft input is decimal `1...127`; editing the draft never mutates the document. Enter/accepted action commits one `setVelocities` transaction to the captured IDs. Escape, outside dismissal, hide, replacement, stale revision, empty capture, or invalid input commits nothing. The prompt never follows a later selection/track/document.

The QML prompt is local modal text input. It may claim Space while the text field is active; outside it, window transport priority remains. Focus returns deterministically to the originating page/roll after close. Do not import or wrap legacy `VelocityPrompt.qml`, `PromptCard.qml`, `DragInput.qml`, `Porydaw.Ui`, or `QuickPopupSession`.

### Refresh/history/performance

Document/Undo/Redo/selection/track/camera/font/DPR/voice-context changes refresh the appropriate projection. Shared-playhead-only movement updates context/readout only if the effective voice-map context changes; otherwise it increments presentation diagnostics without rebuilding static velocity content. Repeated equal publications are no-ops.

## Implementation steps

1. Add direct Swift policy cases for exact `VelocityMap` behavior, handle projection, frozen relative/absolute transactions, prompt capture/staleness, cancellation, Undo/Redo, and no-rebuild diagnostics.
2. Implement `VelocityPage` and production attachment/lifecycle without QML.
3. Route the existing Set Velocity command to the page prompt; do not add a new command or dispatcher.
4. Implement production `VelocityPage.qml` and `VelocityPrompt.qml` with real pointer/keyboard/accessibility input.
5. Extend the existing editor-QML lane with production mounted interaction/rendering and all four velocity/editor-drawer reference profiles available in the sibling inventory.
6. Run the exact commands below; skip project-wide formatting/lint and unrelated suites in the writer task.

## Acceptance predicate

Required independent behavior:

- production app attaches one real Velocity page for the current document and removes it only after acknowledged scene detach;
- exact top-level voice maps, axis labels, handles, selection, readout, shared camera/playhead alignment, real pointer edits, prompt edits, cancellation, Undo/Redo, and command availability match production;
- every completed gesture/prompt makes at most one history entry and every cancellation/stale/no-op path makes none;
- prompt captures stable targets and cannot retarget after selection/track/document change;
- 128 shared-playhead updates do not rebuild static Velocity content;
- production QML is exercised with real input and rendered reference evidence at macOS DPR 1/2, font 12/16 for `velocity-lane`/`editor-drawer`, and DPR 2 font 12/16 for `velocity-prompt`;
- no legacy C++ popup/session path or test scenario body remains behind the Swift page; and
- exact verification passes:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify:qml --filter editorqml-drawer --verbose
deno task verify --filter swiftrollgated --verbose
```

Full task completion additionally requires exact keysplit/drumkit subvoice mapping. With the current interface this is an explicit `BLOCKED` acceptance item: report which legacy/reference cases require it and the smallest native-service read-only data contract that would resolve it. Do not implement that contract without approval.

## Task-specific constraints

- No approximation for keysplit/drumkit/ToneData velocity context.
- No C++/QtBridge/native-service expansion.
- No legacy popup bridge or copied popup controller.
- No page-owned playhead/camera/history/selection authority.
- No new public shortcut or native action.
- Do not touch unrelated dirty planning documents or `.scratch/`.
- Return exact changed files, verification output, translated legacy scenario IDs, rendered-profile evidence, and the capability blocker.