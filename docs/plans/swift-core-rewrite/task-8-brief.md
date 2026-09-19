# Task 8 — Direct piano-grid consumer, then stop

## Context

The core and native host are already cut over. Convert the existing Swift grid
from transport client into a direct `DocumentSession` consumer. This is the only
editor conversion in this plan. See [plan.md](plan.md#global-constraints) and
[spec.md](spec.md#single-consumer-and-host).

## Exact write set

Create `src/swift/app/NoteCommands.swift`, `src/swift/app/Clipboard.swift`.
Modify:
- `src/swift/app/{ApplicationSession.swift,DocumentSession.swift,CMakeLists.txt}`,
  `src/app/{RewriteWindow.h,RewriteWindow.cpp}`, `CMakeLists.txt`.
- `src/swift/app/module.modulemap`, `src/app/native_host.h`.
- Existing `src/ui/songview/quick/swiftroll/{PianoGrid.swift,GridGesture.swift,GridScene.swift,GridGeometry.swift,GridTypography.swift,TimeAxis.swift,EditCommands.swift,EditKeyArbiter.swift,SwiftGridHost.swift,SwiftRollOverlay.qml}`:
  only direct model/input/identity integration and obsolete mirror retirement;
  preserve geometry/rendering algorithms otherwise.
- `src/ui/songview/quick/swiftroll/native/{window_cancel.h,window_cancel.cpp,module.modulemap}`:
  preserve required native cancellation/font services without retired feed imports.
- `src/checks/{CMakeLists.txt,checkcatalog.cpp,fwd.hpp}`;
  existing files in `src/checks/{swiftrollgated,swiftbandkeys,swiftqtml,swiftrollbench,selectionkey,rollcheck,clipboard}`:
  only retained grid/window/input/clipboard cases and fixture driver conversion.
- `docs/plans/qtbridge-integration-contract.md`, this plan's `plan.md`/`spec.md`
  evidence and deferred-case ledger.

Delete the current files in `src/ui/songview/quick/swiftgrid/` (the entire
obsolete feed/executor/band/mount directory) and
`src/ui/songview/quick/swiftroll/{SgdDocument.swift,SgcCommands.swift,SgcKeys.swift,Tick.swift}`.
Remove their build/module imports and registration users together. Retire obsolete
`swiftdocfeed`/`swiftcommands` check files after meaningful cases are covered on
native Swift; do not keep token/pipe tests as production acceptance.
`TrackHeaders.swift` stays unbuilt reference source: do not convert it.
`PianoRollCanvas.qml`, `GridPalette.swift` and font helpers are preserved unless
an imported identity/type reference must change; no visual redesign.

## Prerequisites

Task 7's core/runtime milestone accepted and checkpointed. Task 6's ownership
interface and task 5's playback contract are the only document/native inputs.
No new bridge capability is assumed beyond the recorded object-return/lifetime
and ordinary scalar input support.

Compile the retained grid Swift sources into `PorydawApp`, the same module as
DocumentSession/ApplicationSession. Retire the old `SwiftGrid` library target
and update retained check imports. Do not create the circular dependency
PorydawApp → SwiftGrid → PorydawApp. Keep core and playback separate modules.
Before replacing/closing the session, detach its QML scene while the Swift
presenter is still alive, then release the presenter/session. A failed open
keeps the current document. Do not let a QML proxy outlive its Swift owner.

## Interface contract

`ApplicationSession` strongly owns `PianoGrid(session: DocumentSession)` and
returns it through `gridPresenter() -> PianoGrid`. QML consumes that retained
object; it does not create or own a document. `PianoGrid` reads native document
projections and session selection, and calls semantic Swift methods directly.
There is no fallback into SongView, no string document/session token and no local
undo history. Native input delivery belongs to the small host.

The QML root uses the retained presenter and existing canvas. Wire plot/gutter
pointer input and wheel coordinates into existing gesture behavior; remove
`timelineQuickView`, feed binding and `editingBound` dependencies. Use the same
camera state for drawing and hit-testing. Preserve current right-drag selection
semantics and double-click behavior. Leading resize now calls the core's atomic
edge-resize method through the existing grip.

`NoteCommands` supplies existing note-targeted editing/clipboard actions in the
spec using session selection and core operations. `Clipboard` preserves the
existing `application/x-porydaw-clip` payload and TPQN rescaling semantics from
`src/ui/songview/clipmime.cpp`; native Qt only gets/sets bytes. Do not add another
clipboard format. Commands for absent editor surfaces are not registered.
ApplicationSession installs the grid's native-only audition callback to
NativeAudio.previewNote(track:key:velocity:). Release/cancellation sends velocity
zero for the tracked note; never pass the grid's internal idle key `-1` to the
native UInt8 key API. Capture the native service without a presenter/session
retain cycle. This replaces the removed host audition route, not a new tool.
Keep canonical window QActions and existing key eligibility/auto-repeat policy;
QML never claims bare Space or defines competing command shortcuts.
Extend `native_host.h` with `pd_clipboard_write(const uint8_t*, size_t)` and
`pd_clipboard_read(void* context, consumeBytesCallback) -> bool`, implemented in
RewriteWindow.cpp on the GUI thread. Read synchronously lends the existing MIME
bytes to the callback; Swift copies them once. False means that MIME is absent.
These two native clipboard calls are imported by Clipboard.swift; do not put
clipboard methods in the audio service or invent Swift access to QClipboard.

## Implementation steps

1. Inject the native session and remove all feed/command/row-token translation
   state. Keep render geometry as derived data and retain the scene objects QML
   references. Deduplicate the musical Tick definition into PorydawCore.
2. Attach the existing QML grid to RewriteWindow and replace the inert absorber
   handlers with delivery to existing gestures. Preserve audition, pan/zoom,
   modifier selection, all named cancellation paths, and correct initial theme/
   font/scroll state. No new controls, menus, tools or other editor views.
3. Move retained note command execution out of the old C++ host into direct
   Swift operations. Preserve grouping, clipboard scaling, selection and
   mute/solo behavior; do not implement excluded prompt/editor commands.
4. Repoint existing actual-window/grid behavioral tests to the new host and
   native session. Re-enable only retained grid/window cases in the manifest;
   leave excluded-surface cases explicitly deferred. Remove flag/token-only
   assertions and old transport after replacement proof.
5. Run the actual application smoke, final declared-manifest checks and structural
   reduction review. Record native QtBridge lifetime evidence on this surface.
   Remove throwaway probes and record the terminal gate; do not begin another view.

## Acceptance predicate

The real application opens a staged song, displays themed notes, executes the
existing grid gestures/commands through Swift, undoes/redoes, saves/reopens and
plays the edited song. No old core/transport/editor is compiled or instantiated.
Controller commands:

```sh
deno task build:app
deno task verify --filter swiftrollgated --filter swiftbandkeys --filter swiftqtml --verbose
deno task verify --filter selectionkey --filter clipcheck --filter clipmimecheck --verbose
deno task verify --verbose
```

The last run is the **declared rewrite manifest**, not the historical whole-app
suite. Exact deferred rows must be recorded. `swiftrollgated` retains its name
for check discoverability but no longer asserts a rollout flag. Its scenarios
must drive the actual retained QML/host, not invoke only private model functions.
Close every retained grid row in coverage-ledger.json and repeat the final
[case-by-case reconciliation](spec.md#case-by-case-coverage-reconciliation)
against executed results. All retained core rows remain verified; only reviewed
absent-UI/obsolete-implementation exclusions may be left out.

Native smoke requires an available desktop. Launch the built bundle through the
supervised process tool with `--project <staged-root> --song mus_route101`, capture
its window, and exercise drawing, both resize edges, move/neighbor trim,
right-drag selection, delete, keyboard undo/redo/copy/paste, pan/zoom, play/pause,
save/reopen and ordinary cancellation/close. Confirm the frame shows real notes
with the stored theme and runtime font scaling. Use the existing bench workload
on the same fixture to record cost; do not compare a reduced scene with the old
full scene. Offscreen evidence is not presented as native visual verification.

## Task-specific constraints

Do not port TrackHeaders, ruler, tabs, drawers, browsers or dialogs. Do not expand
the grid's QML feature set to compensate for their absence. Do not keep dead C++
views or feed mirrors to satisfy old tests. After this acceptance, stop.
