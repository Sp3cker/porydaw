# Task T22R — Mid-plan thermo-nuclear review gate (after Task 22)

## 1. Context

The plan's per-task review gates are task-scoped; structural drift across a
ten-task stretch needs one adversarial pass before tasks 23–33 build on the
canonical action set. T22R is a controller-gated, non-committed review
checkpoint inserted after task 22 in the dependency schedule — not a task that
changes source.

## 2. Exact write set

No source files. Checks are in progress.md only, if any — recorded through its
standup section, not as a file edit beyond the plan's next-step patch already
made.

## 3. Prerequisites

- [Task 22](task-22-brief.md) accepted, plus all R-series remediation briefs
  (R1–R10) either landed or explicitly scheduled after this gate.
- Gate 1 (window-delivered vs EditorRouted/manually-delivered split,
  double-fire hazard) re-verified in the review report as a named criterion.
- Gate 2 verbatized: E-M3 ownership (narrowed bind contract, chosen once,
  recorded in task-R9-brief.md) must be visible in the implemented rebind
  interface — no residual reassignment-possible code path may survive.

## 4. Interface contract

Run the thermo-nuclear-code-quality-review skill over tasks 12–22's diffs plus
all R-fixes (R1–R10) against the same range, using the `thermo-nuclear-reviewer`
seat (dual-audit not required for the mid-plan gate; a single adversarial pass
is sufficient, dual audit reserved for final integration). Scope
deliberately bounded: one reviewer, one report, fix-loop capped at one round.
Route/scope: this is a **verification gate, not a task** — it produces a
review, not code.

## 5. Entry criteria

1. Task 22's review gate has SPEC-clear and is reported.
2. All R1–R10 briefs either accepted (implementation landed) or explicitly
   deferred past this gate by the controller.
3. Uncommitted R-slices are checkpoint-eligible per plan.md's Checkpoint
   cadence (no per-task commits; stage accepted work only).
4. Additional audits beyond the single reviewer are not required (no
   duplicated reviews here; thermo-nuclear-dual-audit stays
   final-integration-only).

## 6. Exit criteria

1. One thermo report is filed covering tasks 12–22 + R-fixes, with elevated
   findings ranked (blocker/major/minor) and each carrying the emitted
   structural verdict (ACCEPT/AMEND/REJECT per finding).
2. Reported blockers or majors each either get a fix brief (a new R-file, if
   any) or an explicit deferral note to the existing plan (tasks 23–33 or
   final integration).
3. Gates 1 and 2 are named in the report with their status (held or regressed).
4. No new code is written by this gate itself.
5. The controller records the outcome in progress.md's standup/next-step as
   the gate result.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not spawn parallel
audit agents (thermo-nuclear-dual-audit stays final-integration-only). No
project-wide builds or formatters run by the gate itself — those stay
controller-owned per constraint 6. Skip the fix loop beyond one round: findings
get briefs or deferrals, not in-gate code edits.
