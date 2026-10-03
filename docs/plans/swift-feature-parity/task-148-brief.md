# Task 148 brief — music-player table budgets reach opened song metadata

# Context

Complete the existing project-open track-budget consumer, not a sample editor. `SongCatalog.musicPlayers(root:tableLines:)` already parses `music_player_table.inc`, and `ProjectStore.open()` publishes `ProjectSnapshot.trackBudgets`; `ProjectService.songs()` carries that budget into each song listing. The stale support-ledger preamble says this parser is absent. Prove the actual symbolic, literal, capped and unknown-limit cases at the opened-project boundary. Task 149 consumes the established import budget semantics; it does not require a new parser interface.

Selected **13 GAP rows**, all of `src/checks/onboardcheck/proof.support.txt`, at `fceecd88:src/checks/onboardcheck/support.cpp`:

| Target A-ids | Fork assertion-start lines / clause |
|---|---|
| A001–A005 | 223,225,226,229,237 — fixture, voicegroup/player enumeration, read/write staging |
| A006–A009 | 245,246,247,248 — BGM 12, SE1 3, capped SE2 16, unknown SE3 -1 |
| A010–A013 | 250,253,255,256 — opened-project budget BGM 12 / SE3 16, restore |

Setup-only rows: A001, A004, A005, A010, A013. A002/A003's nonempty collection tests become exact independently expected catalog contents, not new nonempty assertions.

# Exact write set

- `src/swift/project/SongCatalog.swift` — private `musicPlayers(root:tableLines:)` only, conditional repair.
- `src/swift/project/ProjectStore+Open.swift` — budget-map construction and `ProjectSnapshot.trackBudgetFor(song:)` only, conditional repair.
- `src/checks/projectstore/ProjectStoreOpenChecks.swift`
- `src/checks/onboardcheck/proof.support.txt` — whole selected surface; deletion eligible under §17.

# Prerequisites

Accepted Swift project-store open/catalog contracts and 139 failed-open retention. `ProjectService+Songs.swift` and registration APIs remain read-only. Read sprint-3 §17 for shared constraints and execution ownership.

# Interface contract

Keep `SongCatalog.load(root:cfgMap:)`, `ProjectStore.open() async throws -> ProjectSnapshot` and `ProjectSnapshot.trackBudgetFor(song:) -> Int` unchanged. Stage the fork's complete player-table literal on a copied project: `NUM_TRACKS_BGM=12`, `NUM_TRACKS_SE2=20`, rows BGM with that symbol, SE1 with literal `3`, SE2 with its symbol and SE3 with unresolved `NUM_TRACKS_WHO`. Preserve the fixture's player-name/number declarations in `sound/song_table.inc`. Parsed track counts must be `[12,3,16,-1]` for the four named players; unknown is represented as -1 in `MusicPlayer`, not prematurely normalized. The opened snapshot supplies BGM budget 12 and unknown SE3 budget 16. Read voicegroup arguments through the existing store API and compare the complete fixture-derived list; do not infer correctness from a nonempty collection. The source table's bytes and the checked-in fixture remain unchanged outside the isolated copy.

# Implementation steps

1. Extend `runProjectStoreOpenSuite` with the literal custom-player-table case, reusing the file-copy/`awaitValue` pattern already present. Fail staging/open/read errors without an A-id.
2. Assert the exact player names, numbers and the four track limits separately, then ask the opened snapshot for BGM and unknown-player song budgets. Retain existing snapshot detachment/open-failure predicates.
3. Repair only the named parsing or budget-publication boundary if the exact expectations fail; do not add another parser or clamp in the UI.
4. Classify the five setup representations and attach fresh consumer evidence for the remaining rows in this surface change; delete the ledger only once every row is closed.

# Acceptance predicate

The project's real loaded metadata distinguishes parsed unknown limits from the effective 16-track ceiling and honors the known 12/3 limits plus the 20-to-16 cap. `checkcatalog.cpp` registers `projectstore-open` to suite `projectStoreOpen`, and `CoreCheckSupport.swift` case 26 calls `runProjectStoreOpenSuite`; the command therefore executes the changed production-file journey, not just a parser fixture.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-open --verbose
deno task proof check --executed
```

# Task-specific constraints

No new check file, manifest change, public interface or mounted control. The four-file exception is one open/catalog budget surface. This is not physical playback proof, and it changes neither track-count policy nor the excluded sample-studio scope.
