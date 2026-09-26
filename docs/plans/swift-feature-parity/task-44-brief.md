# task-44 — SH06 preference remainder: fork keys Swift does not own

# Context

Close SH06's remainder through the task-36 `PreferencesStore` (`00b96099`,
landed): own the last fork-main `fceecd88` preference keys, restore
window/filter state, repair the output-dial drag law and follow/resonance
enablement. Consumers: task 46 (menu topology reads these gates), AU03.

1. **Fork laws** (`git show fceecd88:…`):
   - Keys (`src/mainwindow.cpp:59-61`): `followPlayhead`, `outputVolume`,
     `dsp/resonanceSuppression` → on-disk `dsp.resonanceSuppression`.
     Constructor restore (`mainwindow.cpp:427-434`): follow default **true**,
     volume 100, suppression default **false**, applied before show. Writes
     on change (`mainwindow.cpp:469-478,482`): follow and suppression on
     toggle (suppression also to audio); volume on change.
   - Window/filter restore (`mainwindow.cpp:165-171`): `windowGeometry`,
     `windowState` via `restoreGeometry/restoreState` (absent/invalid →
     no-op), then `restoreSongFilters` with `songFilterText` (""),
     `songFilterSort` (0), `songFilterCategory` ("") — before first show.
     Saves only in `closeEvent`'s accepted-close block
     (`mainwindow.cpp:1358-1378`; `m_persistSession` false only in fork
     check fixtures), order: geometry, state, text, sort, category.
     `windowState` carries dock layout; the polyphony dock
     (`mainwindow.cpp:584-624`) is the only closeable dock ⇒ debugger
     visibility rides `windowState`.
   - Filter semantics (`src/ui/songlistpanel.cpp:145-171,236-251`): sortIndex
     = combo index (0 "ID order", 1 "A–Z"); category stored as prefix string;
     restore clamps sort, holds the category **pending** until a project's
     songs arrive, missing category → All; a project-less run reports the
     pending category unchanged.
   - Dial drag law (`src/ui/transportbar.cpp:33-78,208-227`): incremental
     global-Y — press records `m_lastGlobalY` + zeroes `m_stepAccumulator`
     (no value jump); each move applies `((y − lastY) · rate)`, `rate =
     Shift ? 0.2 : 0.5`, then `lastY = y`; the accumulator carries fractional
     remainders, truncates toward zero per move; `setValue` clamps 0…100.
     Tooltip (`transportbar.cpp:406`): "Application output volume. Does not
     change the song volume or saved song settings."
   - Enablement (`transportbar.cpp:297-312,437-442`): Follow-Playhead and
     Suppress-Resonances are checkable and **never disabled**; only playback
     actions + Loop gate on `loaded`.
2. **Current Swift state**: `TransportBarPresenter` carries `followPlayhead
   = true` / `resonanceSuppression = false` with apply-only setters
   (`TransportBarPresenter.swift:26-27,173-184`); volume is persisted
   (`:186-195`, task 36); `NativeAudio` exists from session init and
   `refresh()` mirrors audio back including the no-song branch, so
   suppression reaches the engine without a song
   (`ApplicationSession.swift:133`; `TransportBarPresenter.swift:73-76,98`).
   `ShellPresenter` gates follow on `songOpen` and resonance on
   `songOpen && state != 0` (`ShellPresenter.swift:223-235`); no window-frame
   persistence exists (`ShellWindow.qml:60-83` mount-restore, `:164-167`
   accepted-close, `:524-525` debugger dock on `shell.polyphonyVisible`).
   `SongListPresenter` already implements the fork filter law
   (`restoreFilters` + pending category, `SongListPresenter.swift:163-171,
   282-293`) with no persistence caller; the Songs panel binds its controls
   to the presenter, so restore renders. The dial is press-origin relative,
   rates already 0.5/0.2, no tooltip (`TransportOutputDial.qml:62-86`).
