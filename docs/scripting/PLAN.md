# Scripting / Plugins — Scoping & Plan

Status: **proposal, 2026-08-25**. Nothing here is implemented. Facts about the
current codebase (file/line refs) were verified against `scripting` branch tip
`52428aa`; everything else is a recommendation with the decision points marked
**DECIDE**.

Goal: a plugin system powerful enough for, at minimum, these three archetypes —

1. **Editing macros** — hotkeys that edit notes/automation relative to the edit
   cursor and/or the current note/time selection (e.g. "legato selection",
   "insert chord at cursor", "humanize velocities", "select every C#").
2. **Reactive visuals** — a Fruity-Dance-style avatar that animates to the beat
   / transport state.
3. **Custom analysis widgets** — realtime meters, spectrum, per-channel
   activity, i.e. panels fed by audio-rate data at frame rate.

Plus a fourth the survey makes obvious: **project automation** (batch
voicegroup edits, bulk registration, import/export in other formats).

---

## 1. Design stances

1. **One language, one host.** A single embedded runtime with one API surface
   (`porydaw.*`). No native `.dll/.so` plugins (ABI, crashes, no sandbox);
   no second language "for the easy cases".
2. **Scripts are UI-thread citizens.** All script execution happens on the Qt
   UI thread. The audio callback never touches the script engine; scripts see
   audio only through snapshots copied out of lock-free state (same model as
   `polySnapshot`, `playheadSamples()` today, `src/audio/audioengine.h:47-62`).
3. **Every document edit is an undo step.** Scripts mutate the song only
   through `SongDocument`'s existing public edit API, inside a script
   transaction that collapses to one `QUndoStack` entry named after the
   action. No raw pointers to notes cross the boundary — scripts hold
   `NoteId`s (`src/core/noteid.h`) and re-resolve via `findNote`, exactly
   as the UI does.
4. **Commands are keymap citizens.** A script-registered action becomes a
   normal `keymap::Registry` entry (`plugin.<pluginId>.<actionId>`) with a
   context, category, and optional default binding, so it shows up in
   Settings → Keyboard Shortcuts, participates in conflict detection, and
   dispatches through `SongView::handleEditKey` like every other bare-letter
   command (GROUND-RULES rule: never window shortcuts).
5. **Trusted-but-contained.** Plugins are code the user chose to install (the
   porymap model). We don't promise a security sandbox, but the API is
   capability-shaped: no ambient filesystem/process/network access; file IO is
   an explicit API scoped to the plugin dir and the project root, and
   declared in the manifest so the Plugins page can show it.
6. **Developer loop first.** Hot reload on file change, a script console dock
   (log + errors with stack traces + REPL), and a watchdog for runaway
   scripts. Without these the API is unusable no matter how rich it is.
7. **API versioned from day one.** `porydaw.api.version` (semver), manifest
   declares `"api": ">=1.0"`; breaking changes bump major and the loader
   refuses with a clear message. Ship a `porydaw.d.ts` for editor
   autocompletion and generate the reference docs (`docsrc/`) from it.

## 2. Runtime choice — **DECIDE**

| | JavaScript via `QJSEngine` (Qt::Qml) | Lua 5.4 (vendored, ~30 files, MIT) |
|---|---|---|
| New dependency | none — a Qt module we already have installed (6.9) | one small vendored C lib |
| Static-Qt Windows build | must link `Qt6::Qml` statically — known to work, but Phase 0 must prove it on the local static build (`CMakeLists.txt:236-258` static detection) | zero risk |
| Qt integration | native: `QObject`/`Q_INVOKABLE`/signals/`QJSValue` callbacks bind for free; `QJSEngine::setInterrupted` gives a watchdog | needs a binding layer (sol2 or hand-written) for every type |
| Custom widgets | opens the door to **Qt Quick/QML** for plugin UI (Canvas, AnimatedSprite, animations, layouts) — see §5 | only what we hand-build (canvas API) |
| Audience | JS is the most widely known language; **porymap (same author) already ships a QJSEngine scripting API**, so conventions, docs style and user expectations transfer directly | familiar to modders; PICO-8/Roblox/Renoise/REAPER precedent |
| Performance | fine for macros and 60 Hz callbacks if we pass typed arrays and do FFT/RMS in C++ | faster interpreter, same caveat |
| Risks | QJSEngine is ES7-ish (no modules until 6.x `import` support, which exists but is awkward), GC of `QJSValue` callbacks needs care, `Qt6::Qml` adds ~5 MB | Lua string/table ergonomics for UI-heavy plugins are worse; two "how do I…" doc sets (Lua + our API) |

