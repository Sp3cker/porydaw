# Task 186 brief — an incidental band or chrome press preserves an eligible note selection

# Context

The fork's `incidentalBandClickPreservesSelection` pressed every band input and
chrome surface with an eligible note selection staged, then asserted the note
selection was byte-identical afterward. The mounted lane has presses that
extend the selection (S016's multi-note journey), a drawer-resize chrome drag
whose retained selection belongs to the windowtier_gestures rows, and
empty-space menu clicks that assert the time selection — but no predicate
stages the fork's actual case: a band/ruler press against an already eligible
note selection that must leave `noteSelection` untouched.

Surface: grid note-selection stability under incidental input — a user with
notes selected can press the ruler, a band edge or chrome without losing the
selection arrows act on.
Ledger spec: `src/checks/selectionkey/proof.corearrows.txt` A007 (1 GAP), fork
`corearrows.cpp:159` at pinned revision `acc55548`
(`SelectionKeyCoreTest::incidentalBandClickPreservesSelection` — the
per-surface press loop asserting `noteSelection() == selection` with the
label/actual/intended diagnostic message).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input-editing --verbose` (or the owning shell-grid-input entry) and
`deno task verify --filter swiftcore --verbose` if a model-level leg lands in
`localinputtier_window.swift`.
Blocked rows left untouched: none in this ledger (the rest of corearrows is
closed).

# Exact write set

- `src/checks/editorqml/tst_ShellGridInputEditing.qml` — the mounted journey: stage an eligible note selection, deliver real presses to each band/chrome surface the fork enumerated (ruler/band edges/scrollbar-adjacent chrome), assert the note selection's ID set is unchanged after each. One predicate per surface carrying the fork's per-surface literal.
- `src/checks/selectionkey/localinputtier_window.swift` — conditional model-level predicate only if a surface's press cannot be staged mounted.
- `src/checks/selectionkey/proof.corearrows.txt` — A007 only.

# Prerequisites

All write-set files are clean at `0504b68b`. The fork's probe list (which
surfaces get pressed) is in `corearrows.cpp` around `:159` — read the function
before writing predicates; the fork wins on which surfaces count as incidental.
Read sprint-3 §22.

# Interface contract

Real pointer presses on the mounted window; selection compared as an exact ID
set before/after each press; the per-surface diagnostic message names the
surface (the fork's `qPrintable(...arg(label, actual, intended, diagnostics)`
form becomes one literal per surface, not a format string).

# Implementation steps

1. Read the fork function's probe list; map each surface to its mounted object
   name.
2. Add the per-surface press predicates with the eligible selection staged.
3. Repair production input routing only if a press provably disturbs the
   selection (unlikely — the row is GAP, not a known defect).
4. Close A007 in the same commit, compact form.

# Acceptance predicate

Every fork-enumerated incidental surface provably preserves the staged note
selection on the mounted app.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-grid-input-editing --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Do not touch `tst_ShellGridInputCancel.qml` or `note_commands*.swift` (task
181's gesturecommands leg) or the automation drawer files (tasks 180/183/184).
Sole wave-22 writer of the corearrows ledger.
