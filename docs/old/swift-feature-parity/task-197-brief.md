# Task 197 brief — the ruler Insert Time route and the velocity-toggle focus pin their residuals

# Context

`proof.tst_mainwindowrouting_input.txt` keeps three residual clusters that
the mounted shell already drives but has not proven clause-by-clause:

- A154–A165 (12 PARTIAL, the ruler-menu Insert Time journey): S232 stages
  the live prompt (open, type 0/1/0, accept) and S233 observes document
  state, but the fork's per-clause conjuncts — real click on the Insert Time
  row, prompt window open, field edits landing, accept button, popup closed,
  `undoStack.index + 1`, `revision + 1`, the shifted note's tick, and both
  documents' exact SMF bytes — lack executed message-anchored predicates.
  `session_edit_routing.swift` already stages this route; the residuals pin
  each conjunct inside it.
- A036/A037 (2 PARTIAL): the mounted `A` shortcut while the velocity toggle
  is focused tests its `activeFocus` without a message anchor, and the
  native `QQuickWindow.activeFocusItem` pointer identity has no Swift
  surface. A036 gains the executed message-anchored predicate on the focused
  toggle itself; the native pointer-identity conjunct closes
  RETIRED-REPRESENTATION with an executed refusal predicate (QML publishes
  `activeFocus` semantics, not item pointers).
- A152 (1 GAP, `snapTick` equality): include only if the mounted ruler
  journey observes the snapped target; otherwise it stays GAP.

Surface: the mounted shell — the ruler context menu's Insert Time prompt and
keyboard focus on the velocity chrome.
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
input.txt` A154, A155, A156, A157, A158, A159, A160, A161, A162, A163, A164,
A165 (12 PARTIAL), A036, A037 (2 PARTIAL), optionally A152 (1 GAP), fork
`tst_mainwindowrouting_input.cpp:808–925` (`insertTimeRulerFlow`),
`:225–240` (shortcut focus), at the pinned reference `5f768e34`.
Verify lanes:
`deno task verify --filter swiftcore --verbose` (edit routing),
`deno task verify:shell --filter shellwindow-focus --verbose`, and
`deno task verify:shell --filter shellwindow-prompts --verbose` /
`shellwindow-time-editing` wherever the mounted prompt is driven.
Blocked rows left untouched: the input ledger's fixture-open/seed guards
(A088–A091, A120, A123–A125, A146–A147, A150, A166, A169–A174, A191 —
`swift-project-store` family), the ruled-deviation rows A015/A017/A019
(deliberate text-chrome focus retention; cursor commits never seek — same
standing exclusion as transport A009–A013), and every other ledger.

# Exact write set

- `src/checks/workspace/session_edit_routing.swift` — the Insert Time
  residual predicates: exactly one undo and one revision, the shifted note's
  tick, both documents' byte equality around the commit (A159–A165 family),
  each message-anchored.
- `src/checks/editorqml/tst_ShellWindowFocus.qml` — the message-anchored
  focused-toggle predicate (A036) and the executed refusal predicate for the
  native pointer-identity conjunct (A037 RR half).
- `src/checks/editorqml/tst_ShellWindowPrompts.qml` and
  `src/checks/editorqml/tst_ShellWindowTimeEditing.qml` — only if the
  mounted Insert Time prompt journey lives here; otherwise untouched.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` —
  the closed rows only.

# Prerequisites

All write-set files are clean at `b97c1c01`. Read sprint-3 §24 and fork
`tst_mainwindowrouting_input.cpp:808–925` at `5f768e34` for the staged flow.
Confirm the ruled-deviation boundaries: the playhead-seek conjuncts
(A017/A019) stay PARTIAL and are **not** re-pinned or altered — only the
prompt/route/focus clauses in scope.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; a fork require/QVERIFY with conjuncts is ONE
predicate per iteration even inside a loop over surfaces/routes — never
split one clause across several predicates and never fold a clause into
another row's predicate. Expectations are independent literals, independent
of production projections (the shifted tick and byte snapshots come from the
fork's own literals/document bytes, not a re-projection). Fork states
unreachable in Swift close as RETIRED-REPRESENTATION with executed refusal
predicates; no test-only APIs or ingress — the prompt is driven by real
menu/pointer input on the mounted window.

# Implementation steps

1. Read the fork flow at `5f768e34:tst_mainwindowrouting_input.cpp:808-925`
   and list each clause's exact literal.
2. Extend `runEditRoutingChecks`' Insert Time case with the message-anchored
   residual predicates (undo index +1, revision +1, shifted tick, both
   documents' bytes).
3. Pin the mounted prompt clauses (real row click, open, edits, accept,
   closed) in the lane that mounts the prompt.
4. Add the focused-toggle predicate in `tst_ShellWindowFocus.qml`; write the
   A037 refusal predicate.
5. Close the rows in the same commit, compact form — MATCHED where executed,
   RR for the native pointer identity.

# Acceptance predicate

The mounted ruler Insert Time journey commits exactly one undo/revision,
shifts the seeded note by the inserted span, and leaves the inactive
document's bytes identical; the velocity toggle holds visible focus through
the `A` delivery.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-focus --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-prompts --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-24 writer of the input ledger, `session_edit_routing.swift`,
`tst_ShellWindowFocus.qml`, `tst_ShellWindowPrompts.qml` and
`tst_ShellWindowTimeEditing.qml`. Do not touch ruled-deviation rows
(A015/A017/A019), the `swift-project-store` fixture guards, or any
`Shell*Support.qml` shared file.
