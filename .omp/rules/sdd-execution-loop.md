---
name: sdd-execution-loop
description: "When executing a written implementation plan task-by-task: dispatch contract, per-task review gate, fix loop with 5-round cap, controller-side commits, todo tracking."
---

# Plan execution loop

Applies when executing a written plan (e.g. `docs/plans/**`). One task at a
time: dispatch implementer → review gate → fix loop → controller commit → todo done.

## Dispatch (implementer)

- Record BASE: `git rev-parse HEAD` before dispatch.
- The brief file (`docs/plans/<plan>/task-N-brief.md`) is the single source
  of requirements. Dispatch `sdd-implementer` with exactly these slots:
  (1) one line on where this task fits;
  (2) the brief path — "read first, exact values verbatim";
  (3) interfaces and rulings from earlier tasks;
  (4) your resolution of any ambiguity in the brief;
  (5) "return the full result contract in your task result; write no report or
  scratch files, commit nothing."
- Attach an `outputSchema` to the task item enforcing the full result:
  `status` ∈ {DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT}, `summary`,
  `implementation`, `tests` (command + output), `changedFiles[]`,
  `selfReviewFindings`, `concerns`. Permissive mode. Persist whatever of it
  you want (e.g. `task-N-report.md`) as your own scratch — the implementer
  writes nothing.
- Never waive verification in a dispatch. Scope it through the brief
  (narrower target, fewer commands) — never "skip tests" or "no build".
  Shared tree is the only exception: mark the dispatch SHARED_TREE and the
  implementer returns build DEFERRED; you then run the focused check on
  the merged tree at checkpoint-commit, before the review gate.
- Implementer model failure falls back per harness config (`omen-alpha` →
  `terra:xhigh`). A fallback-fired run is the same seat under the same
  contract — its report carries the same weight.
- Seat selection: `sdd-implementer` unless the brief routes Qt-heavy —
  then dispatch `qt-cpp-reviewer` in Implement mode with the same five
  slots. Its pack self-review plus build evidence covers the quality
  verdict; `sdd-task-reviewer` still gates spec compliance. Never point
  any other seat at the vendored pack.
- Never paste accumulated prior-task state into a dispatch. A fresh
  implementer needs its task, its interfaces, and the constraints. Nothing
  else.
- Never make a subagent read the whole plan file.
- Never dispatch dependent tasks in parallel without pipeline discipline
  (see Pipelining). Genuinely independent plan tasks may fan out only with
  non-overlapping file lists — a shared file is dependence; serialize it.
  Every task keeps its own review gate.
- Batch small same-shape mechanical edits (same one-line fix repeated across
  files) into ONE dispatch with a per-file list; review the batch as one
  unit. Reserve one-dispatch-per-task for work needing its own judgment,
  tests, or review surface.

## Handle the report

- DONE → checkpoint-commit, build the diff package, dispatch `sdd-task-reviewer`.
- DONE_WITH_CONCERNS → read concerns first. Correctness/scope concerns:
  address before review. Observations ("file growing large"): note, proceed.
- BLOCKED / NEEDS_CONTEXT → never ignore. Context problem: provide it and
  re-dispatch. Too large: split. Plan wrong: rule on the correction, carry it
  in the next dispatch context, re-dispatch.
- The checkpoint commit is controller bookkeeping, never the implementer's —
  stage only the brief's file list and commit:
  `git add -- <brief files> && git commit -m "task N: <name> (unreviewed)"`.
  Then write `docs/plans/<plan>/task-N-review.diff` so the diff never enters
  your context (use the recorded BASE, never `HEAD~1`, which truncates
  multi-commit tasks):
  `{ git log --oneline BASE..HEAD; git diff --stat BASE..HEAD; git diff -U10 BASE..HEAD; } > docs/plans/<plan>/task-N-review.diff`

## Review gate

- Dispatch `sdd-task-reviewer` with the brief path, the implementer's
  returned result inline, and the diff file path, plus the plan's Global
  Constraints copied verbatim. The constraints are its
  attention lens; don't add open-ended directives, don't ask it to re-run
  tests, and never pre-judge findings ("don't flag X") — let findings
  surface; adjudicate them in the loop.
