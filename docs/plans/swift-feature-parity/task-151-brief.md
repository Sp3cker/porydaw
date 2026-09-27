# Task 151 brief — registration and deletion plans retain the requested song identity

# Context

Complete the nonmutating project-plan consumer used by the mounted Songs confirmations. The selected fork clauses live inside a FIFO test, but describe returned plan/catalog values, not ordering. Swift already exposes these values through `ProjectService` and `ProjectStore`; no worker queue or result bus is required. Task 147 is the mounted consumer of this existing interface, while this task proves the request identity and complete plan values independently of UI state.

Selected **12 GAP rows** in `src/checks/project/proof.ioflow.txt`, at `fceecd88:src/checks/project/ioflow.cpp`:

| Target A-ids | Fork assertion-start lines / clause |
|---|---|
| A021–A027 | 109,110,111,112,113,114,115 — requested label, constant, player, ID, table line, registered status |
| A028–A032 | 117,118,119,120,121 — deletion target/index/count, shared-bank protection, catalog |

No selected row is a fixture-only setup guard. A021/A028's keyed result-envelope representation is retired only alongside an executed assertion that the returned plan describes the exact requested song; never add an envelope field merely to mimic C++.

# Exact write set

- `src/swift/app/ProjectService+Songs.swift` — `songRegistrationPlan` and `songDeletionPlan` only, conditional repair.
- `src/swift/project/SongRegistration+Store.swift` — `registrationPlan`, `removalPlan` and `deletableVoicegroup` only, conditional repair.
- `src/checks/songlist/songlist_service.swift`
- `src/checks/project/proof.ioflow.txt` — A021–A032 only.

# Prerequisites

Accepted registration/deletion contracts 127/128/131/145. Task 150 owns the region algorithms; consume their established API without editing those files. No wave-147 dependency: task 147's UI and these API checks have disjoint writers. Read sprint-3 §17.

# Interface contract

Preserve `ProjectService.songRegistrationPlan(label:) async throws -> SongRegistrationPlan`, `songDeletionPlan(label:) async throws -> SongDeletionPlan`, `voicegroupCatalog()` and the `ProjectStore.registrationPlan(label:constant:player:)`, `registrationStatus(label:constant:)`, `removalPlan(label:constant:)` queries.

Use a copied deterministic project with two registered songs sharing a bank. Request each song by its fixed label rather than current row/selection. The registration values must carry the exact label, constant, player and numeric ID from the seeded table; the lower store plan must contain the exact song-table row, and status must report `inSongTable == true`. The deletion plan must identify that song's exact table index and total table count; a bank still used by the other song must not be offered for deletion. Compare the catalog's complete `groupArgs` against an independently written fixture literal, not `!isEmpty`. Planning and catalog reads leave all registration/MIDI/bank source bytes unchanged.

# Implementation steps

1. Extend `runSongListServiceChecks` with the two fixed-label plan queries on its copied project, preserving the existing stray/partial/registered listing checks.
2. Exercise service plans plus the lower store's table-line/status fields, whose richer representation is intentionally not exposed by the UI adapter. Assert literal IDs/fields and nil deletable shared-bank name; do not manufacture a service field for an internal line.
3. Confirm the existing voicegroup catalog is exact and plan reads preserve the seeded disk images. Repair only demonstrated identity/value mapping errors in the two named query boundaries.
4. Close A021–A032 from the new real-plan consumer predicates. Keep the enclosing test's unselected FIFO, completion-count and sample-probe obligations open.

# Acceptance predicate

Both requested songs produce their own correct registration/removal plans regardless of current UI selection, shared banks stay protected and queries are read-only. `SessionChecks.swift` invokes `runSongListServiceChecks` from `runProjectSessionSuite`, so the focused lane exercises these actual service/store queries.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
deno task proof check --executed
```

# Task-specific constraints

Ioflow A001–A020/A033–A065 remain unchanged, including FIFO/catalog preemption and preview-path obligations. No new async scheduler, event log, sample probe, result envelope or source-list entry. Four files form one plan-query surface. This does not close the whole ioflow ledger.
