# Context

Grid denomination cutover, part 2 of 2 (after task-34a). Surface, strings,
commands, persistence, mounted checks. Fork-main = `fceecd88`.

1. **Fork ruler grid controls + menu**
   (`git show fceecd88:src/ui/songview/timeruler.cpp`):
   - Division control text (`gridDivisionText`, :65-76): `Auto` for Auto,
     `Clock` for Clock, `"1/%1".arg(denominator)` for Musical — the same
     string is the menu row text and the control text. Feel text
     (`syncGridControls`, :112-125): `Triplet`/`Straight`. Tooltips :90-100
     (not mounted by any ported check; see constraints).
   - Division menu (`openGridMenu`, :225-268): rows rebuilt at open from
     `m_grid.selections()`, id = `toMenuId()` (-1 Auto, 0 Clock, else the
     denominator), checked = live selection; feel menu rows Straight(0)/
     Triplet(1) with `static_cast<int>(feel)`. Division activation →
     `setGridSelection(GridSelection::fromMenuId(id))` (:179-183); feel
     activation → `setGridFeel(GridFeel(id))` (:185-187).
   - Controls are keyboard-operable comboboxes: `activeFocusOnTab: true`,
     `Keys.onReturnPressed`/`Keys.onEnterPressed` reopen the menu
     (`git show fceecd88:src/ui/songview/quick/RulerControls.qml:58,
     125-126`).
   - Host dispatch on any grid change (`gridStateChanged`, grid.cpp:
     373-386): cancel the drawer's visible page interaction, sync the ruler
     controls, repaint ruler/roll/drawer grid surfaces.
2. **Fork commands** (`git show fceecd88:src/ui/keymap.cpp:156-161`,
   grid.cpp:398-411): `roll.grid_narrow` Ctrl+1 → `narrowGrid()`,
   `roll.grid_widen` Ctrl+2 → `widenGrid()`, `roll.grid_triplet` Ctrl+3 →
   `toggleGridFeel()`. Swift already mirrors names, shortcuts, command ids
   and routing (EditCommands.swift:44-46 `gridNarrow/gridWiden/
   gridTriplet = 34`, policies :258-263, KeybindingRegistry Ctrl+1/2/3,
   ShellPresenter `roll.grid_*`) — only the handler bodies change.
3. **Fork persistence contract** (the decision):
   - The grid selection + feel live in `SongView::ViewState` — per-tab,
     transient, "never persisted or propagated between tabs"
     (`git show fceecd88:src/ui/songview.h:161-176`; saved/read at
     songview.cpp:872-923).
   - Retained only across an in-place MIDI reload/replacement:
     `SongTab::beginMidiReload` stashes `viewState()`, `applyMidiStage`
     restores it (`git show fceecd88:src/ui/songtab.cpp:144-188`), with
     the atomic `setState(selection, feel)` restore path (songview.cpp:
     894-903).
   - Every song attach resets to Auto/Straight (songview.cpp:601-605).
   - The persisted application-wide `EditorViewState` (QSettings,
     editorviewstate.h:53-89) contains **no** grid fields.
   - Swift already matches on disk: `EditorViewStateCodec.swift` persists
     no grid keys (verified by grep). The only Swift grid "persistence" is
     the in-memory `ReloadedTab` (`snapScale`/`tripletGrid`,
     SongTabsController.swift:140-141, 151-152), restored today by
     simulating menu opens (ApplicationSession.swift:1037-1046).
   - **Decision (boring option): no migration.** Old `snapScale` values are
     never read and never translated — the invented scale is deleted with
     its storage. `ReloadedTab` carries `grid: RollGrid` (selection +
     feel) instead; restore assigns the session grid directly (fork
     `setState` semantics from task-34a), no menu simulation. Launches and
     fresh tabs start Auto/Straight exactly like the fork. Mapping -4…4
     scale values onto denominations would preserve a model the user ruled
     out, so it is rejected.
4. **Fork menu check to port**: `src/checks/host/tst_rulergridmenu.cpp`
   (687 lines; byte-identical to the ledger's pinned reference, SHA-256
   `050bc30d…`). Key assertions: 6 division rows with ids
   `{-1, 4, 8, 16, 32, 0}` (:147-148); per-row id/enabled/checkable and
   exactly one checked (:150-158); the checked row is the current
   selection's `toMenuId` row and its text equals the division control
   text (:159-165); alternate pick `alternateGridMenuId` (musical(8)↔
   musical(16), `git show fceecd88:src/checks/support/support.h:15-20`)
   updates `viewState().gridSelection == musical(target)` and the control
   text to the picked row's text (:166-180); reopen shows the picked row
   checked (:182-188); feel menu ids {0,1}, checked = current feel, row
   text == control text (:200-217), feel pick flips
   `viewState().gridTriplet` (:219-231); checked-noop closes without any
   state or control-text change (:246-264); Return on the focused division
   control reopens the menu with 6 rows and the checked row (:268-282);
   outside-click and Escape preserve selection, feel, cursor and snap
   (:289-356); menus survive selection/cursor changes (:371-405);
   `closePopups` and a foreign-popup takeover preserve the grid state
   (:414-491).
