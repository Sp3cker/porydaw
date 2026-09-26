# Task 69 — Edit-menu command routing

# Context

1. **Surface**: the Edit-menu command routing surface — every Edit/loop/time
   action's enablement and dispatch per focus origin, observed through the
   production authorities `ShellPresenter.actionEnabled/activate`,
   `EditorCommandRouter.isAvailable/route/perform`, and the
   `KeybindingRegistry` window-vs-editorRouted scopes. Menus, window
   shortcuts, context menus and transport buttons share this authority (plan
   R22); the QML `MenuItem.enabled` bindings follow it and add nothing.
2. **Census (verified this freeze)**:
   `proof.tst_mainwindowrouting_input.txt` — 207 rows: 141 GAP, 54 PARTIAL,
   5 MATCHED, 7 RETIRED-REPRESENTATION. Open rows = 195. Reference revision
   `5f768e3401d74d5df185a6de5692595351156a9d`; Original SHA-256 pinned in the
   header. The fork oracle is `git show 5f768e3:<path>` for this ledger, not
   `fceecd88` (which predates the `mainwindowrouting/` harness split).
3. **Fork clauses** (`tst_mainwindowrouting_input.cpp`, eight test functions):
   `freshTabsWithholdReadinessAndAuditionFromTick` (A001–A019),
   `catalogueViewBindingsReachPersistentQuickFocus` (A020–A049),
   `copyActionRoutesCompleteClipAndTimeSelection` (A050–A072),
   `soloActionUsesSingleWindowOwnerAndRespectsTextFocus` (A073–A087),
   `insertTimeRoutesActiveSongAndRestoresUndoBytes` (A088–A119),
   `insertTimeActionAnchorsSelectionDuringPlayback` (A120–A145),
   `insertTimeRulerMenuAnchorsEditCursor` (A146–A165),
   `deleteTimeActionRipplesScopedAndWholeSongSelections` (A166–A207).
4. **Swift current state**: `ShellPresenter.actionEnabled/activate`
   (`ShellPresenter.swift:226-362`) already gates undo/redo on
   `session.canUndo/canRedo`, grid commands on
   `session.gridCommandAvailable`, event moves on the attached/visible/
   non-editing list gate; proven by `tst_ShellClipboard.qml` (undo/redo/
   copy/paste enablement transitions) and `tst_ShellMenus.qml` (loop gates,
   select-all route, event-move gating). `EditorCommandRouter`
   (`ApplicationSession.swift:1390-1461`) owns time-selection ownership,
   pointer-gesture/modal gates, hover-delete and pencil sync; session entry
   points `gridCommandAvailable/performGridCommand/routeGridKey` and
   `routeEventListCommand/performEventListCommand` (`:502-549`) plus
   `requestUndo/requestRedo` (`:1184-1201`). `KeybindingRegistry`
   (`commands/KeybindingRegistry.swift`) pins the `keymap.cpp:54-185`
   catalogue with window vs editorRouted scopes; `ShellPresenter.windowIds`
   derives from it. PARTIAL anchors already execute in
   `workspace/session_time_routing.swift` (S202 routed insert records one
   undo; S204/S216 zero-span no-ops; S207 seam-parked cursor; S210/S211
   undo-restore and all-track removal).
5. **Partition vs task 65**: the task-65 brief defers all 195 input rows to
   this edit-routing task and owns only state/lifecycle/native plus
   workspace ledgers. Fresh-tab readiness (A001–A019) and catalogue focus
   bindings (A020–A049) overlap 65's window-state surface: if 65 has closed
   them, this task re-verifies without moving them; otherwise they stay GAP
   here and 65's disposition stands.

# Exact write set

- `src/checks/workspace/session_edit_routing.swift` — **new**: copy-clip,
  solo/text-focus, insert-time and delete-time predicates per the contract
  (real `mus_route101` fixture songs through `DocumentSession`, never
  synthetic note bytes).
- `src/checks/workspace/session_time_routing.swift` — promote existing
  PARTIAL anchors (S202/S204/S207/S210/S211/S216) to full-clause predicates
  where the production selection/undo route now proves them; messages stay
  verbatim.
- `src/checks/editorqml/tst_ShellMenus.qml` — menu-row enablement per focus
  origin (hidden vs shown event list, text-focus solo, ruler-menu cursor
  anchor) through `presenter.actionEnabled/activate` only.
- `src/checks/editorqml/tst_ShellClipboard.qml` — copy/paste/undo/redo
  enablement transitions for the clip+time-selection routes.
- `src/checks/keyboard/KeybindingRegistryChecks.swift` — window vs
  editorRouted scope expects for the edit ids exercised here, if not
  already pinned.
- `src/swift/app/shell/ShellPresenter.swift`,
  `src/swift/app/ApplicationSession.swift` — contingent only: narrow
  enablement/dispatch repairs a new predicate proves divergent (record
  RED→GREEN for that fix only); no new stored state, no second dispatcher.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips only in `proof.tst_mainwindowrouting_input.txt`.

No `src/project/` or `external/` changes, no production QML, no settings
surface (`PreferencesStore` untouched — this task owns no persisted state).
Sizing exception: one routing surface over ~6 check files with one
verification-surface set — named for the dispatch table.

# Prerequisites

- Task 65 settles first (shared hot files `ApplicationSession.swift`,
  `ShellPresenter.swift`, `ShellWindow.qml`, `tst_ShellWindow.qml`; 65 owns
  the A001–A049 readiness/focus partition — see ¶5). Serialize; do not run
  concurrently with 65.
