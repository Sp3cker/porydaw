# Handoff: restore missing menu items (Swift/QML shell)

Branch `feature/swift-qml-grid`, worktree `.worktrees/swift-qml-grid`.
Last green commit: `5e1deec2` (pulled) on top of `ab73ca06` (legacy widget deletion).

## State

Two parallel edit lanes were dispatched and were still editing when the session
ended. Their changes are **uncommitted, unbuilt and unverified** in the worktree:

```
 M CMakeLists.txt                              (Lane A: AboutDialog.qml registration)
 M src/checks/editorqml/ShellQmlTests.swift    (Lane A: tst_ShellMenus registration)
 M src/checks/rollcheck/note_rendering.swift   (Lane B: new checks)
 M src/swift/app/ApplicationSession.swift      (Lane B: session contract)
 M src/swift/app/roll/GridScene.swift          (Lane B)
 M src/swift/app/roll/PianoGrid.swift          (Lane B)
 M src/swift/app/shell/ShellPresenter.swift    (Lane A)
 M src/swift/app/timeline/GridPalette.swift    (Lane B: velocityNoteColor?)
 M src/swift/app/timeline/GridTypography.swift (Lane B: note-name font spec?)
 M src/ui/shell/ShellWindow.qml                (Lane A)
?? src/checks/editorqml/tst_ShellMenus.qml     (Lane A)
?? src/swift/app/roll/NoteNameLabels.swift     (Lane B)
?? src/ui/shell/AboutDialog.qml                (Lane A)
```

A lane may have stopped mid-edit. First step: `git diff` each file and finish or
revert incomplete hunks. Lane transcripts may still be readable as
`agent://ShellMenuActions` and `agent://RollDisplayModes`.

## Scope (what the menu work must deliver)

Oracle: `src/mainwindow.cpp` (kept, unbuilt) — File 280-320, View 347-384 and
600-665, Help 391-424, transport rows 120-135. Deleted widget code:
`git show ab73ca06^:<path>`.

### Lane A — shell actions and menus
Files: `ShellPresenter.swift`, `ShellWindow.qml`, new `AboutDialog.qml`, new
`tst_ShellMenus.qml` (+ registration in `ShellQmlTests.swift`, CMake lists at
~255 and ~396).

- `file.close_tab` → `session.songTabs.requestClose(tabId: selectedId)`; enabled when a tab is selected.
- Transport: `go_to_start`, `play`, `play_pause`, `pause`, `stop`, `loop` (checkable), `follow_playhead` (checkable), via `session.transportBarPresenter()` (`goToStart`, `setLoopEnabled(enabled:)`, `setFollowPlayhead(enabled:)`).
- View: `velocity_drawer`, `voice_changes_drawer`, `automation_drawer` (checkable) → `selectedPage.drawerPresenter().toggleSection(kind:drawerOwnsFocus:)`, kinds automation=0, velocity=1, voiceChanges=2; checked from `*Section.visible`.
- View: `velocity_colors`, `note_names` (checkable, always enabled) → session setters below; persisted in QSettings root keys `velocityNoteColors`, `noteNames` via QtCore `Settings` in ShellWindow.qml.
- Help: `help.about` → AboutDialog (text from mainwindow.cpp:392-422), themed with GridPalette inks.
- `checked` must bind to tracked properties directly so it follows state changed elsewhere (transport bar, drawer buttons, shortcuts).
- Not in scope: Export WAV, View → Theme, New Song, Import MIDI, Register Song, Import Sample.

### Lane B — roll display modes
Contract on `ApplicationSession`:
`@QtTracked velocityColorMode`, `@QtTracked noteNameMode`,
`setVelocityColorMode(enabled:)`, `setNoteNameMode(enabled:)` — app-wide, applied
to every tab's PianoGrid and to tabs opened later.

- Velocity colours: oracle `git show ab73ca06^:src/ui/songview/trackvoiceops.cpp` ~151-176 — v<=0 → noteVelocityZero; 1 → #5F44E9; >=127 → #E90904; else HSV-linear, t=(v-1)/126, quantized 8-bit. Applies to non-ghost fills and draw preview.
- Note names: oracle `timelinequickview_pianoroll.cpp` synchronizeNoteText, `pianoroll.cpp` ~156, `songview.h` 80-90/343-348 — key height >= 12, selected-track notes only, name + two trailing spaces must fit, box inset by half-space, left/vcentre, contrasting ink; published to `pianoNoteTextModel`.
- Checks in `src/checks/rollcheck/note_rendering.swift`.

## Finish

1. Review diffs; complete or revert.
2. Gates (orchestrator only):
   `deno task build:checks`, `deno task verify`, `deno task verify:shell`,
   `deno task verify:qml`, `deno task verify:qml-roll`,
   `deno task proof check --executed; echo EXIT=$?` (don't pipe).
   Targeted: `deno task verify:shell --filter menus --verbose`,
   `deno task verify --filter rollcheck --verbose`.
3. Update matching proof-ledger GAP rows (rollcheck / mainwindowrouting) to MATCHED if the new checks prove them.
4. Commit "Restore missing menu items" and push `feature/swift-qml-grid`.

Known flake: swiftcore `projectstore-actor` A03 under load.

## Open user decisions
- Delete `origin/feature/swift-qml-grid-rollqml-checks` (`4c0f9215`, unmerged)?
- AGENTS.md pointer to ADR 0002 (needs permission).
- SVGs for Go to Start, Stop, Resonance transport glyphs.
- Design approvals: ProjectStore create-song/SMF-write (New Song / Import MIDI); Swift sample pipeline (sample editor).
