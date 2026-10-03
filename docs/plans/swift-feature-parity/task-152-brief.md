# Task 152 brief — workspace bank edits publish a coherent applied view and receipt

# Context

Complete the existing workspace bank-edit consumer at the document publication boundary. Task 141 proved the raw missing-basis conflict and matching applied receipt; the remaining workspace clauses need the receiving document's full adopted view/identity, not another copy of the same edit fixture. Extend `bankMissingBasisAndApplied` in place so its existing real edit proves that the receipt and publicly visible document bank agree when the async operation returns. The consumer is the existing voice editor's `DocumentSession` bank projection.

Selected **15 PARTIAL rows** in `src/checks/project/proof.workspace.txt`, at `fceecd88:src/checks/project/workspace.cpp`:

| Target A-ids | Fork assertion-start lines / clause |
|---|---|
| A084–A090 | 586,588,594,596,598,602,606 — open/load/occupied-slot and old publication-envelope setup |
| A091 | 619 — occupied-slot edit with missing basis conflicts |
| A092–A098 | 635,638,641,642,644,647,649 — applied view/receipt and original bank identity |

Setup-only: A084–A086, A088–A090. A087/A092–A097's deque counts, event variants and pointer-presence representation must not become fake Swift events; retain the successful operation and coherent adopted-view consumer. A098's bank identity remains portable. A099/A100 (unknown-ID construction/edit hard failure) stay PARTIAL: the public Swift lease API cannot submit a fabricated ghost identity, and an unrelated filesystem error is not an equivalent stimulus.

# Exact write set

- `src/swift/app/DocumentSession.swift` — `applyBankEdit`/bank-view adoption boundary only, conditional repair.
- `src/swift/app/SharedBankState.swift` — `accept`/`publish` coherence only, conditional repair.
- `src/checks/workspace/bank_edits.swift` — extend `bankMissingBasisAndApplied`; preserve other bank scenarios.
- `src/checks/project/proof.workspace.txt` — A084–A098 only.

# Prerequisites

Accepted/checkpointed 141, 144 and 146 before reusing `DocumentSession.swift` or `bank_edits.swift`. Their missing-basis literals, empty-history/fanout and message anchors are preservation contracts. Task 153 exclusively owns the service save file; this task consumes `ProjectService.bankApply` read-only. Read sprint-3 §17.

# Interface contract

Preserve `DocumentSession.applyBankEdit(slot:value:expected:) async throws -> AppliedBankEdit`, `SharedBankState.accept(_:)` and `ProjectBankViews.publish(_:)`.

Use task 141's complete slot-0 square voice literals (key 60 original, key 61 edited). Missing `expected` on occupied slot 0 must throw exactly `.bankConflict` and preserve every publicly visible slot, dirty state, bank source/section identity and publication revision, not only the first voice. Matching `expected` applies once; after return, the document's full slot view, dirty state, load name, lease source/section and publication revision must match the returned applied view and the independent expected edited slot. Identity comparison uses the pre-edit bank identity; publication freshness uses the captured pre-edit revision. Preserve the existing one-history-action and no-materialization-token outcomes. Do not assert the retired C++ two-event ordering or introduce a callback counter.

# Implementation steps

1. Reuse the existing fixed-slot conflict/applied scenario and messages rather than adding a parallel raw bank-edit journey. Capture the complete pre-edit view and identity before either stimulus.
2. Strengthen the conflict observation to cover the full bank view and revision; strengthen successful return to require the entire adopted document view equals the returned receipt plus the independent edited literal.
3. Repair only a demonstrated adoption/publication mismatch in the named owners, preserving stale-revision rejection and publication-owner separation in `SharedBankState`.
4. Close the selected behavior clauses with fresh evidence and retire only the named old publication/setup representations. Leave the ghost-ID branch and all unrelated workspace rows open.

# Acceptance predicate

The voice editor cannot observe a stale or mixed bank view after a successful edit, and a missing-basis conflict publishes nothing. `runBankHistorySuite` in `SessionChecks.swift` invokes `bankMissingBasisAndApplied`; the bank-history lane, not a similarly named project-open lane, executes this extended scenario.

Named checks under §17 ownership:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
deno task proof check --executed
```

# Task-specific constraints

No fabricated `NativeBankLease`, unknown-ID constructor, event bus, test-only publication API or service method change. No second-tab scenario is needed for these selected receipt clauses. A099/A100 and workspace A001–A083 are deliberately untouched; the ledger is not a whole-ledger closure candidate.
