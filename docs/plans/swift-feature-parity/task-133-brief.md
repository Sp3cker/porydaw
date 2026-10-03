# Task 133 brief — failed song I/O identifies its source and leaves the live edit intact

# Context

Complete the existing Reconcile/MIDI/voicegroup/Save failure surface. The current sessionFailureStages checks mostly match diagnostic substrings; the target is the entire failed-operation consequence and subsequent recovery.

Selected **24 open rows (0 GAP + 24 PARTIAL)** in `src/checks/project/proof.iomutations.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A003, A004, A005, A006, A007, A008, A009, A010, A011, A012, A013, A014, A015, A016, A017, A018, A019, A020, A021, A022, A023, A024, A025, A026 | `src/checks/project/iomutations.cpp:218,225,230,232,234,235,243,248,250,252,253,255,261,269,274,275,278,280,281,283,291,293,295,296` — `failureStages` |

# Exact write set

- `src/swift/app/ProjectService+Bank.swift`
- `src/checks/workspace/session_io.swift`
- `src/checks/editorqml/tst_ShellOpenFailure.qml`
- `src/checks/project/proof.iomutations.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 126–128 and 3fbfe933. Task 134 later reuses session_io.swift; checkpoint this writer before that reuse.

# Interface contract

Preserve ProjectService.openSong(label:) and save(_:bank:) signatures and their real ProjectStore boundary. Exercise unknown playable label, temporarily missing MIDI, temporarily missing bank source, and the fork invalid save destination on separate copied fixtures. Each error is associated with the requested operation/song through the actual call result; retain complete MIDI and bank bytes, both dirty records, history and selected live document. Restore the hidden source before comparing bytes, then prove the same valid open/save can complete. The old callback variant, SongStage enum and intermediate MidiStage event log are retired backend representation where the Swift async return is atomic; do not create a second stage enum/event bus to count native envelopes. Retain operation attribution and failure-before-ready behavior through the mounted failed-open dialog.

# Implementation steps

1. Extend sessionFailureStages to capture full before/after state and real recovery, replacing incidental diagnostic-wording assertions with domain failure and preserved-state predicates.
2. Keep each original stimulus distinct; an unrelated permissions failure is not a missing bank or invalid MIDI substitute.
3. Repair only the existing service error/adoption path when behavior diverges. Extend the mounted failed-open journey to keep the same live tab and staged edits through dismissal.

# Acceptance predicate

All four real failure stimuli preserve the live edit and files; restored inputs recover, and the mounted failure UI does not replace the current tab. projectsession executes sessionFailureStages; shell-open-failure executes the actual open-failure surface.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-open-failure --verbose
```

# Task-specific constraints

Only iomutations A003–A026 are writable. No creation collision, preview cleanup, closed-worker transport, catalog outage or bank-undo rows. Setup/restore calls remain fail guards, not passing assertions. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
