# Plan audit

Verdict (final revision): **ready**. The plan now encodes exactly one collision rule — uniform atomic refusal with stable NoteIds — per the binding ruling; the risks recorded below are accepted policy consequences, not open plan defects. This file is a chronological record: the first-cycle audit and the grouped-extension correction are retained as history; the final ruling supersedes the cap/trim/duplicate machinery they describe.

## Basis

Three evidence phases, all source-derived; no application build or behavioral reproduction was run during planning:

1. First cycle: the requested `plan` agent proposed a boolean representability gate in `resolveNoteOverlaps`, optional op builders, range-realism repair and Delete Time reconciliation. The parent independently inspected producer bodies, merge commands, UI callers, existing test fixtures, checkcatalog and the CLI option parser before freezing the stored plan; LSP references enumerated the resolver's consumers and actual resize keyboard/drag callers.
2. Implementation review: the audited plan was implemented as uncommitted work in the main checkout. The production delta vs fork-main measured exactly +343/−116, net +227 (songdocument.cpp +261/−101, songdocument.h +23/−10, songdocument_range.cpp +10/−5, songdocument_timeeditor.cpp +9/−0, four piano-roll files +28, rangeedit.cpp +12; test/doc delta +637 across editcheck, rollcheck and the manual).
3. Final ruling: `agent://NoteIntegrityPlanRuling` — uniform atomic refusal with stable note identity.

## First-cycle findings (retained)

| Severity | Finding / evidence | Stored-plan correction |
| --- | --- | --- |
| Blocker | Per-pitch movement skips unchanged destinations in `buildMoveNotesToPitchesOps`, but exempts the whole selected set from stationary trimming. Validating only rewritten spans misses a selected unchanged note collided with by another selected note. | Task 1 includes unchanged selected paired spans in final participant admission and explicitly tests this case. |
| Blocker | Proposal's merge refusal argument assumed clamping composed additively. Existing merge methods mutate stored accumulated fields before replacing ops; a failed optional rebuild could corrupt later undo. | Candidate fields/ops remain temporary until success. Refusal restores the already-applied two-command state and preserves both command records. Boundary/reversal and later undo/redo are acceptance cases; no claim that refusal is unreachable. |
| Blocker | Proposal placed `applyRangeEdit` validation inside `!m_smf.tracks.empty()`, bypassing an empty-document track-expansion batch. It also omitted combined same-destination groups/eligibility parity. | Task 1 validates the complete eligible emission set before mutation, including new tracks and empty original SMF. |
| Important | Proposal knowingly retained false-success paste announcements. Current `pasteRangeAtEditCursor` and `pasteFromClipboard` also clear selection/advance the cursor after rejection. | Task 2 gates success-only effects on document revision. The empty-content nudge exception remains explicit. |
| Important | Proposed three core/range/ripple tasks share the same behavioral invariant and editcheck surface; check/helper write ownership was not included in their closed sets. | Consolidated into one document package with eleven named files and one acceptance matrix; UI has its own consumer package and verification surface. |
| Important | Proposal claimed selected IDs always survive, but the existing per-pitch builder uses `appendNoteInsertOps` and remints rewritten notes. | Preserve existing accepted-edit identity behavior rather than quietly add an unrelated identity migration. All rejected edits retain IDs exactly. |
| Note | Proposal ranked scale-fold convergence as the most common trigger without measurements. | Removed frequency claims. All defect descriptions explicitly identify code-derived evidence, with runtime proof deferred to execution acceptance. |

Delete Time was independently added during the audit: `TimeEditor::remove` leaves earlier-starting notes intact while shifting later notes left. The stored policy used existing edited-note-wins trimming, with the `[0,100)` / `[110,120)` example and undo/redo proof. A new imported-MIDI cleanup feature remains out of scope.

## User correction: grouped extension (superseded)

*Superseded by the final ruling below; retained as factual history.*

The user replaced rejection for grouped right-edge extension: the earlier selected note must stop at the next selected note's start. The spec and both briefs then required independent end caps, actual capped event emission, and realized-duration-aware undo merging. The concrete +20 example accepted `[0,20)` and `[20,50)`. Later notes continued extending; shortening acted on the visible result without hidden extension debt. That correction superseded the initial blanket-rejection policy, not the underlying first-following-release interpretation — and has in turn been superseded by the final ruling.

## Implementation review and final ruling

The review confirmed the corruption was real — fork-main's resolver was void, planned only stationary trims, and emitted participant-vs-participant overlaps unchecked — and identified the diff's atomicity skeleton as the design to land: side-effect-free optional builders, prebuilt-ops command constructors, refuse-before-history-push, `mergeWith` overflow guards, `applyRangeEdit` combined-destination validation including empty-SMF un-nesting, `moveRange` exact clamped endpoints, `TimeEditor::remove` collision detection, rangeedit revision gates, the `notePairsConsistent` oracle and harness slots, and the insertBlank/duplicate non-goals.