**Recommendation: JavaScript / `QJSEngine`.** The porymap precedent alone is
worth a lot (users of one will use the other), and it's the only option that
makes "custom widgets" mean real widgets rather than a painter API. The Lua
fallback is kept only if Phase 0 shows static `Qt6::Qml` is unworkable on
Windows.

Rejected: Python (distribution/embedding pain on three platforms, large),
WASM (no ecosystem for this audience), native plugins (stance 1).

## 3. Architecture

New layer between UI shell and Document in the SPEC §3 diagram:

```
UI shell ──▶ ScriptHost (src/scripting/) ──▶ Document / Sequencer / Project adapter
                │
                ├─ PluginManager      discovery, manifest, enable/disable, reload, watchdog
                ├─ Engine             one QJSEngine per plugin (isolation: one plugin's
                │                     exception/hang can't take the others down)
                ├─ Api facades        QObject wrappers exposed as `porydaw.*` (below)
                ├─ ScriptConsole      dock: log/errors/REPL
                └─ PluginsPage        Settings → Plugins
```

Modules (all under `src/scripting/`):

| Module | Responsibility |
|---|---|
| `pluginmanifest.{h,cpp}` | Parse `plugin.json`; validate api range; permissions list. |
| `pluginmanager.{h,cpp}` | Scan plugin dirs, own `Plugin{manifest, QJSEngine, state, errors}`, load/unload/reload, file watcher (`QFileSystemWatcher`), watchdog timer (`setInterrupted` after N ms of a single call; configurable, default 5 s, off while a debugger flag is set). |
| `scriptapi_*.{h,cpp}` | One `QObject` facade per namespace (`app`, `project`, `song`, `edit`, `selection`, `view`, `transport`, `audio`, `ui`, `actions`, `io`, `storage`). Thin — they call into `SongDocument` / `SongView` / `AudioEngine` / `MainWindow`. |
| `scripttransaction.{h,cpp}` | `edit.transaction(name, fn)` — begins a `QUndoStack::beginMacro`, runs `fn`, `endMacro`; rethrows and rolls back (undo the macro) on exception. Nested transactions flatten. |
| `audiotap.{h,cpp}` | Audio→UI ring of the final interleaved mix (post `m_outputGain`) written from `AudioEngine::process`, plus C++ analysis helpers (peak/RMS per channel, N-bin magnitude FFT) computed once per UI frame and shared by all subscribers. |
| `scriptconsole.{h,cpp}` | Dock. |
| `pluginspage.{h,cpp}` | Settings page (list, enable toggle, reload, open folder, per-plugin error badge, "Open plugins folder"). |
| `scriptcheck.cpp` | Harness `--scriptcheck` (see §8). |

Plugin lifetime: each plugin exports `activate(ctx)` / `deactivate()`.
Everything registered in `activate` (actions, docks, subscriptions, menu
items) is tracked by a per-plugin `Disposables` list and torn down on
deactivate/reload — no leaked `QAction`s or keymap entries after a hot
reload (cf. the dangling-`QTreeWidgetItem` gotcha in the keymap page).

Packaging:

```
<QStandardPaths::AppDataLocation>/plugins/<id>/plugin.json   # user-global
<projectRoot>/.porydaw/plugins/<id>/plugin.json              # per-project (Sidecar::ensureDir)
```

```json
{ "id": "legato-tools", "name": "Legato Tools", "version": "1.0.0",
  "api": ">=1.0 <2", "main": "main.js", "ui": ["meter.qml"],
  "permissions": ["io.project", "io.plugin"] }
```

