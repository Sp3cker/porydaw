# Task 214 brief — project identity's value laws close on their already-executing predicates

**Released** under the user's 2026-09-28 ruling (1), the narrow ledger-only exception:
a row may close in a ledger-only commit only when its named predicate already executes
and the evidence file carries it (sprint-3.md status header, lines 74–76).

# Context

`src/checks/project/proof.identity.txt` (fork source `src/checks/project/identity.cpp`,
identical at the `fceecd88` oracle and the ledger's `a7fcaa3e` Reference revision; C++
deleted in the S6 flip cutover) has 52 sites: A020–A052 are MATCHED, A001–A019 are
PARTIAL. Each PARTIAL cites a related session-service predicate (S008/S009 in
`session_io.swift`) and says the value law is "unproved". That is stale.
`src/checks/projectstore/ProjectIdentityChecks.swift` ports those exact assertions
against the production value types `SongName` and `VoicegroupId`
(`src/swift/project/ProjectIdentity.swift`; used in production by
`ProjectService+Songs.swift`, `SongRegistration+Store.swift`, `VoicegroupStore.swift`).
It uses the fork's literals: `""`/`intro`/`outro`; the seven rejection rows;
`./drums//shared/../perc.vg`; and `drums/perc.vg` with `kick`/`snare`. Swift
`hashValue` stands in for `qHash`, which follows the same equal-values-hash-equal law.

Execution path, verified: `runProjectIdentitySuite`
(`ProjectIdentityChecks.swift:12`) → `songName` / `voicegroupId`. It is dispatched by
`CoreCheckSupport.swift:187` (`case 12`) and registered as check entry
`projectidentitycheck` (`src/checks/checkcatalog.cpp:133`, argv `--swiftcore … projectIdentity`,
macOS Swift lane). The evidence file `build/debug/proof-evidence/projectidentitycheck.json`
(function `SwiftCoreTest::projectIdentity`) already carries every row literal below.
It records passes only, and all 25 are present.

This task closes A001–A019 as MATCHED on new S entries that index those messages. The
ledger then has zero open rows. Its C++ source is already deleted, and no build,
catalog, CMake or tool registration names the ledger file (verified with `git grep`;
the only mention is historical prose in `docs/old/swift-migration-project.md`, which
stays). So the ledger is deleted in the same commit.

Surface: the project-identity value types that every song-open and bank-bind path
constructs (`SongName`, `VoicegroupId`). They are already executing. No production
change.
Ledger spec: `src/checks/project/proof.identity.txt` A001–A019 (19 PARTIAL → MATCHED),
then delete the file.
Verify lane: `projectidentitycheck` (below). It has no gaps for these rows: each row's
predicate is an exact-literal port of its fork assertion.
Blocked rows left untouched:
- visual chrome A007 (`src/checks/visual/proof.chrome.txt`) stays GAP. It is
  `QVERIFY(name)` on `SongName::create("mus_route101")`, a fixture guard inside
  `VisualChromeTest::shellLoaded`, the loaded-shell composite baseline (A018). That
  baseline falls under the standing visual-baseline-PNG exclusion. No executing
  predicate targets that site or its literal. The exception needs "its named predicate
  already executes", and citing `intro`'s acceptance would be a related-test closure,
  which `proof-ledger-workflow` forbids. Its ledger stays open anyway (3 GAP +
  4 PARTIAL, all excluded).
- The voicegroupbank label-guard rows and every other `SongName::create` conjunct in
  other ledgers are out of scope.

# Exact write set

- `src/checks/project/proof.identity.txt`. Edit A001–A019 and append S040–S058, then
  delete the file in the same commit.

No source, check, catalog, CMake or other ledger file. `ProjectIdentityChecks.swift`
is read-only. Its line-3 V-1 comment naming `proof.identity.txt` A037–A052 stays, since
comments naming deleted ledgers are the repo's existing convention (for example,
`MidiCfgChecks.swift:40` names the deleted `proof.save.txt`).

# Prerequisites

None in-wave. No other task in this sprint writes this ledger. Read sprint-3 §29, and
task 213's brief for the ledger-only close-then-delete shape.

# Interface contract

Append 19 S entries after S039. Each entry has a header plus one `Anchor:` line, and
the path is `src/checks/projectstore/ProjectIdentityChecks.swift`. The function field
is `songName` for S040–S047 and `voicegroupId` for S048–S058. `proof:edit` preserves
entry IDs and cannot create them, so append the new entries with a direct text edit, as
precedent `e24ceefc` did for S086/S087.