- Both verdicts required: spec compliance and task quality. Never accept a
  report missing either. Implementer self-review never replaces the gate.
- Re-review goes to the same reviewer: resume via `hub send`, or fresh
  dispatch carrying its prior verdict. It owns the baseline; a new reviewer
  re-derives it at full cost.

- ⚠️ items (unverifiable from diff) are yours to resolve with cross-task
  context before marking the task complete; a confirmed gap enters the loop.
- Clean review → mark todo done, next task.

## Pipelining (overlap review with next implementation)

Slow implementers never idle while a review runs: dispatch N+1 while N is
in review. At dispatch time, classify what N+1 consumes from N.
- Interfaces only → full overlap: findings against N's internals cannot
  touch N+1. The one exception — a finding that changes a consumed
  interface — invalidates N+1's work product: after N lands clean, re-verify
  N+1 against the new interfaces with a scoped review, or discard and
  re-dispatch; carry the call in the next dispatch context.
- Implementation or behavior → conditional overlap: N+1 proceeds, but if
  N's review returns findings touching anything N+1 consumed, halt N+1 —
  `hub send` a hold while work is early, cancel when the findings
  invalidate its foundations, re-dispatch once N is fixed and re-verified.
- Never stack depth: one unreviewed task beneath in-flight work at most. A
  second pending review halts all new dispatches until the oldest lands.

## Fix loop (5 rounds max per task)

- Triggers: spec ❌, any Critical/Important finding, or a ⚠️ you confirmed
  as a real gap. Minor findings never enter the loop — file them as deferred
  todo items, point the final review at the list. FIX_BASE is the head the
  previous review saw; each re-review diffs from FIX_BASE.
- A finding the plan text mandates is yours to rule on: weigh it against the
  spec (binding authority), record the ruling in the next dispatch context
  before acting.
- Rounds 1–3: `hub send` the findings verbatim to the original implementer
  (agent id from the dispatch result). Its context is intact. Gone? Fresh
  implementer carrying the brief path, the persisted prior results, + findings.
- Rounds 4–5: fresh implementer on a more capable model, framed: "A prior
  implementer attempted this task N times; you own it now. The dispatch
  includes what was tried."
- Every round: fix, re-run covering tests, amend the checkpoint commit, return
  fix details (change, tests, command, output) in the result for Main to
  persist, then scoped re-review from FIX_BASE. Re-reviewer verdicts each
  finding ADDRESSED/NOT ADDRESSED and flags new breakage in the fix diff
  only; new Critical/Important joins the open list, out-of-scope observations
  become deferred minors.
- Never fix findings yourself — your fixes skip review and pollute your
  context.
- Round 5 still open → breaker: adjudicate. Reviewer wrong or contestable →
  park with ruling. Real but nothing downstream → park, ruling says deferred.
  Real and load-bearing → rule on the smallest unblocking change and carry it
  into the next task's dispatch. Carry every adjudication into the next
  dispatch context; silent discards are forbidden. Stop only if every path
  forward is a guess.

## Tracking (todo, not files)

- The omp todo list is the tracker: one phase per plan, one task per plan
  task, plus a Deferred phase for parked minors. After compaction, trust todo
  state + `git log` + report files over recollection; never re-dispatch a
  task whose todo is done.
- Rulings live in dispatch context (each dispatch carries prior rulings as
  slot 3) and reach the user in the finish message. No progress file.
- Decide, don't stall. Four stop conditions only: irreversible/destructive
  operation; security-sensitive action; side effect outside this worktree
  (merge, push, publish); plan broken beyond guessing.

## Finish

All tasks complete → one final whole-branch review: package
`merge-base..HEAD`, most capable reviewer, pointed at deferred minors and
parked rulings. Findings → ONE fix dispatch with the complete list (never
one fixer per finding), one scoped re-review, adjudicate residuals. No
second fix wave. Report to the user: every `Ruling:` line, in order, each
with what it costs if wrong — that list is the only place your decisions
reach them.
