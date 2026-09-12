---
name: sdd-execution-loop
description: "When executing a written implementation plan task-by-task: dispatch contract, before/after structural inspection, per-task evidence/review gates, bounded fix loops, batched Git checkpoints before file reuse, todo tracking."
---

# Plan execution loop

Applies when executing a written plan (e.g. `docs/plans/**`). Each task:
implement → inspect/check → review/fix → todo done. Git checkpoints are
separate batch boundaries, not a condition of task completion.

## Checkpoint policy

- Capture the agreed whole-branch review base and current CHECKPOINT (`HEAD`)
  once at execution start. Refresh CHECKPOINT only after a checkpoint, not
  merely because the next task starts. Existing user changes are not part
  of the batch.
- Accumulate verified, accepted work until a planned coherent milestone or
  final handoff. A task boundary, successful review, serial ordering or an
  interface dependency alone does not require a commit. Disjoint tasks can
  remain uncommitted together; no per-task commit or wall-clock timer.
- Before a different task edits any file written by an earlier uncommitted
  task, finish that prior task's review/fixes and checkpoint its accepted
  work, preferably with other ready work. Check the accumulated pending
  write sets, not just the immediately preceding task. Do not commit broken
  or unreviewed work to bypass this boundary. Same-task fix passes are not
  ownership transfers and do not require commits.
- Checkpoint only accepted task changes and their required predecessors;
  exclude unrelated user changes and in-flight/unreviewed work. Stage the
  bounded batch, name its milestone and included tasks in the commit, and
  follow repository push requirements. Reuse still-applicable verification
  evidence; making a commit alone is not a reason to rebuild.
- A checkpoint that leaves nothing pending satisfies a nearby milestone;
  never create an empty or redundant commit to tick a schedule box. Fixes
  accumulate for the next checkpoint, not per-round commits or amendments.
- Use existing todo/results and the pending task write sets for tracking.
  Do not replace per-task commits with per-task Git refs, index trees,
  full-source snapshot directories or another progress ledger. These rules
  do not grant permission to commit, push, rewrite history or change branches.

## Dispatch (implementer)

- Before dispatch, apply the checkpoint policy to the incoming write set.
  Capture its BASE from CHECKPOINT in the existing task context; keep that
  reference even if disjoint work is checkpointed while the task runs. If
  its files contain unrelated dirty work, resolve ownership and the review
  baseline first; do not silently include that work in the task or commit.
- The brief file (`docs/plans/<plan>/task-N-brief.md`) is the single source
  of task requirements. Dispatch `sdd-implementer` with exactly these slots:
  (1) one line on where this task fits;
  (2) the brief path — "read first, exact values verbatim" — plus the
  plan.md path for its Global Constraints section and linked spec, and the
  Implementer local inspection section below copied verbatim;
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
- Require `selfReviewFindings` to include local inspection evidence:
  tools and file/symbol scope, baseline-to-final diagnostic changes,
  actual versus permitted declaration/scope changes, and any unavailable
  checks with reasons. Include relevant observations, not just "self-reviewed".
  Keep command/output evidence and any `DEFERRED_TO_CONTROLLER` status in
  `tests`.
- Never waive verification in a dispatch. Scope it through the brief
  (narrower target, fewer commands), not a blanket "skip validation".
  For concurrent shared-tree work, mark the dispatch SHARED_TREE and defer
  shared build/test runs and formatter/linter commands to the controller.
  Implementers still perform the read-only, file-local inspection below on
  their owned files; do not alter shared build configuration to obtain it.
  The implementer reports `tests: DEFERRED_TO_CONTROLLER`, not passed. The
  controller runs the covering focused check on the settled batch before
  task review. Checkpoint timing follows the separate policy above.
- Implementer model failure falls back per harness config (`omen-alpha` →
  `terra:xhigh`). A fallback-fired run is the same seat under the same
  contract — its report carries the same weight.
