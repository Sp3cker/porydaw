# Review plan — Per-task oracle and spiritual-correctness gate

## Role

The Review agent is independent and read-only. It does not implement fixes,
stage files, format code, commit, merge, rebase, or change any worktree.

Run this review after Task 00's seed and after every implementation task. Run
it once more over the full integrated series after Task 11.

## Required inputs

Before reviewing, obtain:

- full `docs/EDITOR_DRAWER_REIMPLEMENTATION.md`;
- root `PLAN.md`;
- the active task's complete `PLAN.md`;
- the accepted `START_SHA`;
- `LOGICAL_START_SHA` and transport SHA/tree for a B subtask;
- the exact staged tree ID from `git write-tree`;
- the staged diff and changed-file list;
- Task 00 baseline;
- the task handoff and test record; and
- oracle `52fd478f27594ffe410472fb8d4a62e792378f16`.

If the candidate tree changes during review, stop. The new tree needs a new
review.

## Source precedence

Use this order:

1. Normative specification.
2. Accepted task and root plans.
3. Current integration architecture and repository conventions.
4. Oracle as behavior and UX evidence.

When the oracle differs from the specification, the specification wins. Never
recommend copying a named oracle defect, excluded change, or whole source
file.

## Review procedure

### 1. Bind the candidate

Record:

```text
Task
START_SHA
Staged tree SHA
Specification SHA
Plan SHA
Oracle SHA
Changed files
```

Confirm there are no unstaged tracked edits or untracked source files outside
the staged tree.

### 2. Review the contract

Map every changed behavior to:

- a normative spec paragraph;
- the task's owned acceptance ID; or
- a necessary behavior-preserving refactor named in the task plan.

Flag every line without one of those reasons.

Check task non-goals, global constraints, explicit exclusions, and unrelated
formatting or cleanup.

### 3. Compare the oracle

Inspect the relevant oracle source and checks with read-only Git commands.
For each user-facing behavior, classify it:

| Classification | Meaning |
| --- | --- |
| Retained | Candidate preserves required behavior |
| Improved or contained | Candidate fixes a named oracle defect or ownership problem |
| Rejected | Oracle behavior is excluded, unrelated, or contradicted by the spec |

Review behavior and flow, not line similarity.

The eight named oracle defects must be improved or contained:

1. duplicate-note identity;
2. lost-release preview;
3. inconsistent drawer tick rounding;
4. append-on-repeat lane restore;
5. narrow drawing through the gutter;
6. invalid controller identities `128...254`;
7. non-atomic blank-space exact entry; and
8. unknown sidecar field loss.

### 4. Judge spiritual correctness

Ask:

- Does the result feel like one editor surface?
- Does the drawer remain an overlay and view-state owner only?
- Does automation own automation display and gestures?
- Does velocity own velocity display, note hit testing, and gestures?
- Does the axis model remain widget-independent?
- Does `SongDocument` own mutations, revision checks, and Undo?
- Does `SongView` own shared selection, track, time, scroll, focus, and voice
  context without duplicating those models?
- Do view-only actions leave MIDI, dirty state, revision, and Undo untouched?
- Does one completed edit gesture create at most one Undo command?
- Does every cancellation route restore its specified snapshot and clear
  transient state?
- Do active-tab actions affect and announce only the active song?
- Do exact MIDI velocities survive continuous and intrinsic editing?
- Do visuals and hit tests use the same named `layout` values?
- Do playhead-only updates avoid content rebuilding?
- Does every live drawer gesture pause follow-scroll and resume without
  changing its frozen coordinate system?
- Do edit, selection, zoom, scroll, resize, theme, document, and voice-context
  changes invalidate the right content?
- Does the current `TimelineSurface` contract remain intact, with normal paint
  limited by the event update rectangle and `QRegion` used only for disjoint
  invalid areas?
- Has rejected broad playback paint culling stayed absent?

Reject an implementation that technically passes a narrow check while
violating these ownership or interaction rules.

### 5. Verify checks independently

Rerun the focused commands that can change the verdict. Do not rely only on the
task agent's log.

From Task 05 onward, always rerun:

```text
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 12
QT_QPA_PLATFORM=offscreen <build>/porydaw_themechecks \
  --editor-layout-check --base-font-px 16
python3 tools/check_editor_layout_geometry.py
```

