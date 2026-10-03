# Task 132 brief — Save and reopen retain exact song edits and the saved history point

# Context

Complete the existing Save surface against the full fork save journey, not merely equality to a pre-save Swift output. Task 131 supplies make-backed flag preservation; this task owns normal song save, not the bank-undo repair.

Selected **35 open rows (1 GAP + 34 PARTIAL)** in `src/checks/project/proof.save.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A001 | `src/checks/project/save.cpp:139` — `init` |
| A002, A003, A004, A005, A006, A007, A008, A009, A010, A011, A012, A013, A014 | `src/checks/project/save.cpp:151,158,159,163,164,167,172,173,174,175,176,179,185` — `saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes` |
| A015, A016, A017, A018, A019, A020, A021, A022, A023, A024, A025, A026 | `src/checks/project/save.cpp:193,200,201,205,206,210,212,214,219,221,223,224` — `savedIdentityUndoRedoAndStaleSnapshot` |
| A027, A028, A029, A030, A031, A032, A033, A034, A035 | `src/checks/project/save.cpp:231,238,239,243,248,256,257,258,259` — `savedMidiCompilesWhenAvailable` |

# Exact write set

- `src/swift/app/DocumentSession.swift`
- `src/swift/project/ProjectStore+Save.swift`
- `src/checks/workspace/session_save.swift`
- `src/checks/editorqml/tst_ShellTabsClose.qml`
- `src/checks/project/proof.save.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 131, 118 and the bank-undo fix 3fbfe933. Preserve bank save/undo helpers and their literals unchanged; task 136 owns document merge policy.

# Interface contract

Preserve DocumentSession.save() and ProjectStore.save behavior. Seed the fork note at the oracle edit-window base, pitch 72, velocity 93, duration 24; config volume 111 and the fork loop-start transformation must survive an actual save and new DocumentSession open. Compare the entire config file line sequence: same count, only the target entry changed, every other entry byte-identical. Saving establishes the current clean identity. Two subsequent edits, Undo/Redo and stale snapshot completion reproduce A019–A026 dirty-state crossings and exactly two extra history entries. The persisted edited MIDI must actually compile with mid2agb and exit successfully; do not replace process failure with a skip. Retire old QProcess handshake and setup-only guards only alongside that real compile result, not the semantic compile obligation.

# Implementation steps

1. Extend sessionSavePersistence using a private copied fixture and fork-derived edit-window expectations; leave sessionSaveJourney/sessionSynthUndoTail bank behavior untouched.
2. Add exact post-reopen note/config/loop and full-file comparisons, and count history by the existing behavioral traversal helper rather than exposing test-only stack internals.
3. Repair only demonstrated save/adoption defects; run the persisted-MIDI compiler through the existing native check helper and map the entire save ledger.

# Acceptance predicate

Saving real edited source produces the independently expected reopened song and clean identity; stale completion cannot clean a newer edit; the saved MIDI compiles. The projectsession lane already owns sessionSavePersistence and the compiler helper. shell-tabs-close runs test_jDirtyCancelDiscardSave: strengthen its reopened note comparison to the complete independently expected note sequence, preserving Cancel/Discard behavior.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-tabs-close --verbose
```

# Task-specific constraints

No bank history/merge change, catalog-outage behavior, WAV export, physical playback requirement or sidecar-directory snapshot. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
