# Context

SH01 menu topology & context-menu shape (task 46). Close the remaining consumer-visible
menu divergence against fork-main `fceecd88`: Edit-menu structure, the three registered
loop actions, the fork note-context shape, canonical wording for the in-canvas ruler/time
menus (deferred by task-38b), and shortcut hints on action-backed quick-menu rows.
Prerequisites landed: 36 (`00b96099`) and 44 (in `f7b04f18`).

1. **Fork menubar** (`git show fceecd88:src/mainwindow.cpp`): File = Open Project...,
   New Song... / Import MIDI... (deferred), Save Song, Register Song (deferred), Close
   Tab, sep, Export WAV... (deferred), sep, Quit (:289-318) — Find Song is **not** a
   File row. Edit (:320-346 + `buildEditMenu` :75-135) = Undo, Redo, sep, then the
   canonical clipboard head **Copy, Cut, Paste, Delete, Select All, Find Song**
   (Find Song borrowed from `workspaceui.cpp:133`), then submenus in order **&Time,
   &Notes, &Move, Tr&acks, &Automation, &Events, &Loop, Trans&port** — Time: Insert
   Time, Delete Time, Duplicate, Clear Time Selection, Edit Time Signature at Edit
   Cursor…, Remove Time Signature; Notes: Transpose Up/Down (Semitone), Up/Down an
   Octave, Edit Note Pitch Bend, Set Velocity…, Duplicate, Split Notes, Join Notes;
   Move: Nudge Left/Right; Tracks: Mute/Solo; Automation: Toggle Pencil Mode; Events:
   Move Event Up/Down (Same Tick); **Loop: Set Loop Start at Edit Cursor, Set Loop End
   at Edit Cursor, Loop from Time Selection, Remove Loop Markers**; Transport: Go to
   Start, Play, Play/Pause, Pause, Stop, Toggle Loop — then sep, Preferences..., Song
   Settings..., Engine Settings... Lengthen/Shorten and the grid rows are never menu
   rows in the fork. View (`:347-382,621-652`) = Event List, three drawers, Polyphony
   Debugger, **sep**, Theme... (deferred), Color Notes by Velocity, Show Note Names.
   Fork Transport submenu excludes Follow Playhead and Suppress Resonances (bar
   actions, `transportbar.cpp:290-310`).
2. **Fork note context menu** (`fceecd88:src/ui/songview/pianoroll_commands.cpp:536-576`):
   Set Velocity…, separator, Copy, Cut, Duplicate, Split, Join, Delete — **no Paste**;
   labels/shortcuts/enablement project the canonical QActions; opens only with a
   non-empty selection. Current Swift: `contextIds` = Copy, Cut, Duplicate, Paste,
   Delete, Split, Join, no separator (`ShellPresenter.swift:109-112`; rendered
   `ShellWindow.qml:759-817` with shortcut hints already drawn :775-801, enabled
   already bound :808-811).
3. **Fork in-canvas menus project the canonical action** — time menu
   (`rangeedit.cpp:814-844`): Copy Selection, Cut Selection, Delete Selection, Insert
   Time, Duplicate, Delete Time, Paste at Edit Cursor, sep, Clear Time Selection;
   ruler cursor menu (`timeruler_interaction.cpp:354-386`): Insert Time, Paste at Edit
   Cursor, sep, Set Loop Start at Edit Cursor, Set Loop End at Edit Cursor, Remove
   Loop Markers, sep, Edit Time Signature at Edit Cursor…, Remove Time Signature;
   ruler selection menu: Loop from Time Selection, Insert Time, Duplicate, Delete
   Time, Clear Time Selection, sep, Remove Loop Markers. Every row carries
   `shortcutText` = the QAction's primary native sequence
   (`quickmenumodel.cpp:44-48`). Swift shape/order already match (38b); only wording
   and the missing shortcut field diverge: `RulerMenuRow` has no shortcut field
   (`RulerMenuPresenter.swift:8-29`) and hardcodes short labels ("Copy", "Paste",
   "Set Loop Start", "Loop from Selection", "Duplicate Time", "Edit Time Signature";
   :123-174), while the canonical wording already lives in
   `KeybindingRegistry.swift:106-177` (exact fork keymap strings).