**DECIDE:** per-project plugin dir — yes (song-specific tooling, shareable in
the decomp repo) but it must be opt-in per project ("this project wants to
load 3 plugins — Allow / Never") since opening a stranger's repo shouldn't run
code.

## 4. API surface (v1)

Sketch, not final signatures. Ticks are document ticks (`ticksPerClock`
exposed); tracks are engine track indices as the UI shows them; values are
plain JS objects, never live handles, except `NoteId` (opaque number).

```
porydaw.api.version, porydaw.log(...), porydaw.version

porydaw.project     root, songs[] {id,label,constant,midPath,registered}, open(songId)
porydaw.song        (current tab; also porydaw.songs[] for all open tabs)
  .revision, .ticksPerBeat, .startTempo, .loop{start,end}, .timeSigs[]
  .tracks[] {index, name, voice, muted, soloed}
  .notes({track?, from?, to?, selectedOnly?}) → [{id, track, tick, key, len, vel}]
  .note(id), .lane(track, cc).points({from,to}) → [{tick, value}]
  .rawEvents(track, {from,to})        // read-only view of the SMF, for exotic tools
  .on('changed', fn)                  // documentChanged → (revision)
porydaw.edit        (all inside .transaction(name, fn); throws outside one)
  .addNotes([...]), .deleteNotes([ids]), .moveNotes([ids], dTick, dKey),
  .resizeNotes([ids], dLen, fromLeft?), .setVelocity([{id, vel}]),
  .setLanePoints(track, cc, [{tick,value}], {replaceRange?}),
  .deleteLanePoints(...), .removeTimeRange(...), .duplicateRange(...),
  .addTrack(voice), .renameTrack(i, name), .setStartTempo(bpm), .setLoop(...)
  .rawInsert/Modify/Delete(...)       // gated by "raw" permission; still undoable
porydaw.selection   .notes → ids, .setNotes(ids), .clear(),
  .time → {start,end,scope,lanes}|null, .setTime(...), .track (selected track),
  .on('changed', fn)
porydaw.cursor      .tick (edit cursor), .set(tick), .snap(tick, 'down'|'up'|'nearest'),
  .grid → {ticks, feel, denom}
porydaw.view        .scroll{x,y}, .zoom{h,v}, .visibleTicks{from,to}, .revealTick(),
  .laneVisible(cc), .setLaneVisible(cc,bool), .notesInRect? (later)
porydaw.transport   .state, .play()/.pause()/.stop(), .seek(tick), .playheadTick,
  .tempoAt(tick), .on('tick', fn) (frame rate), .on('beat', fn({bar,beat,tick})),
  .on('state', fn)
porydaw.audio       .sampleRate, .on('frame', fn(frame)) where frame =
  {peak:[l,r], rms:[l,r], pcm: Float32Array (last N interleaved), fft(bins)},
  .channels() → PolySnapshot-shaped {pcm:[{on,releasing,track,key}], cgb:[...]}
  .previewNote(track,key,vel,ms), .previewVoice(...)
porydaw.actions     .register({id, name, category, context:'roll'|'global'|'range'|
  'velocity', default:'Ctrl+Shift+L', run(ctx)}) ; ctx = {song, selection, cursor}
porydaw.ui          .dock({id,title,area, qml|widget}), .menu(path).add(action),
  .contextMenu('roll'|'range'|'track').add(action), .statusMessage(text),
  .dialog.prompt/confirm/form({...}), .toast()
porydaw.io          .readText/writeText/exists/list within plugin dir or project root
porydaw.storage     .plugin (JSON, QSettings-backed) / .song (JSON in the view
                    sidecar, `<root>/.porydaw/<song>.json` "plugins" key)
```

Notes on how these map onto existing code:

- `song.*`/`edit.*` are 1:1 with `SongDocument` (`src/core/songdocument.h`):
  `addNotes/deleteNotes/moveNotes/resizeNotes/setNotesVelocities/writeLanePoints/
  applyRangeEdit/removeTimeRange/duplicateRange/insertRawEvent…`. The
  transaction wrapper is what makes N calls one undo entry; every call still
  goes through `publishMutation`, so revision, `documentChanged`, and the
  timeline snapshot swap for the audio thread all keep working unchanged.
  Optimistic-concurrency variant (`setNotesVelocities(expectedRevision, …)`)
  becomes the default for scripts: a transaction captures `revision()` at
  start and refuses to commit if it moved (a user edit interleaved via a
  nested event loop — e.g. a dialog).
- `selection.*`/`cursor.*`/`view.*` are `SongView` accessors
  (`selection()/setSelection`, `timeSelection`, `editCursorTick/
  commitEditCursor`, `snapTick*`, `gridSegAt`, `viewState`). The range ops
  already living on SongView (`transposeTimeSelection`, `pasteRangeAtEditCursor`,
  …) can be exposed directly; the note-selection ops buried in the private
  `PianoRoll` class (`transposeSelection` songview.cpp:2442, `nudgeSelection`
  :2476) get hoisted to SongView as part of Phase 2 — a good cleanup anyway.
- `transport.*` wraps `AudioEngine` transport atomics + the existing
  `synchronizePlayhead` 17 ms timer (`mainwindow.cpp:274-278`); `on('tick')`
  is driven from that timer, `on('beat')` derives bar/beat from the
  `MidiTimeline` tempo map crossing between two ticks.
- `audio.on('frame')` needs the one engine-side addition: a tap in
  `AudioEngine::process` after gain (a small SPSC ring of the interleaved
  float mix, ~200 ms). Analysis (peak/RMS/FFT) runs once per UI frame in C++
  regardless of subscriber count and is handed to JS as typed arrays. A tiny
  in-house radix-2 FFT (≈80 lines) — no dependency.
- `actions.register` → `keymap::Registry` needs a small extension: today
  `kDefs[]` is a static table (`src/ui/keymap.cpp:30-175`); add
  `registerDynamic(Def)/unregisterDynamic(id)` + the Shortcuts page grouping
  dynamic entries under a "Plugins" category. Bindings persist under the
  same `keymap/<id>` QSettings key so user rebinds survive reload.

## 5. Custom widgets — **DECIDE (gated on Phase 0)**

Two viable designs; both accept a dock spec from `ui.dock(...)` and end up
inside a `QDockWidget` next to Songs/Voicegroup/Polyphony
(`mainwindow.cpp:607-752`), with a plugin-owned `id` so `windowState`
restore works.

**A. Qt Quick (`QQuickWidget`) + QML files shipped by the plugin.** Preferred.
The plugin's JS objects are injected as context properties, so a meter is
literally `Rectangle { height: porydaw.audio.rms[0] * parent.height }` and a
dancing avatar is an `AnimatedSprite` whose `frameRate` is bound to tempo.
Costs: link `Qt6::Quick`/`QuickWidgets` (+ the QML `QtQuick` static plugins
on the Windows static build), ~15 MB, and a QML runtime inside a Widgets app
(fine; QQuickWidget is designed for this). Themeing: expose the resolved
`theme` roles as a context property so plugins can match the current theme.

**B. Widget-primitive + canvas API.** `ui.dock({build(root)})` where `root`
offers `label/button/slider/checkbox/combo/row/column` (mapped to real
`QWidget`s) and `canvas({paint(g, w, h)})` whose `g` is a `QPainter` facade
(`rect/line/text/image/path`, `drawImage` of a pre-decoded sprite sheet).
Repaint on `requestFrame()`. No new Qt modules. Covers both example use cases
adequately, but every future "can I have a…" needs a C++ binding.

Plan: do **A** if Phase 0's static-Qt spike passes; otherwise **B**. Even
under A, ship the `canvas` primitive from B, because a 30-line JS meter that
needs no `.qml` file is the on-ramp most users want.

Piano-roll **overlays** (paint over the roll — scale highlighting, chord
names, per-note annotations) are a separate, later capability
(`ui.overlay('roll', {paint(g, viewport)})`) hooked into `PianoRoll::paintEvent`
after notes and before the playhead. Valuable, but it touches the paint
caching (SPEC §7.1) so it's Phase 4.

## 6. Phases

Each phase is independently landable, adds a `--scriptcheck` section, and
lands a CHANGELOG entry + SPEC §3/§6 update.

**Phase 0 — Spike (≈2–3 days).** Link `Qt6::Qml` (and `Qt6::Quick` +
`QuickWidgets`) behind `PORYDAW_SCRIPTING=ON`; hello-world `QJSEngine`; one
`QQuickWidget` in a dock; **build and run on the Windows static Qt** and inside
the macOS/Linux release pipelines (`release.yml` uses linuxdeploy-plugin-qt /
macdeployqt — both handle Qml, but the AppImage needs the qml dir). Measure
binary size delta. Decides §2 fallback and §5 A/B. Exit criteria written down
in this doc.

**Phase 1 — Host + read-only API + actions (≈1–2 weeks).**
`PluginManager`, manifest, per-plugin engine, hot reload, watchdog, Script
Console dock, Settings → Plugins page, `porydaw.log/app/project/song(read)/
selection(read)/cursor(read)/transport(read+control)/actions.register/
ui.statusMessage/storage`. Keymap `registerDynamic`. Bundled example:
"Select all notes of same pitch as selection". Harness: load/reload/unload a
fixture plugin, action appears in `Registry`, dispatches through
`handleEditKey`, watchdog interrupts an infinite loop, error surfaces in
console.

**Phase 2 — Editing API (≈1–2 weeks).** `edit.transaction` + all mutation
calls, `selection.set*`, `cursor.set`, `view.*`, revision guard, hoist
`PianoRoll::transposeSelection/nudgeSelection` to SongView. Bundled
examples: *Legato*, *Insert chord at cursor*, *Humanize velocities*,
*Strum selection*, *Quantize to grid*. Harness: each example runs against a
fixture song, produces exactly one undo entry, undo restores byte-identical
SMF (`--smfcheck` style), exception mid-transaction leaves the document
unchanged. ← **archetype 1 ships here.**

**Phase 3 — Realtime + widgets (≈2 weeks).** Audio tap + analysis, `audio.on
('frame')`, `transport.on('beat'|'tick')`, `ui.dock` (A or B per §5),
`canvas`. Bundled examples: *VU meter*, *Spectrum*, *Dancer* (sprite-sheet
avatar bobbing on beats, with a sample sprite sheet — needs an asset we own).
Harness: tap ring never blocks the callback (ASAN + `--audiocheck`
extension), frame subscriber gets non-zero RMS while a fixture song plays
through the null backend, dock restores from `windowState`. ← **archetypes 2
and 3 ship here.**

**Phase 4 — Reach (ongoing).** Menus/context menus, dialogs/forms, `io.*`,
per-song plugin storage, roll overlays, `song.rawEvents`/raw edits, project
adapter writes (batch registration, voicegroup edits — via the existing
`SongRegistry`/`VoicegroupSource` APIs), WAV/render hooks (`wavexport` reuse
for "render all songs"), `porydaw.d.ts` + generated `docsrc/reference/
scripting.md`, and a `docsrc/manual/plugins.md` install guide.

## 7. Other plugin categories the API should not preclude

- **Generators/transformers**: arpeggiator, chord tools, humanize, strum,
  echo/delay (as note copies), scale-lock, velocity curves, CC LFO drawers.
- **Analysis**: polyphony-overflow finder over the song (uses `polySnapshot`
  history), unused-voice report, mid2agb-compat lint (things the exporter
  will clamp), "which tracks exceed the budget" — surfaced as console output
  or a dock.
- **Import/export**: other trackers' formats, MML/text notation → notes,
  song → text for diffs, batch render via `TimelinePlayer`.
- **Project maintenance**: bulk voicegroup edits, sample dedup reports,
  registration audits — all through the existing adapter APIs.
- **Live input**: MIDI keyboard input (not yet supported by porydaw at all;
  if added later it would be `porydaw.midi.on('message')` — keep the
  namespace free).
- **Cosmetic**: theme generators (write `theme/*` QSettings), custom note
  colouring (`ui.overlay`), status-bar widgets.
- **Workflow**: macro recorder (record a sequence of `edit.*` calls into a
  script), per-song "plugin state" (e.g. a chord-progression sketchpad
  stored in the song sidecar).

## 8. Testing

- `src/scriptcheck.cpp`, `--scriptcheck <decomp-root>`, following the
  `check(cond, msg)` / PASS-or-exit-1 convention (`src/keymapcheck.cpp`
  tail), added to `tools/run_checks.sh` and swept under ASAN. Fixture
  plugins live in `src/testdata/plugins/`, loaded from a `QTemporaryDir`
  copy so hot reload can be exercised by rewriting the file.
- Every assertion negative-tested (GROUND-RULES). Watchdog test must prove
  the UI thread is released (run with a wall-clock cap).
- Bundled example plugins double as API smoke tests and as the documentation
  samples — they must stay green in CI or the docs lie.

## 9. Risks and open questions

| Risk | Mitigation |
|---|---|
| Static `Qt6::Qml`/`Quick` on the local Windows build | Phase 0 spike; fallback Lua + widget-primitive API |
| `songview.cpp` churn (10.9k lines, private surface classes) vs. a stable script API | Facades only touch `SongView`'s public accessors; hoisting note-selection ops out of `PianoRoll` reduces coupling |
| Per-frame JS callbacks stuttering the UI | Analysis in C++, typed arrays, subscribers decimated to the 17 ms playhead timer, watchdog, `audio.on('frame')` auto-unsubscribes a plugin that throws repeatedly |
| Scripts mutating during playback | Already handled: every edit swaps an immutable timeline snapshot (SPEC §3) |
| Scripts re-entering via dialogs mid-transaction | Revision guard + transactions are synchronous; `ui.dialog.*` is forbidden inside a transaction (throws) |
| Plugin loaded from a cloned repo | Per-project plugins opt-in with an explicit prompt (§3) |
| API freezes too early | v1 is `0.x` until Phase 3 lands; announce stability with the first release that ships the docs |
| Bundle size / release pipeline | Measure in Phase 0; `PORYDAW_SCRIPTING` CMake option keeps it removable |

**DECIDE list (summary):** runtime (§2, JS recommended); widget layer A vs B
(§5, gated on Phase 0); per-project plugin dir opt-in (§3); whether raw SMF
edits are permission-gated or just available (§4); scheduling — Phase 1+2
before or after the current time-selection/clipboard work is pushed.
