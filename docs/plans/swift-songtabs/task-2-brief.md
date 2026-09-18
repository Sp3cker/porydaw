# Context
Reuse existing grid QML in native FocusScope pages; strip must expose no features beyond C++ QTabWidget. Read plan.md constraints/spec and current C++ src/ui/workspaceui.cpp setup. User explicitly rejects excessive custom focus handling and extra controls.

# Exact write set
- src/ui/songview/quick/swift-grid-prototype/Main.qml
- src/ui/songview/quick/swift-grid-prototype/SongTab.qml
- src/ui/songview/quick/swift-grid-prototype/SongTabs.qml
- src/ui/songview/quick/swift-grid-prototype/GridPalette.swift (canonical tab colors only)

# Prerequisites
Task 1 controller, task 4 real list moves. Interfaces frozen; original owners may fix in parallel.

# Interface contract
Main required songTabs QtObject; SongTabs required controller. Controller slots/properties in task-1 brief. Model display role is SongTabSession QObject; page gridModel is display.grid. Persistent Repeater pages use SongTab FocusScope, objectName songTab_<id>, existing child objectNames. SongTabs.currentPage is selected page/null; Main gridModel/audio/pitchBridge derive from it. Retain actual existing resetDemo/escapePressed actions and host shortcuts, disabled without current page or during dirty-close prompt. SongTab exposes readonly noteMenuOpen/pitchEditorOpen; per-page timer refreshes playing audio. Native selected-page visible/enabled/focus bindings only.

Strip controls: songTabSelect_<id>, songTabClose_<id>, songTabScrollLeft, songTabScrollRight. Dialog: songTabDiscard/songTabCancel. Remove songTabAdd, songTabOverflow and all dropdown Menu/Instantiator code. Persistent strip controls Qt.NoFocus, like C++ tab bar; native accessibility press remains. Modal controls retain native focus/activation. No new global shortcuts or keyboard strip traversal feature.

# Implementation steps
1. Preserve completed extraction of original grid/camera/ruler/popups/menu into SongTab.qml. Reuse existing PianoRollCanvas, NoteMenu, PitchBendPopup/Graph rather than twins. Main retains original toolbar once. Existing exact raster geometry and font/palette remain.
2. Strip supports only existing C++ capabilities. Keep title/dirty marker, tooltip, close, selection, pointer reorder; replace dropdown with left/right scroll buttons when overflowing. Use native Flickable positioning/ordinary scroll math to expose offscreen tabs and selected tab, not a second ordering authority. Remove plus/add UI and unsupported empty-state text/instruction; empty workspace is blank. Mirror Qt.NoFocus on tab/close/scroll controls; no custom focus memory/repair or key interception. Accessibility press still works.
   Use canonical Vanilla tab roles from themeruntime.cpp/presetcolors.h: normal #E1DBD6, hover #ECE7E1, selected #B9E8EE; add named palette fields using the existing GridPalette pattern. Keep existing text, outline, chrome and separator roles.
3. Persistent Repeater instances survive row moves; no resets or rebuilds. Selected-page native FocusScope binding routes editor focus. Existing shortcuts remain once at host, not per page. No test-only branches.
4. Dirty dialog keeps Discard/Cancel and native content-data Label composition (verified no binding loop). Native modal true and CloseOnPressOutside pitch-popup semantics stay. On actual page hide call existing inputCancelled(hidden), cancel open pitch preview, close transient UI; no suppress-commit flag or hidden focus restoration. Context menu maps into noteMenu coordinates. Native Flickable pixelAligned true preserves 1px visuals at fractional camera positions.
5. Preserve consumed window metrics/properties for existing actual toolbar/reset/edit operations and original smoke, not hidden legacy scene. No production QWidget edits, transport redesign or synthetic load state.

# Acceptance predicate
Main runs deno task prototype:swift-grid --smoke: unchanged strict raster/gesture checks plus pointer selection/reorder/close/scroll and per-page state tests pass without QML warnings. Native capture shows C++-parity strip with no plus/dropdown. Skip all author gates/formatters; read-only inspection only.

# Task-specific constraints
The current correction removes accidental extra features; it does not add alternative opening UI. Demo fixtures are seeded by App and test setup. Preserve reuse and native Controls rather than inventing a tab focus framework.
