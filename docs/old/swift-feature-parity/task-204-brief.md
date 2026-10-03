# Task 204 brief — the mounted ruler menu and tab strip adjudicate the action-identity and named-lookup tails

# Context

Four routing rows are reachable on mounted surfaces:

- `input` A091 (`tst_mainwindowrouting_input.cpp:482` at `5f768e34`):
  `QVERIFY(action)` on `m_insertTimeAction` inside the ruler-menu path —
  a native QAction identity. The mounted equivalent is the ShellWindow ruler
  context menu publishing the Insert Time command after a ruler press;
  `tst_ShellWindowPrompts.qml`/`tst_ShellGridMenuRulerLifecycle.qml` already
  mount that path. Adjudicate: MATCHED if a mounted predicate proves the
  menu exposes Insert Time, else RR with an executed refusal predicate on
  the real menu model (no unbound command row publishes).
- `input` A150 (`:152` region — the ruler bounds-containment guard
  `rulerInput->bounds().contains(local)`): the fork verifies the injected
  point lands inside the ruler input before the menu opens. On the mounted
  lane the observable law is the menu opening from a real in-bounds ruler
  press and refusing from outside the ruler — MATCHED or RR per clause.
- `input` A152 (grid/time-signature/camera observation in the same ruler
  section): adjudicate against the mounted ruler/camera surface.
- `native` A069 (`nativeBoundViewTeardownUnbindsActions`, fork
  `tst_mainwindowrouting_native.cpp:285` at `39652ca3`): S192/S193 already
  prove song bytes unchanged across tab close/reopen on
  `tst_ShellTabs.qml`; the residual is "resolving the closed song NAME back
  to an absent tab" — a named lookup over the mounted tab strip. The mounted
  law: after closing, no tab row publishes the closed song's label; reopen
  re-publishes exactly one row for that label. MATCHED if the mounted lane
  executes it (the journey already exists — this row may be a genuine
  message-anchored predicate addition on `tst_ShellTabs.qml`), else RR.

Surface: the mounted ruler context menu and the mounted tab strip.

Ledger spec: `mainwindowrouting/proof.tst_mainwindowrouting_input.txt`
A091, A150, A152 (3 GAP);
`mainwindowrouting/proof.tst_mainwindowrouting_native.txt` A069
(1 PARTIAL → MATCHED or RR).

Verify lanes:
`deno task verify:shell --filter shellwindow-prompts --verbose`,
`--filter shell-grid-menu-ruler-lifecycle`, and the `shell-tabs-*` lane
hosting `tst_ShellTabs.qml` (confirm its entry name in
`ShellQmlEntries.swift` — likely `shell-tabs-open-select`).

Blocked rows left untouched: input's ruled deviations A015/A017/A019 and
fixture-seed GAPs (A088–A090/A120/A123–A125/A146/A147/A166/A169–A174/
A191 — parked, no SessionChecks counterpart); every other native GAP
(Cocoa/QAction/signal-count, native close delivery, `focusWidget`).

# Exact write set

- `src/checks/editorqml/tst_ShellWindowPrompts.qml` — the ruler-menu Insert
  Time publication predicate (A091/A150/A152).
- `src/checks/editorqml/tst_ShellGridMenuRulerLifecycle.qml` — only if the
  ruler lifecycle lane owns the menu-open observation; keep out otherwise.
- `src/checks/editorqml/tst_ShellTabs.qml` — the named-lookup refusal/
  re-publication predicate (A069).
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`,
  `proof.tst_mainwindowrouting_native.txt` — the closed rows only.

# Prerequisites

Read sprint-3 §25, the fork input sites at `5f768e34` (`:482` action
identity, the `:152–`-region bounds/camera guards) and the native site at
`39652ca3:285`. Confirm the ruler menu's real mounted ingress (a real
right-press on the ruler inside the shell window) and the existing S192/
S193 close/reopen journey before writing A069's predicate — reuse the same
journey, don't build a second one.

# Interface contract

One predicate per fork clause with its unique complete literal; each A-id on
exactly one predicate; expectations independent of production projections;
real mounted ingress only; fail-closed staging. RR rows need an executed
refusal predicate on a real guard — the mounted menu/tab strip is that
guard, not a text search.

# Implementation steps

1. Adjudicate the three input GAPs per clause on the mounted ruler menu.
2. Adjudicate A069 on the mounted tab strip.
3. Close the four rows across the two ledgers, same commit.

# Acceptance predicate

The mounted ruler menu and tab strip execute the adjudicated predicates;
`proof check` 0 errors.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-prompts --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-menu-ruler-lifecycle --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-open-select --verbose
deno task proof check --executed
```

# Task-specific constraints

Sole wave-25 writer of the input and native ledgers and the three QML check
files. Do not touch the state ledger (200), lifecycle or workspace ledgers,
or any `Shell*Support.qml`.
