# Task 175 brief — command enablement refuses the unbound-with-selection state

# Context

The fork could explicitly unbind its editor target (`rebind(null)`) and observe
Copy/Solo/Insert Time/Delete Time enablement in that unbound-with-selection state.
The Swift app has no rebind seam by design — actions bind to the live session, and
when no song is open the enablement surface refuses everything. Under the sprint's
unreachable-fork-state ruling (159/168 precedent), those rows close as
RETIRED-REPRESENTATION with refusal predicates proving the guard.

Surface: shell command enablement with no open document (the menu/shortcut authority
every window action routes through).
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt`
A087–A091 (5 GAP), fork `tst_mainwindowrouting_state.cpp:254-258` at pinned revision
`5f768e34`: the unbound state after an explicit unbind, and Copy/Solo disabled plus
the Insert Time and Delete Time menu rows in that state.
Verify lane: `deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: the state ledger's QAction/menu identity rows
(A094–A099), whole-project snapshots (A164/A171) and the live-remap ingress rows
(A173–A181).

# Exact write set

- `src/checks/workspace/session_edit_routing.swift` — refusal predicates: with no open song, the command authority disables Copy, Solo, Insert Time and Delete Time, and no session API exposes an unbound-with-selection state.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` — A087–A091 only, closed as RETIRED-REPRESENTATION citing the ruling.

# Prerequisites

None. `session_edit_routing.swift` and the ledger are clean in `git status`; disjoint
from every foreign file and sibling brief. Read sprint-3 §21.

# Interface contract

The predicates observe the production enablement authority (the same surface
`ShellWindow` binds its actions to) with no open song: every window action in the
fork's unbound set reports disabled, and the session API surface offers no
unbind-with-live-selection path (the guard). Independent literal expectations for the
disabled set; no mock router.

# Implementation steps

1. Add the no-song enablement refusal predicates beside the existing routing checks.
2. Close A087–A091 as RETIRED-REPRESENTATION with one-line reasons naming the missing
   `rebind(null)` seam and the ruling, in the same commit. Compact form: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

The unbound-with-selection fork state is proven unreachable and refused by the Swift
enablement surface, with executed refusal evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

No new unbind API (the ruling's point is its absence). No `session_io.swift` edits
(task 176 owns it), no foreign files, no ledger rows beyond the five.
