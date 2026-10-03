# Task 131 brief — songs.mk-backed song settings preserve recipes and variable spelling

# Context

Complete the existing song-settings persistence surface for projects without midi.cfg. The parser checks already cover part of the fork matrix; add real ProjectStore reopen and rule removal consumers rather than relabeling those checks. Task 132 consumes the same configuration write contract.

Selected **36 open rows (36 GAP + 0 PARTIAL)** in `src/checks/project/proof.mk.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A001 | `src/checks/project/mk.cpp:101` — `init` |
| A002, A003, A004, A005, A006, A007, A008, A009, A010, A011, A012, A013, A014, A015, A016, A017, A018, A019 | `src/checks/project/mk.cpp:112,114,116,119,120,121,128,131,134,142,144,145,148,152,154,156,157,158` — `parsesAndVolumeWriteChangesOnlyRecipe` |
| A020, A021, A022, A023, A024, A025 | `src/checks/project/mk.cpp:165,179,182,184,189,203` — `preservesStdReverbVariableSpelling` |
| A026, A027, A028, A029, A030, A031, A032, A033, A034, A035, A036 | `src/checks/project/mk.cpp:209,211,213,216,223,225,227,228,229,230,231` — `appendRemoveRuleRoundsTripsByteExactly` |

# Exact write set

- `src/swift/project/SongsMk.swift`
- `src/swift/project/MidiCfg.swift`
- `src/swift/project/SongRegistration+Removal.swift`
- `src/checks/projectstore/SongsMkChecks.swift`
- `src/checks/project/proof.mk.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted 126–128 registration/removal work; preserve its flags-routing contract. No new registration interface.

# Interface contract

Preserve SongsMk.parseFlags/writeRule and MidiCfg.writeSongFlags and SongRegistration.removeFlags(root:label:). With midi.cfg absent, load concrete expanded options, write only the target recipe, retain $(MID), unchanged -R$(STD_REVERB), neighboring rules, comments and line endings, and never create midi.cfg. Reopen through ProjectStore: masterVolume is 111 while voicegroup and reverb remain unchanged. Repeat the variable-volume case at 99. Append the fork new-label rule, read exactly its flags, remove it, and compare the complete original songs.mk bytes; repeated removal is idempotent. File-read/setup guards are not new behavior tests.

# Implementation steps

1. Extend runSongsMkSuite with a copied real project and independently specified before/after recipe images; retain existing CRLF and case-insensitive option coverage.
2. Repair only demonstrated write/remove/parse divergences in the existing owners; do not move registration logic or introduce a second make parser.
3. Exercise ProjectStore open/reopen after each settings write and the append/remove cycle. Supply exact executed row correspondence for this whole ledger.

# Acceptance predicate

The actual settings storage route and reopened project agree on flags, and removal restores every original byte. projectstore-songsmk runs runSongsMkSuite; shell-songs is the existing mounted consumer smoke after registration prerequisites.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-songsmk --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
```

# Task-specific constraints

The append/remove labels are isolated fixture setup, not New Song or New Voicegroup UI. No song-registration source edits. This ledger is a whole-closure candidate; no native production deletion is authorized by it alone. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
