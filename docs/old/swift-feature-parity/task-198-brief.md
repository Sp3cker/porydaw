# Task 198 brief — the track-header menu, rename and status-hint footer pin every residual conjunct

# Context

`proof.tst_mainwindowrouting_state.txt` keeps two mounted-surface residual
clusters on the same lane:

- Header menu/rename journey (A188, A204 PARTIAL; A208, A217, A224, A227
  PARTIAL): S235 executes a real header-row menu/rename journey on
  `tst_ShellWindowHints.qml`, but the fork's per-clause conjuncts — model
  row counts ≥1/≥2 at fixture seed, `renamingTrack` becoming the menu track,
  a second-row menu ending an in-progress rename, `finishRename` clearing
  `renamingTrack` — are unlabelled checks without message anchors.
- Status-hint footer (A250, A253, A255, A258, A260 PARTIAL; A262, A263,
  A264, A265, A266, A267 GAP): the fork asserts the status bar's caption
  text tracks the hint source, meter x grows with font, bar height is
  stable, and the caption stays centered/elided. The mounted equivalent is
  the shell hint footer (S237–S239 execute it partially): caption identity
  to the current hint, meter x-offset, footer height stability, and centered
  elision. A262 (`hints.currentSource() == plot`) is the same native
  source-token identity retired by task 194 — RR with an executed refusal
  predicate. Any A263–A267 conjunct with no footer counterpart closes RR the
  same way; each must be adjudicated clause-by-clause, never assumed.

Surface: the mounted shell window's track-header context menu, inline
rename, and hint/status footer.
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
state.txt` A188, A204, A208, A217, A224, A227 (6 PARTIAL, header/rename),
A250, A253, A255, A258, A260 (5 PARTIAL) and A262–A267 (6 GAP, footer), fork
`tst_mainwindowrouting_state.cpp:1166–1582` at `85b97239`.
Verify lane:
`deno task verify:shell --filter shellwindow-hints --verbose`.
Blocked rows left untouched: the state ledger's QAction/edit-action identity
GAPs A094–A099 (native QAction surface — excluded class) and every other
ledger; the input/lifecycle ledgers belong to tasks 197/199.

# Exact write set

- `src/checks/editorqml/tst_ShellWindowHints.qml` — the executed
  message-anchored predicates: row-cardinality guards on the mounted model,
  the rename targeting and lifecycle transitions (`renamingTrack` set,
  second-menu ends rename, finish clears), the caption↔hint text identity,
  meter x-offset under the enlarged font, footer height stability, and the
  centered-elision invariants; plus the executed refusal predicate for the
  hint-source-token clause (A262).
- `src/checks/trackheaders/trackheaderinput.swift` — only if the rename
  model predicates live at the Swift check layer; otherwise untouched.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` —
  the closed rows only.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24 and fork
`tst_mainwindowrouting_state.cpp:1166–1582` at `85b97239` for each clause's
literal. For A263–A267, map every conjunct to a footer-observable property
before deciding MATCHED vs RR; a clause with no observable counterpart needs
an executed refusal predicate, not silence.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections (geometries, texts and counts are the fork's own
values, not recomputed projections). Fork states unreachable in Swift close
as RETIRED-REPRESENTATION with executed refusal predicates; no test-only
APIs or ingress — the menu journey uses real pointer input on the mounted
window; WCAG AA beats parity.

# Implementation steps

1. Read the fork journey and footer sections at `85b97239:
   tst_mainwindowrouting_state.cpp:1166-1582`; tabulate every conjunct.
2. Extend the mounted journey in `tst_ShellWindowHints.qml` with the
   message-anchored row-count, `renamingTrack` transition, caption, meter,
   height and elision predicates.
3. Write the executed refusal predicate for the source-token clause (A262)
   and for any footer-invisible A263–A267 conjunct.
4. Close the seventeen rows in the same commit, compact form.

# Acceptance predicate

The mounted header-menu journey pins each rename transition and the footer
proves caption identity, meter offset, height stability and centered elision
— executed on the shellwindow-hints lane.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-hints --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of the state ledger, `tst_ShellWindowHints.qml` and
`trackheaderinput.swift`. Do not touch the QAction-identity GAPs
(A094–A099), the input/lifecycle ledgers, or any `Shell*Support.qml` shared
file — shared support changes go through the controller first.
