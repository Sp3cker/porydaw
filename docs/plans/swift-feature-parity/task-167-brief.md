# Task 167 brief — re-audit project identity A001–A019 and close the ledger whole

# Context

`src/checks/project/proof.identity.txt` holds **19 PARTIAL rows (A001–A019)** that were
never re-audited after the identity cutover: their mappings cite session-level behavior
(`session_io.swift` S008) while the value-level owner and its checks already exist and
execute. `src/checks/projectstore/ProjectIdentityChecks.swift` carries the clauses —
`SongName` acceptance/rejection/round-trip/equality/hash (A001–A008, literals
`"A001: empty label is rejected"` … `"A008: equal song identities have equal hashes"`)
and `VoicegroupId` rejections, normalization and section hashing (A009–A019) — and
`build/proof-evidence/projectidentitycheck.json` contains the executed rows (42
passes, including A001–A005 sampled at planning). The production owner is
`src/swift/project/ProjectIdentity.swift` (`SongName.init(_:)`,
`VoicegroupId.init(sourceRelativePath:sectionLabel:)`), consumed unchanged.

Fork citations (pinned revision per the ledger header,
`src/checks/project/identity.cpp`): `songName_acceptRejectRoundtripHash` A001–A008 at
assertion starts 76, 81–90; `voicegroupId_rejections` A009 at 108 (seven data rows);
`voicegroupId_normalizationAndSectionHash` A010–A019 from 118 onward.

**Whole-ledger closure**: the ledger's remaining rows are already MATCHED/RETIRED;
upgrading A001–A019 disposes every row, so the ledger is deleted in the same commit.
Its C++ source is already absent (verified); record the pinned-revision citation.

# Exact write set

- `src/checks/project/proof.identity.txt` — A001–A019 dispositions, mappings and message anchors; then deleted (whole-ledger closure).

No production or check-source changes: the predicates and executed evidence already
exist. If any clause's predicate is found missing or non-executing at freeze, stop and
report instead of forcing the closure.

# Prerequisites

None. Disjoint from all sibling tasks. Read sprint-3 §19 for shared constraints.

# Interface contract

Each A-row maps to the existing `ProjectIdentityChecks` predicate proving its clause,
with `Anchor: message "<literal>"` quoting the exact emitted literal (the `A0xx: `
prefix is part of the source literal and the evidence row). Dispositions become
MATCHED only where the evidence row exists; setup/data-table guards (the fork's seven
`voicegroupId_rejections` data rows ride A009) classify inside that row's mapping
reason, not as new rows.

# Implementation steps

1. Run the identity lane for fresh evidence; confirm every A001–A019 row appears.
2. Upgrade the 19 rows to MATCHED with their message anchors and one-line mapping
   reasons naming the value-level owner.
3. Verify no open row remains, then delete the ledger, citing the pinned revision and
   the already-absent C++ source.

# Acceptance predicate

The identity value contract is proved by executed, message-anchored predicates and the
ledger closes whole.

Named checks under §19 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectidentitycheck --verbose
deno task proof check --executed
deno task proof list
```

`proof list` no longer reporting `src/checks/project/proof.identity.txt` is part of
the acceptance.

# Task-specific constraints

Do not substitute `swiftcore-projectsession` for the exact `projectidentitycheck`
lane. Ledger deletion authorizes no production C++ removal. Do not touch
`ProjectIdentity.swift`, other identity-family ledgers, or any sibling write set.