4. **Loop actions are registered but unmounted**: `edit.set_loop_start`/`set_loop_end`/
   `remove_loop` exist in the registry (:124-127, editorRouted, no default keys) and in
   `EditCommand` (`EditCommands.swift:31-34` with policy rows :231-235), but no
   presenter action mounts them and `NoteCommands` has no arm — availability falls to
   `false` (`NoteCommands.swift:21-33` default) and `execute` returns false (:84-86).
   Fork law (`editkeyrouting.cpp:212-216,369-380`): Set Loop Start/End available with a
   timeline and write one history entry each at the committed edit cursor;
   Remove Loop Markers available iff any marker exists and writes two entries (undo
   restores one marker at a time, end first). `PianoGrid.performCommand` already
   forwards the edit cursor generically (`PianoGrid.swift:496-504`) — no PianoGrid
   change.
5. **Adjudication — the cited `proof.automationpointmenus.txt` rows are foreign.**
   A070/A071 pin the shared-popup fallback time menu; A148–A155 pin the *division*
   menu publishing over a pending automation point menu (takeover, pick, grid
   selection, focus return); A170–A177 pin a foreign popup surviving an open point
   menu; A192–A204 pin parameter-switch prompt invalidation. All are cross-surface
   popup-session arbitration — task-47's automation point-menu remainder and task-50's
   popup-arbitration slice — not menu topology/wording. Task 46 does not touch that
   ledger or the division menu (landed task-34b, `PianoGrid.gridMenuRows`, proven by
   `shell-grid-menu`); the Swift division surface exists, so A155's "no Swift ingress"
   note is stale preamble, not a task-46 work item.
6. **Ledgers serving this task**: `proof.tst_mainwindowrouting_state.txt` /
   `_input.txt` (menu rows ride with surface tasks; most open rows are native
   QAction-wiring representations with no presenter-level observation), S-row
   inventory for the new predicates. `proof.timemenu.txt` / `proof.ruler_loop_menu.txt`
   hold no label-wording rows (grep: no row cites Copy Selection/Paste at Edit/Loop
   from Time wording); their open behavior rows are 38b/38-remainder and stay
   untouched.

# Exact write set

- `src/swift/app/shell/ShellPresenter.swift`* — action labels delegate to
  `KeybindingRegistry.label`; regroup menu id arrays to the fork Edit structure; add
  the three loop actions; split the note-context arrays.
- `src/ui/shell/ShellWindow.qml`* — menubar restructure (File shape, Edit head +
  eight submenus incl. nested Transport, View separator); note-context menu head +
  separator.
- `src/swift/app/timeline/RulerMenuPresenter.swift` — `RulerMenuRow.shortcutText`;
  row text and shortcut text sourced from `KeybindingRegistry`.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — `MenuMeasure.widestShortcut`;
  ruler/time menu panel shortcut column.
- `src/swift/app/roll/NoteCommands.swift` — loop-marker availability + execution arms.
- `src/checks/editorqml/tst_ShellMenus.qml` — topology/label/loop predicates.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — rendered ruler/time wording +
  shortcut-hint predicates (append; existing anchors keep their messages verbatim).
- `src/checks/editorqml/tst_ShellWindow.qml` — only where pinned containment/order
  expectations change (e.g. `test_eTimeAndTracksMenuContainment`, transport-menu
  lookup); anchors keep messages verbatim.
