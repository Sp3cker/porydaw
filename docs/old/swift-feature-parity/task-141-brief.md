# Task 141 brief — missing edit basis conflicts; matching voice edit applies intact

# Context

Prove the bank-edit conflict consumer against fixed literals, not read-back stimuli. The real chain is `DocumentSession.applyBankEdit(slot:value:expected:)` (`DocumentSession.swift:340`, verified: no `DocumentSession+Bank.swift` exists) → `ProjectService.bankApply` (`ProjectService+Bank.swift:191`, mismatches throw `bankConflict`) → `ProjectStore.applyVoicegroupEdit` (`ProjectStore+Edit.swift:14`, `VoicegroupStore.swift:146`), which republishes under the same record id (`VoicegroupStore.swift:180-184`: `publish(id: record.id, …)`), so the applied view keeps the bank identity — no new generation is minted and the fork identity clause ports exactly.

Selected **15 open rows (0 GAP + 15 PARTIAL)** in `src/checks/project/proof.iomutations.txt`. The following is the closed row inventory; citations identify individual assertion-start lines, not the ledger file's line numbers.

| Target A-ids | Fork citation at `fceecd88` |
|---|---|
| A042, A043, A044, A045, A046 | `src/checks/project/iomutations.cpp:352,357,363,365,369` — loaded-view setup guards |
| A047, A048, A049 | `src/checks/project/iomutations.cpp:381,384,386` — stale edit yields the conflict result |
| A050, A051, A052, A053, A054, A055, A056 | `src/checks/project/iomutations.cpp:393,396,400,403,404,406,407` — matching edit applies with view, identity and no materialization |

# Exact write set

- `src/swift/app/DocumentSession.swift` — conditional, the `applyBankEdit` boundary only, rebased on accepted 138; the service/store chain is read-only.
- `src/checks/workspace/bank_edits.swift`
- `src/checks/project/proof.iomutations.txt` — separate ledger writer only, selected rows above (`L` shared with 140; disjoint A-rows, one ledger writer serializes).

# Prerequisites

Accepted 132 (document/history authority), 138 (`DocumentSession` readiness ownership) and the bank-undo gate `3fbfe933`; preserve their adopted-bank, history and undo contracts. RED may be absent: if production already discriminates correctly, the new consumer conjuncts are still the deliverable — report that honestly, never induce a defect.

# Interface contract

Keep `applyBankEdit(slot:value:expected:) async throws -> AppliedBankEdit` and the `bankConflict` throw contract ("conflicts throw and record nothing"). Fix slot 0 of the staged bank and write complete `BankVoice` literals (every field) from the checked-in fixture — an original and an edited value whose key is exactly one higher. No first-filled-slot search or runtime-derived voice oracle. Match the fork stimulus exactly: submit the original value with `expected: nil` to the occupied slot; require `ProjectServiceError.bankConflict`, unchanged history and the literal original voice. A stale non-nil voice is not a substitute for this missing-basis conflict. Submit the edited literal with the true original literal as expected; require the returned `AppliedBankEdit.view.id` to equal the identity captured at original bank load, the slot-0 voice to equal the edited literal, and `materialization` to be nil. Capturing the original identity proves continuity; never read the edited view to construct an expected voice or ID. Existing stale-voice checks remain additional coverage; result-deque positions are retired backend representation.

# Implementation steps

1. Extend `bankConflicts` (or a same-file sibling on the real session) with the conflict-variant discrimination, the unchanged-state literals and the full applied-view conjuncts above; preserve existing messages verbatim.
2. Keep both stimuli on the fixed slot with the fixture-derived literals; an unrelated token or blank-slot case substitutes for neither conjunct.
3. Repair only a demonstrated discrimination or applied-view divergence at the existing edit boundary.

# Acceptance predicate

A missing expected basis on an occupied slot is observably a conflict with nothing recorded or mutated, and the exactly matching edit applies with the edited voice published in place under the same bank identity and nothing materialized. `swiftcore-projectsession` executes the extended bank-conflict checks; no new mounted lane is required for this model-level service contract, and none is claimed.

Under sprint-3 §16 execution ownership, run:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
```

# Task-specific constraints

Only iomutations A042–A056 are writable. The workspace occupied-slot/applied-receipt/hard-failure PARTIALs (workspace A084–A100) sequence after this task on the same bank owners; unknown-synth-save, viewcache pending/dirty-close and savecore A016–A026 stay open. No test-only observation API, no mocks, no fixture-content edits, no shared bank-lease mutation. Read sprint-3 §16 for shared constraints, excluded rows and conditional native retirement.
