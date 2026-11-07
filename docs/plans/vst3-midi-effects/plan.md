# VST3 MIDI effects — live inserts with an Effect Output pane

A track can host one VST3 MIDI-producing plugin as a **live insert**. With Live on, the plugin runs during song playback and drives that track's engine voice at the plugin's own timing, as a preview. The song never stores plugin output: the `.mid` holds only what the user writes or pastes. **Render** (offline, over a range) and **Grab played** (the live notes last heard) fill the session-only **Effect Output** drawer pane. The user selects notes there, copies them, and pastes them into real tracks with the normal roll paste. Behavior, vocabulary and interfaces: [spec.md](spec.md).

## Decisions

| # | Decision | Rejected alternatives (why) |
|---|---|---|
| D1 | Live insert plus Effect Output pane. Plugin output reaches the song only through Copy and the normal Paste. The `.mid`, WAV export, CPU profile, backups and every editing surface see the song only; the live CPU meter estimates GBA work, not plugin time. While a track is Live, Porydaw plays notes the `.mid` does not contain; the track header shows a badge with the plugin's name, plus a "Live" caption while armed. The modal panel picks and configures the plugin; Live, Render and Grab played live in the Effect Output section header. | Live-effect tracks with cached output flattened into the saved `.mid` (the previous model B): the user wants explicit copy, and it needs flattening, digests and detach. Recording the live take into the `.mid`: files stitched from several passes. An Output track inside the song document: it would ship and pollute undo. |
| D2 | `SongState.effects: [TrackEffect]` holds config plus plugin state: one plugin effect per track, whole-track, no range. Add, remove, replace, config edits and finished plugin edits are undoable history entries; each finished plugin edit is one "edit plugin settings" step restoring the full `PluginStateBlob`. Track remaps move effects inside the same mutation. Live arming is session state in `TrackEffectsController`; it is never saved and every effect opens with Live off. | Effects outside the document: undo of a track delete could not bring them back, and save/dirty would need a second path. Plugin state outside undo: the user wants Cmd-Z to revert plugin edits. Per-range effects: the live insert covers the whole track; the range belongs to Render. |
| D3 | `porydaw-vst3-host` scans and hosts VST3 modules out of process, one helper per `PluginInstance`, launched lazily. Porydaw never loads a plugin module or links the SDK; `porydaw_pluginhost` links only into the helper and checks. The helper owns the top-level editor window. The SDK is a pinned subset under `external/vst3sdk/`, built by our CMake target. | Hosting in Porydaw's process: a plugin crash or hang kills Porydaw. One shared helper: one crash kills every plugin. Swift C++ interop: leaks SDK types. Submodules or FetchContent: worktree churn or network dependency. Qt Quick `WindowContainer`: native children occlude QML popups. |
| D4 | Live uses one bounded bridge round trip per audio render chunk; the helper processes plugin sub-blocks and returns sample-positioned notes to `Sequencer`. `liveMask` suppresses source notes, and the take records dispatched output. A missed reply releases live-held keys and signals input discontinuity; a watchdog kills a hung helper. Slow plugins can still cause dropouts. | A worker running ahead of the playhead: output queue, transport mirroring, resync and extra latency. Snapping live output: notes are snapped only when they enter Effect Output. A separate timeline: the session timeline is shared with the UI and must remain the song. |
| D5 | Sidecar `<projectRoot>/.porydaw/midi-effects/<label>.json` stores effect config and plugin state only. Open drops effects whose track no longer exists and says so; a corrupt sidecar is renamed aside, with a notice. Song deletion removes the sidecar, fork copies it, and backups don't include it. | Storing config inside the `.mid`: mid2agb would export it. App-data storage: not portable with the project. A digest pairing with the `.mid`: nothing derived from the song is stored, so nothing can go stale. |
| D6 | The play/pause binding (`transport.play_pause`, Space by default) always reaches Porydaw, including while a plugin editor window has focus. The helper intercepts those keystrokes before the plugin view sees them and sends `Shortcut(index)`; Swift runs `ShellPresenter.activate(id:)`. Plugin text fields never receive Space. | Plugin keeps its focused keys: rejected by product requirement. Qt `ApplicationShortcut`: foreign native views never deliver their keys through Qt. |
| D7 | Effect Output is a fourth EditorDrawer section (`DrawerSectionKind.effectOutput`). It shows the selected track's effect output on the roll's camera, supports note selection, and puts the selection on the existing `PorydawClip` clipboard. Its section header carries the Live toggle, Render, Cancel Render with progress, Grab played, Open Editor, Copy and Clear for the selected track's effect. Output is session-only: it is lost on close, and the plugin settings persist. | A separate Output window: a second roll surface. Panel-only Copy Notes: no partial selection. Persisted output: the user chose session-only. |
| D8 | The built-in arpeggiator is unchanged. It keeps its own panel, Copy Notes and solo audition, and is not a track-effect kind. | Reworking it into a live effect: scope; its generate-then-copy flow already matches D1. |
| D9 | Crash or hang detaches the insert, cancels Render and marks the effect stopped without changing the document. A manual Reload Plug-in restores the last recorded state and re-arms Live if previously armed. | Automatic restart: the user must control recovery. Modal alert: interrupts the session. |

