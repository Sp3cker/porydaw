# Task 150 brief — regioned registration removal, marker repair and reuse

# Context

Complete the existing Songs registration/removal consumer for numeric and symbolic region layouts. `runSongRegionRegistrationChecks` already executes numeric, alias, stranded-migration and overflow journeys; several ledger GAP descriptions predate those checks. Reuse them rather than duplicate the same assertions. The deliverable is complete byte-preserving remove/re-register coverage, including the symbolic repeat's complete debug image, with the remaining setup representations classified alongside that surface. The consumer is the existing `SongRegistration` API used by the Songs service, not a new region editor.

Selected **35 GAP rows**, all remaining open rows in `src/checks/onboardcheck/proof.regionedlayout.txt`. Ordered IDs map one-for-one to assertion-start lines at `fceecd88:src/checks/onboardcheck/regionedlayout.cpp`:

| Target A-ids | Fork lines / scenario |
|---|---|
| A001–A005 | 78,80,88,92,96 — numeric fixture/read/write guards |
| A010, A013, A018–A020 | 114,123,134,136,139 — SE adjacency and numeric removal |
| A022, A024, A026, A028, A030, A032 | 150,152,154,156,158,160 — full removal images and reusable ID |
| A034, A035, A038, A041, A046 | 183,185,192,196,209 — alias setup, marker, complete status and repeat |
| A048–A054 | 220,223,226,228,229,233,237 — stranded fixture construction |
| A059, A061, A063, A068, A071, A079, A081 | 247,251,255,268,276,299,302 — migration/removal/read guards |

Setup-only/error-buffer rows: A001–A005, A013, A018, A034, A048–A054, A059, A063, A068, A079, A081. Successful mutation return rows A019/A035/A046/A061/A071 accompany the resulting-state journey; they do not justify bare not-throw assertions or new result envelopes.

# Exact write set

- `src/swift/project/SongRegistration.swift` — `plan`/`statuses` region decisions only, conditional on a demonstrated divergence.
- `src/swift/project/SongRegistration+Writes.swift` — region insertion/renumbering only, conditional.
- `src/swift/project/SongRegistration+Removal.swift` — `unregister` marker and fallback-slot behavior only, conditional.
- `src/checks/songlist/SongRegionRegistrationChecks.swift`
- `src/checks/onboardcheck/proof.regionedlayout.txt` — selected rows; deletion eligible only under §17's whole-ledger gate.

# Prerequisites

Accepted 127/128/131 and 145 registration, removal and byte-preserving debug-list contracts. No interface dependency on another wave-147 task; task 147 consumes this established registration API read-only. Read sprint-3 §17 for shared constraints and execution ownership.

# Interface contract

Preserve `SongRegistration.plan(root:label:constant:player:) -> RegistrationPlan`, `status(root:label:constant:) -> RegistrationStatus`, `register(root:label:constant:player:) throws -> Int` and `unregister(root:label:constant:) throws`.

Numeric SE insertion fills ID 3 and retains the following dummy row. Numeric BGM insertion uses ID 7; removal restores `END_MUS` to 6, replaces the nonterminal table slot with the fallback song, retains shifted phonemes at 8/9, restores the original complete debug bytes, preserves linker bytes and makes ID 7 reusable. Symbolic BGM insertion repoints `END_MUS` to `MUS_OLDCHECK` and reports no registration gaps; repeating SE registration preserves ID 3 and every complete file image. Stranded migration uses ID 8 and removal restores the symbolic marker; the next music song reuses ID 8. Preserve the existing overflow contract (SE ID 9 in the BGM debug list, phonemes shifted to 10/11).

`RegionImages`/`RegionJourneyImages` are independent literal oracles. Reuse their exact byte images. Complete the repeated-symbolic debug oracle as a full literal image rather than substring-count checks; do not generate expected bytes from production output. Existing message predicates already covering selected clauses remain single witnesses, not duplicated checks.

# Implementation steps

1. Keep the four existing scenario entry points and fail-closed staging. Strengthen the remove/re-register boundaries with complete literal images and exact status/plan values; replace incidental substring/count-only repeat checks with the full byte-image consumer assertion.
2. Verify numeric removal's marker and alias repeat's completeness through the public APIs, preserving all existing numeric/stranded/overflow outcomes and independently expected phoneme values.
3. Repair only a demonstrated region decision, insertion or removal divergence in the named declarations. Debug-list parsing remains the accepted 145 owner and is read-only.
4. Classify the named setup/error-buffer representations without adding passing setup predicates; close the selected behavior rows only from fresh executed witnesses in this same surface change.

# Acceptance predicate

Remove/re-register cycles retain exact table/header/charmap/debug/linker bytes and numeric/symbolic ID semantics. `songlist_service.swift` invokes `runSongRegionRegistrationChecks`, reached from `runProjectSessionSuite`; the first command executes these file/API consumers. `shell-songs` is the existing mounted Register/Remove smoke, not evidence for byte equality.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-songs --verbose
deno task proof check --executed
```

# Task-specific constraints

No new scenario file, runner registration, debug parser, public API or production C++ deletion. Existing closed rows are preservation obligations, not a second mapping sweep. This ledger is a whole-ledger closure candidate, not a certificate to delete native project boundaries or other registration witnesses.
