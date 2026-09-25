# Context

PJ06: tab open/reuse/replace/reload/reorder, dirty close/save/discard/cancel,
shared-bank order and restored tab recipe. The scout's ledger audit
(tabs_lifecycle: 74 GAP → 50 COVERED-UNMAPPED, 24 CHECK-GAP, 0 BEHAVIOR-GAP;
tabs_persistence: 36 GAP → 21 COVERED-UNMAPPED, 15 CHECK-GAP) shows this is a
closeout, not a feature build: shell-tabs (`tst_ShellTabs.qml`) and workspace
swiftcore (`session_*.swift`/`bank_*.swift`) already prove the open/switch/
close/dirty-gate/startup-recipe surface; the ledgers simply never cite them.
The remaining 39 GAP rows are missing predicates on production behavior that
already exists (fresh-tab camera/grid/eventList defaults; requestReplacement
and requestReload retention; transport stop on selectTab; undo-after-Cancel;
editorViewState per-tab/relaunch equality).

Goal: close every row in both ledgers, then retire them (the C++ originals are
already deleted). `proof check --strict-mappings` applies: every MATCHED cite
must be a message-anchored predicate.

# Exact write set

- `src/checks/editorqml/tst_ShellTabs.qml` — new test functions for the
  CHECK-GAP surface groups (fresh-tab defaults bundle, replace-in-place,
  reload retention, transport stop on switch, undo-after-Cancel,
  editorViewState equality where the shell lane can observe it)
- `src/checks/workspace/SessionChecks.swift` — orchestration calls only if
  the new predicates land in a workspace file
- `src/checks/workspace/session_view_state.swift` (new, or the nearest
  existing `session_*.swift` — implementer picks, stays under 400 lines)
- `src/swift/app/SongTabsController.swift`, `ApplicationSession.swift` —
  **reload repair authorized** (BEHAVIOR-GAP confirmed during
  implementation: `closeTab → reloadApproved → openTab` drops the tab's
  view state and tab identity; the C++ contract retains both). Scope is
  `closeTab`'s reopen path, `reloadApproved`, `startOpen`/`openTab`, plus a
  minimal view-state capture/apply on `DocumentSession`/`DocumentWorkspace`
  if no existing surface suffices.
- `src/swift/app/roll/PianoGrid.swift` — **initial-home repair authorized**
  (second BEHAVIOR-GAP: `EditorCamera.init` homes `scrollX` to `minHScroll`
  at the 480px placeholder width; `configureViewport`'s one-time
  `didApplyInitialHome` block homes vertical only, so `scrollX` stays at
  the stale −48 home after the real viewport sets leadPad −61 — violating
  `scrollPx == -leadPadPx`, A004). Fix inside that existing block:
  `_ = camera.setHScroll(camera.snapshot.minHScroll)` alongside the
  setVScroll. Do not touch `EditorCamera.reconcile` semantics.

Any BEHAVIOR-GAP beyond these two authorized repairs stops and escalates —
no other production edits.

Controller owns the ledger handoff: `proof.tabs_lifecycle.txt` and
`proof.tabs_persistence.txt` remaps happen after the implementer's checks
pass, via the ledger agent; implementer does not edit proof files.

