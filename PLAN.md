# Editor drawer reimplementation plan

## Purpose

This plan turns
[`docs/EDITOR_DRAWER_REIMPLEMENTATION.md`](docs/EDITOR_DRAWER_REIMPLEMENTATION.md)
into a reviewed, linear implementation built by task agents in separate Git
worktrees.

The current `cleanup/psg-velocity-history-20260729` branch contains the
reference implementation plus the specification and this plan. It is a plan
source and UX oracle, not the implementation base. Production work starts from
a freshly fetched `upstream/main`. Only the specification and plan documents
move to that fresh branch.

The reference oracle is fixed at
`52fd478f27594ffe410472fb8d4a62e792378f16`. Agents may inspect it with
read-only Git commands. They must not merge it, cherry-pick it, copy whole
files from it, or treat its defects as requirements.

## Outcome

The completed integration branch must:

- implement every normative rule and acceptance ID in the specification;
- apply Fowler-style refactoring with buildable, focused commits;
- use shared `layout` values for all in-scope static geometry;
- retain no unrelated source, test, asset, formatting, or build churn;
- pass the focused gates after every slice and the full final suite; and
- have review evidence for behavior, UX, code ownership, and comparison with
  the oracle.

## Roles

### Coordinator

The coordinator owns the integration branch and is the only role that:

- marks a task ready after its blockers are integrated;
- authorizes a commit;
- creates reviewed task-local transport commits when a logical slice has two
  agents;
- commits an approved slice or synthesizes reviewed subtask work;
- fast-forwards the integration branch;
- assigns remediation after review;
- runs integration-branch checks after each accepted slice; and
- removes the task worktrees after final acceptance.

The coordinator does not accept a task merely because it builds.

### Dependencies agent

Task 00 creates the clean integration worktree, all task worktree directories,
the branch map, isolated build and fixture conventions, and the unchanged-base
record. It makes no production source change.

### Task agent

A task agent works only in its assigned worktree and follows that directory's
`PLAN.md`. It:

- starts from the exact accepted predecessor SHA;
- writes tests before or with the behavior they protect;
- makes the smallest in-scope diff;
- runs every required focused check;
- stages the exact candidate tree but leaves it uncommitted;
- writes a handoff record outside the candidate Git diff; and
- fixes all review findings in the same worktree.

A task agent must not commit, push, merge, rebase, edit another task worktree,
or broaden its scope without coordinator approval.

### Review agent

After each task agent hands off, an independent Review agent follows
[`plans/editor-drawer/review/PLAN.md`](plans/editor-drawer/review/PLAN.md).
The Review agent reads the candidate diff, the task plan, the full
specification, the accepted predecessor, and the oracle. It does not edit the
candidate.

Review approval is required before the coordinator commits or synthesizes the
slice.

### Final verification agent

Task 11 audits the integrated result, runs the full automated and manual
acceptance matrix, checks the final history and exclusions, and routes any
failure back to the owning task. It is not a place to hide unreviewed fixes.

## Runtime worktree layout

Task 00 creates this disposable runtime structure:

```text
<repo>/.worktrees/editor-drawer-reimplementation/
  base/
  oracle/
  integration/
  01-track-remaps/
  02-note-identity/
  03-velocity-batch/
  04-geometry-characterization/
  05-layout-migration/
  06-automation-extraction/
  07-drawer-shell/
  08a-state-menus/
  08b-gestures/
  09a-axis-selection/
  09b-gestures-status-perf/
  10a-psg-model/
  10b-intrinsic-ux/
  11-final-verification/
  _coordination/
  _state/
```

Recommended branches:

