# Task 170 brief — a reloaded song presents its resolved bank identity to the voicegroup dock

# Context

Loading a song resolves its configured voicegroup to a concrete bank identity and
binds it. The Swift service observes only the timeline publication callback
(`session_playback`'s same-labelled predicate); no executing predicate observes the
bank view's identity or contents — which bank (source path + section label, load
name, populated slots) the mounted voicegroup dock presents after an open or an
in-place reload of a song whose voicegroup changed on disk. That is the user-visible
half of the fork's `voicegroupLoadAndPreviewPaths` journey; the C++ result-envelope
and preview shadow-path internals stay representation.

Surface: the mounted voicegroup dock's presented bank after open and after an
externally changed voicegroup is reloaded.
Ledger spec: `src/checks/project/proof.ioflow.txt` A051–A054 (GAP) — fork
`ProjectIoFlowTest::voicegroupLoadAndPreviewPaths` at pinned revision `a7fcaa3e`,
`src/checks/project/ioflow.cpp:203-221`: the loaded bank view's id matches the song's
resolved `bankId` (sourceRelativePath and sectionLabel), the bank is non-null with
contents, and the binding identity equals the bank id.
Verify lane: `deno task verify:shell --filter shell-voicegroup --verbose` (mounted
dock journey) plus the service bank lane for the binding identity.
Blocked rows left untouched: A055–A065 (preview shadow/target paths — internal
filesystem contract with no documented Swift consumer surface) and the ledger's
protocol rows (FIFO/result-count/stage-order).

# Exact write set

- `src/checks/editorqml/tst_ShellVoicegroup.qml` — open and external-change+reload journeys observing the dock's presented bank identity and contents.
- `src/checks/workspace/` or `src/checks/projectstore/` bank check file — the service-level binding identity predicate (beside the existing bank-view checks from 152).
- `src/swift/project/VoicegroupStore.swift` — conditional repair only if the journey exposes a real divergence.
- `src/checks/project/proof.ioflow.txt` — A051–A054 only.

# Prerequisites

Task 152's bank-view contracts are landed and consumed read-only. Disjoint from every
sibling. Read sprint-3 §19.

# Interface contract

The mounted journey opens a song, observes the dock's bank identity (load name and
slot contents) against independent literals derived from the fixture's configured
argument; then changes the song's voicegroup file on disk (or its configured argument
through the dock), triggers the in-place reload through the real path, and observes
the dock present the new bank identity with its contents. The service predicate
observes the resolved `VoicegroupId` (path + section) and the bound load identity on
the production load path. No C++ result envelope, no event counting.

# Implementation steps

1. Add the service-level binding identity predicate on the production load path.
2. Add the mounted open and reload journeys with real input and observed dock state.
3. Close A051–A054 in the same commit. Compact form for closed rows: header +
   `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Opening or reloading a song presents exactly the bank it resolves to — identity and
contents — on the mounted voicegroup dock.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-voicegroup --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
deno task proof check --executed
```

# Task-specific constraints

No fake worker, no stage injection, no preview-shadow path assertions. Bank-lease
identity rows in `tst_voicegroupbank` stay untouched. Sibling files and ledgers stay
untouched.