But the implemented resolver carried three policies — participant-vs-participant rejection, participant-vs-stationary silent trim/remove, and identical-duplicate admission on `addNotes` only (already inconsistent with `applyRangeEdit`'s refusal of identical twins) — plus a public planning API (`resizeNotesDurations`) consumed per drag tick, capping and realized-duration undo machinery, and per-pitch reminting that forced by-value merge matching: net +227 production lines for an invariant that refusal alone fixes.

The user then issued the binding direction — **uniform atomic refusal with stable note identity** — explicitly releasing the legacy behaviors: edited-note-wins stationary trimming/removal, the grouped-resize cap with realized durations recorded above, duplicate-span acceptance, and per-pitch identity reminting. The cap rule under "User correction: grouped extension" is superseded by this later ruling; the correction remains part of the record. If the user later reaffirms the cap, the admission predicate stays unchanged and only capping plus realized durations (~75 core lines) return.

Document consequences: spec.md's collision policy is the one rule plus the mechanical overflow/zero-length rules; plan.md routes five brief-backed tasks plus one Direct inline fixup — task 6 realigns two downstream fixtures that uniform refusal would otherwise redden after task 2: `documentPublicationNetZero`/`documentMergedOverlapPublication` move key 69 by +1 onto an equal-start stationary key-70 note, and `transientBandAndStackedNodes` seeds its stacked node through semantic `addNote`; the fixup reroutes the publication slots through free pitches and reseeds the drawer overlap via public `insertRawEvent`. This worktree implements from its fork-main baseline, so the ruling's deletions against the uncommitted diff become "do not introduce" here, and the main checkout's uncommitted work remains reference evidence only.

## Post-audit GUI correction (Task 5 contract)

A GUI audit of the Task-5 surface (`agent://RefusalGuiAudit`, verdict PASS_WITH_FINDINGS) confirmed every refusal gate is truthful except one: `removeTimeSelectionContents` still announced "Nothing to remove in the time selection" on a false `removeTimeRange`, which Task 4's collision refusal now also produces — a false emptiness claim on a refused Delete Time. The brief's freeze of that function predated the manual's refusal sentence and contradicted it. Correction recorded in `task-5-brief.md`: the function keeps its announce-and-early-return shape but must emit one neutral no-change message true of both the no-op and the refused shift, with no new result type, status channel or dialog. The same audit's test-quality notes are folded into the rollcheck acceptance language: an accepted transpose positive control after the refused one, and undo/redo preservation of the accepted move. The audit's informational note stands: the draw gesture clears the note selection at press before any edit attempt, so the manual's "nothing changes" refusal promise does not cover pre-press selection — no plan change at that time, since `pianoroll*.cpp` then remained outside Task 5's write set (the final audit below adds `pianoroll_commands.cpp` for the transpose gate).

## Final-audit corrections (post-implementation review)

Two read-only reviews of the settled worktree diff (`agent://FinalQtAudit`, `agent://FinalThermoAudit`, both verdict FAIL) found no Critical findings and five convergent Important findings plus one Qt-only Important. All are recorded as plan corrections; the briefs and spec now state the corrected contracts. No checks were run or claimed inside the audit agents.

| Finding | Defect | Recorded correction |
| --- | --- | --- |
| Clamp non-composition in merges (QT-3 / Thermo-1) | The reworked `mergeWith` bodies verified only that the incoming command starts at the previous output; an accumulated candidate could pass admission yet rebuild different geometry than the two applied commands (move −20 then +10 clamped at tick 0; duration −20 then +5 clamped at 1). | `task-2-brief.md` and `spec.md` now require a merge to commit only when the accumulated candidate geometry from gesture originals exactly equals the already-applied sequential final geometry per `NoteId`; mismatch returns false before any revert. Boundary/reversal regressions for move, per-pitch time movement and resize are required inside `noteMoveMerge`. |
| Per-pitch destination misalignment (QT-4 / Thermo-2) | `movesMyOutputs` matched by `NoteId` in any order, but `mergeWith` reused `other->m_destPitches` positionally against `m_notes`, swapping destinations under reordered input. | `task-2-brief.md` and `spec.md` require incoming destinations to stay bound to the incoming notes' `NoteId`s — realign to the original order or refuse — with a reversed-input merge regression asserting each `NoteId`'s pitch through undo/redo. |
| Delete Time participant misclassification (QT-1 / Thermo-3) | Only deleted notes entered `editNotes`; shifted notes were treated as stationary, so a shifted note longer than the deleted span refused against its own old span. | `task-4-brief.md` and `spec.md` now classify every paired note with `note.tick >= s` — deleted and shifted — as an `editNotes` participant exempted by `NoteId`; only pre-range notes are stationary. A long-note accepted ripple (final span overlapping only its own old span) is a required positive case in `timeRangeNoOps`. |
| Unterminated per-pitch overflow bypass (Thermo-4) | The `note.unterminated()` skip let a positive `dTick` past `kMaxTick` headroom silently clamp the moved note-on instead of refusing. | `task-2-brief.md` and `spec.md` require start-tick overflow validation for every rewritten note including unterminated ones (end-tick/duration checks remain terminated-only), with a refusal regression inside `noteMoveBatch`. |
| Quadratic cross-pitch admission scan (QT-5 / Thermo-5) | `noteEditAdmissible` compared all participant pairs before filtering by track/key and linearly scanned `editNotes` per stationary note, contradicting the grouped-scan constraint. | `task-2-brief.md` reiterates grouping/indexing by `(engineTrack, key, tick)` with neighbor-only comparisons, efficient `NoteId` membership for exemption, stationary comparisons restricted to the matching group, and one `notesForTrack` pass per touched track. |
| Ungated ordinary transpose (QT-2) | `PianoRoll::transposeSelection` revealed and auditioned the requested destination even when `moveNotes` refused; only the time-selection transpose was gated. | `task-5-brief.md` adds `src/ui/songview/pianoroll_commands.cpp` to its write set (now six files), requires the revision gate before reveal/audition/update, and requires an ordinary selected-note refusal plus accepted positive control in the rollcheck scenario. |

Plan status updated accordingly: the worktree contains the implementation under final review — implemented, unmerged, pending controller validation.

## Intentional behavior changes (user-released)

- Grouped right-edge extension that would collide is refused, reversing the cap-at-next-start rule above. Fork-main's behavior there was corrupted pairing, so there is no regression against a working state.
- No edit silently shortens, moves or deletes a note the user did not select: draw-over-tail, move-onto-note, paste-over and range-move-over now refuse.
- Identical duplicate inserts refuse everywhere; fork-main accepted them as twin notes via plain paste.
- Delete Time that would shift a note onto an earlier same-pitch note refuses; non-colliding ripple delete is unchanged.
- Per-pitch/scale-fold moves preserve NoteIds; unterminated selected notes move their patched note-on instead of staying behind.
- Rejected paste/transpose/nudge no longer clear selection, advance the cursor or announce success.
- Undo-merge failure leaves the document untouched by construction (plan-first rebuild) rather than by a restore dance.

## Residual risks and controller load

- **Policy:** one rule — any final same-track/same-pitch overlap, participant or stationary, refuses the whole edit. Refusal frequency rises in draw-adjacent and extend-to-neighbor workflows; mitigation is the honest no-op UX (task 5), unaffected single-note resize into free space, and legal adjacency.
- **Delete Time straddle:** refusal blocks a structural edit in dense same-pitch material. A trim variant remains a documented one-place exception if users complain, at the cost of re-growing a trim planner.
- **Duplicate identity:** paste-identical-twins workflows disappear; on this engine they were inaudible doubles, and unison via a different pitch/channel remains audible.
- **Kept subtlety:** the `moveNotes`/`resizeNotes` merge compatibility loops remain the subtlest retained code; plan-first rebuild removes their transactional hazard, and they carry regression coverage.
- **Baseline:** implementation proceeds from this worktree's fork-main source; the main checkout's uncommitted implementation is never merged or touched during execution.
- **Controller load:** serial 1 → 2, then parallel 3/4/5/6 on disjoint write sets after the task-2 checkpoint; one final accepted-work checkpoint; native desktop access required for rollcheck and velocity-page shown checks and smoke.

## Structural inventory (historical; re-run before dispatch)

Executed during the first cycle, against the superseded two-task plan:

```sh
bun skill://wbs-plan-audit/scripts/inventory.mjs docs/plans/note-pair-integrity
```

Tool output: two listed tasks and two briefs; no missing/extra briefs or link-name mismatch; complete dictionary fields and named checks; no missing prerequisites, cycles, shared write sets, hot files, fan-in or fan-out. Task 1 had eleven files/five steps, Task 2 four files/four steps. Both exceeded the default file cap under the explicitly recorded cohesive-behavior exceptions, not a false mechanical designation. Critical path was Task 1 → Task 2, length two; only Task 1 was initially ready.

This run predates the revision; re-run it before dispatch. The revised structure is five brief-backed tasks (`task-1-brief.md` through `task-5-brief.md`) plus the Direct inline task 6, critical path 1 → 2 → {3, 4, 5, 6}, with tasks 3–6 mutually disjoint.
