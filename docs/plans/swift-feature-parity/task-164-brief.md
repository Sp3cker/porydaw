# Task 164 brief — activating a polyphony event row reveals its note in the roll

# Context

The mounted Event List selects a row but never reveals its note: `EventListTable.qml`'s
row-header click calls `page.selectRow(...)` and requests focus only — the fork's
`headerRevealNote` behavior (activating a raw polyphony event row selects and reveals
the corresponding note in the roll) is missing user-visible behavior. Build it on the
existing Event List surface and prove the fork's reveal/no-mutation contract.

Surface: raw-event row activation in the mounted Event List.
Ledger spec: `src/checks/rollcheck/proof.presentation.txt` A018–A024 (7 PARTIAL), the
ledger's only open rows — fork `PianoRollTest::headerRevealNote` at pinned revision
`02752345`, `src/checks/rollcheck/presentation.cpp:153-181`: a polyphony row activation
selects the track/note and scrolls the roll to it; misses preserve the documented
selection semantics; activation creates no undo history and does not alter exported
MIDI bytes.
Verify lanes: `deno task verify:shell --filter shell-event-list --verbose` (and the
roll-reveal observation through the same mounted window).
Blocked rows left untouched: none in this ledger; the automation raster pixel rows and
every other ledger stay out.

# Exact write set

- `src/ui/songview/quick/EventListTable.qml` — row activation reveals the note (selection + camera reveal) through the existing presenter seam.
- `src/swift/app/eventlist/` (presenter/controller file that owns row actions) — the reveal command only, conditional repair.
- `src/checks/editorqml/tst_ShellEventList.qml` — mounted reveal/miss/no-mutation journeys.
- `src/checks/rollcheck/proof.presentation.txt` — A018–A024 only.

# Prerequisites

None. Disjoint from Task 158 and every sibling brief. Read sprint-3 §19.

# Interface contract

Reuse `EventListPresenter`'s row model and the existing selection APIs; the reveal
routes through the production note-selection and camera-reveal paths the roll already
exposes (the same ones click-selection uses) — no ghost API, no direct grid mutation
from QML. A hit selects exactly the note and moves the camera to its tick/lane; a miss
(row without a resolvable note) leaves selection, revision, history and bytes
untouched; activation never creates an undo entry. Independent literals for the
expected selected note id/tick.

# Implementation steps

1. Add the reveal command on the row-activation path (click/Enter on the row header
   area the fork used), routing through the presenter to note selection + reveal.
2. Extend `tst_ShellEventList.qml` with hit, miss and no-mutation journeys driving
   real input and observing the mounted roll's selection/camera state.
3. Close A018–A024 in the same commit; the ledger's remaining rows are already
   closed, so it is deleted with its already-absent C++ source cited at the pinned
   revision. Compact form for closed rows: header + `Disposition` + one S-citing
   mapping line; no pasted C++/Swift code.

# Acceptance predicate

A user activating a polyphony event row sees its note selected and revealed in the
roll, with no document effects; the presentation ledger closes whole.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-event-list --verbose
deno task proof check --executed
deno task proof list
```

# Task-specific constraints

No new selection subsystem, no Event List menu relabeling, no roll-side edits beyond
consuming its existing reveal API. `tst_ShellWindow*.qml`, `tst_EditorDrawer.qml` and
every sibling ledger stay untouched.
