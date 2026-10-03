# Task 128 brief — regioned song registration keeps SE/MUS IDs, markers and debug lists coherent

# Context

Complete the region-aware half of the existing Register/Delete Song surface. Consume 126's ordinary registration repair and 127's removal/refusal contracts; preserve both while exercising numeric and symbolic END_SE/END_MUS layouts. This is project-file behavior behind the existing Songs dock, not a new onboarding wizard.

Verified planning selection: **82 open rows (82 GAP + 0 PARTIAL)** from sprint-3 §14.

- `src/checks/onboardcheck/proof.regionedlayout.txt` — A001–A082, inclusive.

Oracle: `fceecd88`; source pin `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`.

# Exact write set

- `src/swift/project/SongRegistration.swift`
- `src/swift/project/SongRegistration+Writes.swift`
- `src/swift/project/SongRegistration+Removal.swift`
- `src/swift/project/SongRegistration+Debug.swift`
- `src/checks/songlist/songlist_service.swift`
- `src/checks/songlist/SongRegionRegistrationChecks.swift` — new, region-marker allocation/migration scenarios.
- `src/checks/CMakeLists.txt` — register the new Swift check source only.
- `src/checks/onboardcheck/proof.regionedlayout.txt` — separate ledger writer only.

Closed list. The ledger may close completely; regionedlayout.cpp is already absent. No unbuilt native production deletion is enabled by this ledger alone. SongDocument and workspace units retain the import/action/project/routing blockers listed in §14; no built project/native boundary may be deleted.

# Prerequisites

Accepted/checkpointed 126 and 127 before reusing their registration/removal/check files. Their public interfaces remain unchanged. The existing shell-songs mounted route is the consumer smoke; this task does not need another QML fixture or shell runner entry.

# Interface contract

- Keep RegistrationRegions, SongTableScan, SongRegistration.plan/register/unregister and DebugSoundLists as the only owners. Preserve numeric markers as numeric, aliases as symbolic and comments/indentation/line endings byte-for-byte outside the exact fork changes. No alternate registry or parsing convention.
- Reproduce both regionFixture variants from the pinned source. In the numeric layout, se_valcheck receives ID 3 and the SE player number 1; mus_valcheck receives ID 7, END_MUS advances to 7 then returns to 6 on removal. Markerless planning follows its exact fork expected ID. Compare complete table/header/charmap bytes and unchanged linker/debug images after the paired cycle, not only substring presence.
- In the alias layout, mus_oldcheck receives ID 7 and END_MUS refers to MUS_OLDCHECK; its charmap entry is `MUS_OLDCHECK = 07 00`. se_oldcheck receives ID 3, appears in SOUND_LIST_SE, and re-registration is idempotent.
- Stage mus_straggler beyond END_MUS with the original ID-9 bytes. Registration migrates it to ID 8, repairs header/charmap and keeps debug.c byte-identical. Removal restores END_MUS to MUS_OLDCHECK. mus_refill and the reuse-source/refill cycle both reuse ID 8 with correct marker adjacency.
- Fill the remaining SE slot with se_extra at ID 4. se_over then receives ID 9 in the music region: END_MUS refers to SE_OVER and its debug entry belongs before SOUND_LIST_SE, in the BGM list. Preserve every original before/after file snapshot and both registration completeness queries.
- Expected IDs, complete bytes and marker targets come from the fork's two fixture variants, never from RegistrationPlan output. Fixture writes/reads and native optional guards are setup representations; execution must still fail on I/O errors. Do not replace them with setup-success assertions or infer this ledger closes onboardcheck/debuglayout's separate formatting matrix.

# Implementation steps

1. Add runSongRegionRegistrationChecks(report:fixtureRoot:) in its concept file, call it from the existing registered song-list service entry and register the source.
2. Run numeric/alias allocation, migration, reuse and overflow journeys on separate copied fixture roots with independent expected images.
3. Repair only demonstrated marker/renumber/debug-placement divergences in the existing owners, preserving 126/127's ordinary repair and removal behavior.
4. Have the separate ledger writer map/delete only this complete inventory after executed evidence settles.

# Acceptance predicate

Both original region-layout variants survive register/remove/re-register with exact IDs and files, including out-of-region migration and SE overflow. The existing mounted Songs route continues to execute the same production service interface.

The implementer runs:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
```

# Task-specific constraints

Read sprint-3 §14 “Evidence and execution contract.” No ApplicationSession, QML, service-signature, fixture-content or other onboarding-ledger writes. Keep every Swift/QML file at most 600 lines; the single-domain checks/CMakeLists.txt source manifest is exempt and remains the direct registration owner. The new check file owns one region-allocation concept; do not scatter the two dependent scenario sequences into per-row fragments.
