# Task 126 brief — Register Song repairs project registration without disturbing existing bytes

# Context

Complete the existing Songs dock registration transaction from plan through project files and refreshed listing. SongDockController and ProjectService already expose this production flow; the ledger's absent-ingress preamble is stale. This task supplies the ordinary registration contract that tasks 127 and 128 preserve while extending removal and region allocation.

Verified planning selection: **88 open rows (88 GAP + 0 PARTIAL)** from sprint-3 §14.

- `src/checks/onboardcheck/proof.registration.txt` — A001–A088, inclusive.

Oracle: `fceecd88`; source pin `a1244957bb05a59d62b8912e053d49b2a6f3d771`.

# Exact write set

- `src/swift/project/SongRegistration.swift`
- `src/swift/project/SongRegistration+Writes.swift`
- `src/swift/project/SongRegistration+Store.swift`
- `src/swift/app/ProjectService+Songs.swift`
- `src/swift/app/songlist/SongDockController.swift`
- `src/checks/songlist/songlist_service.swift`
- `src/checks/songlist/SongRegistrationChecks.swift` — new, ordinary registration/repair scenarios.
- `src/checks/editorqml/tst_ShellSongs.qml`
- `src/checks/CMakeLists.txt` — register the new Swift check source only.
- `src/checks/onboardcheck/proof.registration.txt` — separate ledger writer only.

Closed list. The ledger may close completely. Its original registration.cpp is already absent. No remaining native production unit is freed by this ledger alone: songdocument.cpp/h still serve roll, project, routing and import obligations; workspaceui_project.cpp still serves action/lifecycle/session obligations. Those units are not write targets.

# Prerequisites

The split baseline and existing SongDockController plan/confirmation route. Independent of tasks 118/119. Task 127 consumes registration's stable ID/file behavior; task 128 consumes its complete/partial registration handling.

# Interface contract

- Preserve SongRegistration.status/plan/register, ProjectStore.registerSong(label:constant:player:), ProjectService.songRegistrationPlan(label:)/registerSong(_:) and the existing SongDockController confirmation. No new command, wizard or controller is needed.
- In the fork's mus_onboardcheck scenario, the stray is playable with config but not registered, derives MUS_ONBOARDCHECK and MUSIC_PLAYER_BGM, and proposes the original table count as ID. Its exact table line is `\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0`. Header ID, little-endian charmap bytes, linker object path and applicability must agree with independent fixture expectations. The aligned charmap uses the original 26-column equals alignment; preserve LF/CRLF and untouched bytes.
- Register once, deliberately damage the song's songs.h/charmap entries, and register again. The second registration repairs only missing/broken registration and restores the original full table/header/linker/charmap bytes, with the same ID. It must not append a duplicate table entry. Repeat the exact fork missing-middle-line table for songs.h and charmap: the restored file is byte-identical, not merely searchable for the constant.
- With the fork's duplicate song-table label, status/plan/repair consistently use the first ID. Re-registration repairs its header while preserving charmap and unrelated entries. Fresh service listing/status after each transaction must expose the result; do not use the production plan as the expected file generator.
- Real mounted Register, Cancel, reopen and Accept input crosses the existing confirmation. Snapshot all relevant project bytes before opening, while staged and after Cancel: no write until Accept. Cancel is a real button/Escape input, not controller.cancelConfirmation() as its sole witness. Registration state and warning badge refresh after completion.
- Retire only old native fixture/open/read/write-success guards and intermediate substring-location guards whose consumer is the independent complete-file/result predicate. Keep diagnostic failure paths live; no `directory exists`, optional-nonnull or error-string-empty replacement assertions. No New Song or New Voicegroup claim follows from staging fixture files.

# Implementation steps

1. Add runSongRegistrationChecks(report:fixtureRoot:) in the new concept file, call it from runSongListServiceChecks, and register the source in the existing target. Reuse isolated copied-project staging.
2. Implement the fork's ordinary, repair-in-place, missing-middle-line and duplicate-label journeys with literal expected file bytes and exact result identities.
3. Repair only demonstrated registration divergences in the listed owners and strengthen mounted confirmation staging/acceptance in the existing shell-songs journey.
4. Give executed evidence and bounded setup classifications to the separate ledger writer; delete registration's ledger only after every behavioral clause is proved.

# Acceptance predicate

A real service registration followed by file reload and mounted confirmation execution proves the entire ordinary registration/repair surface; cancellation never writes. Existing song-list checks remain registered and all project mutations use private copies.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No checked-in project data, sample studio, import wizard, WAV export, task-118/119 or unselected onboarding-ledger writes. SongRegistrationChecks is a substantial ordinary-registration concept, not one file per assertion. Every Swift/QML file stays at most 600 lines; do not append this inventory to the existing songlist_service body. The single-domain checks/CMakeLists.txt source manifest is exempt from that cap; add the source directly there, without extracting another manifest.
