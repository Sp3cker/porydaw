# Task 144 brief — background-tab isolation, tab close/reopen and fresh-tab identity

# Context

Complete the tab isolation surface in the host family: a background tab's
view-state fanout that touches no song bytes, history or revision; the
second song's history depth across song opens; and the fresh tab's empty
history, selection and preview. Task 138 proved atomic readiness publication
for fresh and retained reload; what is selected here is the cross-tab
non-interference behind that publication plus the fresh-open identity
conjuncts. The Qt signal-count, sidecar-snapshot and project-switch clauses
around them stay open (native harness, project-store), as does the
window-close conjunction deferred below.

Selected **15 open rows (15 GAP + 0 PARTIAL)** across two ledgers. Citations
are assertion-start lines at `fceecd88`, grouped by fork test.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A135, A136, A137 | `src/checks/host/tst_hostintegration.cpp:585,586,588` — `documentMutationUndoRedoAndReloadPreemptPreview` (same-song reopen branch) |
| A150, A151, A152, A153 | `src/checks/host/tst_hostintegration.cpp:651,652,653,654` — `nonSelectedEditorStateFansOutWithoutTouchingSongBytes` |
| A155, A156, A157, A158, A159, A160 | `src/checks/host/tst_hostintegration.cpp:657,658,659,660,661,662` — same test |
| A172 | `src/checks/host/tst_hostintegration.cpp:693` — `projectSwitchAndClosePreserveProjectBoundaries` (song-open history depth only; the test's window-close/bytes conjuncts are deferred, see constraints) |
| A028 (seams) | `src/checks/host/tst_hostseams.cpp:125` — `documentChangedPreservesCosmetics` |

# Exact write set

- `src/checks/workspace/session_view_state_fanout.swift` — cross-tab,
  song-open and fresh-identity predicates (runs inside
  `runSessionViewStateChecks`, projectSession suite).
- `src/checks/editorqml/tst_ShellTabsClose.qml` — mounted background-close
  and close/reopen journeys (existing `shell-tabs-close` entry; no manifest
  change).
- `src/swift/app/SongTabsController.swift` — conditional, only if cross-tab
  fanout fails at its selection/projection boundary.
- `src/swift/app/ApplicationSession.swift` — conditional, only if fanout
  publication or persistence fails at its boundary.
- `src/swift/app/DocumentSession.swift` — conditional, only if view-state
  projection or fresh-identity ownership fails at its boundary
  (`editorViewState`, `selectedNotes`, history).
- `src/checks/host/proof.tst_hostintegration.txt`, `src/checks/host/proof.tst_hostseams.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 138 (atomic readiness, retained state) and 135 (startup recipe)
before reusing tab/close files; preserve their publication and normalization
contracts. Accepted 139–141 before touching shared session files. No
interface depends on the unselected Qt signal counts, sidecar snapshots or
project-switch gates.

# Interface contract

Preserve 138's pending/ready publication and 135's recipe normalization.
Count publication and persistence only through the existing
`onEditorViewStateChanged`/`onEditorViewStatePersisted` callbacks already
used in the fanout file — no new logging or observation API. New predicates
observe, through production tab APIs and the mounted close lane:

- Fanout: applying the fork's state (velocity `{true, 173}`, automation
  `{false, 44}`, voice changes `{true, 149}`, active page VoiceChanges,
  empty lane `{track 0, controller 74}`, lane range 96) on the origin tab
  fires each callback exactly once; both tabs read back the identical state
  while both songs' bytes, revisions and history depths stay exactly
  unchanged (A150–A153, A155–A160).
- DocumentChanged: applying `{velocity {true, 180}, activePage Velocity}`
  then delivering document-changed through all three drawer areas preserves
  the view state exactly (seams A028).
- Song-open depth: opening the second song through the production service
  leaves its history depth exactly at its recorded fresh-open value; the
  differential is captured before the open, never read back from the result
  (A172).
- Fresh identity: reopening the same song through a fresh binding (not 138's
  in-place retained reload) yields zero history depth, an empty note
  selection and a cleared velocity preview (A135–A137).

# Implementation steps

1. Extend the fanout checks with the fork-literal state above; assert exactly
   one changed-callback and one persisted-callback observation, both-tab
   equality and byte, revision and history non-interference from independent
   staged baselines.
2. Exercise the three-area document-changed delivery against the applied
   cosmetic state and assert exact state preservation.
3. Open the second song and assert its exact history depth; reopen the same
   song fresh and assert empty history/selection/preview — in swiftcore and
   through the mounted `tst_ShellTabsClose` background-close and
   close/reopen journeys, never cached plist bytes.
4. Repair only the named tab/session owners at their boundaries; no new
   close protocol, event bus or snapshot mechanism.

# Acceptance predicate

Background-tab fanout touches no song state, song opens preserve history
depths, and fresh tabs start empty — proved in swiftcore and on the mounted
close lane.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-close --verbose
```

# Task-specific constraints

Deferred, not substituted: A174 (window-close acceptance — the fork delivers
`QApplication.sendEvent(window, QCloseEvent)`; the acceptance decision lives
in `ShellPresenter.beginClose`, and no registered lane delivers a real close
to its own harness window) and its bytes conjunction A176/A177. Tab-close
acceptance in the mounted lane does not prove window acceptance.
Preference observations go through synchronized `CFPreferences`/`UserDefaults`,
never plist bytes; the Qt `QSettings` equality lines are proved via the Swift
persistence observation, not a Qt settings read. Expected heights, lane ids
and ranges are fork literals, never fixture read-back. Leave open: A162
setup guard, teardown order A183–A185, project-switch/sidecar/signal-count
clauses, native close rows and transport policy rows. Read sprint-3 §16 for
shared constraints, excluded rows and conditional native retirement.