Use fresh scratch fixtures for mutating checks. Compare failures with Task 00's
same-fixture baseline before attributing them.

For **PERF-01**, require fixture, warmup, 120 updates, final tick, staged tree
or branch SHA, and all build/invalidation/presentation counters. A build or
subjective smoothness claim is not enough.

From Task 07 onward, independently inspect the rendering path for
`TimelineSurface` placement, event update-rectangle use, limited `QRegion`
use, the no-broad-culling rule, every named invalidation source, and
follow-scroll pause/resume. Counters do not replace this source and interaction
review.

For sidecar work, explicitly check `splitter[1]`-only restoration, positive
non-resizing `splitter[0]`, one-fifth fallback for missing or short arrays,
unknown-page fallback, silent read/write failure, repeated replacement,
unknown-key preservation, and typed non-menu range `91` through load, remap,
and save.

If a Task 06–10 diff introduces a static geometry value absent from Task 04's
inventory, request changes. The feature must wait for a separate reviewed
inventory and named-`layout` preparatory refactor.

### 6. Write findings

Classify each finding:

- **Critical** — corruption, partial mutation, wrong Undo, unsafe Git or
  fixture handling, or a fundamental contract breach.
- **High** — required behavior, UX, lifecycle, identity, layout, performance,
  or ownership is wrong or missing.
- **Medium** — focused maintainability or test gap that can let the task's
  behavior regress.
- **Low** — optional follow-up that is outside the current specification.

Critical, High, and Medium findings block approval. A Low note must state why
it is outside scope.

## Review report template

Write `_coordination/<task-id>/REVIEW-<NN>.md`:

```text
Verdict: APPROVED | CHANGES_REQUESTED | BLOCKED
Task:
START_SHA:
LOGICAL_START_SHA (split task):
Transport SHA/tree (B subtask):
Staged tree SHA:
Specification SHA:
Plan SHA:
Oracle SHA:

Acceptance IDs checked:
Commands and exit codes:
Baseline-attributed failures:
Manual checks:

Oracle comparison:
- Retained:
- Improved or contained:
- Rejected:

Ownership and spiritual correctness:
Known-defect audit:
Explicit-exclusion audit:
Findings:
Non-blocking follow-ups:
```

## Verdict rules

### CHANGES_REQUESTED

Use when the task agent can fix an in-scope finding. Send exact evidence and
the violated contract back to the same agent. On return, review the full new
tree and every prior finding again.

### BLOCKED

Use only for a real external prerequisite or unresolved spec ambiguity that
cannot be settled from the repository, plan, or oracle. State the exact needed
input.

### APPROVED

Approve only when:

- no blocking finding remains;
- the staged tree ID still matches;
- focused checks are sufficient and passing or correctly baseline-attributed;
- no required manual result is falsely claimed;
- the oracle comparison is complete for the slice;
- the diff is narrow and all changed lines are in scope; and
- the candidate is safe to commit at the task's required boundary.

Any edit after approval invalidates it.

## Synthesis review

Tasks 08, 09, and 10 use this fixed sequence:

1. Review A's staged tree against the logical integration predecessor.
2. Confirm the coordinator's A transport commit has the approved tree.
3. Review B's staged delta against that transport.
4. Review the full A+B staged tree against `LOGICAL_START_SHA`, including
   conflicts, duplicate owners, initialization and signal order, tests,
   exclusions, UX, and the one-commit boundary.
5. Bind approval to that full tree ID. Confirm the coordinator-created B
   transport commit has that tree before synthesis.
6. The integration worktree must reproduce it exactly before and after commit.

Prior A or B approval alone never covers the combined result. Transport
commits stay off the integration branch.

## Final-series review

After Task 11, review `BASE_SHA..HEAD` and each commit in order. Confirm:

- all ten logical slices remain traceable in order and every actual commit is
  clear and buildable;
- any extra refactor is named, focused, and reviewed;
- every acceptance ID has evidence;
- final source and history contain no excluded or unrelated work;
- baseline failures are attributed honestly;
- the integration worktree is clean; and
- the result is better structured than the oracle while preserving the
  specified editing experience.
