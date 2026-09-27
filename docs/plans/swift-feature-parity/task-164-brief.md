# Task 164 brief — message-anchor the voicegroup bank and source-editing debt

# Context

The largest verified strict-mapping clusters whose existing literal predicates already
execute: **56 sites** across two voicegroup ledgers. Both checks emit bare distinctive
literals that appear verbatim in their evidence artifacts (verified at planning):
`src/checks/projectstore/BankLeasesChecks.swift` emits 36 clause literals whose rows
appear in `build/proof-evidence/vgbankcheck.json`; `src/checks/projectstore/
VoicegroupEditingChecks.swift` emits bare messages since 0b12f4e7 and its rows appear
in `build/proof-evidence/projectstore-editing.json`. The debt is only that the cited
S-sites carry `Anchor: function`.

Selected debt sites (from the live `deno task proof check --strict-mappings`
inventory; re-derive the exact list at freeze):

| Ledger | Sites | A-ids |
|---|---:|---|
| `src/checks/voicegroup/proof.tst_voicegroupbank.txt` | 38 | A002–A013, A019, A021, A025, A027, A028, A034, A036–A040, A043, A047, A051, A053, A058–A062, A068, A069, A074–A076, A078, A084 (cited S-sites S003–S046 in `BankLeasesChecks.swift`) |
| `src/checks/voicegroup/proof.voicegroupsourceediting.txt` | 18 | A015–A018, A031, A043–A052, A055, A056, A082 (cited S-sites among S001–S090 in `VoicegroupEditingChecks.swift`) |

Conversion rule per site: the cited S-site's `Anchor: function` becomes
`Anchor: message "<literal>"` quoting the exact executed literal emitted by that
S-site's function; add `#n` occurrence indexes where the literal repeats inside the
function. A019–A021's shared lease-reuse literal legitimately covers two clauses: both
A-rows may cite the same message-anchored S; keep the existing shared-reason wording.
Any site whose literal cannot be uniquely matched stays debt with an explicit reason —
do not force it.

# Exact write set

- `src/checks/voicegroup/proof.tst_voicegroupbank.txt` — the 38 selected sites' S-anchors only (anchor ownership handed to the ledger writer under the standing protocol).
- `src/checks/voicegroup/proof.voicegroupsourceediting.txt` — the 18 selected sites' S-anchors only.

No check-source changes: the literals already exist and execute.

# Prerequisites

None. Disjoint from Task 158. Read sprint-3 §19 for shared constraints.

# Interface contract

Anchors must resolve against the live check sources (`deno task proof check` reports
no `literal not found`/ambiguity) and match executed rows (`proof check --executed`).
Dispositions stay MATCHED; only anchor kinds and occurrence indexes change. The
before/after `(ledger, A-id)` strict inventory is recorded in the task report.

# Implementation steps

1. Capture the fresh strict inventory for both ledgers (before).
2. For each selected site, identify the cited S-site's function, its emitted literal,
   and the evidence row; upgrade the anchor with occurrence index where needed.
3. Re-run both lanes for fresh evidence, then the strict inventory (after); the delta
   must equal exactly the converted set.

# Acceptance predicate

Every converted site is `MATCHED` with a message anchor whose literal resolves and
executes; the strict debt for these two ledgers falls from 56 to only the sites left
with explicit reasons.

Named checks under §19 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter vgbankcheck --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter projectstore-editing --verbose
deno task proof check
deno task proof check --strict-mappings
deno task proof check --executed
```

# Task-specific constraints

No disposition changes, no new predicates, no check-source edits, no compaction. This
is the renewed bounded mapping exception: only sites whose existing executed literals
prove the clause convert; everything else keeps its debt with a written reason.
