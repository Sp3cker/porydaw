# Plan audit

Verdict: **ready-with-risks**. No unresolved scope/dictionary blockers. This audits a plan, not an implemented repair; no application build or behavioral reproduction was run during planning.

## Basis

The requested `plan` agent proposed a boolean representability gate in `resolveNoteOverlaps`, optional op builders, range-realism repair and Delete Time reconciliation. Parent independently inspected the producer bodies, merge commands, UI callers, existing test fixtures, checkcatalog and CLI option parser before freezing the stored plan. LSP references enumerated the resolver's current consumers and actual resize keyboard/drag callers.

## Findings resolved before freeze

| Severity | Finding / evidence | Stored-plan correction |
| --- | --- | --- |
| Blocker | Per-pitch movement skips unchanged destinations in `buildMoveNotesToPitchesOps`, but exempts the whole selected set from stationary trimming. Validating only rewritten spans misses a selected unchanged note collided with by another selected note. | Task 1 includes unchanged selected paired spans in final participant admission and explicitly tests this case. |
| Blocker | Proposal's merge refusal argument assumed clamping composed additively. Existing merge methods mutate stored accumulated fields before replacing ops; a failed optional rebuild could corrupt later undo. | Candidate fields/ops remain temporary until success. Refusal restores the already-applied two-command state and preserves both command records. Boundary/reversal and later undo/redo are acceptance cases; no claim that refusal is unreachable. |
| Blocker | Proposal placed `applyRangeEdit` validation inside `!m_smf.tracks.empty()`, bypassing an empty-document track-expansion batch. It also omitted combined same-destination groups/eligibility parity. | Task 1 validates the complete eligible emission set before mutation, including new tracks and empty original SMF. |
| Important | Proposal knowingly retained false-success paste announcements. Current `pasteRangeAtEditCursor` and `pasteFromClipboard` also clear selection/advance the cursor after rejection. | Task 2 gates success-only effects on document revision. The empty-content nudge exception remains explicit. |
| Important | Proposed three core/range/ripple tasks share the same behavioral invariant and editcheck surface; check/helper write ownership was not included in their closed sets. | Consolidated into one document package with eleven named files and one acceptance matrix; UI has its own consumer package and verification surface. |
| Important | Proposal claimed selected IDs always survive, but the existing per-pitch builder uses `appendNoteInsertOps` and remints rewritten notes. | Preserve existing accepted-edit identity behavior rather than quietly add an unrelated identity migration. All rejected edits retain IDs exactly. |
| Note | Proposal ranked scale-fold convergence as the most common trigger without measurements. | Removed frequency claims. All defect descriptions explicitly identify code-derived evidence, with runtime proof deferred to execution acceptance. |

Delete Time was independently added during the audit: `TimeEditor::remove` leaves earlier-starting notes intact while shifting later notes left. The stored policy uses existing edited-note-wins trimming, with the `[0,100)` / `[110,120)` example and undo/redo proof. A new imported-MIDI cleanup feature remains out of scope.

## Structural inventory

Executed:

```sh
bun skill://wbs-plan-audit/scripts/inventory.mjs docs/plans/note-pair-integrity
```

Tool output: two listed tasks and two briefs; no missing/extra briefs or link-name mismatch; complete dictionary fields and named checks; no missing prerequisites, cycles, shared write sets, hot files, fan-in or fan-out. Task 1 has eleven files/five steps, Task 2 four files/four steps. Both exceed the default file cap under the explicitly recorded cohesive-behavior exceptions, not a false mechanical designation. Critical path is Task 1 → Task 2, length two; only Task 1 is initially ready.

## Residual risks and controller load

- **Policy tradeoff:** conflicting selected-note batches reject wholesale instead of auto-trimming/dropping selected notes. Keyboard no-op and drag snap-back are intentional. The spec is explicit; no hidden tie-break winner.
- **Undo risk:** merged replanning must preserve both state and command records on failure. Focused regression plus full editcheck is required; compilation alone does not prove this.
- **Native proof:** shown rollcheck and new-song smoke require desktop access. Tests that skip the native path do not satisfy the brief.
- **Scope:** no guarantee is made for arbitrary malformed raw/imported streams, and this plan does not delete existing orphan releases.
- **Controller load:** two serial packages, disjoint writes, no parallel-ready pair or shared-file locks, no large fan-in. One final accepted-work checkpoint suffices. Task 1's larger write set is the necessary closure of one private contract and its tests; Task 2 consumes only public mutation outcomes.