```text
feature/editor-drawer-reimplementation
task/editor-drawer/01-track-remaps
task/editor-drawer/02-note-identity
task/editor-drawer/03-velocity-batch
task/editor-drawer/04-geometry-characterization
task/editor-drawer/05-layout-migration
task/editor-drawer/06-automation-extraction
task/editor-drawer/07-drawer-shell
task/editor-drawer/08a-state-menus
task/editor-drawer/08b-gestures
task/editor-drawer/09a-axis-selection
task/editor-drawer/09b-gestures-status-perf
task/editor-drawer/10a-psg-model
task/editor-drawer/10b-intrinsic-ux
task/editor-drawer/11-final-verification
```

The committed task packets live under `plans/editor-drawer/`. Every worktree
therefore contains its agent's plan. The runtime worktree directories above
contain code, builds, and tests; the committed plan directories do not.

Tasks 08, 09, and 10 are logical specification slices with two task agents
each. Their parent `PLAN.md` files define the combined slice; each child
directory contains the plan for one agent and one worktree. The parent plans
do not receive a runtime worktree.

Task 00 creates all task branches at the reviewed integration seed commit.
Before a task starts, the coordinator confirms its worktree is clean and
fast-forwards its untouched branch to the latest accepted integration commit.
No task may implement against its original seed after a blocker has advanced.

Each worktree uses its own task directory beneath `_state/` for:

- build directory;
- scratch copy of the `hearth-test` fixture;
- isolated settings directory;
- screenshots;
- test logs; and
- temporary files.

Build trees, settings, and mutable fixtures are never shared between agents
and never live inside a Git worktree.

## Coordination records

Task 00 creates these untracked records beneath `_coordination/`:

```text
BASELINE.md
BRANCHES.md
INTEGRATION_LOG.md
<task-id>/HANDOFF.md
<task-id>/REVIEW-<NN>.md
<task-id>/TESTS.md
```

They must stay outside candidate diffs and commits.

`BASELINE.md` records:

- fetched `upstream/main` SHA;
- specification SHA;
- plan SHA;
- oracle SHA;
- `hearth-test` fixture HEAD, dirty-state manifest hash, and copied content
  manifest;
- primary `mus_lovely` song and secondary `mus_poke_center` song;
- evidence that the named manual song set supplies tempo, voice, controller,
  DirectSound, Square, Noise, Wave, and key-split cases;
- build type and configure command;
- platform and settings isolation;
- every unchanged-base command and exit code;
- named pre-existing failures;
- screenshot paths; and
- skipped checks with reasons.

Every `HANDOFF.md` records:

- task and accepted predecessor SHA;
- changed files and diffstat;
- behavior delivered;
- acceptance IDs exercised;
- exact test commands, exit codes, and result summaries;
- geometry-gate results when applicable;
- manual checks and screenshots;
- known gaps or assumptions; and
- confirmation that the worktree is staged but uncommitted, with its
  `git write-tree` ID.

Every `REVIEW-<NN>.md` records findings by severity, oracle comparisons, tests
run, the reviewed diff SHA or worktree state, and one status:

```text
CHANGES_REQUESTED
APPROVED
BLOCKED
```

## Dependency graph

The implementation chain is deliberately linear:

```text
00 Dependencies and baseline
  -> 01 Track identity remaps
  -> 02 Exact note identity
  -> 03 Revision-checked velocity batch
  -> 04 Static geometry characterization
  -> 05 Shared layout migration
  -> 06 Automation characterization and extraction
  -> 07 Drawer shell and generic saved state
  -> 08A Automation state, remaps, and menus
  -> 08B Automation gestures and drawing
  -> 08 Combined review, synthesis, and integration
  -> 09A Continuous axis, drawing, and selection
  -> 09B Velocity gestures, status, and performance
  -> 09 Combined review, synthesis, and integration
  -> 10A Intrinsic level and axis metadata
  -> 10B Intrinsic UX and strict harness
  -> 10 Combined review, synthesis, and integration
  -> 11 Final verification and evidence
```

The linear chain is intentional. The slices share `SongDocument`, `SongView`,
layout, sidecar, harness, and build-registration seams. Starting code agents
from stale parallel bases would trade a small scheduling gain for large merge
and review risk. Agents may research later tasks in parallel, but code starts
only when the predecessor is reviewed and integrated.