- Seat selection: `sdd-implementer` unless the brief routes Qt-heavy —
  then dispatch `qt-cpp-reviewer` in Implement mode with the same five
  slots. Its pack self-review plus build evidence covers the quality
  verdict; `sdd-task-reviewer` still gates spec compliance. Never point
  any other seat at the vendored pack.
- Direct tasks within a written plan retain their lighter
  Target/Change/Acceptance dispatch and status/summary result. Include the
  same local inspection section and put its evidence in the summary;
  this does not change the task's route or reviewer requirements.
- Implementers read plan.md's Global Constraints section and the spec it
  links — nothing else in the plan file. Never paste accumulated prior-task
  state into a dispatch: a fresh implementer needs its task, its interfaces,
  and the constraints. Nothing else.
- Never dispatch dependent tasks in parallel without pipeline discipline
  (see Pipelining). Genuinely independent plan tasks may fan out only with
  non-overlapping file lists — a shared file is dependence; serialize it.
  Every task keeps its own review gate.
- Batch small same-shape mechanical edits (same one-line fix repeated across
  files) into ONE dispatch with a per-file list; review the batch as one
  unit. Reserve one-dispatch-per-task for work needing its own judgment,
  tests, or review surface.

## Implementer local inspection

Applies to every implementation and fix pass, including Qt Implement mode
and SHARED_TREE work. Keep baselines in working context; return evidence in
the result, not new report/scratch files. This is scoped inspection, not a
workspace-wide audit or a substitute for the named build/check.

1. **Before editing:** use `lsp symbols` and file-local `lsp diagnostics`
   where supported to record declarations/scopes and baseline diagnostics.
   Use `read` to inspect complete affected constructs and their enclosing
   boundaries; recover elided content. Identify permitted whole-declaration
   deletions, body-only changes, and declarations/signatures/scopes that
   must remain. Resolve symbol references before exported-symbol changes.
2. **For structural surgery:** before partial-function deletions or moves,
   capture a scoped AST when supported. With clangd, use `lsp request`
   with `textDocument/ast`, the file URI and optional range, using the
   project's compilation configuration. Whole-file AST comparison is not
   mandatory for ordinary edits.
3. **Edit within those boundaries:** use LSP refactors where available,
   `ast_edit` for suitable structural rewrites, and anchored `edit` for
   small statement changes. Inspect staged AST proposals before applying.
   A body-only edit must not consume its enclosing declaration. Re-ground
   locations after edits; do not reuse stale ranges.
4. **After each logical edit:** run file-local diagnostics and obtain the
   declaration inventory again. Compare observed deletions, signatures and
   enclosing scopes with the permitted changes. For captured ASTs, compare
   the affected subtrees and parents, not raw dumps containing shifted
   offsets or unstable IDs. Fix new syntax errors and unintended structural
   changes before handing off. A recovery AST or an empty symbol result is
   not proof of a clean parse; these checks do not prove semantic intent.
5. **When inspection is unavailable:** report UNAVAILABLE with the tool,
   scope and reason; never turn missing configuration, stale results or
   changing dependencies into a pass. Do not rebuild/reconfigure a shared
   tree to hide the gap. The controller must arrange equivalent structural
   inspection and covering parse/compile evidence before acceptance.

## Handle the report

- Before accepting DONE, check local inspection evidence and covering
  build/check results. Missing evidence is an incomplete report. New syntax
  errors or unintended structural changes require a fix; unavailable tools
  require equivalent inspection and a covering check, not a waiver. Resolve
  SHARED_TREE `DEFERRED_TO_CONTROLLER` reports with the controller's focused
  check before review. DONE alone is not verification.
- Evidence complete and covering checks pass → freeze the task's review
  package and dispatch `sdd-task-reviewer`, without requiring a commit.
- DONE_WITH_CONCERNS → read concerns first. Correctness/scope concerns:
  address before review. Observations ("file growing large"): note, proceed.
- BLOCKED / NEEDS_CONTEXT → never ignore. Context problem: provide it and
  re-dispatch. Too large: split. Plan wrong: rule on the correction, carry it
  in the next dispatch context, re-dispatch.
