# Task 166 brief — voicegroup switch/null terminates an active velocity gesture

# Context

Replacing or clearing the song's voicegroup while a velocity gesture is held must
terminate the gesture cleanly — preview cleared, bytes/revision/history preserved,
selection semantics intact. The Swift app has no voicegroup-switch cancel plumbing
(the ledger says so explicitly: "voice-replace and voice-null executions have no Swift
equivalent... no voicegroup-switch cancel plumbing"), while the sibling routes
(page-switch, drawer-hide, focus-loss, tab-switch, last-tab-close, song-reload,
escape, primary-track switch, bank edit) all cancel correctly.

Surface: changing or clearing the song's voicegroup (the voicegroup dock's commit
path) during an active drawer velocity gesture.
Ledger spec: `src/checks/host/proof.tst_hostintegration.txt` A114–A120 (PARTIAL), fork
`lifecycleTermination` at pinned revision `c17d966f`,
`src/checks/host/tst_hostintegration.cpp:515-525`: every termination execution
(teardown, bytes/revision/history unchanged, preview cleared, selection cleared or
preserved per route) includes the voice-replace and voice-null inputs. The shell-route
residuals (undo depth and preview emptiness on tab-switch/last-tab-close/song-reload)
ride in the same rows and are provable on the existing mounted termination journey.
`src/checks/host/proof.tst_hostseams.txt` A017's residual Qt bank-pointer identity is
pure representation and retires in this task's commit (the voice slot resolution it
accompanies is re-proved here); that closes the hostseams ledger whole.
Verify lanes: `deno task verify --filter swiftcore-projectsession --verbose` and
`deno task verify:shell --filter shellwindow --verbose`.
Blocked rows left untouched: hostintegration A162, A174–A185 (window close, teardown
ordering); A079/A140 belong to Task 158's ledger and stay out.

# Exact write set

- `src/swift/app/drawer/velocity/` interaction file owning gesture cancellation — the voicegroup switch/null cancel seam, conditional production repair.
- `src/swift/app/DocumentSession.swift` or the bank-adoption path — cancel-on-adopt hook only if the dock's commit path lacks one.
- `src/checks/velocity/VelocityClickCancellationChecks.swift` — voicegroup switch/null termination journeys (beside `drawerVelocityLifecycleCancellation`).
- `src/checks/editorqml/tst_ShellWindow.qml` — the shell-route undo-depth and preview-emptiness conjuncts on the existing termination journey.
- `src/checks/host/proof.tst_hostintegration.txt` — A114–A120 only; `src/checks/host/proof.tst_hostseams.txt` — A017 only.

# Prerequisites

Task 152's bank-adoption contracts are landed and consumed read-only. Disjoint from
158 and siblings. Read sprint-3 §19.

# Interface contract

The voicegroup dock's commit and clear paths (the production commands that adopt a new
bank or remove the argument) cancel the active interaction exactly as the primary-track
switch does (the `VelocityClickSelectionChecks` :301 pattern): gesture torn down,
`frozenPreview` empty, document snapshot/revision/undoCount unchanged, note selection
cleared or preserved per the fork's route table. The mounted termination journey adds
undo-depth and preview-emptiness observations for its existing shell routes.
Independent literals for snapshot/undoCount values.

# Implementation steps

1. Add the cancel hook on the voicegroup switch/null command path.
2. Extend the cancellation checks with replace/null journeys observing the full
   termination contract.
3. Add the two missing conjuncts (undo depth, preview emptiness) to the mounted
   termination journey's existing routes.
4. Close A114–A120 MATCHED and retire hostseams A017's pointer-identity residue in
   the same commit (its ledger closes whole; cite the pinned revision). Compact form
   for closed rows: header + `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Switching or clearing the voicegroup mid-gesture behaves like every other termination
route, and the shell routes prove history depth and preview emptiness.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow --verbose
deno task proof check --executed
```

# Task-specific constraints

No new gesture state machine — reuse the existing cancellation seam. Bank history
legitimately advances on applyBankEdit; the predicates cover song revision, MIDI bytes
and note velocity only, as the landed rows do. `tst_ShellGridMenu*.qml`, the event-list
and drawer QML files of siblings stay untouched.
