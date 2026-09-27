# Task 145 brief — byte-preserving debug sound-list registration

# Context

Complete the existing Songs registration surface's `src/debug.c` consumer, not a sample editor or a new onboarding wizard. The Swift `SongRegistration` owner already routes registration into `DebugSoundLists`; prove and repair the six fork layout journeys rather than leaving this entire 72-GAP cluster behind the deleted C++ check. The consumer is `ProjectService.songs()` registration-gap reporting and the existing Songs Register/Remove action.

Selected **72 GAP rows**, all of `src/checks/onboardcheck/proof.debuglayout.txt`. Ordered A-id ranges below correspond one-for-one to the ordered assertion-start lines at `fceecd88:src/checks/onboardcheck/debuglayout.cpp`:

| Target A-ids | Fork assertion-start lines / scenario |
|---|---|
| A001–A008 | 38,45,46,50,59,61,68,70 — missing debug file and catalog gaps |
| A009–A015 | 74,75,78,80,81,85,88 — sole removal then empty-list insertion |
| A016–A026 | 107,108,111,118,119,120,123,130,134,138,142 — named/aligned insertion and repeat |
| A027–A033 | 143,146,147,150,151,152,153 — named SE/music removal |
| A034–A041 | 157,161,162,166,167,171,182,183 — incomplete status, mid-backfill and before-first |
| A042–A056 | 187,190,192,194,195,199,213,215,216,217,219,220,221,222,223 — append/SE bytes and unrelated-file preservation |
| A057–A072 | 225,228,229,231,232,234,235,236,237,238,239,241,242,243,244,245 — repeat, status, removal and preserved files |

# Exact write set

- `src/swift/project/SongRegistration+Debug.swift`
- `src/swift/project/SongRegistration.swift` — debug applicability/status only; preserve ID allocation and region planning.
- `src/checks/songlist/SongDebugLayoutChecks.swift` — new cohesive six-scenario check file.
- `src/checks/songlist/songlist_service.swift` — invoke `runSongDebugLayoutChecks(_:fixtureRoot:)` beside the existing registration checks.
- `src/checks/CMakeLists.txt` — add only the new check file to the existing Swift check source list.
- `src/checks/onboardcheck/proof.debuglayout.txt` — selected surface rows; remove the ledger only after every row is closed with executed evidence (its C++ source is already absent).

# Prerequisites

Accepted 127/128/131 registration, removal and recipe-persistence behavior. No interface dependency on 139–144 or 146. Observe sprint-3 §16's settled-source verification gate and shared-manifest ownership.

# Interface contract

Preserve `SongRegistration.plan`, `status`, `register`, `unregister` and removal-plan APIs, and `DebugSoundLists.insert`/`remove`. An absent `src/debug.c` is non-applicable, not a registration failure. A present sound list contributes precisely the missing `src/debug.c` gap until insertion; a listed song does not have that gap. Registering a BGM or SE song selects the correct list, inserts by song ID (including before-first and middle backfill), retains indentation, named display strings, comma/paren/backslash alignment and untouched bytes, and is idempotent. Removing the final entry produces an empty define without a dangling continuation; reinsertion works. Named music and SE removal restores the exact prior literal image. Existing IDs, songs header, song table, charmap and linker stay unchanged when only debug backfill is required; SE register/remove restores the fork's unchanged-file outcomes.

# Implementation steps

1. Add `runSongDebugLayoutChecks(_:fixtureRoot:)` with the fork's append, se-route, mid-backfill, before-first, sole-empty and named scenarios. Stage isolated real project files with literal complete before/after byte images, including independent expected header/table/charmap/linker images. Do not compute expected images by reading or modifying output from the system under test.
2. Exercise the production registration API and `ProjectService.open`/`songs` consumer for A006–A008. Assert the exact `mus_littleroot_test` debug-only gap and absence of that gap for `mus_caught`; require the named songs to exist. Setup/write/read failure must fail the scenario. Retire C++ fixture-pointer and empty-error-buffer representations only where the corresponding successful operation and exact resulting state are proved; do not add bare setup or not-throw assertions.
3. Repair the existing `DebugSoundLists` parser/insertion/removal and debug applicability/status logic only as required by those journeys. Keep existing registration transaction, region ID routing and public APIs unchanged.
4. Add one message-anchored predicate per surviving fork clause, with each A-id cited exactly once. Wire the new check through `runSongListServiceChecks`; the existing `runProjectSessionSuite` caller provides the registered lane. Close or retire the selected rows alongside the check/owner change under the shared proof policy.

# Acceptance predicate

All six real-file journeys preserve the complete literal debug images, correct registration-gap status and unrelated-file bytes through insert/repeat/remove. The existing service/shell registration path remains operational. `SessionChecks.swift` calls `runSongListServiceChecks` from `runProjectSessionSuite`; the first command executes this file-level consumer proof. The second is the existing mounted Songs interaction smoke, not a claim that a new wizard exists.

Controller, after writers settle, runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
deno task proof check --executed
```

# Task-specific constraints

The check file is a cohesive file-format scenario matrix, not six fragment files. Do not use a text-only source test or a copied C++ implementation as the oracle. Closing this ledger is not a transitive deletion certificate for the remaining core or workspace units: other onboarding consumers stay open and the `src/project/` native boundary is retained. No production C++ deletion belongs to this write set. All other onboarding ledgers are untouched. Read sprint-3 §16 for shared constraints.
