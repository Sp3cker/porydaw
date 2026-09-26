# Context

Ruler live input + loop commands (task 53). The ruler surface is mounted and largely
proven (mounts inventoried in finding 2). The ledgers' open rows are NOT "feature
missing": most GAP reasons ("no ruler menu UI exists in Swift") are stale preamble
predating task-38a/38b (sprint-3 §2 hazard). What remains: four small surface gaps
plus unproved conjuncts split between mounted delivery (QML) and exact byte/history
arithmetic (presenter). Re-verify every mount at freeze.

1. **Fork laws** (`git show fceecd88:src/checks/rollcheck/ruler_loop_menu.cpp`,
   `keyboard.cpp`, `timemenu.cpp`):
   - `rulerLoopMenuSetAndTwoStepUndo` (:119-197): right-press/release opens the menu
     at the release; rendered Set Loop Start/End clicks write one history entry each
     at the snapped/chip press tick; Remove Loop pushes exactly two (undo restores
     the end marker first); Loop from Selection pushes two over a distinct
     selection; activations close the menu first; ordinary (non-prompt) commands
     refocus the ruler band; disabled-row clicks neither dispatch nor dismiss.
   - `rulerLoopMenuEnablementSelectionContext` (:234-362): no markers/selection →
     Remove Loop disabled, scoped rows absent, enabled Insert Time at the cursor;
     explicit-chip press commits the chip's exact tick (enabling Remove Time
     Signature, one undo); a **tick-row** press (band bottom) provably hits no chip
     (row guard), so Remove Time Signature renders disabled there and a click is a
     no-op; Clear Time Selection runs, closes, drops the selection, and the rebuilt
     menu loses the scoped rows.
   - `rulerLoopMenuStaleCancelNoWrite` (:364-479): outside press commits the clicked
     snapped cursor before opening; Escape dismisses with no byte/undo/revision
     change and refocuses the ruler band; document edits and selection changes
     retire an open menu **and return focus to the ruler band**; an outside left
     press dismisses without retargeting or writing.
   - `timelineRulerScope` (`keyboard.cpp:140-311`): plain left-drag past the
     start-drag threshold creates the exact snapped range with primary-only scope;
     Ctrl-drag derives the scope of overlapping note tracks; a time-scoped secondary
     header publishes its selection overlay; a left click outside an active
     selection keeps it; right-drag never creates a selection and its release opens
     the menu (Escape closes).
   - `keyboardTimeSelectionShortcuts` (:414-483): with an active time selection,
     Up transposes covered notes, Right nudges them and advances the selection
     start; a left click on empty roll space inside the selection clears it; note
     selection is not leaked.
   - `timemenu.cpp:216-340`: rejected pastes preserve bytes, revision, undo index/
     count, selection, scope, cursor, camera, status — with **zero cursor-move and
     zero status emissions** — for every entry variant incl. menu-row Paste;
     admitted range paste drops the time selection, advances the cursor by the
     span, one undo entry, undo/redo restore exact bytes; note-clip paste advances
     past the pasted notes (2× snap) and selects them; empty-band Right nudge moves
     start to the next snap tick, end to next+snap, no document edit.

2. **Swift current state**. Implemented, partly proven: sweep + scope
   (`RulerMenuPresenter.beginSweep/updateSweep/endSweep/sweepTrackScope` :314-378),
   deferred open + snap/chip policy (`captureRulerPress`/`openRulerAtRelease`
   :107-158), loop arms (`NoteCommands.swift:30-34, 89-95`), range command routing
   — transpose/nudge/duplicate/paste over the selection
   (`AutomationSelectionCommands.transposeSelection :159-173`, `nudgeSelection
   :136-157`, `pasteClipboard :91-106` drops range selections) — reached from real
   keys via `SongTabs.qml:39-45` → `ShellPresenter.routeEditorKey` →
   `EditorCommandRouter` (`ApplicationSession.swift:1354-1417`); mounted menu tests
   (`tst_ShellGridMenu.qml` `openRulerMenu/openTimeMenu/sweepNoteRange` and the
   escape/loop/chip/clipboard/insert-time functions). Arithmetic available:
   `SongHistory.undoIndex/undoCount` (`SongHistory.swift:234,236`),
   `coreTimeBytes` (`TimeRangeChecks.swift:1195`).
