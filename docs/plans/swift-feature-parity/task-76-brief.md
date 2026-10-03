# Task 76 brief — shell roll certificate close-out (grid-menu keyboard traversal, transport observation, tabs/drawer parity)

# Context

Task 76 certifies the retired-prototype harness residue against the mounted
shell roll surface and lands the one real behavior it exposes: keyboard
traversal of the note/grid context menu. 63 open rows across
`src/checks/swiftgridprototype/` (the non-pitch rows — the pitch-curve rows
belong to task 75) and `src/checks/swiftrollgated/`. The certificates'
preambles record the retirement facts (C++ originals uncompiled and
unregistered; `src/ui/songview/quick/swiftgrid/` gone — all re-verified this
freeze: zero references in `src/checks/CMakeLists.txt`, `checkcatalog.cpp`,
`fwd.hpp`; the directory does not exist).

1. **Census (verified this freeze by awk over `Disposition:`)**:
   - **Behavior gap — note/grid menu keyboard traversal, 6 rows**:
     interaction_smoke A019/A020 and jurisdiction_smoke A174-A177 (pinned
     `18fee935`). The fork right-clicks a note (multi-selection preserved
     while the menu opens, no truncated labels), then drives Down, Down,
     Return through the menu: the keyboard-activated Delete removes exactly
     the selected notes and no others (interaction_smoke.cpp:200-210);
     Escape closes the menu preserving the selection with no undo entry,
     and idle Escape through the grid input clears the selection without
     history (jurisdiction_smoke.cpp:897-935). Current Swift: the grid menu
     loader (`EditorSurface.qml:886-941`) handles Escape only;
     `QuickMenuPanel` publishes `highlightedRow` (:28) and pointer
     activation through `host.activateRow` (:255/:264) but nothing moves the
     highlight by keyboard. The drawer menus already implement the law
     (`VoiceChangeMenu.qml:37-45`: clamped `moveRow`, Return/Enter
     activates, Escape dismisses, `Keys.onShortcutOverride` accepted). The
     idle-Escape clauses already execute ("idle Escape clears the ephemeral
     selection", "idle Escape is not a history edit",
     `tst_ShellGridInput.qml:517-529`).
   - **Transport/playhead rows — 8 rows, re-verification**: interaction_smoke
     A021-A028 (playing flag, pause stationary, stop, playhead visibility).
     The GAP reasons only checked the certificates' own counterpart lanes;
     the landed transport surface proves the behaviors today
     (`tst_ShellTransport.qml:241` `test_transportControlTransitionsAndSettings`
     — play state, "playing disables duplicate Play", clock;
     `tst_SwiftRollPlayhead.qml` — playhead pixels in the roll plot and
     drawer bodies). Per row: map to the executing predicate or retire the
     harness-internal clause (e.g. `window->property("audio")` session
     lookup).
   - **Representation rows — 43**: `proof.tabchecks.txt` 36 (A031 GAP:
     fork QTabBar DemiBold weight — the Swift strip inherits the published
     body role, task-32 registered deviation; 35 PARTIALs whose behavior
     halves are observed by S010/S012/S015-S021 in `tst_ShellTabs.qml` —
     per-note QQuickItem layer/rect/fillColor internals of the canvas-
     painted shell, C++ signal-spy emission counts, view handles, native
     exposure, model-index persistence, per-row session object identity,
     A288's fixture scratch-restore step); `proof.drawerparity.txt` 7
     (A040 frame-height equality derived from S037's shared anchor; A062
     focus-window handle; A064/A066/A068/A069 QML key acceptance flags
     with resize effects observed by S036; A065 exact spacing step).
   - **Menu-existence rows — 4, mapping-only against landed predicates**:
     gesturechecks A073/A074/A080 (Nudge Right / Delete mounted menu items
     exist and compare enabled state) and clipboardchecks A011
     (Copy/Paste/Undo/Redo items exist). `tst_ShellMenus.qml` now asserts
     the structure (":187-241 the Edit clipboard head follows Undo and
     Redo", "the Move submenu retains the fork actions" with
     `roll.nudge_right`, the note-context shape) and disabled-with-no-song
     enablement (":390-412") — these post-date the GAP reasons.
   - **Blocked rows — 2**: clipboardchecks A017/A023 (QMimeData text beside
     the clip bytes): production `clipboard_host` deliberately moves only
     the application/x-porydaw-clip MIME; the sentinel/preserved bytes are
     MATCHED (S055). Text ownership is the ED11 clipboard-interop surface —
     certificates do not change clipboard behavior. Stays GAP with the
     ED11 blocker named.
2. **Overlap ruling**: task 69 (in flight) owns `tst_ShellMenus.qml` and
   `tst_ShellClipboard.qml`. The 4 menu rows flip mapping-only against
   already-landed predicates; if any enabled-state half needs a new
   predicate in those files, that addition waits for 69 to land. Tasks
   73/74/75 are file-disjoint from this write set; 75 shares the two
   swiftgridprototype ledger files with row-disjoint sections (controller
   serializes the ledger passes).

# Exact write set

- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — the grid menu
  loader Item gains `Keys.onUpPressed`/`Keys.onDownPressed`/
  `Keys.onReturnPressed`/`Keys.onEnterPressed` (+ `Keys.onShortcutOverride`
  accepted while open) driving the panel's `highlightedRow` and the same
  `host.activateRow(panel, row)` path a click takes. Escape handling stays.
- `src/checks/editorqml/tst_ShellGridMenu.qml` — append-only keyboard-
  traversal journey functions (right-press opens the note menu over a
  multi-selection; Down/Down/Return runs Delete; Escape preserves the
  selection and writes no history).
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips in the two swiftgridprototype ledgers (non-pitch rows) and the
  four swiftrollgated ledgers; deletion of each ledger that reaches zero
  open rows (`tabchecks`, `drawerparity`, `gesturechecks` are candidates;
  `clipboardchecks` stays — A017/A023 blocked; the swiftgridprototype pair
  deletes only after task 75's rows also close).

No `tst_ShellMenus.qml`/`tst_ShellClipboard.qml`/`tst_ShellTabs.qml`/
`tst_ShellDrawerParity.qml` edits; no production Swift; no in-flight-owned
files.

# Prerequisites

- The 4 menu rows' verification consumes task 69's settled menu-lane
  predicates if any enabled-state half lacks cover (mapping-only against
  landed predicates may proceed immediately).
- Ledger coordination with task 75 (see its Prerequisites).

# Interface contract

- Grid-menu keyboard law (mirrors the fork QMenu behavior through the
  established `VoiceChangeMenu.qml:37-45` convention):
  - Up/Down move `highlightedRow` clamped to `[0, rowCount-1]` (no wrap),
    scrolling the row into view (`positionViewAtIndex`, already bound to
    `highlightedRow`).
  - Return/Enter activate the highlighted row through
    `host.activateRow(panel, highlightedRow)` — identical command path and
    dismissal as a pointer activation; disabled rows do not activate.
  - While the menu is open it owns keys (`Keys.onShortcutOverride`
    accepted); Escape dismisses (existing).
  - The fork's clause that the keyboard-activated Delete removes exactly
    the selected notes and no others is asserted through the document
    outcome, not menu internals.
- New mounted anchors (message-anchored, one per fork clause):
  - "arrow keys move the grid menu row selection".
  - "Return activates the highlighted grid menu row" (journey: keyboard
    Delete removes exactly the selected notes).
  - "opening the note menu preserves an existing multi-selection".
  - "Escape closes the grid menu preserving the selection without a
    history entry" (if `tst_ShellGridMenu.qml` does not already assert this
    for the note menu — verify first; reuse the existing anchor if so).
- Row dispositions (ledger agent; fork-verified at each ledger's pinned
  revision — swiftgridprototype `18fee935`, tabchecks/drawerparity
  `03a190a0`, gesturechecks `2e8e0879`, clipboardchecks `68209547`):
  - MATCHED: A019/A020 → the traversal anchors; A174-A177 → the Escape
    anchors + the landed `tst_ShellGridInput.qml:517-529` idle-Escape
    anchors; A021-A028 → per-row mapping to the landed transport/playhead
    predicates; A073/A074/A011 (+A080 existence) → the landed
    `tst_ShellMenus.qml` structure anchors.
  - RETIRED-REPRESENTATION (one-line reason citing the observed behavior
    half): the 43 tabchecks/drawerparity rows and any transport row whose
    clause pins the retired harness (`audio` property lookup, native
    playhead item identities).
  - GAP unchanged (blocker named): clipboardchecks A017/A023 (ED11
    clipboard text ownership).
- Preservation contract: pointer menu behavior, menu geometry, dismissal
  laws, and every existing check message in touched files stay verbatim;
  the drawer menus' existing key handling is untouched (no shared-code
  refactor — the grid menu host gets its own handlers over the shared
  panel).

