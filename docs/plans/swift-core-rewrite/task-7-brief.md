# Task 7 — Core runtime cutover and native host

## Context

Make the checked Swift core the application's only core, migrate its remaining
native playback clients, and exclude unconverted editors. This closes the core
milestone before task 8 converts the single document consumer. The intermediate
window has native application actions but intentionally no document editor;
that is the approved absence of unmigrated surfaces, not a dummy grid.
See [plan.md](plan.md#global-constraints) and [spec.md](spec.md).

## Exact write set

Create `src/swift/app/ApplicationSession.swift`,
`src/swift/app/NativeAudio.swift`, `src/app/RewriteWindow.h`,
`src/app/RewriteWindow.cpp`, `src/audio/swift_audio_service.h`,
`src/audio/swift_audio_service.cpp`.
Create `src/app/native_host.h` for the C-only host boundary, initially declaring
`pd_app_register_types()`. ApplicationSession supplies type registration;
task 8 adds retained grid registrations. This is not a C document facade.

Modify:
- `CMakeLists.txt`, `src/swift/app/CMakeLists.txt`, `src/swift/app/module.modulemap`,
  `src/main.cpp`, `src/porydaw_pch.hpp`, `tools/cli.ts`, `deno.json`.
- `src/audio/{audioengine.h,audioengine.cpp,timeline_handoff.h,wavexport.h,wavexport.cpp}`,
  `src/audio/swift_playback.h`, `src/swift/playback/PlaybackBridge.swift`,
  `tools/porydaw_render_cli.cpp`.
- `src/project/{songregistry.h,songregistry.cpp}`: remove only `blankSong` and its
  now-unused SMF include/forward declaration; preserve native project functions.
- `src/checks/{CMakeLists.txt,checkcatalog.cpp,fwd.hpp}` and existing driver/assertion
  files in the closed directories `src/checks/{swiftcore,editcheck,midi,playback,clipboard,project,voicegroup,voicegroupsave,audio,keyboard,support}`,
  plus `src/checks/automation/domain/`: only retained core/service cases and their
  necessary support. No new files in those directories other than task-owned
  Swift check files already introduced by tasks 1–6.
- This plan's evidence/deferred-check ledger in `plan.md` and `spec.md`.

Delete every old `src/core` file named in spec.md after its final comparison.
Exclude old editor/shell sources in build lists without editing their bodies.
The grid/old transport source retirement belongs to task 8.

## Prerequisites

Tasks 1–6 and cumulative core semantic review accepted. Task 5's realtime API and
task 6's session/project interface are stable. Record the final live comparison
before removing the C++ reference; do not use historical passing output for it.

## Interface contract

`ApplicationSession` owns one `DocumentSession`, exposes native application
operations to QtBridge, and strongly owns all Swift objects it returns. It does
not own a presenter until task 8. `RewriteWindow` is a small native container,
not a subclass of the old MainWindow and not a second policy owner.
QtBridge-facing entrypoints are ordinary synchronous invokables; they start
Swift async work internally, never expose a Swift async/throws signature to Qt.
Provide `isDocumentDirty() -> Bool`, `requestSave()`, observed `saveInProgress`
and `lastSaveError`. Publish completion only after dirty/error state is updated.
`RewriteWindow::closeEvent` offers Save/Discard/Cancel for a dirty document;
Save ignores the close until successful completion, while cancellation/failure
keeps the window open. Do not block the main actor waiting for its own save.
Apply the same Save/Discard/Cancel decision before replacing the loaded song
or project. A failed save does not proceed with that replacement.

`NativeAudio` wraps only the retained AudioEngine service: bind/unload song,
publish timeline, play/pause/stop, seek, preview-note and telemetry. Use task 5's
publication ownership and task 6's opaque bank lease; AudioEngine and WAV export
consume the new immutable view. Native shared_ptr owners adopt a retained
publication with `pd_playback_data_release` as deleter, preserving
`TimelineHandoff`'s actual lifetime algorithm and device quiescence points.
No callback allocation, retain or release.

The app provides Open Project/Open Song, Save, Undo/Redo, Play/Pause native
actions and dirty-close handling. Existing registered actions use
`keymap::Registry::attach`. Open Song is an unshortcutted menu QAction, not a
nonexistent `file.open_song` registry ID or a new shortcut. Its native modal
picker displays registered labels from ApplicationSession's scalar
`songCount()`/`songLabel(index:)` queries and calls `openSong(label:)`.
Use existing `applicationstartup`, layout, typography, ThemeController/runtime/
resolver/color services and restore the stored theme. No legacy editor, hidden
document view, or replacement browser is constructed. Optional project/song
startup arguments select real data only.

The existing `porydaw` and `porydaw_checks` targets become the rewrite targets.
Keep their task names. Replace `porydaw_app`'s monolithic source membership with
an explicit closure of retained native services/bootstrap and this small host;
remove its `src/core` and legacy UI entries. Do not keep a flag-selected old app.
The check manifest declares retained coverage only; preserve exact deferred case
names in the evidence ledger. C++ test scenarios retain meaningful assertions,
with operation drivers repointed to Swift. Delete comparison-only plumbing once
its oracle retires; no production reverse facade.

## Implementation steps

1. Repoint AudioEngine, handoff, WAV export and render CLI to the accepted Swift
   timeline/sequencer and task 5's file-load entry; no second native SMF decoder
   or quantization table.
2. Implement the small native host and Swift application composition. Reuse real
   project/session services, canonical QActions, theme/font startup and save/close
   behavior. The editor area stays absent until the next task.
3. Cut over build membership and all retained core/service test drivers together.
   Exclude old workspace/ProjectIo orchestration and every unconverted editor.
   Preserve source for deferred UI checks; remove implementation-pinning cases.
4. Run final comparisons before deletion; remove all old core implementations and
   the native blank-song constructor. Migrate render CLI build/launch through the
   Deno runner, adding a `build:render` task only for that existing executable.
5. Exercise retained checks against actual Swift services and inspect the compiled
   source/link closure. Record deferred coverage and separate code-reduction
   quantities. No old source may be kept solely to satisfy a stale test driver.
Before excluding the old host, run
`deno task verify --filter swiftrollbench-swift --verbose` with the fixture/frame
settings task 8 will use. This is its baseline, not acceptance of the new consumer.

## Acceptance predicate

`porydaw` opens/saves/plays real songs with Swift as the only core. Native engine
clients and retained C++ behavioral checks use that implementation. No `src/core`
file or unconverted editor is compiled into the app or rewrite check executable.
Controller commands:

```sh
deno task build:app
deno task verify --filter smfcheck --filter editcheck --filter noteidcheck --filter xcmdcheck --filter automation-domain --filter velocity-model --verbose
deno task verify --filter savecheck --filter vgbankcheck --filter vgsavecheck --filter roundtrip --verbose
deno task verify --filter loopcheck --filter primecheck --filter transportcheck --filter trackactivitycheck --filter exportcheck --verbose
deno task build:render
```

`build:render` is prospective in this task; it builds `porydaw_render_cli` through
the existing Deno CLI, not direct cmake. Preserve its existing arguments and run
it over the staged loop/tail fixtures, comparing output with task 5's reference
render evidence. A build alone is not render acceptance.

Launch the actual app with staged project/song arguments; use native actions to
play/pause, save/reopen and close. This proves host/service operation, not a grid.
The controller records the generated build source/link evidence and manifest
case partition before accepting the core milestone.

## Task-specific constraints

Do not add a full old-app target, type aliases, compatibility headers, or C++
SongDocument facade. Whole-directory test write scopes above are a bounded
mechanical driver cutover, not permission to change unrelated behaviors. Do not
move the sequencer to native code. Do not implement any QML document view here.