## Fowler-style refactoring discipline

Every task agent must:

- add characterization or regression coverage before changing a risky seam;
- keep a structural step behavior-preserving and verify it before adding new
  behavior;
- make one small named transformation at a time;
- separate a needed refactor from its feature change when each deserves its
  own review and rollback boundary;
- move behavior toward the specification's named owner instead of adding a
  parallel path;
- remove only duplication or compatibility code made obsolete by that task;
  and
- stop when a refactor expands beyond the task's acceptance contract.

Passing tests do not excuse a weak owner, duplicated model, mixed view/document
state, or a large unreviewable change.

## Task index

| Task | Plan | Primary result | Acceptance ownership |
| --- | --- | --- | --- |
| 00 | [Dependencies](plans/editor-drawer/00-dependencies/PLAN.md) | Fresh base, worktrees, isolated baseline | Preflight |
| 01 | [Track remaps](plans/editor-drawer/01-track-remaps/PLAN.md) | One complete ordered remap event | CORE-01 |
| 02 | [Note identity](plans/editor-drawer/02-note-identity/PLAN.md) | Duplicate-safe shared selection | CORE-02 |
| 03 | [Velocity batch](plans/editor-drawer/03-velocity-batch/PLAN.md) | Revision-checked atomic mutation and Undo | CORE-03 |
| 04 | [Geometry characterization](plans/editor-drawer/04-geometry-characterization/PLAN.md) | Complete checked geometry inventory | LAY-01 precursor |
| 05 | [Layout migration](plans/editor-drawer/05-layout-migration/PLAN.md) | Named layout values and executable source gate | LAY-01 |
| 06 | [Automation extraction](plans/editor-drawer/06-automation-extraction/PLAN.md) | Hostable automation page with parity | AUT baseline |
| 07 | [Drawer shell](plans/editor-drawer/07-drawer-shell/PLAN.md) | Overlay, tabs, lifecycle, generic persistence | DRW-01...DRW-05 partial |
| 08 | [Automation deltas](plans/editor-drawer/08-automation-deltas/PLAN.md) | Combined logical slice and synthesis gate | AUT-01...AUT-03 |
| 08A | [State and menus](plans/editor-drawer/08-automation-deltas/08a-state-menus/PLAN.md) | Typed lane state, remaps, persistence, and menus | AUT-01; DRW-04/05 lane state |
| 08B | [Gestures and drawing](plans/editor-drawer/08-automation-deltas/08b-gestures/PLAN.md) | Automation interaction, lifecycle, and Undo | AUT-02, AUT-03 |
| 09 | [Continuous velocity](plans/editor-drawer/09-continuous-velocity/PLAN.md) | Combined logical slice and synthesis gate | VEL-01...VEL-03 |
| 09A | [Axis and selection](plans/editor-drawer/09-continuous-velocity/09a-axis-selection/PLAN.md) | Continuous axis, drawing, exact selection, and canonicalization model | VEL-01; VEL-03 model |
| 09B | [Gestures, status, and performance](plans/editor-drawer/09-continuous-velocity/09b-gestures-status-perf/PLAN.md) | Continuous editing, access, lifecycle, and counters | VEL-02; PERF-01 |
| 10 | [Intrinsic PSG](plans/editor-drawer/10-intrinsic-psg/PLAN.md) | Combined logical slice and synthesis gate | VEL-04 |
| 10A | [Level and axis metadata](plans/editor-drawer/10-intrinsic-psg/10a-model-context/PLAN.md) | Intrinsic level and selection-axis projection | VEL-04 model |
| 10B | [UX and harness](plans/editor-drawer/10-intrinsic-psg/10b-ux-harness/PLAN.md) | Intrinsic interaction and strict native proof | VEL-04; A11Y-01 |
| 11 | [Final verification](plans/editor-drawer/11-final-verification/PLAN.md) | Performance, UX, history, and final evidence | PERF-01 and final matrix |

