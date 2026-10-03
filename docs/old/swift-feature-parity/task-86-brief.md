# Task 86 brief — roll ruler/time/note-menu residue closes on the mounted roll

# Context

Task-53 landed the mounted ruler input and menus, task-54 the pencil latch
core; what remains in their ledgers is narrow unproved residue (snap-lattice
guards, exact undo arithmetic, no-write dismissals, rendered-row clicks), plus
the note-command clauses that the same roll surface still executes without
proof. This task closes that residue on the mounted roll: one press-to-focus
production gap, otherwise executed predicates against the already-mounted
ruler menu, time menu, note menu and pencil latch. It is not a remap or
camera task; those rows stay open.

Freeze: HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`; oracle `fceecd88`.
Rebase after 81 lands for the named constructor migration before implementing.

1. **Verified census: 37 open rows (30 PARTIAL + 7 GAP), five ledgers**,
   selected with `deno task proof sites <ledger> --status PARTIAL` and
   `--status GAP` under `src/checks/`:
   - `rollcheck/proof.ruler_loop_menu.txt` PARTIAL (**11**): A003, A036,
     A056, A063, A064, A066, A083, A086, A095, A104, A107.
   - `rollcheck/proof.timemenu.txt` PARTIAL (**8**): A015, A017, A024, A046,
     A047, A050, A076, A087.
   - `rollcheck/proof.pencil_velocity.txt` (**2**): A052 PARTIAL, A047 GAP.
   - `rollcheck/proof.note_commands.txt` (**14**): PARTIAL A004, A009, A012,
     A017, A019, A024, A033, A042, A064 (**9**); GAP A006, A053, A054, A055,
     A056 (**5**).
   - `rollcheck/proof.selection.txt` (**2**): A013 PARTIAL, A034 GAP — both
     are the pencil's velocity-latch establishment, not band-selection law.
   - Excluded on purpose: `proof.remap.txt` and `static/camera|gate|geometry`
     (task 90's separate camera/remap surface), selection band-preview rows
     (A003/A037/A039/A040/A044…), `proof.keyboard.txt` (task 82 owns
     `rollcheck/keyboard.swift` now), clipboard ledgers (88) and automation
     ledgers (85).
2. **Fork laws**, read at `fceecd88`:
   - `src/checks/rollcheck/ruler_loop_menu.cpp:114-130`: the loop fixture's
     start/end ticks sit exactly on the grid snap lattice (`snapTick ==
     tick`), from which chip and insert seams derive (`:244` chip tick,
     `:498` insert ticks).
   - `:312-320`: a rendered click on the disabled Remove-Time-Signature row
     neither dispatches nor mutates bytes/history.
   - `:341-363`: with a time selection active the ruler menu carries an
     enabled Clear row; a real row click closes the menu and drops the
     selection; the rebuilt menu loses its scoped rows.
   - `:420-455`: a document edit or a selection change under an open ruler
     menu retires it and writes no loop marker, byte, undo-index or revision
     change beyond the intervening edit (A083 `:433`, A086 `:448`).
   - `:490-550`: the ruler Insert Time row shifts the selected note to the
     insert end as exactly one undo step (`undoIndex + 1` at `:535`,
     `undoCount + 1` at `:545`).
   - `src/checks/rollcheck/timemenu.cpp:160-188`: the rendered Copy row
     writes a decodable clip whose span is exactly the snap cell and leaves
     bytes, undo index and count unchanged; `:190-210`: a real click on the
     disabled Paste row keeps the menu open and mutates nothing.
   - `:280-315`: every rejected paste variant emits zero cursor moves and
     zero status announcements (`:291-292`); the admitted paste lands a note
     with velocity 90 (`:307`).
   - `:400-413`: retiring the menu on selection loss writes nothing (bytes,
     undo index/count, revision — A076); `:415-467`: the Insert Time row
     commits exactly one undo transaction (A087 `:462`).
   - `src/checks/rollcheck/pencil_velocity.cpp:318-340`: a real press on the
     roll input grants it keyboard focus (A047); `:360-375`: hover publishes
     the host cursor — a sized cursor at a note edge, the arrow cursor on the
     body (A052).
   - `src/checks/rollcheck/note_commands.cpp:143-151,179-196,210-290,296-320,
     361-380,426-445`: duplicate/split/join land as exactly one undo step
     (`undoIndex + 1`, `undoCount + 1`) and note duplication never leaks into
     the time selection (`:150`).
   - `:470-545`: the Quick note menu opens on a right click over a selected
     note, carries the typed command rows (Duplicate/Split/Join), a real row
     click dispatches the command and the menu closes on activation
     (`:503-512`), with the undo arithmetic at `:541`.
   - `src/checks/rollcheck/selection.cpp:150-170,355-375`: the velocity-latch
     fixtures establish note B at 93 through the actual modifier velocity
     drag, not by seeding (A013 `:156`, A034 `:363`).
3. **Current Swift/QML**, verified at the worktree:
   - `src/checks/rollcheck/ruler_loop_menu.swift:10-22` runs the suite;
     `:24-28` `openRulerMenu`; `ruler_loop_menu_loop.swift:7-86` proves loop
     set/undo but never asserts the fixture endpoints through the production
     snap API; `:89-109` signature removal (no disabled-click no-write
     predicate); `:112-143` insert time (identity only, no index/count
     arithmetic); `:145-259` rendered row activation incl. the stale-click
     no-write at `:247-258` (no Clear-row presence/click/drop predicates);
     `ruler_loop_menu_retirement.swift:48-54` proves a disabled row refuses
     `activate` and keeps the menu open.
   - `src/checks/rollcheck/timemenu.swift:62-133` proves copied relTick/pitch
     but not the exact span, and no Copy no-mutation predicate; `:211-306`
     rejected variants assert bytes/selection but count no cursor/status
     publications (the channel exists: `:342-354` counts `.cursor`
     publications and `:282-293` reads `grid.statusText`); `:308-373` admitted
     paste has no velocity-90 predicate; `:129-131` stale duplicate asserts
     identity only; `:19-61` insert lacks the count+1 predicate.
   - `src/checks/rollcheck/note_commands.swift:155-173` duplicate proves
     history identity and one-undo bytes, never `undoIndex + 1`; same shape
     in `:210-243` (`checkKeyboardSplitNotesGrid`), `:245-267`,
     `:268-285` (`:174` equality), `:286-319`, `:320-383`, `:384-452`;
     `:453-524` `checkKeyboardNoteCommandPopupActivation` calls
     `grid.performCommand` directly (`:486`) — no menu session, row or click.
   - `src/checks/rollcheck/selection_editing.swift:8-` (grouped velocity drag)
     and `:138-` (threshold draw cell) read `grid.lastVelocity` but always
     consume the pair seeded at 93/100 by
     `src/checks/rollcheck/selection.swift:35-65` `velocityPairSeed`
     (`:54-59` seeds directly).
   - `src/ui/songview/quick/swiftroll/EditorSurface.qml:484-528` is the
     mounted roll input: `cursorShape` publishes `gridModel.cursorKind`
     zones at `:498-506` (Swift kinds proven by
     `src/checks/rollcheck/resize.swift` S024–S026), but `onPressed`
     (`:508-528`) never grants focus — the press-to-focus law is absent.
   - `src/checks/editorqml/tst_ShellGridMenu.qml:687-737` retargets the
     mounted note menu and `:739-` opens Set Velocity through it; rows are
     addressable (`shellContextAction_<id>` objectNames, `:702`); the lanes
     force focus first (`:286`), so no unforced-press focus proof exists.

# Exact write set

- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — **hot file**; the
  sole production write, limited to the roll-input press focus grant.
- `src/checks/rollcheck/ruler_loop_menu_loop.swift`
- `src/checks/rollcheck/ruler_loop_menu_retirement.swift`
- `src/checks/rollcheck/timemenu.swift`
- `src/checks/rollcheck/note_commands.swift` — **rebase after 81 lands**
  (task-81 migrates the router constructor at `:185-193`).
- `src/checks/rollcheck/selection_editing.swift`
- `src/checks/editorqml/tst_ShellGridMenu.qml` — rebase after task 85's
  accepted Group-A checkpoint; preserve its held-B and point-menu journeys.
- `src/checks/rollcheck/proof.ruler_loop_menu.txt` — the 11 selected rows.
- `src/checks/rollcheck/proof.timemenu.txt` — the 8 selected rows.
- `src/checks/rollcheck/proof.pencil_velocity.txt` — rows A047/A052.
- `src/checks/rollcheck/proof.note_commands.txt` — the 14 selected rows.
- `src/checks/rollcheck/proof.selection.txt` — rows A013/A034.

`ruler_loop_menu_sweep/seek.swift`, `selection.swift`, `pencil.swift`,
`resize.swift`, `SessionChecks.swift`, `tst_ShellWindow.qml`,
`tst_ShellGridInput.qml` (79 owns now), `rollcheck/keyboard.swift` (82 owns
now), `RulerMenuPresenter.swift`/`EditorCommandRouter.swift` (81 owns now),
and every 83/84 file (`ApplicationSession.swift`, `DocumentWorkspace.swift`,
`ShellPresenter.swift`, `ShellWindow.qml`, `EditorViewStateCodec`,
session_view_state checks, `tst_ShellTabs.qml`) are unchanged. No CMake
changes.

# Prerequisites

The settled sprint-3 §8 split. Preserve `RulerMenuPresenter` rows and
`activate(actionId:)`, `AutomationPage.consumeSelectionCommand`,
`session.onChange` domains, `PianoGrid.performCommand` and
`GridClipboard`/`PorydawClip`. Group B follows task 85's
`tst_ShellGridMenu.qml` handoff; `note_commands.swift` work must
**rebase after 81 lands**.

# Interface contract

- **Production (A047):** the mounted roll input grants itself keyboard focus
  on every accepted press — add `rollInput.forceActiveFocus(Qt.
  MouseFocusReason)` at the top of `onPressed` in
  `EditorSurface.qml:508-528`. No other production line changes. Open popups
  keep their own `PopupFocusReason` focus; no forwarding, no focus memory,
  no second dispatcher.
- **Snap lattice (A003/A036/A095):** assert through the production grid API
  (the `PianoGrid`/camera snap the roll already uses) that the loop
  start/end, chip and insert-seam ticks of the existing fixtures are exactly
  snap-aligned, as separate predicates from the note-seeding ones.
- **Ruler menu (A056/A063/A064/A066/A083/A086/A104/A107):** add predicates,
  reusing the presenter the mounted menu drives: disabled-row click refuses
  with bytes/undo-index equality; scoped menu contains an enabled Clear row
  resolved by action id; the activated Clear click closes the menu (anchor
  to the existing rendered-click scenario) and drops the time selection;
  document-edit and selection-change dismissals leave bytes, undo index,
  revision and loop markers exactly at their post-intervening-edit values;
  ruler Insert Time proves `undoIndex + 1`, `undoCount + 1` and the shifted
  note at the insert end.
- **Time menu (A015/A017/A024/A046/A047/A050/A076/A087):** Copy decodes with
  `span == snapCell` and leaves bytes/index/count unchanged; disabled-Paste
  click keeps the menu open and mutates nothing; each rejected paste variant
  counts zero `.cursor` publications and an unchanged `grid.statusText`;
  the admitted paste lands velocity 90 at the snap base; the stale Duplicate
  activation asserts bytes/index/count/revision equality; the Insert Time
  row proves `undoCount + 1` beside the existing identity predicates.
- **Note commands (A004/A009/A012/A017/A019/A024/A033/A042/A064):** each
  named scenario gains its exact `undoIndex`/`undoCount` delta predicate
  (the identity/bytes halves already execute). A006: after note-only
  duplication assert `session.timeSelection == nil` (the sibling
  range-precedence case at `:176-207` stays as is).
- **Note menu rows (A053–A056):** a mounted journey in
  `tst_ShellGridMenu.qml`: right-press a selected note, resolve the typed
  command row through the mounted model (`roll.duplicate`/`roll.split`/
  `roll.join` action ids), real-click the row delegate, assert the command
  outcome (copy one span later / three grid pieces / joined span) and menu
  close. The Swift scenario keeps its document-level twin in
  `checkKeyboardNoteCommandPopupActivation`.
- **Latch establishment (A013/A034):** in `selection_editing.swift`, raise
  note B to 93 through the actual modifier velocity drag (the grid pointer
  path the grouped-drag scenarios already drive) before the pinned
  latch-audition and drag predicates; `velocityPairSeed` and every other
  consumer stay unchanged.
- **Cursor publication (A052):** mounted predicates read
  `swiftRollInput.cursorShape` after real hover moves at a drawn note's
  right/left edge and body: `Qt.SizeHorCursor` at the edges,
  `Qt.ArrowCursor` on the body, matching the proven `cursorKind` zones.
- One literal message anchor per clause above; fork messages stay verbatim
  where a predicate already carries them. No existing message is reworded.

# Implementation steps

1. Stage a different real control with focus, then press the roll without
   forcing roll focus in the check. Add the press-focus and hover cursor
   assertions to the menu journey and the selected semantic predicates to the
   Swift scenarios. The missing grant is source evidence, not a claimed executed
   failure; record the controller-run baseline honestly.
2. Give the existing roll input focus directly on its accepted press, before
   dispatching that press's gesture/menu. Change no other production behavior.
   The named controller lane confirms the completed input path after writers settle.
3. Close the ruler/time menu clauses inside the existing check functions;
   do not fork new fixture builders — reuse `rulerMenuDocument`,
   `openRulerMenu` and the timemenu fixtures.
4. Add the mounted note-menu typed-row journey and its document-level twin
   predicates; then the latch-establishment drag in
   `checkGroupedVelocityDrag`/`checkThresholdDrawCell` staging.
5. After writers settle, attach only the executed anchors to the 37 selected
   rows in the same change. Leave A019–A021 (keyboard), remap, camera and
   band-selection rows open.

# Acceptance predicate

Controller-run on a settled built tree, separate invocations, each at most
180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — snap
  lattice, menu no-write/click/undo arithmetic, clipboard span/velocity,
  zero-emission, note-command arithmetic, no-leak and latch-establishment
  predicates; `build/proof-evidence/swiftcore-projectsession.json`.
- `deno task verify:shell --filter shell-grid-menu --verbose` — mounted
  note-menu typed-row clicks, unforced press focus and cursor-shape zones
  plus existing menu regressions; `build/proof-evidence/shell-grid-menu.json`.

Registration: `src/checks/workspace/SessionChecks.swift:69,72,76,78` calls
the four roll suites; the entry is `swiftcore-projectsession` in
`src/checks/checkcatalog.cpp:107-125`; the menu lane is
`src/checks/editorqml/ShellQmlTests.swift:66-67`; evidence writing is
`tools/run_checks.ts:426-434`. The first lane does not prove rendered
delivery; the menu lane is required even if every Swift predicate passes.

# Task-specific constraints

All **sprint-3 §8 Wave constraints and §9 policy** apply: no new C++, Swift 6.4
idioms on touched Swift, no avoidable allocation/copy, comments at most two
lines; base-font geometry, no hard-coded pixels, WCAG AA beats pixel parity.
Keep sole window keyboard authority: no synthetic forwarding, focus memory,
second dispatcher or bare Space in chrome. One message-anchored predicate per
fork clause, existing messages verbatim, real fixtures/no test-only seams.
No `Qt.callLater` coalescing or idempotence guards; workarounds need user
approval. Deferred menus, parked areas and savecore A016–A026 stay unchanged.

The press-focus grant is direct focus taking on user press, not focus
memory; it must not introduce forwarding or a second dispatcher. Retirement
is not used: every selected row closes on executed behavior. Do not widen
`velocityPairSeed`'s contract or touch the drawer velocity page (task-80/85
territory). No row outside the five named ledgers changes.

# Controller verification

After both lanes have fresh evidence, run `deno task proof check --executed`,
then separately:

- `deno task proof sites rollcheck/proof.ruler_loop_menu.txt --status PARTIAL`
- `deno task proof sites rollcheck/proof.timemenu.txt --status PARTIAL`
- `deno task proof sites rollcheck/proof.pencil_velocity.txt --status GAP`
- `deno task proof sites rollcheck/proof.pencil_velocity.txt --status PARTIAL`
- `deno task proof sites rollcheck/proof.note_commands.txt --status GAP`
- `deno task proof sites rollcheck/proof.note_commands.txt --status PARTIAL`
- `deno task proof sites rollcheck/proof.selection.txt --status GAP`
- `deno task proof sites rollcheck/proof.selection.txt --status PARTIAL`

Expected: all 37 selected rows MATCHED with per-clause anchors; no ledger is
deleted (each retains open rows elsewhere); remap/camera/keyboard and the
clipboard/automation ledgers are untouched.