5. **Current Swift surface to replace**: `PianoGrid.openGridMenu(kind:)` /
   `activateGridMenuRow(actionId:)` accept -4…4 / 0…1
   (PianoGrid.swift:539-564); `refreshGridMenuPresentation` (:566-587)
   renders `"Auto"/"÷N"/"×N"` controls and `"Adaptive"/"Adaptive ÷N"/
   "Adaptive ×N"` rows; `performCommand` gridNarrow/Widen clamp the scale
   (:476-483), gridTriplet toggles the flag (:484-488); metrics rebuild
   preserves the scale (:322-329); `GridRowControl` opens only on click,
   no key handling (EditorSurface.qml:583-638).
6. **Ledger**: `src/checks/host/proof.tst_rulergridmenu.txt` — 166 A rows
   (38 MATCHED, 28 GAP, 100 RETIRED-REPRESENTATION). Every GAP's reason
   cites the snapScale model, the missing `toMenuId` mapping, the
   "Adaptive" row text, the row-text/control-text equality, the
   `viewState().gridSelection` identity, or keyboard reopen. `tst_ShellTabs
   .qml` pins fresh-tab `"Auto"` + straight feel (:1364-1366) and reload
   retention (:1416, 1444-1446) — both survive with fork semantics.

# Exact write set

- `src/swift/app/roll/PianoGrid.swift` — `refreshGridMenuPresentation`
  renders the ladder from `session.grid.ladder(axis)` with fork texts
  (`Auto`, `1/N`, `Clock`; `Straight`/`Triplet`); division control text =
  the checked row's text; `activateGridMenuRow` accepts menu ids via
  `GridSelection.fromMenuId`; `openGridMenu(kind: 1|2)` unchanged in shape;
  `performCommand` `.gridNarrow/.gridWiden/.gridTriplet` become
  `session.grid.narrowed/widened/togglingFeel(axis:)`; publish the current
  selection as `gridSelectionMenuId: Int` (`toMenuId`) for view-state
  assertions; `tripletGrid` published property stays as
  `session.grid.feel == .triplet`; drop the metrics-rebuild scale
  preservation (:322-329 — state now lives on the session).
- `src/swift/app/timeline/GridGeometry.swift` — delete `snapScale`,
  `tripletGrid` and any interim seam left by task-34a.
- `src/swift/app/SongTabsController.swift` — `ReloadedTab` carries
  `grid: RollGrid` instead of `snapScale`/`tripletGrid` (:140-141,
  151-152).
- `src/swift/app/ApplicationSession.swift` — restore assigns
  `session.grid = tab.grid` (atomic selection+feel, no menu simulation;
  :1037-1046); fresh opens rely on the DocumentSession reset from 34a.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — `GridRowControl`
  gains `activeFocusOnTab: true` and `Keys.onReturnPressed`/
  `Keys.onEnterPressed` → `openGridMenu(menuKind)` (fork RulerControls.qml
  :58, 125-126); no other QML change — bindings already read
  `gridDivisionControlText`/`gridFeelControlText`.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — rewrite the grid
  predicates per the mapping below (ladder rows, fork strings, identity,
  keyboard reopen, checked-noop).
- `src/checks/editorqml/tst_ShellTabs.qml` — reload retention asserts
  `gridSelectionMenuId` + `tripletGrid` (fork identity check,
  mainwindowrouting_lifecycle A016/A017 analog); fresh-tab pins unchanged.
- `src/checks/rollcheck/note_commands.swift` (:49-54) and
  `src/checks/rollcheck/selection.swift` (:501-516) — replace the
  `gridWiden` loops with explicit division picks through the production
  menu path (`openGridMenu(kind: 1)` + `activateGridMenuRow(actionId:)`),
  e.g. musical(8) for a 12-tick stride at 24 PPQN.

# Prerequisites

Directly after task-34a (owns `GridGeometry.swift`, `DocumentSession`,
`PianoGrid` snap consumers). After task 32 (PianoGrid typography,
EditorSurface) and task 33 (EditorSurface:9). `ApplicationSession.swift`
is shared with tasks 30/32/33 — take the controller-sequenced slot.
Task 35 (roll pointer parity) rebases on this brief's landed
`rollcheck/selection.swift` (:501-516) and `GridGesture.swift` versions
(sequencing agreed with Brief35RollInput).

# Interface contract

