# Task 213 brief — the view-state round trip closes on its already-executing joint predicate (re-dispatch of 208)

# Context

Task 208 was briefed in §26 but never dispatched — no commit landed and
`rollcheck/identity` A014 is still PARTIAL. This task re-dispatches the
same closure with no scope change.

`rollcheck/identity` A014 (`identity.cpp:223` at `85b97239`, source
deleted `67544720`): the fork QFAILs when `view.applyViewState`
restores runtime state while changing cosmetics — i.e. it requires the
joint observation "runtime fields restored AND cosmetics retained,
together, without MIDI edits." The residual claimed no predicate
observes the cosmetics retained together with those runtime fields
across the restore — stale.

`identity.swift:194-215` (S021, cppID
`swiftcore/PianoRollTest::viewStateRoundTrip`) executes exactly that
joint predicate on the mounted `DocumentSession`/`PianoGrid`: after
restoring the captured runtime state it asserts
`session.editorViewState == cosmetics` AND every runtime field
(camera snapshot, selected track, edit cursor, grid selection/feel)
AND `document.state == originalState` AND the undo index — a positive
observation of the real mounted replacement surface, not a tautology
and not a test-only read (`editorViewState`, `camera`, `grid`,
`editCursor`, `document.state`, `history.undoIndex` are production
values).

Executed evidence is already on disk:
`build/proof-evidence/swiftcore-projectsession.json` carries the row
literal "restoring captured live runtime state preserves all camera
grid owner cursor and cosmetic values without MIDI edits" under
`swiftcore/PianoRollTest::viewStateRoundTrip`. Confirm with
`deno task proof check --executed` before editing the ledger; if the
anchor fails resolution, re-run the lane command below first.

Close A014 MATCHED on S021. This is a mapping correction inside the
commit that owns this ledger, not a standalone reconciliation over
already-executing predicates: the row's `Mapping:` line already lists
S021; the `Mapping/reason` note is refreshed to record the joint
clause it discharges.

With A014 closed, `proof.identity.txt` has zero open rows and its C++
source is already deleted (`Deleted in: 67544720`) — delete the ledger
file in the same commit per the closed-ledger rule.

Surface: the mounted session view-state restore, already executing.

Ledger spec: `rollcheck/proof.identity.txt` A014 (1 PARTIAL →
MATCHED), then delete `src/checks/rollcheck/proof.identity.txt`.

Verify lane: `swiftcore-projectsession` executes
`PianoRollTest::viewStateRoundTrip`; `deno task proof check
--executed` resolves the S021 anchor against
`build/proof-evidence/swiftcore-projectsession.json`.

Blocked rows left untouched: rollcheck presentation A018–A024
(QtBridge object passing, task-164 family), resize A002–A004/A027/A028
(directional cursors, user decision).

# Exact write set

- `src/checks/rollcheck/proof.identity.txt` — A014's mapping refresh
  and close, then file deletion.
- `src/checks/rollcheck/identity.swift` — reference only; edit solely
  if `proof check --executed` reports the S021 anchor unresolvable.

# Prerequisites

Read sprint-3 §29, `identity.swift:126-216` (the whole
`checkRetainedCosmetics` body — S021 is the final `report.expect` at
:205-215), the fork site `85b97239:identity.cpp:220-230`, and
`proof.identity.txt`'s preamble (`Deleted in:` header, correspondence
map). Confirm the evidence JSON row literal above resolves.

# Interface contract

The mapping correction records which S021 conjunct discharges the
fork's joint clause; no new predicates unless executed evidence is
missing. Compact closed-row form; ledger deletion in the same commit.

# Implementation steps

1. `deno task proof check --executed` — confirm S021's anchor resolves.
2. Refresh A014's mapping note and close it MATCHED (compact form).
3. Delete `proof.identity.txt` in the same commit.

# Acceptance predicate

`proof check` 0 errors; the ledger file is gone and `proof list` no
longer reports `rollcheck/proof.identity.txt`.

```sh
deno task proof check --executed
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
```

# Task-specific constraints

Sole wave-29 writer of `rollcheck/proof.identity.txt` and (only if
required) `identity.swift`. Do not touch the other rollcheck ledgers
(presentation, resize) or any other ledger.