- Task 46 landed (fork menu topology in `tst_ShellMenus.qml`); reuse its
  mounted-menu predicates, do not re-prove topology.

# Interface contract

- Unchanged authorities (behavioral additions only, no signature changes):
  `ShellPresenter.actionEnabled(id:) -> Bool` /
  `activate(id:)` — the single availability/dispatch gate, same enabled
  gate as `QAction::triggered`; `EditorCommandRouter.isAvailable(_:)/`
  `route(_:autoRepeat:)/perform(_:)`; `ApplicationSession`
  `gridCommandAvailable/performGridCommand/routeGridKey`,
  `routeEventListCommand/performEventListCommand`, `requestUndo/requestRedo`;
  `KeybindingRegistry.scope(_:)` window vs editorRouted.
- New check anchors (message-anchored, one per fork clause; the `message:`
  strings are the ledger anchors and stay verbatim once written):
  - `sessionEditRouting::copyClipAndTimeSelection` — "copy routes the
    complete clip and time selection".
  - `sessionEditRouting::soloWindowOwner` — "solo uses the single window
    owner and yields to text focus".
  - `sessionEditRouting::insertTimeActiveSong` — "insert time routes the
    active song and restores undo bytes".
  - `sessionEditRouting::insertTimePlaybackAnchor` — "insert time anchors
    the selection during playback".
  - `sessionEditRouting::insertTimeRulerAnchor` — "the insert-time ruler
    menu anchors the edit cursor".
  - `sessionEditRouting::deleteTimeRipple` — "delete time ripples scoped
    and whole-song selections".
  - `sessionEditRouting::freshTabReadiness` — "fresh tabs withhold readiness
    and audition" (only if 65 left A001–A019 open).
  - `sessionEditRouting::catalogueBindings` — RETIRED-REPRESENTATION only
    (native QAction shortcut/tooltip/signal-delivery pins, verified at the
    ledger's Reference revision); any surviving behavior row keeps its GAP.
- Preservation contract: every existing check message in touched files stays
  verbatim; production behavior in `DocumentSession`, `PianoGrid`,
  `AutomationPage`, `EventListPresenter` is unchanged except contingent
  routing repairs recorded RED→GREEN.

# Implementation steps

1. Re-census A001–A049 against 65's landed dispositions; record which rows
   this task owns vs leaves. Catalogue native-action pins
   (shortcut/objectName/shortcutContext/signal delivery) retire in place
   only after fork-verification at `5f768e3`.
2. Add `session_edit_routing.swift`: copy-clip route (complete clip bytes +
   time selection through `consumeSelectionCommand`), solo window-owner +
   text-focus yield, insert-time active-song route with one-undo byte
   restore, playback selection anchor, ruler-menu cursor anchor, delete-time
   scoped/whole-song ripple with seam-parked cursor and one-undo restore.
   Real fixture songs; no test-only seams or synthetic forwarding.
3. Promote the `session_time_routing.swift` PARTIALs whose unproved halves
   (Qt view/byte/selection route) the new predicates now execute; leave the
   rest PARTIAL with the remaining gap named.
4. Add the `tst_ShellMenus.qml` focus-origin rows and the
   `tst_ShellClipboard.qml` clip+time enablement transitions; window
   shortcuts outrank chrome focus per AGENTS.md — no `ShortcutOverride`,
   no focus memory, bare `Space` untouched.
5. Run the lanes below; the per-lane evidence JSONs under
   `build/proof-evidence/` feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — new routing predicates +
  time-routing promotions, no regressions.
- `deno task verify:shell --filter shell-menus --verbose` — focus-origin
  menu enablement rows.
- `deno task verify:shell --filter shell-clipboard --verbose` — copy/paste/
  undo/redo enablement transitions.
- `deno task verify:shell --filter shellwindow --verbose` — no window-state
  regression from contingent routing edits.
- `deno task proof check --executed` — every flipped row cites an executing
  anchor above.
- Runtime prerequisite: macOS (`Platform::MacOS` lanes); native audio not
  required. Coverage gap: pixel-grab/selection-rendering observations have
  no headless lane and stay GAP/Blocked, named per row.

# Task-specific constraints

- No new C++; never `src/project/` or `external/`.
- No code comments — delete stale ones inside edited regions.
- One message-anchored predicate per fork clause; a related passing check
  is never evidence for an uncovered predicate.
- RETIRED-REPRESENTATION only for rows pinning C++/QWidget/QAction
  internals (pointers, `focusWidget` chains, signal counts), fork-verified
  at the ledger's Reference revision `5f768e3`.
- Keyboard priority: window shortcuts outrank incidental chrome focus; no
  second dispatcher, synthetic forwarding, or focus memory.
- Swift owns settings via `PreferencesStore`; this task adds no persisted
  state and does not touch it.
- Implementers never edit ledgers; the controller delegates them to the
  ledger agent. Rows outside this input ledger do not move; the ledger is
  NOT deleted (state/lifecycle/native ledgers belong to 65).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`, then
   `deno task proof sites --area mainwindowrouting` confirms only input rows
   moved and the A001–A049 partition matches 65's dispositions.
2. Confirm `deno task proof sites --area mainwindowrouting --status GAP`
   names only the 65-owned, representation-blocked, or pixel-gated residue
   with per-row reasons.
