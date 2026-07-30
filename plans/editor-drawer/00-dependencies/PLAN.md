# Task 00 — Dependencies, worktrees, and unchanged-base record

**Blocked by:** None.

**Production commit:** None. This task prepares one reviewed docs-only seed
commit, then creates the implementation worktrees.

## Read first

Read the root `PLAN.md`, the full editor drawer specification, the repository
instructions, and this file before changing Git state.

## Objective

Create a clean, reproducible environment in which Tasks 01 through 11 can work
without sharing build state, mutable fixtures, branches, or stale bases.

## Required identities

Resolve and record:

- freshly fetched `upstream/main` as `BASE_SHA`;
- the specification commit, including `4426ca1`;
- the commit that contains this complete plan as `PLAN_SHA`;
- oracle `52fd478f27594ffe410472fb8d4a62e792378f16`;
- fixture repository `/Users/spencer/dev/hearth-test`, expected HEAD
  `3522f554b2a9f0b5f44b74c7875264e5caa5eea0`, its full working-copy manifest,
  and a hash of that manifest;
- `mus_lovely` as the primary roll and manual song;
- `mus_poke_center` as the second `tabcheck` and mixer-independence song;
- build type, Qt platform, and settings isolation; and
- the exact commands used to validate the song set.

Do not reuse a cached remote answer. Stop if an intended branch or worktree
path already exists; do not reset, delete, or repurpose it. The named fixture
working copy currently contains intentional tracked and untracked work, so its
HEAD alone is not a reproducible pin. If its HEAD differs from the expected
value, stop for a plan update. In all cases record tracked changes, untracked
paths, and content hashes before copying it.

## Work

1. Fetch and prune all remotes.
2. Create detached `base` and `oracle` worktrees at `BASE_SHA` and the oracle
   SHA.
3. Create the integration worktree and
   `feature/editor-drawer-reimplementation` at `BASE_SHA`.
4. Bring only these reviewed documents from `PLAN_SHA` into the integration
   worktree:

   - `docs/EDITOR_DRAWER_REIMPLEMENTATION.md`
   - root `PLAN.md`
   - `plans/editor-drawer/**`

5. Stage that docs-only seed, record its tree ID, and send it through the
   Review plan. After approval, let the coordinator create the seed commit.
6. Create the clean task branches and worktrees named in the root plan:
   01 through 07, 08A, 08B, 09A, 09B, 10A, 10B, and 11. Create the A and B
   agents' directories separately; the 08, 09, and 10 parent plans are logical
   slice packets and do not get worktrees.
7. Initialize required submodules in each worktree. Give each worktree its own
   build, settings, scratch-fixture, screenshot, log, and temporary paths
   beneath runtime `_state/<task-id>/`, outside the Git worktree.
8. Create `_coordination/BASELINE.md`, `BRANCHES.md`, and per-task handoff,
   review, and test locations outside every Git index.
9. Build the unchanged detached base.
10. Make a fresh scratch reflink of the pinned fixture content for every
    mutating command. Never reuse a scratch project between commands.
11. Run the complete required baseline suite. Record exact commands, exit
    codes, named failures, screenshots, and skips.
12. Validate and record the manual fixture matrix:

    - `mus_lovely` loads and exposes tempo, voice, at least one controller,
      DirectSound, Square, Noise, Wave, and key-split contexts in its pinned
      `voicegroup_hanabi` data;
    - `mus_poke_center` loads and provides the second-song and
      mixer-independence case; and
    - each manual case names its song, track, tick or prepared scratch edit,
      program, note key, and expected context.

    Preparation may edit only a fresh scratch reflink. Record that preparation
    as a repeatable fixture recipe under `_coordination/`; do not add it to the
    `hearth-test` working copy or this repository.
13. Confirm every task worktree is clean and points at the seed commit.

The check harness mutates projects. Never run two checks against the same
fixture copy.

## Acceptance

- `BASE_SHA` is the fetched authoritative integration tip.
- The base and oracle worktrees are detached and treated as read-only.
- The integration seed changes documentation only.
- All task-agent branches start at the reviewed seed commit.
- Each worktree has isolated generated and mutable state.
- No build, settings, fixture, screenshot, log, or temporary output lives
  inside a Git worktree.
- Every mutating baseline command used its own scratch reflink.
- The manual matrix has a named and validated song, track, time/key context,
  or repeatable scratch preparation for all eight required content classes.
- The unchanged base builds.
- Every required baseline command has a recorded result or a specific recorded
  skip reason.
- Known roll-check failures are named rather than summarized as “failed.”
- No production source, existing worktree, or unrelated branch changed.

## Handoff

Record the branch-to-worktree table, all pinned SHAs, fixture manifest and
hash, named song/case matrix, seed staged-tree ID, baseline results, reflink
paths, build path, settings path, and any external blocker. Leave the seed
staged and uncommitted for review.

## Review gate

The Review agent verifies branch/path safety, exact identities, the docs-only
seed, fixture isolation, baseline completeness, and that no source or unrelated
Git state changed. Oracle behavior review does not apply yet.

## Completion

After seed approval and commit, create the task worktrees. Task 01 may start
only after the coordinator marks the baseline complete.