## Task lifecycle

Each task follows this state machine:

```text
WAITING
  -> READY
  -> IMPLEMENTING
  -> REVIEW
  -> CHANGES_REQUESTED -> IMPLEMENTING
  -> APPROVED
  -> TRANSPORTED_OR_COMMITTED
  -> INTEGRATION_VERIFIED
```

For Tasks 08A, 09A, and 10A, `TRANSPORTED` means the coordinator created an
approved task-local commit only to give the B agent an exact Git base. A
transport commit never enters the integration branch and is not part of the
final history.

### Ready gate

Before assigning an agent, the coordinator:

1. Confirms every blocker is `INTEGRATION_VERIFIED`.
2. Records the current integration SHA as the task predecessor.
3. Confirms the task worktree has no changes or commits beyond its old base.
4. Fast-forwards the untouched task branch to the predecessor with an
   ancestry check.
5. Confirms its task plan, the root plan, and the specification are present.
6. Creates fresh build, fixture, settings, screenshot, and log locations.

For a B subtask, its predecessor is the reviewed A transport commit and the
coordinator also records the logical slice's integration predecessor as
`LOGICAL_START_SHA`. If a fast-forward is not possible, quarantine that
worktree and create a new clean one; do not merge, rebase, or reset a stale
task branch. `BASE_SHA` and the integration series remain fixed even if
`upstream/main` advances during the work.

### Implementation gate

The task agent:

1. Reads the root plan, full specification, and its full task plan.
2. Repeats the accepted predecessor SHA in its handoff.
3. Adds characterization or failing checks before changing behavior.
4. Applies small Fowler-style transformations.
5. Builds and checks after each meaningful step.
6. Runs every task-specific acceptance command.
7. From Task 05 onward, runs both fixed-font resolver checks and
   `python3 tools/check_editor_layout_geometry.py`.
8. Stages only explicit in-scope paths, with no unstaged tracked changes or
   untracked source files left behind.
9. Runs `git diff --cached --check`, inspects the staged file list and
   exclusions, and records `git write-tree`.
10. Leaves the exact staged tree uncommitted and writes the handoff.

### Review gate

The Review agent:

1. Reviews the complete staged diff against the predecessor and records its
   tree ID.
2. Checks the specification before consulting the oracle.
3. Compares user flow and behavior with oracle commit `52fd478`, while
   requiring the specified improvements over its defects.
4. Runs or independently verifies the focused checks.
5. Checks module ownership, Undo boundaries, view-only behavior, cancellation,
   focus, active-tab routing, layout ownership, rendering invalidation, and
   unrelated churn as applicable.
6. Writes `CHANGES_REQUESTED`, `APPROVED`, or `BLOCKED`.

Any correctness, UX, ownership, lifecycle, Undo, layout, performance, or spec
finding blocks approval. A low-priority note may remain only when the Review
agent states why it is outside this specification.

### Remediation loop

For `CHANGES_REQUESTED`:

1. The coordinator returns the exact findings to the same task agent.
2. The task agent changes only what resolves those findings.
3. The task agent reruns all focused checks, not only a new regression.
4. The Review agent reviews the full updated diff again.
5. The loop continues until `APPROVED` or a real external blocker is recorded.

### Commit and integration gate

This plan uses one final integration commit for each numbered specification
slice 01 through 10. That is the clearest current use of the user's permission
to use one or more slices per commit: the strict dependencies stay visible,
and every accepted tree becomes the next slice's base. Cross-number grouping
is not planned. If the coordinator later finds a concrete reason to group
slices, amend this plan before either grouped slice starts and define one
combined base, worktree, test matrix, and Review gate. Never squash an
already-integrated predecessor out from under reviewed descendants.

A behavior-preserving preparatory refactor may be a separate commit only when
the specification calls for it. It gets its own stage, Review, commit, and
integration-check cycle. One approved staged tree never becomes several
commits.