3. **Real gaps**:
   - **Chip row guard missing**: `RulerMenuPresenter.signatureTick(at:)` (:380-393)
     and `ApplicationSession.timeSigChipTick(contentX:)` (:361-365) ignore the press
     row. Fork `timeruler.cpp:597-621` hits chips only inside the marker row
     (`markerRowHeight` = bold ruler metrics height + 1 px; Swift composition
     `PianoGrid.swift:1251-1252`). Today a tick-row press at a chip's X commits the
     chip tick — ledger A053 names exactly this.
   - **Retirement focus law missing**: `onIsOpenChanged` (:140-161) refocuses the
     opening band only when `menuDismissReturnsFocus` (activation/Escape/outside).
     Document-edit and selection-change retirements (`sessionDidChange` :207-212 →
     `close()`) leave focus nowhere — fork row A082 requires the opening band back;
     but a retirement must NOT steal focus another control took (mounted
     `test_rulerClipboardRowsFollowClipAndTimeSelection` :999-1007 pins the
     division control keeping focus across a clipboard-flip retirement). Return
     focus only when the menu host still holds it.
   - **Dead code**: `PianoGrid.routeKey` (:457-469) has zero callers (the session
     router owns routing) and hardcodes `timeSelectionActive: false`.
   - Seed guards are `report.fail` branches, never asserting predicates (rows
     repeatedly GAP on "Open setup obligation").

# Exact write set

- `src/swift/app/timeline/RulerMenuPresenter.swift` — row-guarded chip hit-test.
- `src/swift/app/roll/PianoGrid.swift`* — marker-row height exposure; delete dead
  `routeKey`.
- `src/swift/app/ApplicationSession.swift`* — `timeSigChipTick` gains the press row.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — double-click passes
  `mouse.y`; retirement focus law.
- `src/checks/rollcheck/ruler_loop_menu.swift` — seed/history/bytes/clear-selection/
  chip-row presenter predicates.
- `src/checks/rollcheck/timemenu.swift` — admitted-paste, nudge band end, payload
  detail, seed predicates.
- `src/checks/rollcheck/keyboard.swift` — time-selection transpose/nudge outcomes,
  slot unwind bytes, seed predicates.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — mounted delivery predicates.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  `src/checks/rollcheck/proof.ruler_loop_menu.txt`, `proof.timemenu.txt`, and the
  ruler-scope rows of `proof.keyboard.txt`.

No C++, no `NoteCommands.swift`, no `AutomationSelectionCommands.swift`, no
`ShellWindow.qml`, no `tst_ShellGridInput.qml`/`tst_ShellClipboard.qml` (task-58/49
surfaces; their patterns are reused read-only). Sizing exception: one behavior
family over 8 files, one verification-surface set.

# Prerequisites

Task-41b settled (owns uncommitted `EditorSurface.qml`/`PianoGrid.swift`) and task-52
accepted (same-file chain 52 → 53 serial per sprint-3 §5). Consumes interfaces only:
38a/38b menu semantics, task-46 loop command arms + `KeybindingRegistry` labels.
50a is disjoint but dispatch respects the controller's in-flight ordering.

# Interface contract

- `RulerMenuPresenter.signatureTick(at contentX: Double, pointerY: Double) -> Tick?`
  (internal reshape): returns a chip tick only when `pointerY` lies within the marker
  row; `nil` for tick-row presses regardless of X. `captureRulerPress` (unchanged
  signature, already carries `pointerY`) feeds it. All downstream behavior
  (`openRulerAtRelease` inside/cursor logic, exact-chip commits) unchanged.