- Package only the task's write set from its captured BASE to the current
  working tree: `git diff -U10 BASE -- <brief files>`, not `BASE..HEAD`.
  Include new untracked task files explicitly (for example,
  `git diff --no-index -- /dev/null <new file>`; exit 1 means a diff, not
  failure). Include deletions and both paths of renames. Never omit a new
  file or include a disjoint task merely because neither is committed.
- Keep immutable controller-owned `task-N-review-r0.diff`, then r1, r2, ...
  for actual fix reviews, in the existing review-artifact location. Each
  is the task-scoped diff against the same BASE. The previous and current
  packages provide the fix-review comparison; no staging, snapshot tree or
  bookkeeping commit is needed to generate them.

## Review gate

- Dispatch `sdd-task-reviewer` with the brief path, the implementer's
  returned result inline, and the diff file path, plus the plan's Global
  Constraints copied verbatim. The constraints are its
  attention lens; don't add open-ended directives, don't ask it to re-run
  tests, and never pre-judge findings ("don't flag X") — let findings
  surface; adjudicate them in the loop.
- Both verdicts required: spec compliance and task quality. Never accept a
  report missing either. Implementer self-review never replaces the gate.
- Supply the local inspection evidence and any controller-provided fallback
  to the reviewer in the result contract. Declaration preservation and
  parse evidence complement, but never replace, behavioral/spec review.
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
  todo items, point the final review at the list. Re-reviews compare the
  previous and current immutable task packages against the same BASE;
  do not manufacture a FIX_BASE commit or use the moving HEAD as a baseline.
- A finding the plan text mandates is yours to rule on: weigh it against the
  spec (binding authority), record the ruling in the next dispatch context
  before acting.
- Rounds 1–3: `hub send` the findings verbatim to the original implementer
  (agent id from the dispatch result). Its context is intact. Gone? Fresh
  implementer carrying the brief path, the persisted prior results, + findings.
- Rounds 4–5: fresh `sdd-implementer` dispatch — escalate to a stronger
  model where the harness seat permits — framed: "A prior implementer
  attempted this task N times; you own it now. The dispatch includes what
  was tried."
- Every round: fix, repeat local inspection and covering checks, return fix
  details and evidence, then freeze the next task package. Send previous and
  current packages plus the prior verdict to the same reviewer. Review only
  the changed code and prior findings: each is ADDRESSED/NOT ADDRESSED; new
  Critical/Important findings in the fix join the open list, unrelated
  observations become deferred minors. Do not commit or amend per fix round.
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
- A done task may still be uncommitted. Recover pending accepted work from
  existing todo/results, checkpoint task IDs and scoped working-tree changes;
  never re-dispatch merely because there is no per-task commit. Ownership
  stays locked through review/fixes, and cross-task file reuse waits for the
  checkpoint even when disjoint work is pipelined.
- Rulings live in dispatch context (each dispatch carries prior rulings as
  slot 3) and reach the user in the finish message. No progress file.
- Decide, don't stall. Four stop conditions only: irreversible/destructive
  operation; security-sensitive action; side effect outside this worktree
  (merge, push, publish); plan broken beyond guessing.

## Finish
All tasks complete → one final whole-branch review, including accepted work
not yet committed. Package the committed branch diff from the agreed branch
base through HEAD plus the pending accepted-plan diff from HEAD to the
working tree, including new files and excluding unrelated user changes.
Do not use a committed-only range that silently misses the pending batch.
Use the most capable reviewer, pointed at deferred minors and parked rulings.
Findings → ONE fix dispatch with the complete list (never one fixer per
finding), one scoped re-review, adjudicate residuals. No second fix wave.
After final verification/review, checkpoint remaining accepted work when
authorized; create no extra commit if it is already checkpointed. Report
every `Ruling:` line in order, with what it costs if wrong — that list is
the only place your decisions reach the user.
