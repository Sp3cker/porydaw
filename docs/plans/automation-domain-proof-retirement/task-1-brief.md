# Task 1 — gestures: terminal dispositions, certificate, delete

## Context

`proof.gestures.txt` carries 67 sites: 62 MATCHED (standing) and the five
PARTIAL sites A048-A052 of `AutomationDomainTest::
pointRangeAndPencilReplacements` (`gestures.cpp:218-226`) — the empty-lane
pencil started with a constructor-injected lead-in `NodePoint{0, 20}`.
The audit (spec §5.1) shows the live Swift already asserts four of the
five observables on the production empty-lane pencil
(`gestures.swift:618-638`, engine-default lead-in 0), and the fifth
(A052's `48:20` restoration) is a mechanism with no Swift public ingress.
This task makes the proof terminal and deletes the C++ original. It is
proof-only: `gestures.swift` is not edited (its SHA pin and the line
anchors eight other proofs cite must stay valid — plan.md file-ownership
policy).

Forward pointer: Task 7 deletes `tst_automationdomain.h`, whose remaining
includers after this task are `xcmd.cpp` alone.

## Exact write set

- `src/checks/automation/domain/proof.gestures.txt`
- delete `src/checks/automation/domain/gestures.cpp`

## Prerequisites

None.

## Interface contract

- A048, A049, A050, A051: `Disposition: MATCHED`; mapping lines cite the
  existing executed predicates under `drawerAutomationPointRangeID`:
  start guard `gestures.swift:623-631` (report.fail on failure — same
  accepted pattern as A053), `!stroke.completion().unchanged`
  (`:637`), exact array `["24:80","48:0"]` (`:632`, closes size, order,
  and first-point observables per the array rule, spec §2.1). Each mapping
  states that the site's observable does not read the injected lead-in.
- A052: `Disposition: RETIRED-REPRESENTATION`; mapping carries the
  no-ingress proof: the C++ `AutomationPencilGesture::start` lead-in
  argument has no public Swift ingress (`AutomationPencilTransaction`
  reads the lead-in from facts — `AutomationFrozenFacts.freeze(
  includingLeadIn:)` → `snapshot.leadInValue` → `metadata.defaultValue`,
  `AutomationLaneProjection.swift:162-165`); no synthetic metadata may
  substitute (spec §2.1 hard rule); the surviving observable is asserted
  through the same production completion path
  (`AutomationPencilTransaction.completion()` →
  `AutomationLaneReplacement.heldSpan`) by `gestures.swift:652`
  (past-last pencil, `["24:80","48:20"]`) and `:544` (heldSpan freeze).
- Preamble becomes the spec §3 certificate: retain `Reference revision
  f3069ef693542bdb63564b80a29773e2f5b2a360`; `Original SHA-256
  edb8678e…` verified against the on-disk file AND
  `git show f3069ef6:src/checks/automation/domain/gestures.cpp` before
  deleting; `Swift counterpart: gestures.swift` + its unchanged on-disk
  SHA `ed769eee…` (re-verify; refresh only if unrelated work legitimately
  changed the file — then re-read and report); `Covered native
  implementation: src/ui/editordrawer/nodelane/nodelane.{h,cpp} ::
  NodeLane/NodeLaneEdit; gesture.h :: PointDragGesture/SweepGesture;
  pencilgesture.h :: AutomationPencilGesture`; `Registered run path:
  runAutomationPageChecks (AutomationPageChecks.swift:361-365) →
  projectSession (suite 10)`; Verification line records the controller's
  post-deletion full swiftcore PASS.
- The trailing supplemental sections (awaited-history regression, QML
  separation note) are preserved verbatim under the certificate — those
  Swift-only scenarios stay live in `gestures.swift`.

## Implementation steps

1. Verify the SHA pins per §2.2 (on-disk `gestures.cpp`, reference
   revision content, `gestures.swift`).
2. `deno task proof:edit automation/domain/gestures.cpp A048 --before
   '<exact PARTIAL block>' --after '<MATCHED block>' --apply` (mapping
   coupled), then A049-A051 likewise, then A052 with the
   RETIRED-REPRESENTATION mapping.
3. Rewrite the preamble to the certificate format (direct edit).
4. Delete `src/checks/automation/domain/gestures.cpp`.
5. Edge cases: do not touch any other A entry, the fixture/loop inventory,
   or `gestures.swift`; do not touch `tst_automationdomain.h` (still
   included by `xcmd.cpp`).

## Acceptance predicate

- NAMED CHECKS: `deno task proof show automation/domain/gestures.cpp`
  parses with 67 sites terminal (66 MATCHED, 1 RETIRED-REPRESENTATION);
  `deno task proof list --area automation/domain` shows gestures
  `PARTIAL 0, GAP 0`; `gestures.cpp` absent from the folder. Implementer
  runs both proof commands; controller runs
  `deno task verify --filter swiftcore --verbose` and records the Result
  line (this is also the certificate's Verification evidence).
- Coverage: the two proof commands prove the ledger end state; the
  swiftcore run proves the retired original's surviving suite (including
  every gestures predicate the MATCHED sites cite) still passes with the
  C++ file gone.

## Task-specific constraints

- If `gestures.swift`'s on-disk SHA differs from the proof pin at task
  start, STOP and report (concurrent-edit signal; plan.md baseline
  policy) instead of refreshing blindly.
- Do not renumber or re-quote the 62 standing MATCHED entries; the
  `proof:edit` tool preserves entry IDs.