The coordinator, not the task agent, creates every commit. Each commit must:

- build and pass its focused checks;
- contain only reviewed lines;
- name one behavior or refactor;
- record the task ID, specification SHA, plan SHA, predecessor SHA, approved
  tree ID, and checks in its body; and
- preserve the ordered and reviewable traceability of the implementation
  slices.

The first implementation commit, Task 01, must also record the original
`BASE_SHA`, oracle SHA, `hearth-test` HEAD, and fixture manifest hash in its
body. Its predecessor is the docs seed, so `START_SHA` is not a substitute for
`BASE_SHA`.

Immediately before commit, the coordinator confirms `git write-tree` still
equals the approved tree. Immediately after commit, it confirms
`HEAD^{tree}` equals that tree. Any edit after approval invalidates the review.

For one-agent slices 01 through 07, the coordinator commits the approved tree
on the task branch and fast-forwards the integration branch.

For split slices 08 through 10:

1. Review A's staged delta and tree against the slice's integration
   predecessor.
2. After approval, the coordinator creates an A transport commit whose tree
   equals the approved A tree.
3. Fast-forward the untouched B branch to that transport commit.
4. Review B's staged delta against the transport commit.
5. Review the full A+B tree against `LOGICAL_START_SHA`, including
   initialization order, shared ownership, tests, and the proposed one-commit
   boundary.
6. After approval, the coordinator creates a B transport commit whose tree is
   the approved full tree. This leaves the B worktree clean and gives
   synthesis an immutable source tree.
7. Materialize that exact approved full tree in the clean integration
   worktree. If its `git write-tree` differs, stop and review again.
8. Create one logical-slice integration commit with
   `LOGICAL_START_SHA` as parent and the approved full tree as its tree.

The integration branch remains linear. Task-local transport commits and their
branches are disposable evidence, not integration ancestors.

After integration, rerun the task checks on the integration worktree. A task
is not complete until those checks pass there.

## Spiritual-correctness review

“Spiritual correctness” means the result preserves the intended editing
experience and improves the implementation boundary rather than cloning the
oracle's code shape.

Review must ask:

- Does the drawer feel like one editor surface rather than a bolted-on dialog?
- Do automation and velocity share track, time, selection, focus, playhead,
  and Undo state in the ways the specification defines?
- Do view-only actions remain view-only?
- Does one completed gesture create at most one Undo command?
- Does cancel or lost capture leave no staged mutation or stale preview?
- Do active-tab shortcuts and status messages affect only the active song?
- Does narrow and scaled geometry keep visuals and hit targets aligned?
- Does the velocity editor preserve exact MIDI values while showing intrinsic
  hardware levels?
- Does steady playback move the playhead without rebuilding page content?
- Are responsibilities kept in `SongDocument`, `SongView`, the page, axis
  model, drawer, and sidecar owners named by the specification?

The Review agent must not demand parity with an oracle behavior that the
specification identifies as a defect.

## Acceptance ownership