- Division menu rows: one per `session.grid.ladder(axis)` entry, ordered
  Auto, 1/4 … finest representable, Clock; `actionId = toMenuId()`; row
  text = control text = fork `gridDivisionText` (`Auto`, `1/N`, `Clock`);
  exactly one row checked = the live selection; feel menu rows
  Straight(0)/Triplet(1) with the live feel checked.
- Picking a division row sets the selection via the 34a transition
  (canonicalizing against the live feel); picking a feel row sets the feel
  (canonicalizing the live selection); the control text updates to the
  picked row's text; the menu closes; a checked-noop closes with zero
  state, text or snap change.
- `.gridNarrow`/`.gridWiden` move one ladder position (no-op + no repaint
  at either end); `.gridTriplet` runs the 34a `toggleFeel` transition and,
  like the fork standalone operations, survives an active pointer gesture
  (existing policy rows are unchanged).
- Keyboard: Tab reaches both controls; Return/Enter on a focused control
  reopens its menu (A061).
- Reload/replacement retains selection + feel atomically; fresh songs and
  launches start Auto/Straight; nothing grid-shaped is written to
  `EditorViewStateCodec` storage.
- No pixel constants, no code comments, no C++, no palette changes
  (affordance predicates from task 25b stay untouched and green).

# Implementation steps

1. Write the failing mounted predicates first (ladder rows + fork strings
   + identity + keyboard reopen); record RED.
2. Switch `PianoGrid` menu/command code to the session grid; publish
   `gridSelectionMenuId`; delete the last `snapScale`/`tripletGrid`
   references in `GridGeometry.swift`.
3. Replace `ReloadedTab` fields + the ApplicationSession restore path.
4. Add the `GridRowControl` key handling.
5. Re-express the two rollcheck harness setups as division picks.
6. Run the lanes below; report GREEN with predicate messages and
   file:line. The expected-RED lane from 34a (`shell-grid-menu`) must be
   green again.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-grid-menu --verbose`
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:bridge`
- Controller-side after both briefs: `deno task proof check`,
  `deno task proof check --executed`, `deno task proof check
  --strict-mappings` before treating either ledger as closed.

# Visual parity

Counterpart: fork `timeruler.cpp:65-76, 112-125, 225-268`,
`RulerControls.qml:46-160`, `keymap.cpp:156-161`. Mounted evidence is the
shell-grid-menu lane; no dedicated reference capture exists for the grid
controls. Ruler typography/affordance parity belongs to task 32 and task
25b and is out of scope here.

# Task-specific constraints

- Implementers never edit ledgers; the controller delegates
  `src/checks/host/proof.tst_rulergridmenu.txt` (and refreshes the GAP
  reasons in `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
  lifecycle.txt` A016-A017 and `src/checks/rollcheck/proof.identity.txt`
  A013, whose Swift mirrors now exercise the real selection) to the ledger
  agent.
- Fork assertion → Swift predicate mapping (ledger agent: A rows map to
  these `tst_ShellGridMenu.qml` anchors):
  - A009/A062/A112 → `assertRows(divisionMenu, [-1, 4, 8, 16, 32, 0],
    checkedId)` rowCount (mus_route101: 24 PPQN, clock 1).
  - A011 → `assertRows` per-row `actionId`.
  - A015/A054/A063/A113 → the `checkedId` argument of `assertRows` equals
    `grid.gridSelectionMenuId` (the `toMenuId` lookup).
  - A017/A024 → new predicate `rowTextEqualsControlText(divisionMenu)`:
    the checked row's `itemData.text` equals `grid.gridDivisionControlText`
    before and after the pick.
  - A018/A019/A092 → target row located by `actionId ==
    alternateGridMenuId(grid.gridSelectionMenuId)` (8 ↔ 16 helper).
  - A023/A095 → `tryCompare(grid, "gridSelectionMenuId", 8)` after the
    pick (the `GridSelection::musical(targetDivision)` identity).
  - A040/A046/A047 → same text-equality predicate against
    `gridFeelControlText` (`Straight`/`Triplet` rows).
  - A058/A059/A102/A103/A115/A116 → surround the checked-noop,
    closePopups/foreign-menu analogues with `gridSelectionMenuId`,
    `tripletGrid`, `gridDivisionControlText` unchanged-pins.
  - A061-A064 → `keyClick(Qt.Key_Return)` on the focused division control
    reopens with 6 rows and the checked row.
  - A085 → `grid.editCursorTick` pinned across Escape dismissal.
  - Existing MATCHED rows (menu open/close, feel dispatch, affordance,
    timeSig/header menus) keep their current predicates untouched.
- Tooltips and `Accessible.*` on the grid controls are fork surface pinned
  by `src/checks/rollcheck/static/proof.gate.txt` (A045-A051), not by
  tst_rulergridmenu; they stay out of scope and those rows stay open.