Execution ruling approved by the user: loop-wrap input offs precede chased ons at offset 0 of the first wrapped block; both use the new loop context. Keep exact boundary timing and one bridge request per chunk. Task 7 also repairs the Playback take seam with completed-position records and explicitly flagged discontinuity releases, so silent tails and old-timeline endpoints remain exact.

## Gates

- G1 — approved by the user (out-of-process wording). Task 5 applies this AGENTS.md "Native boundary" amendment verbatim:
> C/C++ exists only at: `src/app/`, `src/audio/`, `src/project/`, `src/pluginhost/`, `src/ui/songview/quick/swiftroll/native/font_metrics.cpp`, and the display-list boundary in `src/render/` … `src/pluginhost/` builds `porydaw-vst3-host`, the helper executable that scans and hosts every VST3 plugin in its own process, and `pluginbridge.h`, the C wire format (shared-memory layout, control frames, cross-process wait/wake) that Swift imports. Porydaw's process never loads a plugin module. Steinberg SDK types, plugin threads, editor windows and editor key interception stay inside the helper. Native code never decides scan policy, capture pacing, crash or hang policy, which keys Porydaw owns, or which events reach the document.
  It also adds `src/swift/pluginhost/` (PorydawPluginHost: Core + Playback + PorydawPluginBridge) to the project map and module rules.
- Vendoring Steinberg VST3 SDK 3.8.1 (MIT) is approved.
- No specific target plugin is available. Acceptance rests on the in-repo fixture plugin, plus any installed VST3 with an event-output bus in the final smoke.

## Global Constraints

- Follow spec.md exactly. Implementers never invent names; a missing decision is NEEDS_CONTEXT.
- Do not include external product names, links, logos or vendor assets in committed content, except the open-source host names cited as technical precedent in this plan. No VST logo in the UI.
- The song is the truth: the `.mid`, WAV export, CPU profile, backups, clipboard sources and every editing surface read `SongDocument` state, which never contains plugin output (D1). Only the audio callback's live path sounds plugin output.
- Realtime: live and Render never use the instance concurrently. Porydaw's callback-side code is allocation-, lock- and dispatch-free; its one deliberate blocking call is bounded `pdpb_wait_reply` (D4). Task 4 owns `Sequencer`/`AudioRenderEngine`; task 7's bounded correction may extend only the take-event seam, `Sequencer` feedback and its existing checks to preserve exact segment endpoints. `AudioDevice` is untouched.
- Threads: every VST3 call runs inside the helper. Its Qt main thread dispatches control, editor windows, Linux `IRunLoop` and key interception; its RT thread processes requests. A stdin reader posts control frames to the main thread. Porydaw's main actor sends control frames; plugin callbacks only flip atomics or enqueue.
- QML: follow rule://qtbridge-surface and rule://text-contrast. Geometry comes from the resolved base font through existing layout policies; no hard-coded pixels. Persistent chrome never claims bare `Space`; Space reaches `transport.play_pause` from the main window and from plugin editor windows (D6).
- Swift: rule://swift-standards, rule://swift-locality, rule://swift-typecheck-complexity. Explicit closure types. Comments are at most 2 lines.
- Ownership of shared files. The controller owns registration edits: `src/checks/CMakeLists.txt`, `src/checks/checkcatalog.cpp`, `src/checks/support/corecheck/{core_check.h,tst_swiftcore.cpp,CoreCheckDispatch.swift}`, `src/checks/editorqml/ShellQmlEntries.swift`, `src/swift/*/CMakeLists.txt` source lists, `src/swift/app/shell/PorydawQmlTypes.swift`, `qt_add_qml_module` file lists, and `bridge:baseline`/`qml-aot:baseline` runs for intended surface changes. The controller also owns all shared-tree builds, checks and formatting. A brief names the registration its new files need; the controller applies it.
- Implementers do read-only local inspection only. They run no builds, checks, formatters or linters, and report DEFERRED_TO_CONTROLLER. Implementers reuse the commands recorded here without repeating discovery. A stale command or scope change is reported with the concrete mismatch and revised command, never silently narrowed.
- New checks test behavior through the module's interface (`@testable import` is the checks' existing convention); no source-text or wiring checks. No `proof.*.txt` ledgers exist under `src/checks`; none are in scope.
- Use `--release` on build and check commands if the Debug cache's Qt kit disagrees with the checkout-local kit (the arpeggiator plan's precedent); otherwise run them as written.
- No commits until a checkpoint. At each checkpoint the controller commits the accepted tasks, then pushes the branch to `origin`. Untracked `docs/ideas/memacc-flow-ableton-wayfinding.md`, `profiler/` and `prototypes/` stay untracked and uncommitted.

