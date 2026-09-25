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
- `src/swift/app/SongTabsController.swift`, `DocumentSession.swift`,
  `DocumentWorkspace.swift`, `ApplicationSession.swift` — **only** if a
  CHECK-GAP proves the production path is actually missing (scout found none;
  any such find escalates to controller before editing)

Controller owns the ledger handoff: `proof.tabs_lifecycle.txt` and
`proof.tabs_persistence.txt` remaps happen after the implementer's checks
pass, via the ledger agent; implementer does not edit proof files.

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
- Reload retention (A091, A093–A098): seed a view-state bundle, reload through
  `requestReload`/`reloadApproved`, assert count/selection/`songTabFor`
  unchanged, undo stack cleared, `sameViewState` preserved.
- Transport stop on switch (A077): play on tab A, selectTab to B, assert
  transport stopped (DocumentWorkspace.deactivate → audio.stop()).
- Undo-after-Cancel (A120–A121): extend the dirty-close journey — after
  Cancel on the gate, perform the undo the site describes and assert the
  dirty/canUndo outcomes.
- editorViewState (persistence A006, A008, A041–A042): per-tab set/propagate
  and post-relaunch equality — through whichever shell/workspace surface can
  observe it without new debug seams.
- Every assertion a ledger row maps to must have a message anchor the
  controller's ledger agent can cite (message-literal or function anchor is
  **not** sufficient post-R20; prefer `expect*` calls whose `message:`/`what:`
  strings describe the contract).

# Implementation steps

1. Add the CHECK-GAP predicates first (both lanes as needed), run them once
   to confirm they pass — these are missing checks, not missing behavior;
   a failure here is a BEHAVIOR-GAP → stop, report, do not patch production.
2. Report the new predicate functions with exact `message:`/`what:` strings
   and the file+line each lives at — the controller's ledger agent needs
   verbatim anchors.
3. Report which already-existing predicates cover the 71 COVERED-UNMAPPED
   rows (the scout's table names them; the implementer verifies each by
   reading the predicate, not by trusting the table).

# Acceptance predicate

- All 39 previously-unproved rows now have executing predicates.
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

No production edits unless a CHECK-GAP exposes a real behavior gap (then stop
and escalate — this task proves surfaces, it does not repair them). No ledger
edits by the implementer. No new lanes/registrations — reuse shell-tabs and
swiftcore. No sleeps/timing hacks; `waitForNative` polling only. Do not touch
`proof.tabchecks.txt` (it already owns the shell-tabs ↔ tabchecks mapping);
the two ledgers in scope are `proof.tabs_lifecycle.txt` and
`proof.tabs_persistence.txt`. Keep predicate messages contract-shaped
("the replaced tab keeps a single entry", not "count == 1").
