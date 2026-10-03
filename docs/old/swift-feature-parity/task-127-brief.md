# Task 127 brief — Delete Song protects the fallback and removes only unreferenced project data

# Context

Complete the existing Songs dock deletion transaction and its unused-voicegroup option. Consume task 126's stable registration/repair contract. This uses the current ProjectStore deletion path, not New Voicegroup creation; creation calls in the native deletion fixture are setup, not permission to build the excluded creation surface. Task 128 preserves these removal laws when region markers participate.

Verified planning selection: **71 open rows (71 GAP + 0 PARTIAL)** from sprint-3 §14.

- `src/checks/onboardcheck/proof.deletion.txt` — A001–A071, inclusive.

Oracle: `fceecd88`; source pin `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`.

# Exact write set

- `src/swift/project/SongRegistration+Removal.swift`
- `src/swift/project/SongRegistration+Store.swift`
- `src/swift/app/ProjectService+Songs.swift`
- `src/swift/app/songlist/SongDockController.swift`
- `src/checks/songlist/songlist_service.swift`
- `src/checks/songlist/SongDeletionChecks.swift` — new, removal and reference-protection scenarios.
- `src/checks/editorqml/tst_ShellSongs.qml`
- `src/checks/CMakeLists.txt` — register the new Swift check source only.
- `src/checks/onboardcheck/proof.deletion.txt` — separate ledger writer only.

Closed list. The whole ledger may close; deletion.cpp is already absent. No C++ production deletion is enabled by this ledger alone: workspaceui_project.cpp and workspaceui.cpp/h retain action, lifecycle, session and scale blockers. Voicegroup creation and sample units remain blocked and are not write targets.

# Prerequisites

Accepted/checkpointed 126 before reusing its service/controller/check/registration files. No dependency on another Group B writer and no task-118/119 write paths. Task 128 later consumes this removal interface.

# Interface contract

- Preserve SongRegistration.removalPlan/unregister/removeFlags, ProjectStore.deletableVoicegroup(label:)/deleteSong(label:voicegroupName:), ProjectService.songDeletionPlan/deleteSong and the existing confirmation. Refuse ID 0 before **any** file mutation; retain the literal existing refusal diagnostic and compare every original snapshot byte.
- Unregistering an absent song is idempotent. Removing a middle song replaces its slot with the fork fallback row without renumbering survivors; dummy count increases exactly once. The next registration reuses that exact ID, with its header/charmap definition before the later survivor. Removing the tail trims trailing fallback placeholders; after the full A/B/C cycle the original project snapshots return byte-for-byte.
- Remove the requested MIDI flags in both midi.cfg and songs.mk forms without touching neighboring rules/formatting. The actual service path moves MIDI into .porydaw/trash and removes its generated assembly; observe the real path rather than mocking filesystem success. Preserve the current trash-name collision policy, but do not add unrelated new failure/retry behavior.
- The unused-voicegroup query returns no candidate for a second song reference, an external C/header symbol reference, or keysplit/drumkit host use. With those references absent it returns the exact per-file bank name. Checked deletion removes that bank file and only its include-hub entry, restoring the original hub bytes; repeated removal is harmless. Seed the temporary bank/include bytes independently in the copied fixture, rather than introducing createVoicegroup/appendIncludeLine into production.
- Mounted Cancel must preserve MIDI, flags, registration and bank/include bytes; the opt-out checkbox preserves the bank while deleting the song, and opt-in deletes only a freshly revalidated unused bank. After acceptance the row disappears and the disclosed trash destination contains the original MIDI. Use actual checkbox/button input and a clean copied fixture for each branch.
- Retire only fixture/read-success/remove-success guards and the setup-only creation calls A056/A057/A062 in this deletion ledger, paired with their downstream deletion/reference predicates. This is not evidence for voicegroupsourceediting A086–A092 or presentation A032–A037; leave those ledgers untouched.

# Implementation steps

1. Add runSongDeletionChecks(report:fixtureRoot:) in the new concept file, register it and call it from the existing song-list service entry.
2. Execute fallback refusal, absent/middle/tail removal, dummy reuse and exact restoration against independent fork file images.
3. Execute the real unused-bank reference matrix and mounted cancellation/opt-in/opt-out paths; repair only the declared removal owners.
4. Hand settled evidence to the separate ledger writer and delete the deletion ledger only when every behavioral conjunct executes.

# Acceptance predicate

The real store/service and mounted Songs dock agree on refusal, stable IDs, file/trash results and safe bank removal; staging/cancellation writes nothing. Registration from task 126 remains correct after all deletion cycles.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No new creation UI/API, actual user-project deletion, shared bank mutation, checked-in fixture or reserved-state file writes. Every Swift/QML file stays at most 600 lines; the single-domain checks/CMakeLists.txt source manifest is exempt and remains the direct registration owner. Source/include creation used solely to stage a deletion scenario is fixture setup, never a new passing setup assertion or closure of the excluded creation feature.