# Implementation steps

1. Re-verify the 4 menu rows against the landed `tst_ShellMenus.qml`
   anchors; record which halves need 69's settled files (if any).
2. Grid-menu keyboard law in `EditorSurface.qml` (RED first: no keyboard
   traversal exists); follow the VoiceChangeMenu convention exactly.
3. Append the journey functions to `tst_ShellGridMenu.qml` driving the fork
   sequence (multi-selection preserved on open → Down/Down/Return → Delete
   removes exactly the selection → Escape preserves selection, no
   revision change). Real key delivery; no synthetic forwarding.
4. Classification pass for the 8 transport rows and 43 representation rows
   against the pinned forks and the landed lanes; produce the rowMap for
   the controller's ledger agent.
5. Run the lanes below.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:shell --filter shell-grid-menu --verbose` — the new
  keyboard journeys plus regressions (macOS host).
- `deno task verify:qml-roll --verbose` — EditorSurface regression (the
  mounted roll lane).
- `deno task proof check --executed` — every new anchor executes.
- RED evidence for the traversal predicates before they pass.

# Task-specific constraints

- No new C++; no code comments; keyboard priority holds — the menu owns
  keys only while open (a modal popup is the sanctioned local exception;
  `Keys.onShortcutOverride` releases on dismissal); no second dispatcher,
  no synthetic forwarding, no focus memory.
- One message-anchored predicate per fork clause; existing messages
  verbatim; no menu-row pixel constants — rows derive from published
  geometry.
- Implementers never edit ledgers; the controller's ledger agent flips the
  rows and deletes each ledger that closes (swiftgridprototype pair only
  after task 75's rows). `clipboardchecks` stays open on A017/A023.
- No drum/program or clipboard-text predicates are invented; blocked rows
  name their blockers.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`; `deno task proof sites --area
   swiftrollgated` shows only `clipboardchecks` A017/A023 open; combined
   with task 75, `deno task proof sites --area swiftgridprototype` shows
   none and both ledgers delete.
2. Confirm `deno task verify:shell --filter shell-grid-menu`,
   `deno task verify:qml-roll`, and (after the 4 menu rows' verification)
   `deno task verify:shell --filter shell-menus --verbose` are green at
   the settled tree.
3. Manual smoke (desktop): right-click a note, navigate with arrows,
   activate Delete with Return, reopen and Escape — menu closes, selection
   intact, one undo restores the notes.
