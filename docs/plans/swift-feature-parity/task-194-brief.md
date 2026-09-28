# Task 194 brief — the automation drawer's hint and gesture invariants retire their native-token tails

# Context

`tst_automationhover` (automation/hover ledger) has exactly six open rows,
all PARTIAL and all naming the same residual: fork clauses that read
`hints.currentSource() == plot` — a native `QObject` hint-source token that
has no Swift/QML counterpart. §23 already classifies A108/A121/A123/
A126/A133/A143 as "a native pointer-token identity that has no observable
Swift surface." The mounted drawer lane (`tst_EditorDrawerAutomation*.qml`)
already proves every observable contract behind those tokens: hover publishes
the hint, a real pointer-opened menu suppresses it and owns its modal
underlay, an outside click restores the hint without another plot move, the
Alt fine-grid and in-bounds dip behaviours execute.

`automationgesturecheck` parity keeps two PARTIAL helper guards: A001
(`isOneEdit(before, after) && sameNodePoints(...)`, a completed gesture
commits one edit with the shared node result) and A002 (`isUnchanged(before,
snapshot)`, a parked/cancelled gesture mutates nothing). The per-gesture
predicates exist but are unlabelled; neither row has a message-anchored
predicate that executes the law itself.

Surface: the mounted automation drawer — pointer hover hints, the point menu
underlay, and gesture undo/revision invariance.
Ledger spec: `src/checks/automation/hover/proof.tst_automationhover.txt`
A108, A121, A123, A126, A133, A143 (6 PARTIAL); `src/checks/
automationgesturecheck/proof.parity.txt` A001, A002 (2 PARTIAL), fork
`tst_automationhover.cpp` and `parity.cpp` at their pinned references.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --filter editorqml-drawer --verbose` and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: automation presentation A037 (physical DPR-2
pixels — standing exclusion), every other ledger.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawerAutomationHover.qml` — the executed
  refusal/contract predicates for the source-token rows: after the menu
  closes by real outside click the mounted hint row shows the plot's hint
  text again without another plot move; no hint-source object is published
  or observable at any point.
- `src/checks/automation/domain/tst_automationdomain.swift` and/or
  `src/checks/automation/AutomationPageChecks.swift` — message-anchored law
  predicates for the two parity guards: a completed gesture commits exactly
  one undo revision and the expected node set (A001), a cancelled/parked
  gesture mutates no bytes, revision or undo depth (A002).
- `src/checks/automation/hover/proof.tst_automationhover.txt` — the six
  rows, closed; the ledger reaches zero open rows.
- `src/checks/automationgesturecheck/proof.parity.txt` — the two rows,
  closed; the ledger reaches zero open rows.
- Delete `src/checks/automation/hover/proof.tst_automationhover.txt` and
  `src/checks/automation/hover/tst_automationhover.cpp` (uncompiled in all
  CMake targets), plus `src/checks/automationgesturecheck/proof.parity.txt`
  and `src/checks/automationgesturecheck/parity.cpp`, in the same commit
  once both ledgers close.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24. Confirm at
`fceecd88` (or each ledger's pinned reference) that each retired clause is
genuinely a `hints.currentSource()`/source-token observation and not a text
observation the mounted lane misses — if a clause proves observable text,
close it MATCHED with an executed predicate instead of RR.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections. Fork states unreachable in Swift close as
RETIRED-REPRESENTATION with executed refusal predicates; no test-only APIs
or ingress — the mounted drawer drive stays on real production pointer
ingress.

# Implementation steps

1. Read the six hover clauses in `tst_automationhover.cpp` at the pinned
   reference (`A108` ~:480, `A121` ~:536, `A123` ~:554, `A126` ~:571, `A133`
   ~:638, `A143` ~:650) and map each to its observable consequence.
2. Add the executed refusal predicates to
   `tst_EditorDrawerAutomationHover.qml` (outside-click restores the hint
   without a re-hover; no source object is observable).
3. Add the message-anchored one-edit and unchanged law predicates to the
   automation domain/page checks (A001/A002).
4. Close the six hover rows (RR for source-token clauses; MATCHED only where
   an observable clause is proven) and the two parity rows, compact form, in
   the same commit.
5. Delete the two ledgers and their uncompiled C++ sources.

# Acceptance predicate

`proof check` reports both ledgers closed (files deleted) with 0 errors; the
drawer lane executes the new refusal predicates.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --filter editorqml-drawer --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of both ledgers, of `tst_EditorDrawerAutomationHover.qml`,
and of the automation domain/page check files. Do not touch
`automationgesturecheck`'s retired parity C++ test beyond deletion, the
presentation ledger's DPR-2 row, or any `Shell*Support.qml` shared file.
Deletion waits until the ledger's last open row is closed — never delete a
ledger with open rows.
