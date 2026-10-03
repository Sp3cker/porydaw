# Task 192 brief — the automation drawer's second leave clears hover completely, and point-equality covers Tempo/CC

# Context

Two automationgesturecheck tails are the last unproved clauses of the
mounted drawer hover/gesture contract:

- `proof.hover.txt` A030 (PARTIAL): plot-to-gutter pointer leave clears the
  background hover and hint on the first transition, but the fork's clause
  requires the **complete** guide/ghost/ring/text and framebuffer clear
  immediately on lane transition — including a second leave. S016/S017/S035/
  S041/S048–S055 cover the first transition only; the second-leave predicate
  was added to the task-183 raster plan and is now free to land.
- `proof.contract.txt` A001 (PARTIAL): `sameNodePoints` equality for every
  Tempo/CC case of the original shared NodeLane helper — the Swift point
  predicates cover the mounted cases but not the helper's full Tempo/CC
  matrix.
- `proof.parity.txt` A001/A002 (PARTIAL): the helper-level one-edit/
  unchanged guards whose unproved half is the retired native NodeLane
  pointer delivery — these ride along only if the new predicates genuinely
  discharge them; otherwise they stay PARTIAL as the retired-fixture tail.

Surface: the mounted automation drawer's pointer leave/re-entry and the
point-equality law over Tempo/CC values — user-visible as hover chrome that
fully disappears and gesture outcomes that match the fork's point model.
Ledger spec:
`src/checks/automationgesturecheck/proof.hover.txt` A030, fork
`hover.cpp` at `7430fb42` (`leaveCleared` lane-transition clause);
`src/checks/automationgesturecheck/proof.contract.txt` A001, fork
`contract.cpp` at `7430fb42` (`sameNodePoints` over the Tempo/CC matrix);
`src/checks/automationgesturecheck/proof.parity.txt` A001/A002 only if the
new point predicates discharge their helper guards.
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose` (editorqml-drawer automation selectors) and
`deno task verify --filter swiftcore --verbose` for the point-matrix check.
Blocked rows left untouched: automationhover A108/A121/A123/A126/A133/A143
(native MouseHints source-token identity — no observable Swift surface);
hostadapter A095's same-GUI-pass residue.

# Exact write set
- `src/checks/editorqml/tst_EditorDrawerAutomationHover.qml` — the
  second-leave journey: enter a plot, leave to the gutter, re-enter, leave
  again; assert the published hover state (guide/ghost/ring/text, hint,
  background) is fully cleared on both transitions.
- `src/checks/automation/` domain checks (`gestureSweep.swift` /
  `gestureNodeDrag.swift` / `gesturePointRange.swift`, or a sibling in the
  same directory) — the Tempo/CC point-equality matrix: independent expected
  points computed from the fork's table, not read back from the projection.
- `src/swift/app/drawer/automation/` — conditional repair only if the
  second-leave clear or a Tempo/CC point outcome provably diverges.
- `src/checks/automationgesturecheck/proof.hover.txt` — A030 only.
- `src/checks/automationgesturecheck/proof.contract.txt` — A001 only.
- `src/checks/automationgesturecheck/proof.parity.txt` — A001/A002 only if
  discharged.

# Prerequisites

All write-set files are clean at `85a806f9`. Read sprint-3 §23. The mounted
lane's published hover surface (the properties the QML reads to draw guide/
ghost/ring/text) must be confirmed before writing the second-leave predicate
— observe published state, not private fields.

# Interface contract

The mounted second-leave predicate observes the published hover surface
through real pointer transitions on the mounted drawer. The Tempo/CC matrix
compares the gesture's produced points against independently computed literals
per lane type (Tempo, each CC); one predicate per fork clause with its unique
literal.

# Implementation steps

1. Read `hover.cpp` at `7430fb42` for the leave/transition sequence and the
   `leaveCleared` literal; read `contract.cpp` for the Tempo/CC point cases.
2. Add the mounted second-leave predicate (A030).
3. Add the Tempo/CC point-equality matrix to the automation domain checks
   (contract A001).
4. Repair the publication only where a predicate provably fails.
5. Close A030 and contract A001 in the same commit; sweep parity A001/A002
   only if the new predicates genuinely discharge them, compact form.

# Acceptance predicate

A second plot-to-gutter leave fully clears the drawer's published hover
chrome; the Tempo/CC gesture matrix compares equal to independently computed
points; the named lanes pass with executed evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:qml --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

One predicate per fork clause: the second leave is its own assertion, not a
repeat of the first-leave literal. No test-only hover-state ingress — read the
published drawer surface. Sole wave-23 writer of the three automationgesture
check ledgers and of `src/checks/editorqml/`'s automation hover/drawer tests;
do not touch `tst_EditorDrawerVelocity*.qml` or the velocity checks (181's
files settled at `85a806f9`, but their wave-22 scope is closed).