| Acceptance | Owning task | Required recheck |
| --- | --- | --- |
| LAY-01 | 04 inventories; 05 closes | 07, 08A, 08B, 09A, 09B, 10A, 10B, 11 |
| CORE-01 | 01 | 08, 11 |
| CORE-02 | 02 | 09, 11 |
| CORE-03 | 03 | 09, 11 |
| DRW-01 | 05 geometry; 07 behavior | 11 |
| DRW-02, DRW-03 | 07 | 11 |
| DRW-04, DRW-05 | 07 generic state; 08A lane state | 08B, 11 |
| AUT-01 | 08A | 08B, 11 |
| AUT-02, AUT-03 | 06 characterizes; 08B closes | 11 |
| VEL-01 | 09A | 09B, 10, 11 |
| VEL-02 | 09B | 10, 11 |
| VEL-03 | 09A model and fallback; 09B gestures and mixed canonicalization | 10A, 10B, 11 |
| VEL-04 | 10A model; 10B interaction | 11 |
| A11Y-01 | 09B continuous; 10B intrinsic | 11 |
| LIFE-01 | 07 shared route; 08B automation; 09B velocity; 10B categorical | 11 |
| PERF-01 | 07 automation seams; 09B combined test | 10B, 11 |
| UX-01, UX-02 | 07 | 11 |
| UX-03 | 08A menus; 08B gesture actions | 11 |
| UX-04 | 08B | 11 |
| UX-05 | 09A and 09B | 11 |
| UX-06 | 09B | 11 |
| UX-07, UX-08 | 10B | 11 |
| UX-09 | 07 and 09B | 10B, 11 |
| UX-10 | 07 generic state; 08A lane state | 11 |
| UX-11 | 05 scaling; 07, 08B, 09B, and 10B interactions | 11 |

## Global constraints for every task

- The specification wins over this plan, task plans, source, checks, and the
  oracle.
- Do not port commits or whole files from the oracle branch.
- Do not copy the oracle's eight listed defects.
- Do not touch any path or hunk in the specification's explicit exclusions.
- Preserve unrelated dirty work and existing style.
- Do not reformat whole files.
- Add no feature beyond the specification.
- Use no feature-local static screen geometry.
- In Tasks 06 through 10, stop if Task 04 missed a static geometry value.
  First extend the checked inventory, add its named `layout` enum or accessor,
  add resolver coverage at both fixed font inputs, and pass the source gate in
  a separate reviewed preparatory refactor. Resume feature work only after
  that refactor is integrated.
- Use scratch fixtures because check harnesses mutate projects.
- Do not infer UX or rendering parity from a build result.
- Stop and report a real ambiguity before making a behavior choice not settled
  by the specification.

## Final acceptance and cleanup

Task 11 and the final Review agent must verify:

1. Every acceptance ID has recorded evidence.
2. The full required suite ran on the same pinned fixture and settings model as
   the baseline.
3. Pre-existing failures were compared with that exact baseline.
4. All twelve PSG velocity results appeared exactly once and the harness
   returned the correct status.
5. Both layout resolver processes and the layout source audit passed.
6. The manual UX matrix, including second-scale checks, has results.
7. PERF-01 reports fixture, warmup, update count, branch SHA, and counters.
8. The final diff contains no excluded or unrelated work.
9. Every commit is buildable, focused, reviewed, and ordered.
10. The integration worktree is clean.

Any final fix returns to the task that owns the failed acceptance ID and goes
through its Review loop. If a cross-cutting synthesis is needed, it receives a
new focused plan note and full Review before commit.

After final approval:

1. Preserve `_coordination/`, including every approved tree ID, transport SHA,
   integration commit, and final evidence record.
2. Confirm every A and B candidate is stored in its coordinator-created
   transport commit and that each combined transport tree equals its
   integration commit tree.
3. Confirm every disposable worktree has clean tracked state and no untracked
   source. Remove only its task-local `_state/<task>/` generated data.
4. Resolve every removal target from Task 00's recorded branch-to-worktree
   table and prove it is inside the dedicated runtime root, was created by
   Task 00, and is neither `integration` nor any pre-existing worktree.
5. Do not run `git submodule deinit`: this repository shares submodule
   registration across worktrees. Remove each validated disposable worktree
   with `git worktree remove --force <exact-created-path>`. The scoped force is
   permitted only to handle Git's initialized-submodule restriction after
   steps 1–4 prove that it discards no uncommitted source or unique evidence.
6. Delete task branches only with non-forced deletion where ancestry permits.
   Preserve non-ancestor transport branches as review evidence unless the user
   later asks for their forced deletion.

Do not run repository-wide worktree pruning. Preserve the integration
worktree, integration branch, and coordination evidence. Do not push or remove
any pre-existing worktree or branch without a separate user request.
