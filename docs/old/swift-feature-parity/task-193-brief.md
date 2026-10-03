# Task 193 brief — a rejected track remap is a total no-op, and view-only mutations touch no sidecar bytes

# Context

`MainWindowRoutingStateTest` stages two document-level no-op laws whose Swift
counterparts exist but stop at MIDI/revision/history:

- A164/A171 (GAP): after a view-only view-state insertion or removal the fork
  snapshots the **entire project directory** (`porydawSnapshot(...)`) and
  requires byte equality; S313–S315/S319–S321 prove MIDI bytes, revision and
  history but not the non-song sidecar bytes.
- A173–A181 (GAP): `rejectedRemapIsTotalNoop` emits a `TrackRemap` the live
  document rejects; S322/S323 reject a pure `EditorViewState` value copy but
  never exercise the rejected remap through the live document. The fork
  asserts the sibling view state, MIDI bytes, revision, directory snapshot,
  origin/hub/persisted signal counts — every conjunct a no-op on the rejected
  ingress.

Surface: the session's document-remap and view-state mutation paths — a
rejected remap and a view-only edit provably mutate nothing user-visible,
including on-disk bytes.
Ledger spec: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_
state.txt` A164, A171, A173, A174, A175, A176, A177, A178, A179, A180, A181
(11 GAP), fork `tst_mainwindowrouting_state.cpp:439,455,474–...` at `85b97239`
(`viewOnlyLaneMutationsPersistWithoutDocumentMutation`,
`rejectedRemapIsTotalNoop`).
Verify lanes:
`/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose` (the workspace
session checks).
Blocked rows left untouched: the remainder of the state/input/lifecycle/native
ledgers — fixture guards, `swift-project-store` sidecar families the fork
writes (these rows prove *absence* of writes, which the Swift session lane
can stage), native window close, QAction/focusWidget identity, pending-reload
input gate.

# Exact write set

- `src/checks/workspace/session_view_state_fanout.swift` — extend
  `runCompleteEditorViewStateChecks`: an opaque directory snapshot (the
  `porydawSnapshot` equivalent — recursive byte listing) before and after the
  view-only insertion/removal (A164/A171); the rejected live `TrackRemap`
  delivered to the document, then the sibling's view-state equality, the
  document's MIDI bytes, revision, directory snapshot, and zero origin/hub/
  persisted emissions (A173–A181).
- `src/swift/core/` or `src/swift/app/` — conditional repair only if the
  rejected remap provably mutates or emits.
- `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_state.txt` — the
  eleven rows only.

# Prerequisites

All write-set files are clean at `85a806f9`. Read sprint-3 §23. Confirm the
Swift remap ingress (`SongDocument`'s remap application) exposes a rejected/
no-op path before writing predicates — the fork's `rejected` remap uses an
identity `engineTrackMap` plus a reduced `newEngineTrackCount`; the Swift
equivalent must be a genuinely rejected live-document remap, not a pure value
copy.

# Interface contract

Directory snapshots are opaque byte listings compared for equality — allowed
as opaque pre-stimulus snapshots. Emission counts observe the session's
published change domains (a rejected remap publishes nothing). One predicate
per fork clause with its unique literal; each of A173–A181 is its own
conjunct, not a folded megacheck.

# Implementation steps

1. Read `tst_mainwindowrouting_state.cpp` at `85b97239` around `:439–500` for
   the staged insertion/removal and the rejected remap's exact shape.
2. Add the directory-snapshot fixture to
   `session_view_state_fanout.swift` (or reuse the existing fixture-root copy
   helper) and prove the view-only mutations leave it identical (A164/A171).
3. Stage the live rejected remap and assert each no-op conjunct (A173–A181).
4. Repair the remap rejection only where a predicate provably fails.
5. Close the eleven rows in the same commit, compact form.

# Acceptance predicate

View-only view-state mutations and the rejected live remap both leave MIDI
bytes, revision, view state, directory bytes and emission counts untouched —
executed on the swiftcore lane.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore --verbose
deno task proof check --executed
```

# Task-specific constraints

Independent literals: the directory snapshot is the fork's own
`porydawSnapshot` shape, not a projection read back. Sole wave-23 writer of
the state ledger and of `session_view_state_fanout.swift`; 189 owns
`session_editor_semantics.swift`, 191 owns `session_edit_routing.swift` and
`tst_ShellTransportVolume.qml`. Do not touch the input/lifecycle/native
ledgers or the pending-reload gate.
