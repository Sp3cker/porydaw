# Task 168 brief — a stale time-signature form accepts typed edits and closes harmlessly

# Context

When the song's time signature changes while a time-signature/insert-time form is
open, the stale form must still accept field-level input and close without applying
anything further. The service-level predicate exists (`session_time_routing.swift`
S288: stale acceptance after an intervening edit closes with no further change), but
the mounted delivery clauses are unproved: no QML predicate types Tab-separated
values into the stale form, clicks its OK button, or observes its close.

Surface: the stale time-signature prompt on the mounted roll (grid menu → time
signature → intervening edit → stale form delivery).
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`
A113–A115 (PARTIAL) and A092 (GAP) — fork at pinned revision `5f768e34`
(`src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`): A092 observes the
grid's time-signature segments after the edit (`beatTicks == 1 && beatsPerBar == 3`
at the source tick, `:473-490`); A113–A115 deliver Tab-separated field entry, the OK
click (`insertTimeAccept`), and the close observation on the stale form.
Verify lane: `deno task verify:shell --filter shell-grid-menu-ruler-lifecycle
--verbose` — `tst_ShellGridMenuRulerLifecycle.qml` already hosts the insert-time
prompt journey (`insertTimeAccept` control and `timeSigMenuOpen` state).
Blocked rows left untouched: the ledger's fixture-open guards (A088–A090, A120–A125),
Qt action wiring (A091) and the foreign-window cluster (A031–A058).

# Exact write set

- `src/checks/editorqml/tst_ShellGridMenuRulerLifecycle.qml` — the stale-form typing/OK/close journeys and the time-signature segment observation.
- `src/swift/app/workspace/session_time_routing.swift` — conditional repair only if the mounted journey exposes a divergence.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt` — A092, A113–A115 only.

# Prerequisites

None. Disjoint from every sibling (`tst_ShellWindow.qml` belongs to 166). Read
sprint-3 §19.

# Interface contract

The journey opens the real prompt, performs a real intervening time-signature edit
through the mounted surface, then drives the stale form with actual keyboard input:
Tab between fields, typed digits, the real `insertTimeAccept` click, and the observed
close. The stale acceptance changes nothing further (revision, bytes, cursor, prompt
state); the post-edit grid exposes the new time-signature segments with independent
literal expectations (1 tick, 3 beats per bar at the source tick). No direct
time-signature setter bypasses the surface.

# Implementation steps

1. Extend the existing prompt journey with the intervening edit and observe the
   grid's time-signature segments (A092).
2. Deliver Tab-separated field edits and the OK click on the stale form; observe the
   close and the no-further-change invariants (A113–A115).
3. Close the four rows in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

A stale time-signature form accepts typed input, its OK click closes it, and nothing
further changes — all observed on the mounted surface with real input.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-menu-ruler-lifecycle --verbose
deno task proof check --executed
```

# Task-specific constraints

No new prompt type, no presenter-only substitute for the typed delivery. The ledger's
guards and wiring rows stay GAP/unmapped as they are. Sibling files and ledgers stay
untouched.