3. **Check inventory**: every lane stages the store in scratch
   (`ShellQmlTests.swift:149-151`, `SessionChecks.swift:16`; `stageShared`
   wins over later `configureShared` — nothing writes
   `~/Library/Preferences`). Shell entries run whole files (empty
   `testFunctions`), so new test functions need no harness change. Reuse the
   relaunch (`tst_ShellTransport.qml:377-395`), close-walk
   (`tst_ShellSongs.qml:30-49`) and staged-presenter
   (`transport_checks.swift:44-77`) patterns. Ledger
   `src/checks/workspace/proof.tabs_transport.txt` (73 sites; dial rows
   A025–A027, A041–A058, A065–A070) has no fork A rows for follow/suppression
   persistence, window state or song filters — those become S rows.

# Exact write set

- `src/swift/app/transport/TransportBarPresenter.swift` — toggle restore;
  persist-on-change in the two setters.
- `src/swift/app/shell/ShellPresenter.swift` — enablement; window members +
  restore in `configureSettings`; filter-restore call; `persistSessionState`.
- `src/swift/app/songlist/SongListPresenter.swift` — `restoreFromPreferences()`.
- `src/ui/shell/ShellWindow.qml` — frame application + on-screen guard;
  normal-frame tracking; `onClosing` persist hook.
- `src/ui/shell/TransportOutputDial.qml` — incremental drag law; tooltip.
- `src/checks/workspace/transport_checks.swift` — staged toggle predicates.
- `src/checks/songlist/songlist_checks.swift` — staged filter predicate.
- `src/checks/editorqml/tst_ShellTransport.qml` — enablement, persistence
  relaunch, drag law, tooltip.
- `src/checks/editorqml/tst_ShellSongs.qml` — filter persistence + fallback.
- `src/checks/editorqml/tst_ShellWindow.qml` — frame/state/debugger restore,
  offscreen guard, key-spelling readback, fresh-store guard.
- Ledger (controller-delegated): `src/checks/workspace/proof.tabs_transport.txt`.

No CMake, `TransportBar.qml`, `ShellQmlTests.swift`, engine or settings-dialog
changes. Sizing exception: one preference family over 11 files with one
verification-surface set — named for the dispatch table.

# Prerequisites

Task 36 accepted. Slot after the current batch settles;
`ShellWindow.qml`/`ShellPresenter.swift` are hot composition files —
serialize with any in-flight writer (task 46 follows and reads its gates).

# Interface contract

- `TransportBarPresenter.restoreTransportToggles()` — reads `followPlayhead`
  (fallback true) and `dsp.resonanceSuppression` (fallback false), applies
  via the existing setters; called from `ShellWindow.qml`
  `Component.onCompleted` right after `restoreOutputVolume()` (:79).
  `restoreOutputVolume`/`commitOutputVolume` keep names and behavior (ledger
  A045/A055/A064 cite them).
- `setFollowPlayhead(enabled:)` persists `followPlayhead` after the existing
  change guard; `setResonanceSuppression(enabled:)` persists the applied
  `resonanceSuppression` after the audio apply (`setBool` +
  `synchronize`). Keys verbatim dotted: `followPlayhead`,
  `dsp.resonanceSuppression`.
- `SongListPresenter.restoreFromPreferences()` — reads `songFilterText`
  (""), `songFilterSort` (0), `songFilterCategory` ("") and routes through
  the existing `restoreFilters`; pending-category semantics unchanged.
- `ShellPresenter` window members: `@QtTracked windowX/windowY/windowWidth/
  windowHeight: Int = -1`, `windowMaximized: Bool = false`, restored inside
  `configureSettings` beside the dock reads (`ShellPresenter.swift:482-483`),
  which also calls `session.songDockController().presenter
  .restoreFromPreferences()` — fork restore order: geometry, state, filters.
  `persistSessionState(x:y:width:height:maximized:debuggerVisible:)` writes
  in fork order: `windowGeometry` = `"x,y,w,h"` string; `windowState` =
  comma tokens from `["maximized", "debugger"]` ("" = none);
  `songFilterText` = presenter `searchText`; `songFilterSort` = `sortIndex`;
  `songFilterCategory` = `categoryPrefix()` (pending-aware); then
  `synchronize()`. Representation is Swift-owned: the fork's QByteArray
  payloads (CFData on disk) read as absent through `string(key:)` fallbacks;
  `songFilter*`, `followPlayhead`, `dsp.resonanceSuppression` keep fork types
  so fork installs restore them directly.