- `PianoGrid.rulerMarkerRowHeight: Double` — the bold-typography marker row height
  (the `measured.boldHeight + 1` term of the `:1251` composition), set in the same
  measurement block that writes `rulerHeight`; read by the presenter; no QML
  consumer required.
- `ApplicationSession.timeSigChipTick(contentX: Double, pointerY: Double) -> Double`
  — same row guard (returns -1 for tick-row double-clicks); sole caller
  `EditorSurface.onDoubleClicked` passes `mouse.y`.
- EditorSurface focus law (behavioral): any ruler/time menu dismissal — activation,
  Escape, outside press, retirement via `sessionDidChange` — returns focus to the
  band that opened the menu (`rulerInput` for menuKind 1, `rollInput` for menuKind 2
  via the existing `timeMenuFocus` ownership flag), except when a prompt opened or
  the menu host no longer held active focus. Only the retirement branch changes.
- `PianoGrid.routeKey(command:autoRepeat:)` deleted with no replacement.
- New message-anchored predicates (one per fork clause — slash-joined families below
  expand to one predicate per member; exact messages fixed at implementation,
  recorded for the ledger agent):
  - `tst_ShellGridMenu.qml`: "a sub-threshold ruler press releases as a cursor
    tap, not a selection"; "a ruler drag past the drag threshold creates the exact
    snapped selection"; "a Control ruler drag adds the overlapping track to the
    scope"; "the time-scoped secondary header publishes its selection overlay";
    "a left click outside the time selection keeps it"; "a ruler right-drag creates
    no time selection"; "releasing a ruler right-drag opens the ruler menu";
    "Escape dismisses the right-drag ruler menu"; "the Clear Time Selection row
    closes the menu and drops the selection"; "the rebuilt ruler menu drops
    selection-scoped rows after Clear Time Selection"; "a document edit retires
    the open ruler menu and refocuses the ruler band"; "a selection change
    retires the open ruler menu and refocuses the ruler band"; time-menu Escape
    quartet ("Escape dismisses the time menu", "the time selection survives a
    time-menu Escape", "a time-menu Escape writes nothing", "a time-menu Escape
    refocuses the roll band"); "a conflicting <variant> paste via the rendered row
    emits no cursor movement" / "… no status announcement"; "an admitted range
    paste drops the time selection"; "a left click on empty roll space inside the
    selection clears it"; "Up/Right with an active time selection transposes/
    nudges the covered note".
  - swiftcore `ruler_loop_menu.swift`: seed asserts ("the ruler fixture seeds its
    snap-aligned range", "the ruler insert fixture seeds its shifted note"); undo
    arithmetic ("Set Loop Start writes exactly one undo entry", "Set Loop End/
    Remove Loop Markers/Loop from Selection advance the undo index by exactly
    one/two/two", "removing an explicit time signature writes exactly one undo
    entry"); byte equality ("the ruler loop round trip restores the exact song
    bytes", "dismissing the ruler menu preserves the exact song bytes and history
    depth", "a document-edit dismissal writes no loop marker", "a selection-change
    dismissal writes no markers", "an outside-press dismissal preserves the exact
    song bytes and history depth"); chip row guard ("a tick-row ruler press
    ignores the signature chip", "a marker-row press commits the chip's exact
    tick").
  - swiftcore `timemenu.swift`/`keyboard.swift`: ("the rejected-paste fixture
    seeds its note at the track and tick", "the time-shortcut fixture seeds its
    covered note"); ("an admitted range paste advances the cursor by the clip
    span", "an admitted note-clip paste advances the cursor past the pasted
    notes", "an admitted paste publishes exactly one cursor move and one status
    announcement", "one undo and redo restore the exact song bytes after an
    admitted paste"); ("an empty-band nudge moves the start to the next snap
    tick", "… the end to start plus the band length"); ("Up over an active time
    selection transposes the covered notes", "Right over an active time selection
    nudges the covered notes and advances the band start", "the scenario unwind
    restores the slot's post-seed bytes").
- Preservation: menu row sets/order/enablement (38b), activation
  close-before-dispatch, insert-time prompt flow, sweep snapping/threshold
  semantics, existing objectNames, and every ledger-anchored message already cited
  by S rows stay verbatim and green.

# Implementation steps

1. RED in `tst_ShellGridMenu.qml`: chip row guard (tick-row press at a chip's X →
   cursor lands on the snapped background tick, Remove Time Signature disabled while
   the chip exists), retirement refocus, right-drag refusal, drag threshold, clear
   sequence, time-menu Escape quartet. RED in presenter checks for the undo-index
   and byte conjuncts. Record RED.
2. Surface: `PianoGrid.rulerMarkerRowHeight`; row-guard
   `RulerMenuPresenter.signatureTick(at:pointerY:)`;
   `ApplicationSession.timeSigChipTick(contentX:pointerY:)` + `onDoubleClicked`
   passes `mouse.y`; delete `PianoGrid.routeKey`.
3. Surface: retirement focus law in `EditorSurface.qml` — the menu host item tracks
   whether it still holds active focus; `onIsOpenChanged`'s no-`returnFocus` branch
   refocuses the owning band only under that condition and the existing no-prompt
   guards. Keep the clipboard-retirement case (focus already elsewhere) un-stolen.
4. Presenter checks: `ruler_loop_menu.swift` — convert fixture `report.fail`
   guards to `report.expect` seed predicates, add the exact undo-index/count +
   `coreTimeBytes` conjuncts around existing loop/chip/insert activations, add
   clear-selection, dismissal no-write, chip row-guard, slot-unwind predicates;
   `timemenu.swift`/`keyboard.swift` — admitted-paste outcomes (cursor advance,
   selection drop, single-emission counting via a session state-change observer
   installed around the activation), empty-band nudge exact arithmetic,
   copied-range payload relTick/key conjuncts, time-selection transpose/nudge
   outcomes through `consumeSelectionCommand`, seed asserts.
5. Mounted checks (`tst_ShellGridMenu.qml`): drag-threshold pair; Ctrl-drag scope
   via the secondary header overlay (`TrackHeaderBand` row `overlayColor`, derived
   from `session.selectedTracks` — `TrackHeadersGeometry.swift:235-237`,
   `DocumentSession.swift:227-230`; locate or pencil-draw an overlapping
   second-track note, fixture assert); right-drag → release-menu → Escape; outside
   left click keeps selection; Clear Time Selection click/close/rebuild sequence;
   document-edit retirement (commit one loop write, reopen the menu, trigger the
   Undo window shortcut — a real document edit — assert retirement + ruler-band
   focus + marker gone); selection-change retirement (a second sweep); time-menu
   Escape quartet; rejected/admitted Paste row clicks with `GridInputClipProbe`
   clips + `SignalSpy` on `editCursorTickChanged`/`statusTextChanged` (the
   `tst_ShellClipboard.qml:254-280` pattern, new instantiation of the existing
   probe type); empty-cell click clears selection (via `grid.gridCommandAvailable
   (17)` and menu row sets); roll-band `keyClick` Up/Right over an active selection
   asserting `noteSummary` deltas.
6. GREEN on the lanes below; regressions green; ledgers close per the mapping.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-grid-menu --verbose` — all new mounted
  anchors above plus the existing 38a/38b/46 anchors verbatim.
- `deno task verify --filter swiftcore --qt projectSession --verbose` — rollcheck
  suite executes the presenter predicates; then `deno task verify --filter swiftcore
  --verbose` full-suite green.
- `deno task verify:shell --filter shell-clipboard --verbose` — clipboard lane
  regression (probe semantics, retirement non-interference).
- `deno task verify:shell --filter shellwindow --verbose` — ShellWindow lane
  regression (EditorSurface focus-law edit ripples).
- Runtime prerequisite: macOS window server for the QML lanes (real mouse/key
  delivery); human desktop stays idle during runs (AGENTS.md).

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants (marker-row height derives from measured typography); geometry stays
  base-font multiples; no palette literals in QML.
- One message-anchored predicate per fork clause; existing anchored messages
  verbatim. Implementers never edit ledgers; the controller delegates to the ledger
  agent:
  - `proof.ruler_loop_menu.txt` (61 open: 30 GAP + 31 PARTIAL): every row maps to
    the new anchors or upgrades its PARTIAL — rendered open/click/close delivery →
    mounted anchors; exact undo-index deltas and byte equality → swiftcore anchors;
    focus-after-retirement → mounted retirement anchors; A051 single-command depth,
    A053 chip-present tick-row fixture, A056 byte+undo no-op, A064–A068 clear/
    rebuild sequence, A077/A083/A086/A092 no-write equality, A099–A113 conjunct
    completion. Seed-guard rows (A001, A003, A036, A069, A071, A093, A095–A097)
    flip on the seed-assert anchors.
  - `proof.timemenu.txt` (33 open): A027/A028 (native `QSignalSpy` validity
    guards) and A065/A066 (native `focusTimelineBand`/`QGuiApplication`
    focus-identity guards) → `RETIRED-REPRESENTATION`, one-line reasons (precedent:
    the ledger's A019/A067/A069); the behavior they guarded is covered by the
    emission-count and Escape anchors. A001/A002/A025/A026/A068/A078/A099 seed
    guards flip on seed asserts; A005/A011/A029 on the mounted time-menu open
    anchors; A015–A017/A024/A046/A047/A051–A060/A070–A076 on the named anchors.
  - `proof.keyboard.txt` — ONLY the 29 ruler-scope rows: `timelineRulerScope`
    A019–A039 and `keyboardTimeSelectionShortcuts` A050–A053/A055/A057–A060.
    A033/A034 (native header-band framebuffer recapture/repaint pixel comparison)
    → `RETIRED-REPRESENTATION`; A037/A038 (native popup open / host Escape) map to
    the mounted right-drag and Escape anchors (the "no Swift window" preamble is
    stale); A022/A023 (header records guard) stay open for task-66's headers
    surface. `timelineOtherEventsStrip` A040–A046, `timelinePartialSelectionRepaint`
    A047–A049, `timelineDuplicateTime` A061–A067, `timelineInsertBlankTime*`
    A071–A088 and all non-ruler functions stay untouched (58/64 own them).
- RETIRED-REPRESENTATION only for the rows named above (native harness internals),
  each with a one-line reason, inside this task's commit.
- Both `proof.ruler_loop_menu.txt` and `proof.timemenu.txt` target all-rows-closed;
  when the last row is MATCHED/RETIRED, delete both ledger files in the same commit
  (their C++ originals are already deleted at `67544720`). Any row that cannot close
  keeps a named reason — never a silent GAP.

# Controller verification

1. Shared baseline: `deno task verify:bridge` (bridged `rulerMarkerRowHeight`,
   reshaped `timeSigChipTick`), `deno task format --check`,
   `deno task proof check`, `deno task proof check --executed`,
   `deno task proof check --strict-mappings` — ruler_loop_menu/timemenu rows show
   executing anchors; keyboard ruler rows flip; no unmapped MATCHED sites.
2. Re-run `deno task verify:shell --filter shell-grid-menu --verbose` on the settled
   tree; confirm the focus-law predicates (retirement refocus + clipboard-retirement
   non-steal) and the chip row-guard predicates pass together.
3. Native smoke (desktop): right-click the ruler → Set Loop Start/End at the
   cursor, Remove Loop Markers undoes one marker at a time; a tick-row press at a
   4/4 chip's X commits no chip (Remove Time Signature disabled) while a top-row
   double-click opens the prompt; Escape/outside click dismiss and return keyboard
   to the band; Ctrl-drag highlights the second track's header; with a swept
   selection ↑/→ edit the covered notes; ⌘V via the time menu drops the selection
   and lands pasted content.
