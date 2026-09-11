---
name: sdd-plan-writing
description: "When authoring an implementation plan executed task-by-task: bounded briefs, symbol-level change/preservation contracts, no repetition, verification-sized tasks, and sparse milestone checkpoints instead of per-task commits."
---

# Plan writing (SDD-compatible output)

Applies when authoring a plan executed via `sdd-triage-gate` /
`sdd-execution-loop`. The plan's job: implementers never invent, reviewers
never guess, nothing stated twice.

## Layout

- `docs/plans/<plan>/plan.md` — task list, one line each, plus route per
  task (Direct vs SDD-track with a one-line justification citing triage
  signals; seat is `sdd-implementer` unless the work is Qt-heavy — Qt
  Widgets/C++ touching ownership, threading, or model contracts — which
  names `qt-cpp-reviewer` instead).
- `docs/plans/<plan>/spec.md` (or a plan section) — agreed behavior, shared
  vocabulary, forward-facing interfaces.
- `docs/plans/<plan>/task-N-brief.md` — one per task, skeleton below. The
  loop's dispatch quotes it; the reviewer judges against it.
- Global Constraints live ONCE in plan.md. Briefs reference that section and
  carry deltas only.

## Brief skeleton (these headings, no extras)

1. Context — what changes and why, plus the forward pointer: a producer
   task names its planned consumer; a consumer cites the producer's contract.
2. Exact write set — files touched or created. Closed list.
3. Prerequisites — task numbers whose *interfaces* this consumes, never
   their implementation detail.
4. Interface contract — exact names, signatures, and behaviors produced.
5. Implementation steps — what + constraints + edge cases per step.
6. Acceptance predicate — ending in NAMED CHECKS (commands). A prose claim
   with no check is unwritable.
7. Task-specific constraints — deltas on top of Global Constraints.

Briefs contain requirements ONLY: no controller instructions, no report
shape, no route banners, no line-count accounting. The harness owns
envelopes; the brief owns requirements.

## Specificity (no invention, no transcription)

- Every behavior the implementer must produce is named: exact identifiers,
  exact edge-case behavior, exact non-goals ("do not add X").
- For deletion/extraction or mixed-purpose code surgery, distinguish whole
  declarations to remove from bodies to edit and named declarations,
  signatures, enclosing scopes and behavior to preserve. Put these bounds
  in the existing contract/steps, not a new checklist section. Use symbols,
  not brittle line ranges or prescribed function bodies.
- Steps describe decisions already made. A step that needs the implementer
  to choose between valid approaches means the plan is unfinished — decide
  it here, or split the choice into its own design task.
- Specify the interface and its contract, never the keystrokes. A step
  quoting the function body it wants back is transcription: it wastes an
  expensive seat and robs review of independence, since no reviewer can
  judge code the brief dictated.

## Sizing (earn the build)

- Lower bound: one task = one independently-verifiable behavior change.
  Slices sharing a single verification surface (one check run proves both)
  are ONE task — micro-slices that each demand a full build are churn.
  Merge until the work exceeds the verification cost.
- Upper bound: triage caps (at most 3 files, 5 steps, 1 acceptance
  predicate). Over cap → split at interface boundaries.
- Batching: same-shape mechanical edits across files go in one dispatch
  with a per-file list, reviewed as one unit.
- Route honestly: mechanical, reversible, single-predicate work goes Direct
  with inline Target/Change/Acceptance. SDD-track is for judgment work,
  not the default.

## Checkpoint cadence (not task bookkeeping)

- Put a few coherent checkpoint milestones in plan.md, not a commit step in
  every brief. Use existing integration/behavior boundaries, not arbitrary
  task counts, timers, separate commit tasks or a new tracking document.
- Task completion, review acceptance and Git persistence are independent.
  Serial tasks with disjoint write sets need no intervening commit, even
  when one consumes the other's interface. Keep their verification/review
  requirements; do not weaken those to reduce Git bookkeeping.
- Identify cross-task file reuse from the accumulated uncommitted write sets,
  not just adjacent task numbers. Before a later task re-edits such a file,
  checkpoint its accepted prior writer with other ready work. Unreviewed or
  failing work is fixed first; repair passes within one task do not force
  commits. The execution loop owns staging, diff packaging and fix handling.
- If successive tasks repeatedly hand off the same files for one behavior
  change, merge them where the existing sizing caps permit instead of
  creating a train of mandatory checkpoints. Scope tasks for useful work,
  not one-commit-per-task history.
- Earlier ownership-boundary checkpoints can satisfy nearby milestones.
  Final handoff checkpoints any remaining accepted work after final review;
  never require an empty/redundant checkpoint to satisfy a plan marker.

## Repetition ban

- Any sentence appearing in 3+ briefs belongs in plan.md Global Constraints
  or the loop — cross-reference it, never copy it.
- One statement of verification policy per plan, in plan.md. Who runs what
  is decided once, not re-litigated in every brief.
- Keep the before/edit/after tooling protocol and evidence contract in
  `sdd-execution-loop`; do not copy them into briefs. Parallel-work policy
  must distinguish implementer-owned, read-only local inspection from
  controller-run shared builds/tests and formatter/linter commands. Never
  use a blanket "skip validation" instruction that suppresses both.