- `ShellWindow.qml`: after `shell.configureSettings(...)` (:76) apply the
  saved frame when `windowX >= 0` and the frame's center lies on some
  `Qt.application.screens` rect (offscreen → ignore; natural size stands);
  then `if (shell.windowMaximized) root.visibility = Window.Maximized`.
  Track the last frame observed while not maximized (`normalFrame`, gated on
  `visibility !== Window.Maximized`; falls back to the current frame when
  the session never left Maximized). In `onClosing` (:164-167), when
  `shell.beginClose()` returns true, call `shell.persistSessionState(...)`
  with that frame + maximized + `shell.polyphonyVisible` — exactly once, on
  the accepted pass (mirrors the fork's `m_closeAccepted` block). No writes
  anywhere else.
- `actionEnabled`: `transport.follow_playhead` and `transport.resonance`
  return true unconditionally (drop the `songOpen` gates at
  `ShellPresenter.swift:223-224,234-235`; keep Loop's gate untouched — AU03).
- `TransportOutputDial.qml` input region (:62-86): replace
  `pressedY`/`pressedValue` with `dragLastY: real` + `stepAccumulator: real`;
  press records both and takes focus (unchanged); each pressed move:
  `rate = Shift ? 0.2 : 0.5`; `stepAccumulator += (mouse.y − dragLastY) *
  rate; dragLastY = mouse.y`; `steps = Math.trunc(stepAccumulator)`; when
  nonzero, `stepAccumulator −= steps` and emit
  `valueCommitted(clamp(dial.value + steps, 0, 100))`. Wheel/keyboard
  unchanged. Add the fork tooltip text verbatim on hover
  (`transportbar.cpp:406`).
- New message-anchored predicates (verbatim commitments):
  - `tst_ShellTransport.qml`: "follow playhead stays enabled without an open
    song"; "resonance suppression stays enabled without an open song"; "the
    follow-playhead preference survives a fresh shell session"; "the
    resonance-suppression preference survives a fresh shell session";
    "pressing the output dial without dragging leaves the volume unchanged";
    "dragging the output dial accumulates steps from the pointer's last
    position"; "shift dragging the output dial uses the fine rate"; "the
    output dial tooltip explains it does not change the song volume".
  - `tst_ShellWindow.qml`: "a saved window frame restores across a fresh
    shell session"; "an offscreen saved frame is ignored"; "the maximized
    flag restores across a fresh shell session"; "debugger visibility
    restores with the window state"; "preferences keep the fork's on-disk key
    spellings".
  - `tst_ShellSongs.qml`: "song filter text, sort and category restore across
    a fresh shell session"; "a restored category the project does not have
    falls back to all songs".
  - swiftcore (`transport_checks.swift`): "stored follow-playhead preference
    restores into the transport presenter"; "toggling follow playhead stores
    its preference on change"; "stored resonance suppression restores into
    the audio engine"; "toggling resonance suppression stores its preference
    on change"; `songlist_checks.swift`: "stored song filters restore into
    the songs presenter".
- Preservation contract: `restoreOutputVolume`/`commitOutputVolume` paths and
  volume semantics, every other task-36 key family, `resetPreferences`,
  staging order, and `tst_ShellWindow.qml`'s existing natural-size messages
  stay verbatim.

# Implementation steps

1. `TransportBarPresenter`: persist-on-change in the two setters;
   `restoreTransportToggles()`.
2. `ShellPresenter`: enablement fix; window members + filter-restore call in
   `configureSettings`; `persistSessionState`.
   `SongListPresenter.restoreFromPreferences()`.
3. `ShellWindow.qml`: frame application + screen guard; `normalFrame`
   tracking; `onClosing` persist hook. `TransportOutputDial.qml`:
   incremental law + tooltip.
4. Checks. swiftcore: staged-store toggle/filter predicates (audio attach
   like `transport_checks.swift:56-66`). `tst_ShellTransport`: enablement
   (`actionable === true`, song-less, both toggles); persistence relaunch
   (toggle → `cleanup()` close-walk → `openShell()` → restored); drag law
   via mousePress/mouseMove/mouseRelease — accumulator discriminator: start
   40, drag 140 px down → clamped 100, drag 10 px up → **95** (press-origin
   law stays 100); fine rate: 10 Shift px → +2 (`keyPress(Qt.Key_Shift)`
   around the moves); tooltip. `tst_ShellSongs`: filter persistence through
   the mounted panel (open project, set search "route", sort A–Z, a real
   category, close-walk, remount, reopen, assert panel + presenter);
   bogus-category fallback (seed `songFilterCategory` "zz"). `tst_ShellWindow`:
   frame restore (drive `root.x/y/width/height`, close-walk, remount,
   assert); seeded offscreen frame (x −99999 → natural size); seeded
   `windowState` "maximized"/"debugger" → `windowMaximized`, `visibility ===
   Window.Maximized`, `polyphonyVisible`; key-spelling readback through
   `bootstrap.preferences` after a persisted close (the seven keys above).
   Prepend `bootstrap.resetPreferences()` to the natural-size/typography
   function; keep its messages verbatim.
5. Run the lanes below; record RED→GREEN for the drag-law predicates (they
   must fail on the press-origin law before step 3) and the enablement
   predicates.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore-projectsession --verbose` — toggle
  and filter presenter laws, existing volume laws.
- `deno task verify:shell --filter shell-transport --verbose` — enablement,
  persistence relaunch, drag law, tooltip.
- `deno task verify:shell --filter shell-songs --verbose` — filter
  persistence and fallback.
- `deno task verify:shell --filter shellwindow --verbose` — frame/state
  restore, offscreen guard, key spellings, fresh-store natural size.
- `deno task verify:bridge` — new bridged members (`windowX`…,
  `windowMaximized`, `persistSessionState`).
- Leak tripwire (before/after the three shell lanes):
  `ls ~/Library/Preferences | grep -c '^com\.sp3cker\.'` must not increase.
- Runtime prerequisite: macOS host audio for the resonance predicates
  (`NativeAudio()` failure reports as failure, not skip).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants (drag rates 0.5/0.2 and bounds 0…100 are fork interaction
  laws, not geometry).
- Ownership transfer: task 36's untouched-key list loses `followPlayhead`,
  `dsp.resonanceSuppression`, `windowGeometry`, `windowState`, `songFilter*`;
  the store still never removes or rewrites `lastImportDir`,
  `lastWavExportDir`, `sampleLibraryFolders`, `keymap.*`, or any other
  unowned key, and never deletes these keys on restore.
- Checks stage the store in scratch only; no check may construct
  `PreferencesStore()` in an entry before its staging point (new swiftcore
  predicates run only inside the already-staged `runTransportBarChecks`/
  `runSongListModelChecks` frames).
- One message-anchored predicate per fork clause; existing predicate messages
  stay verbatim; no predicate is deleted without replacing its clause.
- Accepted deviations (record in ledger reasons, do not code around):
  `windowGeometry`/`windowState` payloads are Swift strings under the fork
  keys (fork blobs read as absent — fork installs migrate toggles/filters,
  not geometry); one natural-size frame shows before `onCompleted` applies a
  saved frame; persistence runs at every accepted close (fork skipped it only
  in check fixtures; Swift isolates via scratch, not a production flag);
  suppression persists the applied value (identical whenever `NativeAudio()`
  initialized).
- Implementers never edit ledgers; the controller delegates them. Ledger
  mapping for `proof.tabs_transport.txt`: A043 → the tooltip predicate; A049
  → "pressing the output dial without dragging leaves the volume unchanged";
  add S rows (predicate inventory) for every new message above so
  `--executed` classifies them. Rows left untouched: A025–A027, A041–A042,
  A044, A046–A047, A050–A057, A065–A070 (dial raster, bounds accessors,
  document/history effects, tab-switch volume — AU03/ED surfaces); A058
  stays PARTIAL.

# Controller verification

After the writer settles and no check processes remain:

1. `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — new S rows execute; no
   unmapped MATCHED sites.
2. Native smoke (desktop): song-less, toggle Follow Playhead off and
   Suppress Resonances on (both enabled); drag the output dial slowly with
   and without Shift; set a song filter/category/sort; move+resize, maximize,
   open the Polyphony Debugger; quit with Cmd-Q; relaunch — frame, maximized
   state, debugger pane, toggles and filters all restore;
   `defaults read com.sp3cker.porydaw` shows the seven keys with fork
   spellings (`dsp.resonanceSuppression` dotted) and no other new keys.
3. Repeat the leak count around the three shell lanes.
