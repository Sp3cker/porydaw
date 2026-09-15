# State-tree simplification — implementation plan

Execution: `rule://sdd-execution-loop`. Shared vocabulary and behavior:
[spec.md](spec.md). This plan changes code structure, not user-facing behavior.

**Goal:** remove the artificial null-document state, centralize automation
presentation facts, separate refresh policy from target validity, then replace
repeated popup freshness checks with that validity definition.

**Non-goals:** playback/repaint optimization, changing readiness/InputGate,
changing EditorViewState/remap/persistence or SongDocument, file-count targets,
removing every canvas document query, and migrating non-drawer popup lifetimes.

## Tasks

1. [Atomic document lifetime and observation cutover](task-1-brief.md) — SDD, `qt-cpp-reviewer`; constructor injection, replacement observation, and every view/drawer/check caller migrate together. No intermediate reference API with pointer callers.
2. [Centralize automation presentation facts](task-2-brief.md) — SDD, `sdd-implementer`; model ownership and consumer migration, including selection-only storage lifetime.
3. [Extract complete per-page refresh classification](task-3-brief.md) — SDD, `sdd-implementer`; preserve the recorded outcome tables, including axis-context and interaction cases.
4. [Centralize automation command-target validity](task-4-brief.md) — SDD, `qt-cpp-reviewer`; popup reentrancy and generation checks, with consumed-command regression evidence.

## Dependencies and execution order

Run **1 → 2 → 3 → 4**. Every task ends with a buildable accepted tree.

- Task 2 consumes task 1's reference-returning page document interface.
- Task 3 preserves task 2's selection-refresh publication contract. It also
  occupies the same page implementation, so it is not parallel-dispatched with
  task 2.
- Task 4 consumes task 1's constant document identity and task 2's stable
  row-identity/publication contract. Run it after task 3's accepted refresh
  rewrite so the final validity gate exercises the settled refresh policy.

The first task combines observation handling with the entire document-type
cutover. No separate preparatory extraction or compatibility API is required.
No parallel-ready implementation batch is advertised for this plan.

## Global constraints

- User decision: the three-file-per-task cap is void. Size tasks by cohesive
  ownership, complete caller migration and independently verifiable behavior;
  do not split a buildable cutover merely to satisfy a file count.
- Preserve existing behavior. A failing assertion requires diagnosis, not
  wording re-pinning. Remove only obsolete implementation assertions identified
  in the brief; keep behavior coverage. Fix regressions before handoff.
- Reuse the recorded verification commands; do not rediscover coverage. A stale
  command or newly discovered caller requires an explicit contract/write-set
  correction and revised coverage, not a silently narrowed implementation.
- Keep nullable timeline and EventTableModel source contracts. Their absence is
  legitimate; document lifetime is not nullable. QObject lifetime checks are not
  document-presence guards.
- Each cutover removes the old definition and migrates all consumers in its
  package. No compatibility getter, alternate dispatcher, event bus or cache.
- Use LSP for symbol/reference work and scoped searches to corroborate partial
  indexing. Never grep without path. Do not create a reference-map document.
- Preserve existing selection/remap identities, layout primitives and Qt owner
  teardown. Do not change AGENTS.md; no project-map addition is needed here.
- On a failed check, follow AGENTS.md's single-baseline-run policy, not repeated
  reruns or stash loops. Report and resolve failures before handoff.

## Verification policy

- The controller owns shared-tree builds, named checks and formatting after the
  writer settles. Implementers inspect locally and supply the brief's concrete
  smoke/regression scenario; they do not run competing shared builds or suites.
- Run each brief's recorded commands at its acceptance gate. For native or
  WindowSystem checks, reserve the desktop; do not label all Qt checks as
  software-only. Related passing checks do not substitute for named coverage
  gaps and their explicit scenarios.
- Format touched implementation files with `deno task format`, then check those
  files with `deno task format --check`; do not reformat unrelated user work.
- Final gate: `deno task verify`, `deno task build:app`, and task 4's native smoke.
  No implementation tests/builds are needed merely to edit these plan documents.

## Checkpoints

These are acceptance/persistence boundaries, not permission to commit. Git
commits and pushes require the user's explicit authorization; when authorized,
follow the repo's push-every-commit rule. Do not let an execution controller
silently skip the required persistence gate if that authorization is absent.

- **After task 1, before task 2:** full non-null cutover accepted, including
  replacement observation smoke and caller/rig coverage. Task 2 reuses the
  accepted canvas/page files.
- **After task 2, before task 3:** presentation model and selection-only storage
  lifetime accepted. Task 3 reuses automationpage.cpp.
- **After task 3 / before final validity gate:** refresh policy accepted; all
  earlier accepted canvas work must be persisted before task 4 reuses it.
  A prior checkpoint already covering those files satisfies that requirement;
  no redundant commit is required for disjoint accepted work.
- **Final:** epoch regression, full suite and native smoke accepted; persist any
  remaining accepted changes only under the same Git authorization.

The shared ownership seams explain the serial schedule. Do not combine
verification across a broken intermediate API or begin later shared-file work
before the earlier writer's review gate passes.