Confirmed coverage corrections (from the implementer's row audit):
`test_kStartupRestoresTabsAndFreshCamera` does NOT cover persistence
A041–A042 (it sets a lane range but never compares the restored tabs'
`laneRanges`); lifecycle A081 needs an actual `requestUndo` on the untouched
sibling (test_e only asserts `!canUndo` without requesting); A119 needs a
`canUndo` assert **after** Cancel; A128/A129 need explicit clean+`!canUndo`
asserts on the reopened saved song; A083/A084 need a real two-tab song undo
with the sibling observed clean — none of those exist as predicates.

# Interface contract

- New QML tests follow `tst_ShellTabs.qml` conventions: `test_<letter><Name>`
  continuing the suite's lettering (next after test_n), `openShell`,
  `waitForNative`, `verify`/`compare`, `mouseClick` for real button paths,
  `fileFingerprint` for bytes. Assertions name observable state, never
  internals.
- Fresh-tab defaults group (lifecycle A001–A011, persistence A009–A019):
  open a tab through the production shell and assert the DocumentSession
  camera/selection/grid/event-list defaults the original listed: `state.valid`,
  `pxPerBeat`/`keyHeight`/`scrollPx`/`scrollY`/`selectedTrack`/`editCursorTick`,
  `gridSelection` automatic, `!gridTriplet`, `!eventList`/`!eventListVisible`.
  Read them via the existing camera/view-state surface (e.g.
  `DocumentSession.camera`, `sameViewState` bundle); do not invent a new
  debug accessor without a check-side seam.
- Replace-in-place (A043, A047–A049): open a song into a tab, drive
  `requestReplacement`/`openSong` with `newTab=false` through the controller
  (not a fresh `openShell`), assert `openTabCount`/`tabCount` stays 1, the
  label tracks the replacement, and `songTabFor(old)`/page identity resolves
  to the replacement.
- Reload retention (A091, A093–A098): the C++ contract
  (`reloadRetainsCameraAndFreshOpenResetsIt`) keeps the **same SongTab
  pointer** and the seeded view state (`sameViewState`: pxPerBeat, keyHeight,
  scroll, selectedTrack, editCursorTick, gridSelection, triplet, eventList)
  while resetting the undo stack. Implement the repair: `closeTab`'s reload
  path hands the outgoing tab's view-state bundle and tab id to
  `reloadApproved`/`startOpen`/`openTab`; `openTab` applies it to the new
  `DocumentSession`'s camera before the tab installs. Assertions: count/label
  stable, `selectedSongTab`/`songTabFor` resolve to the same tab identity
  (same `tabId`, not just same index), undo stack empty, `sameViewState`
  preserved. The seed-and-land sequence mirrors the original: apply a seeded
  `EditorViewState`, reload, compare `viewState()` for equality.
- Transport stop on switch (A077): play on tab A, selectTab to B, assert
  transport stopped (DocumentWorkspace.deactivate → audio.stop()).
- Undo-after-Cancel (A120–A121): extend the dirty-close journey — after
  Cancel on the gate, perform the undo the site describes and assert the
  dirty/canUndo outcomes.
- Two-tab undo isolation (A081, A083–A084): requestUndo on the untouched
  sibling is a no-op (no inherited history); undo on the edited tab leaves
  the sibling clean and keeps its own history.
- Reopen-clean (A128–A129): after Save+close+reopen, assert the reopened
  document starts clean with `!canUndo`.
- editorViewState (persistence A006, A008, A041–A042): per-tab set/propagate
  and post-relaunch equality — through whichever shell/workspace surface can
  observe it without new debug seams.
- Coverage audit is part of the work: the scout's per-row table is
  directional, not authoritative. Verify every claimed predicate by reading
  it; any row whose claimed predicate doesn't assert the site moves to
  CHECK-GAP and gets a new predicate.
- Every assertion a ledger row maps to must have a message anchor the
  controller's ledger agent can cite (message-literal or function anchor is
  **not** sufficient post-R20; prefer `expect*` calls whose `message:`/`what:`
  strings describe the contract).

# Implementation steps

1. Reload repair first: the view-state capture/apply + tabId preservation in
   `closeTab`/`reloadApproved`/`openTab`, verified by its new assertions —
   this is the one authorized production change.
2. Add the CHECK-GAP predicates (both lanes as needed), run them once to
   confirm they pass. A failure outside the authorized reload repair is a
   BEHAVIOR-GAP → stop, report, do not patch production.
3. Report the new predicate functions with exact `message:`/`what:` strings
   and the file+line each lives at — the controller's ledger agent needs
   verbatim anchors.
4. Report which already-existing predicates cover the COVERED-UNMAPPED rows
   — verify each by reading the predicate, not by trusting the scout table;
   rows whose claimed predicate doesn't assert the site move to CHECK-GAP
   and get new predicates.

# Acceptance predicate

- All previously-GAP rows in both ledgers now have executing predicates, and
  the reload repair is verified by A091/A094/A096/A098-anchored assertions
  (same tabId + retained view state + cleared undo).
- `deno task verify:shell --filter shell-tabs` — new QML tests pass.
- `deno task verify --filter swiftcore` — workspace predicates pass.
- `deno task verify:bridge` — clean.
- After controller ledger handoff: `deno task proof check` + `--executed` +
  `--strict-mappings` show zero remaining sites for both ledgers; both ledger
  files are deletable under the retirement rule in the same commit that
  closes their last row.

Controller-run named checks after the writer freezes:
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:bridge`
- `deno task proof check --strict-mappings` (post-handoff)

# Task-specific constraints

Production edits are limited to the reload repair named in the write set;
any other suspected BEHAVIOR-GAP stops and escalates. No ledger edits by the
implementer. No new lanes/registrations — reuse shell-tabs and
swiftcore. No sleeps/timing hacks; `waitForNative` polling only. Do not touch
`proof.tabchecks.txt` (it already owns the shell-tabs ↔ tabchecks mapping);
the two ledgers in scope are `proof.tabs_lifecycle.txt` and
`proof.tabs_persistence.txt`. Keep predicate messages contract-shaped
("the replaced tab keeps a single entry", not "count == 1").
