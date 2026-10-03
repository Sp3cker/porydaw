# Task 184 brief — automation gestures compare the full document snapshot at every staged mid-point

# Context

The automationgesturecheck and automationselection ledgers keep PARTIAL rows
whose missing conjunct is the same user-visible law: at each staged mid-gesture
point (armed before row rebuild, focus-lost while the grab is still held,
released after a geometry rebuild, recovered after cancellation) the document
compares byte-identical — serialized SMF, revision and undo index/count — and
the committed result carries exact endpoints and lanes. The Swift check hosts
can observe all of it; the rows stayed PARTIAL because no predicate compares
the snapshot at those intermediate points or on those exact fixture intervals.

Surface: automation gesture lifecycle integrity — an interrupted, cancelled,
stale-released or focus-lost gesture never mutates the document mid-flight, and
a committed gesture lands exactly its endpoints in one edit.
Ledger spec:
`src/checks/automationgesturecheck/proof.contract.txt` A063 (PARTIAL — snapshot
immediately after arming before row rebuild);
`src/checks/automationgesturecheck/proof.crosslane.txt` A001/A011 (PARTIAL —
post-hover full snapshot; complete Tempo row at ticks 0/384 after the mixed
drag);
`src/checks/automationgesturecheck/proof.hover.txt` A013 (PARTIAL — frozen
snapshot at focus-lost-while-held);
`src/checks/automationgesturecheck/proof.parity.txt` A007/A010/A011/A015/A016
(PARTIAL — same-tick group order at destination; mounted Shift-ramp endpoints
tick-48 node; pencil one-edit byte/undo comparison; stale release after
geometry rebuild; recovery `isOneEdit`);
`src/checks/automation/proof.automationselection.txt` A124/A131/A132/A133
(PARTIAL — CC-only [96,144)→[144,192) interval, ordered Pan [10,20] at tick144,
LFO [96] at tick144 after the CC-only drag, notification count);
`src/checks/automation/hover/proof.tst_automationhover.txt` A017 (PARTIAL —
frozen document state at focus loss while still held).
All at pinned revision `c17d966f` except automationhover (`proof sites` shows
the row's pinned revision in its header — cite it).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose` and
`deno task verify --filter swiftcore-projectsession --verbose`; mounted legs
under `deno task verify:qml --verbose` if the check lands in a `tst_EditorDrawer*`
suite within this task's own file set.
Blocked rows left untouched: automationhover A108/A121/A123/A126/A133/A143
(MouseHints native source-token identity — no observable Swift surface);
automationgesturecheck contract A001 (every-case Tempo/CC helper sweep),
parity A001/A002 (native rig representation), hover A030's framebuffer clause
(task 183 owns pixel probes); nodedrag/ownership/painting pixel rows (task 183).

# Exact write set

- `src/checks/automation/domain/gestureNodeDrag.swift` — armed/stale/recovery snapshot comparisons.
- `src/checks/automation/domain/gestureSweep.swift` — Shift-ramp endpoint and interval conjuncts.
- `src/checks/automation/domain/gesturePointRange.swift` — conditional, same family.
- `src/checks/automation/automationcanvashover.swift` — focus-loss-while-held frozen snapshot (hover A013, automationhover A017).
- `src/checks/automation/automationselection.swift` and `automationselection_mixed.swift` — the CC-only interval and ordered-lane conjuncts (A124/A131/A132/A133).
- `src/checks/automation/automationcanvasediting.swift` — conditional shared snapshot helper only.
- `src/checks/automation/AutomationPageChecks.swift` — call-list wiring for the new checks.
- `src/swift/app/drawer/automation/AutomationGestureEditing.swift`, `AutomationTransactions.swift`, `AutomationNodeTransactions.swift` — conditional repairs only where a mid-gesture mutation is found.
- The six ledgers above — named rows only.

# Prerequisites

All write-set files are clean at `0504b68b`. Read sprint-3 §22.

# Interface contract

A snapshot is the triple (serialized document bytes, revision, undo
index/count) captured before the gesture stage and compared at the exact fork
point — mid-grab, not after teardown. Selection/lane assertions use the fork's
exact intervals and tick positions. One predicate per clause, each with its
unique complete literal.

# Implementation steps

1. Add a shared snapshot-capture helper (if none exists) in
   `automationcanvasediting.swift` and reuse it; do not duplicate capture code.
2. Add the staged mid-point predicates per row, mapping each clause to one
   predicate.
3. Repair production only where a mid-gesture mutation is proven.
4. Close the named rows in the same commit, compact form.

# Acceptance predicate

Every named mid-gesture point has an executed byte/revision/undo comparison or
endpoint/lane equality, and the automation suites stay green.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No test-only snapshot API on production objects — capture through the existing
document/history surface. Do not touch the raster/painting ledgers or
`tst_EditorDrawer*` QML files beyond this write set (task 183), the velocity or
host ledgers (tasks 180/181), or `EditorDrawer*` layout files (task 182).
