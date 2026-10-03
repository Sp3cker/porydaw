# Task 189 brief — the scale bar's Fold/Highlight state is per-tab and survives every toggle path

# Context

`WorkspaceTabsTest::scaleRouting` keeps the transport scale controls
(root, type, Highlight, Fold) bound to the selected tab while each tab owns
independent scale state. The surviving clauses are all Fold/Highlight reads
that no executing predicate makes:

- A021/A023 (GAP): the first tab's Fold stays off after its Highlight/root/
  type edits and after the Highlight toggle cycle — S191/S192 compare only
  `scaleHighlight` in `tst_ShellTransportSession.qml`.
- A027 (PARTIAL): the second tab's Highlight stays off after its root/type
  edits and Fold click.
- A033 (PARTIAL): the Fold toggle turns Fold off — S193 asserts only the on
  transition.
- A050 (PARTIAL): the second document is not dirty after the track
  delete/undo sequence — no predicate reads the dirty flag there.
- A054 (PARTIAL): the first tab's Fold is still off after the second tab
  enabled Fold (the mirrored instance of S195's independence clause).

Surface: the mounted transport scale controls and their per-tab Fold/
Highlight/dirty state across root, type, toggle and tab-switch inputs.
Ledger spec: `src/checks/workspace/proof.tabs_scale.txt` A021, A023 (2 GAP),
A027, A033, A050, A054 (4 PARTIAL), fork `tabs_scale.cpp:58–157` at `a7fcaa3e`
(`scaleRouting`).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-session --verbose` and
`deno task verify --filter swiftcore --verbose`.
Blocked rows left untouched: tabs_transport A062 (physical audio readback) and
A050's undo-index residue (task 191); session A024/A042 (sidecar, no Swift
owner); selftest_* physical-output conjuncts.

# Exact write set

- `src/checks/editorqml/tst_ShellTransportSession.qml` — extend
  `test_scaleControlsFollowSelectedTab` (or a sibling journey in the same
  file): read the mounted Fold/Highlight state at each fork point above, with
  the fork's literal expectations (Fold off after Highlight edits; Fold-off
  after the Fold toggle; the mirrored per-tab independence).
- `src/checks/workspace/session_editor_semantics.swift` — the model-level
  conjuncts that the mounted lane cannot cheaply stage (dirty flag after the
  delete/undo sequence, A050) in `checkPerTabScaleState` or a sibling check.
- `src/swift/app/` scale/transport presenter — conditional repair only if a
  published Fold/Highlight/dirty value provably diverges.
- `src/checks/workspace/proof.tabs_scale.txt` — the six rows only.

# Prerequisites

All write-set files are clean at `85a806f9`. Read sprint-3 §23. The mounted
lane's published surface for Fold/Highlight must be confirmed before writing
predicates (observe the published properties, not private model state); the
Swift check host may read the session's `scaleProjection.fold` and document
dirty flag directly.

# Interface contract

Mounted predicates toggle the real transport controls and switch real tabs,
reading the published control/session state at the fork's points. The model
predicate stages the track delete/undo and reads `document.isDirty`. One
predicate per fork clause, independent literal expectations; the first tab's
Fold-off literals and the second tab's Highlight-off/Fold-off literals are
each asserted once.

# Implementation steps

1. Read `tabs_scale.cpp` at `a7fcaa3e` (`scaleRouting`) for the exact toggle
   order and each clause's literal.
2. Extend the mounted journey to read Fold after each Highlight/root/type
   stimulus and after each Fold toggle (A021/A023/A027/A033/A054).
3. Add the model-level dirty-flag predicate after the delete/undo sequence
   (A050).
4. Repair the publication only where a predicate provably fails.
5. Close the six rows in the same commit, compact form.

# Acceptance predicate

The mounted scale journey reads Fold/Highlight at every fork point and the
model check proves the post-undo clean document; both lanes pass with executed
evidence.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-transport-session --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

One predicate per fork clause — assert each Fold/Highlight read once with its
own literal; do not roll the six clauses into one conjunct soup. Sole wave-23
writer of the tabs_scale ledger and of `session_editor_semantics.swift` (193
uses `session_view_state_fanout.swift`; 191 uses `session_edit_routing.swift`).
Do not touch `tst_ShellTransport.qml` (S197's home is stable) or the tabs_
transport ledger.