- Ledgers (controller-delegated ledger agent, this task's commit scope): S rows for
  the new predicates; `mainwindowrouting` re-verification only.

No C++, no `PianoGrid.swift`, no `EventListMenus.swift`, no automation/voice-change
menus, no division menu. Sizing exception: one behavior family (menu surface) over 8
files with one verification-surface set.

# Prerequisites

Tasks 36 + 44 landed (satisfied at `f7b04f18`). Consumes 38a/38b's menu semantics
(`RulerMenuPresenter` capture/retirement) unchanged. Dispatch after the current batch
(41/42/47/51) settles: `ShellWindow.qml`/`ShellPresenter.swift` are unowned now, but
task-42 owns `PianoGrid.swift` mid-flight (read-only here).

# Interface contract

- `ShellPresenter.actionLabel(id)` returns `KeybindingRegistry.label(id)` for every
  registry id; `help.about` (not in the registry) keeps "About porydaw". Net visible
  renames: Copy Notes→Copy Selection, Cut Notes→Cut Selection, Paste Notes→Paste at
  Edit Cursor, Delete Notes→Delete Selection, Save→Save Song, Transpose Up/Down→…(Semitone), Transpose Up/Down an Octave→…(Octave). Accepted deviations (record, do
  not code around): fork menubar-local ellipsis/mnemonic style ("Open Project..." vs
  "Open Project", "Preferences..."), "Voice Changes Drawer" (keymap) vs fork menu
  "Voice-change Drawer".
- Menu id arrays (bridged, consumed by `ShellWindow.qml`): `editTopActionIds`
  (undo/redo), `editClipboardActionIds` (roll.copy, roll.cut, roll.paste, roll.delete,
  roll.select_all, songs.find), `timeActionIds` (unchanged), `notesActionIds`
  (roll.transpose_up/down, +/− octave, roll.pitch_bend, edit.set_velocity,
  roll.duplicate_time, roll.split, roll.join), `moveActionIds` (roll.nudge_left,
  roll.nudge_right), `tracksActionIds` (unchanged), `automationActionIds`
  (automation.pencil_mode), `eventsActionIds` (eventlist.move_up, move_down),
  `loopActionIds` (edit.set_loop_start, edit.set_loop_end, edit.loop_from_selection,
  edit.remove_loop), `transportActionIds` (unchanged six + transport.follow_playhead
  last), `editTailActionIds` (edit.preferences, edit.song_settings,
  edit.engine_settings), `contextHeadActionIds` (edit.set_velocity),
  `contextBodyActionIds` (roll.copy, roll.cut, roll.duplicate_time, roll.split,
  roll.join, roll.delete). `fileActionIds` drops `songs.find`. Submenu titles
  qsTr("&Time"/"&Notes"/"&Move"/"Tr&acks"/"&Automation"/"&Events"/"&Loop"/"Trans&port");
  the nested Transport menu keeps objectName "shellTransportMenu"; new objectNames
  shellNotesMenu/shellMoveMenu/shellAutomationMenu/shellEventsMenu/shellLoopMenu.
  `roll.duplicate_time` mounts in both Time and Notes (fork does; objectName
  duplication is accepted — findChild resolves the Time copy first).
- Loop rows: enabled via the generic path (`songOpen && gridCommandAvailable`);
  `NoteCommands.isAvailable` gains `.setLoopStart`/`.setLoopEnd` → true (a mounted
  page implies the fork's timeline gate) and `.removeLoop` → any marker
  (`session.timeline.loopStartTick != TimeDefaults.noTick || loopEndTick != ...`).
  `NoteCommands.execute` arms: setLoopStart/End → `session.document.setLoop(end:_,
  tick: Int64(editCursor))` (one history entry each); removeLoop → clear start then
  end (two entries; undo restores the end marker first). Presenter `Action` entries
  carry the commands; activation rides the existing `performGridCommand` path.
- `RulerMenuRow` gains `public var shortcutText: String = ""`. Row `text` and
  `shortcutText` come from a `KeybindingRegistry` held by `RulerMenuPresenter`
  (action→id map: copy→roll.copy, cut→roll.cut, paste→roll.paste,
  deleteSelection→roll.delete, insertTime→edit.insert_time, duplicate→
  roll.duplicate_time, removeContents→edit.delete_time, clearSelection→
  edit.clear_time_selection, loopFromSelection→edit.loop_from_selection,
  setLoopStart/setLoopEnd/removeLoop→edit.set_loop_start/set_loop_end/remove_loop,
  editTimeSignature→edit.edit_time_signature, removeTimeSignature→
  edit.remove_time_signature). Row ids, order, enablement sources unchanged (38b).
- `MenuMeasure` gains `widestShortcut` (same per-row advance measurement over
  `shortcutText`, skipping separators/empty); the ruler/time `QuickMenuPanel` host
  sets `shortcutRight`/narrowed `textRight`/widened `menuWidth` only when some row
  carries hint text — the `EventListPage.qml:1283` precedent. Fork fromAction
  projection: primary native sequence only, empty string hides the hint (loop and
  signature rows show none).
- Deferred rows stay absent: New Song, Import MIDI, Export WAV, Register Song,
  Import Sample, Theme. Suppress Resonances stays a bar control (no menu row);
  Follow Playhead keeps its verified menu row (task-44) as the Transport submenu's
  trailing seventh row.

# Implementation steps

1. RED in `tst_ShellMenus.qml`: topology predicate (Edit nests the eight submenus in
   fork order; File keeps only its four rows; Find Song lives after Select All),
   label predicate through `actionLabel`, loop-row predicates (below), note-context
   shape predicate. Record RED.
2. `ShellPresenter`: registry-backed labels; regroup arrays; add loop `Action`
   entries; context head/body split; drop `songs.find` from `fileIds`.
3. `NoteCommands`: loop availability + execution arms (contract above).
4. `ShellWindow.qml`: File menu loses the leading separator/insertion arithmetic
   (plain append); Edit gains the submenu chain with the existing
   lazy-activation pattern (declaration order replaces index arithmetic; keep
   `Component.onCompleted` activation); Transport nests under Edit; View gains the
   separator before Color Notes by Velocity; `gridContextMenu` renders
   head + static separator + body Instantiators.
5. `RulerMenuPresenter`: `shortcutText` + registry-sourced wording (no other logic
   change). `EditorSurface.qml`: `MenuMeasure.widestShortcut` + ruler panel column.
6. Update pinned expectations in `tst_ShellMenus.qml`/`tst_ShellWindow.qml`
   (transport title "Trans&port", containment, labels) without touching
   ledger-anchored message strings.
7. GREEN on the lanes below; regressions green.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-menus --verbose` — topology, labels, File
  shape, nested Transport, loop rows: "the Edit menu nests the fork's eight command
  submenus in order", "Find Song moves from File to the Edit clipboard group",
  "the File menu keeps only the mounted file rows", "menu rows show the keymap
  label", "Set Loop Start at Edit Cursor writes one undoable marker at the edit
  cursor", "Set Loop End at Edit Cursor writes one undoable marker at the edit
  cursor", "Remove Loop Markers writes two undo entries restoring one marker at a
  time", "loop rows gate on song and markers", "the note context menu leads with
  Set Velocity and omits Paste".
- `deno task verify:shell --filter shell-grid-menu --verbose` — rendered ruler/time
  wording + hints: "the ruler cursor menu shows the fork row wording", "the shared
  time menu shows the fork row wording", "action-backed ruler rows show their native
  shortcut hint"; 38b's retirement/enablement/insert-time anchors re-run green with
  messages verbatim.
- `deno task verify:shell --filter shellwindow --verbose` — Edit containment and
  shortcut-routing regressions after the restructure.
- `deno task verify --filter swiftcore --verbose` — loop-arm availability/undo
  predicates beside the existing ruler-loop checks.
- `deno task verify:bridge` — new bridged `shortcutText` property.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants; no palette literals; geometry stays base-font multiples.
- Implementers never edit ledgers. Ledger mapping (agent; re-verify at freeze):
  add S rows for the anchors above (no fork A rows pin menu wording, topology, or
  hints — predicate inventory only, like task-43's flash rows); `mainwindowrouting`
  menu rows flip only where a mounted predicate executes the clause, messages
  verbatim, clauses never dropped; the native QAction-wiring representation rows
  stay untouched. `proof.timemenu.txt`/`proof.ruler_loop_menu.txt` open behavior rows
  and all of `proof.automationpointmenus.txt` stay untouched (Context ¶5–6).
- Anchor-message rule: existing test messages that ledger Anchor lines cite keep
  their text verbatim; expected row-label *data* changes with the fork wording.
- The note-context open gesture (selection guard, focus law) is not re-opened here;
  neither are 38b's menu semantics.

# Controller verification

1. Shared baseline: `deno task verify:bridge`, `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings`.
2. Visual smoke (desktop): Edit menu shows the fork chain — clipboard head with Find
   Song, Time/Notes/Move/Tracks/Automation/Events/Loop/Transport submenus, settings
   tail; Loop rows set markers at the cursor and Remove undo one marker at a time;
   right-click a note shows Set Velocity… leading with no Paste; ruler and
   time-selection rows read "Copy Selection"/"Paste at Edit Cursor"/"Loop from Time
   Selection" with ⌘C/⌘V-style hints where keys exist; File shows four rows.
