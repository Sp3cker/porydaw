# Task 5 — Restore the Voice Changes page

## Context

Follow [Global Constraints](plan.md#global-constraints), [Page transaction contract](spec.md#page-transaction-contract), [Voice Changes page](spec.md#voice-changes-page), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

Restore the document-bound Voice Changes section after the shared playhead and independent Velocity work. Behavioral authority is `src/ui/editordrawer/voicechangearea/`, the voice picker/menu production code, `src/checks/drawerpresentation/voice.cpp`, relevant automation voice-context scenarios, and sibling `voice-picker`/`editor-drawer` references.

Known capability blocker: native C++ exposes `AudioEngine::previewVoice`, but Swift `NativeAudio` and `swift_audio_service` expose only `previewNote(track:key:velocity:)`. Arbitrary picker-slot audition is not equivalent to previewing the selected track's active voice. Do not misuse `previewNote`, fake audition, or add the required native C API without approval. Implement/review every independent Voice Changes behavior and leave audition as an explicit blocked acceptance item.

## Exact write set

Create:

- `src/swift/app/VoiceChangesPage.swift`: page owner, voice-lane projection, stable occurrence identity, frozen transactions, picker/menu state, active-context projection, diagnostics, and QML bridge.
- `src/ui/songview/quick/drawer/VoiceChangesPage.qml`: production marker/readout/input composition.
- `src/ui/songview/quick/drawer/VoicePicker.qml`: production Swift-owned picker using current bank-slot symbols.
- `src/ui/songview/quick/drawer/VoiceChangeMenu.qml`: production point/background actions and value selection.
- `src/checks/swiftcore/VoiceChangesPageChecks.swift`: direct projection, identity, transaction, context, menu/picker, cancellation, history, and diagnostics checks.

Modify:

- `src/swift/app/ApplicationSession.swift`: own/attach/refresh/cancel/detach the page in the current document lifecycle; provide only already-authorized audio callbacks.
- `src/swift/app/CMakeLists.txt`: compile the page.
- `CMakeLists.txt`: add the three production QML components to `drawer_qml`.
- `src/checks/swiftcore/SessionChecks.swift` and `src/checks/CMakeLists.txt`: dispatch/compile checks.
- `src/checks/editorqml/EditorQmlTests.swift` and `src/checks/editorqml/tst_EditorDrawer.qml`: add mounted production page/picker/menu/input/rendering/performance cases in the existing lane.

The implementer may change `EditorDrawer.qml` only for a production-generic modal/focus fact unavailable through its existing Loader; name and justify any such change. Read-only: native audio/C++ bridge, legacy sources/checks, sibling references. No other files.

## Prerequisites

- Shared playhead/page interaction seam accepted.
- Independent Velocity changes touching shared session/composition files are accepted/checkpointed before dispatch.
- `SongDocument` exposes `lanePoints`, voice-lane write/move/delete operations, stable occurrence handling, and history.
- `DocumentSession.bankSlots`, selected track, edit cursor, timeline, camera, and history are current.
- Voice audition remains unavailable under the authorized Swift/native interface.

## Interface contract

### Page owner and projection

`@MainActor @QtBridgeable public final class VoiceChangesPage` implements `EditorDrawerPage` with `.voiceChanges`, fixed production URL/body policy, and `interactionActive` true for pointer gestures, pan, picker, menu, prompt, or audition state.

Publish QML primitives/models for stable voice-change markers (occurrence identity, tick/x, slot, symbol/label, selected/hover/preview state), shared camera facts, current context readout, picker rows, menu state, cursor kind, and content/presentation diagnostics. Use the current bank-slot view; missing/blank slots remain explicit and never synthesize a voice.

The shared playhead line remains composition-owned. While transport is playing, current voice context uses rounded shared playhead tick; while stopped/paused it uses `DocumentSession.editCursor`. A move within the same voice span updates presentation without rebuilding static markers; crossing a voice boundary updates the readout/indicator.

### Stable identity and transactions

Identify a voice event by document revision/track plus stable lane occurrence identity, not list index alone. At gesture/menu/picker open, capture document revision, track, point identity, tick/slot before-value, selection, and camera projection.

Support production insertion, selection, horizontal drag/move, deletion, value replacement, point/background context actions, and picker commit. Motion is preview only. Release/accepted picker performs one existing semantic lane operation and creates at most one history entry. Collisions, boundary snapping, same-value/no-op, stale revision, missing point, and invalid/empty slot follow production and never retarget a different occurrence.

A picker/menu remains valid only for the captured document/track/point identity. Track/document/history replacement, page hide, Escape, outside dismiss, pointer ungrab, window deactivation, or scene retirement cancels synchronously, releases follow suspension, and commits nothing.

### Picker, menu, keyboard, and audition

`VoicePicker.qml` and `VoiceChangeMenu.qml` are production components driven by page-owned state. Pointer, Enter/Return, accessibility press, arrow navigation, Escape, outside dismissal, and text/type navigation follow production. Bare Space remains global transport unless focus is in an explicit audition control; because arbitrary voice audition is blocked, do not advertise a working audition control.

Do not import legacy native popup/controller infrastructure. Do not call `previewNote` as a substitute for arbitrary slot audition. Publish an explicit capability-unavailable flag/diagnostic so the absent action is honest and covered.

### Refresh/history/performance

Document edits, Undo/Redo, track/bank/camera/font/DPR changes rebuild the necessary model and invalidate stale modal state. Playhead-only positions within one effective context span change no static content-build count. Equal refreshes publish nothing.

## Implementation steps

1. Add direct checks for voice-event projection/identity, current playing-versus-edit-cursor context, insertion/move/delete/value replacement, collision/no-op/stale behavior, modal capture/cancellation, Undo/Redo, and no-rebuild diagnostics.
2. Implement `VoiceChangesPage` and attach it through `ApplicationSession` lifecycle.
3. Implement mounted production marker/readout input, picker, and menu QML without native popup infrastructure.
4. Extend the existing editor-QML lane with real input, focus/keyboard/accessibility, cancellation, shared-playhead/context, and rendered reference cases.
5. Run only the exact commands below; skip project-wide formatting/lint and unrelated suites inside the writer task.

## Acceptance predicate

Required independent behavior:

- one real page is attached per current document and obeys acknowledged detach lifetime;
- marker projection/labels, active context, selection, insertion, drag/move, delete, picker/menu value commit, collision/no-op/stale behavior, cancellation, Undo/Redo, shared camera/playhead alignment, and focus/commands match production;
- playing context follows shared playhead while stopped context follows edit cursor;
- modal state cannot follow a replacement track/document/point;
- playhead-only movement inside one voice span does not rebuild static marker content;
- production page/picker/menu are exercised with real input and `voice-picker` DPR 2 font 12/16 plus relevant `editor-drawer` rendered evidence;
- no C++ scenario/popup body or fake audition path remains; and
- exact verification passes:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify:qml --filter editorqml-drawer --verbose
deno task verify --filter swiftrollgated --verbose
```

Full completion additionally requires arbitrary picker-slot audition. Under the current authorized interface this is `BLOCKED`. Report the exact smallest native audio-service function/signature and legacy cases it would unlock; do not implement it without approval.

## Task-specific constraints

- Never substitute `previewNote` for `previewVoice`.
- No native C API/C++/QtBridge expansion.
- No legacy popup/controller dependency.
- No page-local clock/camera/history or index-only identity.
- No new global command/shortcut.
- Do not touch unrelated dirty planning documents or `.scratch/`.
- Return exact changed files, verification output, translated legacy scenario IDs, rendered evidence, and audition blocker.