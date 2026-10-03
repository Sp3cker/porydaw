# Task 165 brief — deleting a track remaps SongView-owned state atomically

# Context

Deleting a track must remap everything the view owns before the document change
publishes: the primary falls back, note and time selections clear, mute/solo remap,
and per-owner cosmetic state drops from the removed track; undo restores survivors.
The Swift session cannot even stage the fork's fixture: `setSelectedNotes` clears the
time selection (`DocumentSession+Selection.swift:13`), `applyTimeSelection` clears the
note selection (`:47`), and `selectedTrack.didSet` clears both
(`DocumentSession.swift:96-98`) — the model forbids the coexistence the fork's
selection model allowed and the remap clauses stage.

Surface: track deletion in the editor (track headers → session), with the selection
model's capacity to hold note and time selections simultaneously.
Ledger spec: `src/checks/rollcheck/proof.remap.txt` A044, A045, A048, A049, A056–A058
(7 PARTIAL), the ledger's only open rows — fork `PianoRollTest::trackRemapDelete`
(`src/checks/rollcheck/remap.cpp:383-409`) and `trackRemapMetadata` (`:464-472`) at
pinned revision `85b97239`: delete remaps before `documentChanged`; primary falls back
to `min(removed, count-1)`; note/time selections and removed-track mute/solo/cosmetics
are gone; undo restores surviving state without inheriting dropped owners.
Verify lanes: `deno task verify --filter swiftcore-projectsession --verbose`.
Blocked rows left untouched: none in this ledger; ioflow/iomutations protocol rows
stay out.

# Exact write set

- `src/swift/app/DocumentSession+Selection.swift` — allow note + time selection coexistence (drop the cross-clears) with command-layer explicit clears where the fork's commands cleared.
- `src/swift/app/` track-deletion command seam (the headers' delete-track path into the session) — the atomic state remap, conditional repair.
- `src/checks/rollcheck/remap.swift` — staged delete/metadata/undo journeys through production APIs.
- `src/checks/rollcheck/proof.remap.txt` — the 7 selected rows only.

# Prerequisites

None. Disjoint from Task 163 (`ApplicationSession+Tabs.swift`) and 158. Read sprint-3 §19.

# Interface contract

The model-level APIs (`setSelectedNotes`, `applyTimeSelection`, `selectPrimaryTrack`)
no longer implicitly clear each other; every command whose fork behavior cleared a
selection keeps doing so explicitly (Select All, time-selection shortcuts, prompt
accepts). **Preservation list — these landed predicates must stay green:**
`tst_ShellWindowParameterKeys.qml`'s Select All/clears-the-time-range rows,
`keyboard_time_selection`'s shortcut outcomes, and the insert-time scope journeys.
The delete path remaps primary/scope/mute/solo/cosmetics before publication, and undo
restores them; independent literals for fallback indices and surviving state.

# Implementation steps

1. Remove the cross-clears; add explicit clears at the command sites the fork cleared
   (verify each against the landed predicate list above).
2. Implement/repair the delete-track state remap on the session seam with the
   fallback/scope/mute/solo/cosmetic contract.
3. Stage the fork's combined-selection fixture through production APIs and prove the
   delete/metadata/undo journeys in `remap.swift`.
4. Close the 7 rows in the same commit; all other rows are already closed, so the
   ledger is deleted with its already-absent C++ source cited. Compact form for closed
   rows: header + `Disposition` + one S-citing mapping line; no pasted code.

# Acceptance predicate

Deleting a track leaves no orphaned view state and undo restores it; the session holds
combined note+time selections when staged; every preservation-list predicate still
passes; the remap ledger closes whole.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shellwindow-parameter-keys --verbose
deno task proof check --executed
deno task proof list
```

# Task-specific constraints

The coexistence change is the riskiest edit in this wave: if any landed clearing
predicate fails, restore that command's explicit clear rather than weakening the
predicate. No event-bus invention, no new selection types beyond what the fork's model
held. `tst_ShellGridMenu*.qml` and sibling ledgers stay untouched.
