# Task 134 brief — opening a project publishes a detached snapshot and preserves the prior project on failure

# Context

Complete the existing project-open value surface consumed by the Songs dock. Current Swift ProjectSnapshot already owns songs, players and budgets; no snapshot infrastructure needs inventing. This is distinct from task 133 song-stage failures.

Selected **16 open rows (0 GAP + 16 PARTIAL)** in `src/checks/project/proof.ioflow.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file’s line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A003, A004, A005, A006, A007, A008, A009, A010, A011, A012 | `src/checks/project/ioflow.cpp:64,65,69,70,71,72,74,75,76,77` — `openPublishesSnapshotDetached` |
| A033, A034, A035, A036, A037, A038 | `src/checks/project/ioflow.cpp:128,135,137,139,143,144` — `failedOpenKeepsWorkerProject` |

# Exact write set

- `src/swift/project/ProjectStore+Open.swift`
- `src/swift/app/ProjectService+Songs.swift`
- `src/checks/projectstore/ProjectStoreOpenChecks.swift`
- `src/checks/workspace/session_io.swift`
- `src/checks/project/proof.ioflow.txt` — separate ledger writer only, selected rows above.

# Prerequisites

Accepted/checkpointed 133 before session_io.swift reuse; accepted 126–128 before ProjectService+Songs.swift reuse.

# Interface contract

Preserve ProjectStore.open() async throws -> ProjectSnapshot, ProjectSnapshot.trackBudgetFor(song:), ProjectService.open(root:), songs() and openSong(label:). Assert normalized root, exact fixture song order, five player entries, one-track budget 1 for the one-track effect, playable/config flags and matching selected song identity. Hold the returned value, replace the copied source registry and reopen: the old value remains unchanged while the new result reflects the new source. A failed replacement open yields an error without discarding the prior service store; subsequently read its songs and successfully open the original song with identical metadata. Old completedInline/callback and SamplesProbed envelopes are backend representation; preserve async caller isolation and usable retained project, not a recreated worker protocol.

# Implementation steps

1. Extend runProjectStoreOpenSuite with detached-value mutation and the exact five-player/one-track conjunctions using the checked-in fixture table as independent oracle.
2. Extend sessionOpenAndRecovery to compare the complete retained listing/source after a failed replacement, not only its label.
3. Repair only candidate adoption in the existing open owners; preserve registration/removal methods in ProjectService+Songs.swift byte-for-byte.

# Acceptance predicate

Returned snapshots stay detached, reopened snapshots reflect changed source, and failed replacement leaves the prior project usable. projectstore-open exercises the value contract; projectsession exercises actual ProjectService retention; shell-open-failure is an unchanged mounted consumer smoke.

Under sprint-3 §15 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-open --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-open-failure --verbose
```

# Task-specific constraints

No FIFO scheduling/catalog preemption, sample probing API, new project-state machine, or policy change to deliberate project-switch priority. Only ioflow A003–A012 and A033–A038 are selected. Read sprint-3 §15 for shared constraints, excluded rows and conditional native retirement.