## Tasks

| # | Task | Route / seat | Depends | Brief |
|---|---|---|---|---|
| 1 | Core lattice and batch normalizer extraction | SDD, sdd-implementer: behavior-preserving arpeggiator refactor plus new policy. Over-cap (4 files): one Core behavior, one suite | — | [task-1-brief.md](task-1-brief.md) |
| 2 | Core effect model: types, document operations, history, track remap, plugin-state undo, dirty | SDD, sdd-implementer: new state field across mutation/history/remap. Over-cap (9 files): one model, one suite | — | [task-2-brief.md](task-2-brief.md) |
| 3 | Sidecar codec + save/open/fork/delete + drop/corrupt notices | SDD, sdd-implementer: persistence pairing and open-time restore. Over-cap (12 files): one persistence behavior, one suite | 2 | [task-3-brief.md](task-3-brief.md) |
| 4 | Live insert seam: slot and event types, `Sequencer` input/output and ledgers, `liveMask`, `AudioRenderEngine` slots, `NativeAudio` attach/detach | SDD, sdd-implementer: one realtime path. Over-cap (5 files) | — | [task-4-brief.md](task-4-brief.md) |
| 5 | Vendored VST3 SDK subset, SDK target, license notice, AGENTS.md amendment | SDD, sdd-implementer: third-party source drop. Over-cap (5 entries): one dependency behavior | G1 | [task-5-brief.md](task-5-brief.md) |
| 6 | Helper-internal `pdph_` engine, host scan mode, helper build and per-platform packaging, fixture plugins and ABI checks | SDD, sdd-implementer: native SDK lifecycle and threading. Over-cap (15 entries) | 5 | [task-6-brief.md](task-6-brief.md) |
| 7 | PorydawPluginHost: catalog, bridged instance and capture, `LiveInsert`, `LiveTakeRing`, `LiveTake` | SDD, sdd-implementer: callback bridge and worker capture. Over-cap (10 files) | 1, 2, 4, 13 | [task-7-brief.md](task-7-brief.md) |
| 8 | Helper editor windows and key interception; Swift control routing (D6) | SDD, qt-cpp-reviewer: QWindow ownership, per-platform native views and keys, Linux run loop. Over-cap (17 files) | 7, 13 | [task-8-brief.md](task-8-brief.md) |
| 9 | `TrackEffectsController`, `EffectOutputStore`: lifecycle, Live, Render, Grab, crash watchdog and manual Reload | SDD, sdd-implementer: workspace-owned controller and insert lifetime. Over-cap (6 files) | 3, 4, 7 | [task-9-brief.md](task-9-brief.md) |
| 10 | `MidiEffectsPresenter`, header badge and Stopped caption, catalog/folders, editor transport and Reload | SDD, sdd-implementer: presenter lifecycle. Over-cap (11 files): one surface | 8, 9 | [task-10-brief.md](task-10-brief.md) |
| 11 | `MidiEffectsPanel.qml` (setup only) + mount + shell check + contrast | SDD, sdd-implementer: QML surface. Over-cap (6 files) | 10 (may be drafted alongside it) | [task-11-brief.md](task-11-brief.md) |
| 12 | Effect Output drawer section: header controls including Reload, page, publication, selection, Copy, QML, drawer registration + shell check | SDD, sdd-implementer: drawer section on the roll camera. Over-cap (11 files): one surface | 9, 10, 11 (its shell check uses task 11's `injectPluginFault`) | [task-12-brief.md](task-12-brief.md) |
| 13 | Per-instance helper host mode, shared-memory bridge and Swift transport | SDD, qt-cpp-reviewer: process, Qt threading and realtime IPC. Over-cap (15 files): one bridge behavior | 6 | [task-13-brief.md](task-13-brief.md) |

Parallelism (disjoint write sets):
- tasks 1 ∥ 2 ∥ 4 ∥ 5;
- then 3 (after 2) ∥ 6 (after 5);
- then 13 (after 6), then 7 (after 1, 2, 4, 13);
- then 8 ∥ 9;
- then 10;
- then 11, then 12 (task 12 drafting may overlap 11; its shell check needs task 11's bootstrap).

## Checkpoints

- **A1** — after tasks 1, 2 and 4: Core model and live engine. Commit and push before task 3 re-edits `SongDocument.swift`.
- **B0** — after task 5: the vendored SDK gets its own commit. Commit and push before task 6 extends `src/pluginhost/CMakeLists.txt`.
- **B0.5** — after task 6: checkpoint its accepted engine before task 13 re-edits `pluginhost.h`, `scanner/scanner_main.cpp` and `src/pluginhost/CMakeLists.txt`.
- **A** — after task 3: effects persist end to end. Full `uv run --no-sync dev checks`, then commit and push.
- **B1** — after tasks 6 and 13. Commit and push before task 7 reuses bridge and module files.
- **B** — after task 7. Commit and push before task 8 re-edits helper and instance files; then tasks 8 ∥ 9.
  After tasks 8–9, checkpoint accepted work before task 10 re-edits `DocumentWorkspace.swift` and `ApplicationSession+Tabs.swift`.
- **C** — after task 10. Commit and push before task 12 re-edits `DocumentWorkspace.swift`.
- **Final** — after tasks 11–12, plus the final verification below.

## Final verification (controller)

```
uv run --no-sync dev build:checks
uv run --no-sync dev checks
uv run --no-sync dev checks:qml
uv run --no-sync dev checks:shell
uv run --no-sync dev checks:qml-roll
uv run --no-sync dev checks:bridge
uv run --no-sync dev checks:qml-aot
uv run --no-sync dev format --check
uv run --no-sync dev lsp:swift
```

Native smoke with `uv run --no-sync dev build:app` on a desktop, using a scratch copy of a fixture project:

1. Open "MIDI Effects..." on a track, add the fixture folder and any installed VST3 MIDI-producer folder, and select a plugin. Confirm the track header shows the plugin badge. In the Effect Output section header, turn Live on and confirm the header shows "Live", then Space plays the song with the plugin driving that track while the track's own notes are silent. Close the panel and confirm Live and the editor survive.
2. Open the plugin editor while playing and change a parameter. Confirm the change is audible within about one audio buffer.
3. In the editor turn a knob and edit a pattern; in the main window Cmd-Z reverts each as one step, redo reapplies it, and the plugin UI reflects both.
4. Loop a 2-bar range. Confirm the wrap is seamless; seek elsewhere and confirm the effect resumes within about a bar.
5. Click into the editor window and press Space; confirm Porydaw toggles playback and the plugin does not react. Repeat with a plugin text field focused, if it has one.
6. In the Effect Output section header, stop playback, then Grab played. Confirm the section shows the notes just heard. Select some, copy them, paste them into another track at the edit cursor, then Undo.
7. Make a time selection and press Render in the section header. Confirm the section shows the render over the selection; copy everything and paste it.
8. Export WAV with Live on; confirm it contains the song only.
9. Save, close and reopen. Confirm the effect restores with its plugin state and Live off, the `.mid` on disk holds no plugin output, and the Effect Output section is empty.
10. Fork the song, then delete the fork; confirm the sidecar is copied and then removed.
11. With Live armed and the song playing, kill that effect's helper from a terminal (`kill -9 <pid of porydaw-vst3-host>`; Task Manager on Windows). Confirm Porydaw's audio keeps playing, the effect shows "<name> stopped working." and the header shows "Stopped", then Reload Plug-in restores the last recorded state and re-arms Live. The shell checks cover the same path with the fixture's `fault` state.
12. Freeze the helper instead (`kill -STOP <pid>` on macOS/Linux). Confirm audio keeps playing and, within about 2 s, the effect shows "<name> stopped responding." and "Stopped", the frozen helper is gone, and Reload Plug-in restores and re-arms. On macOS also check helper editor focus and menu-bar behavior while its window is key, and that it has no Dock icon.

Capture screenshots of the plugin badge with its Live caption, the panel, the Effect Output section and the editor window.

Risks: helper scheduling affects RT wake latency without an IO workgroup join; each instance incurs a process and Qt startup; macOS editor focus and menu-bar behavior need the smoke above. Linux runs the non-windowing ABI and bridge checks in the ASAN CI job (offscreen, `build.yml:241-250`) but not editors; Windows is proven only by CI compilation and the packaged-helper start check, because its CI builds no checks.