| Row | Fork site (`identity.cpp`) | New S | `Anchor: message "…"` (exact source literal) |
|---|---|---|---|
| A001 | :76 `!SongName::create("")` | S040 | `A001: empty label is rejected` |
| A002 | :81 `QVERIFY(first)` | S041 | `A002: intro is accepted` |
| A003 | :82 `QVERIFY(same)` | S042 | `A003: repeated intro is accepted` |
| A004 | :83 `QVERIFY(different)` | S043 | `A004: outro is accepted` |
| A005 | :87 `value() == "intro"` | S044 | `A005: accepted label round-trips` |
| A006 | :88 `*first == *same` | S045 | `A006: equal labels have equal identity` |
| A007 | :89 `*first != *different` | S046 | `A007: distinct labels have distinct identity` |
| A008 | :90 `qHash` equal | S047 | `A008: equal song identities have equal hashes` |
| A009 | :108 seven `_data` rejections | S048 | `A009/\(row): path is rejected` |
| A010 | :115 `QVERIFY(normalized)` | S049 | `A010: relative source is accepted` |
| A011 | :118 `sourceRelativePath` | S050 | `A011: source path is lexically normalized` |
| A012 | :119 empty `sectionLabel` | S051 | `A012: empty section label is preserved` |
| A013 | :127 `QVERIFY(kick)` | S052 | `A013: kick section is accepted` |
| A014 | :128 `QVERIFY(sameKick)` | S053 | `A014: dotted kick path is accepted` |
| A015 | :129 `QVERIFY(snare)` | S054 | `A015: snare section is accepted` |
| A016 | :133 `sectionLabel == "kick"` | S055 | `A016: section label round-trips` |
| A017 | :134 `*kick == *sameKick` | S056 | `A017: equivalent source paths and sections have equal identity` |
| A018 | :135 `*kick != *snare` | S057 | `A018: distinct sections have distinct identity` |
| A019 | :136 `qHash` equal | S058 | `A019: equal voicegroup identities have equal hashes` |

S048's anchor keeps the Swift interpolation verbatim, as lifecycle S-entries do with
`\(target)`. The anchor resolver matches `\(…)` as a wildcard, so it resolves to the
single `report.expect` at `ProjectIdentityChecks.swift:49-50`. The evidence carries all
seven concrete rows (`A009/empty`, `/absolute`, `/parent`, `/parent-file`,
`/nested-parent`, `/project-root`, `/normalizes-to-root`).

Each row closes in compact form. The header is unchanged, followed by
`Disposition: MATCHED` and one line
`Mapping: S0xx - <one-line clause naming the Swift value law>`, in S023's style. Drop
`Source context since previous assertion:` and `Original expression:` bodies. Paste no
code.

# Implementation steps

1. Run `deno task checks --filter projectidentitycheck --verbose` so the evidence file
   is fresh against current source. It must pass, and the JSON must carry all 25 row
   literals above. If a literal is missing, stop and report. Do not edit the Swift
   check.
2. Append S040–S058 exactly as in the table.
3. For each of A001–A019, run one `deno task proof:edit src/checks/project/proof.identity.txt A0xx --before '<current Disposition … Original expression block>' --after '<Disposition: MATCHED + Mapping line>' --apply`.
   The mapping line changes, which satisfies the editor's disposition rule.
4. Run the acceptance commands below on the edited, not-yet-deleted ledger.
5. `git rm src/checks/project/proof.identity.txt`. Commit steps 2–5 as one commit. The
   commit message body lists `A001–A019 MATCHED on S040–S058
   (ProjectIdentityChecks.swift songName/voicegroupId; evidence
   projectidentitycheck.json); ledger deleted at zero open rows`.

# Acceptance predicate

Before deletion, the edited ledger resolves every new anchor, and every one executes.
After deletion, no project-identity ledger remains, and the lane still passes.

```sh
deno task checks --filter projectidentitycheck --verbose
deno task proof sites src/checks/project/proof.identity.txt --status PARTIAL   # 0 sites
deno task proof check --executed
deno task proof check --strict-mappings
# after git rm:
deno task proof check --executed
```

- `proof check --executed` must report 0 errors. It must print no
  `src/checks/project/proof.identity.txt S0xx: not executed` line and no
  `MATCHED site(s) without executed predicates` failure.
- `proof check --strict-mappings` exits non-zero on pre-existing debt in other ledgers
  (strict debt ≈215). Its error list must contain no line naming
  `src/checks/project/proof.identity.txt`.
- The implementer runs all of these. Coverage: the lane proves the 19 value laws on
  production types. `proof` proves the anchors resolve and execute.

# Controller verification

After the commit, rerun `deno task checks --filter projectidentitycheck --verbose`,
then confirm that `build/debug/proof-evidence/projectidentitycheck.json` carries the 25
literals in the table. That includes the seven `A009/<row>: path is rejected` rows. The
closure record is this table, because the edited ledger does not survive in history.

# Task-specific constraints

- This is the sole writer of `src/checks/project/proof.identity.txt`.
- No predicate is added or changed. If evidence is missing, stop; do not "fix" the
  check.
- Do not touch `src/project/projectidentity.{cpp,h}`. They are built native production
  code (`CMakeLists.txt:206-207`, bridged by `banklease.h`) and still referenced by open
  ledgers (workspace, chrome, voicegroupbank, viewcache).
- Do not touch `proof.chrome.txt` or any other ledger.
