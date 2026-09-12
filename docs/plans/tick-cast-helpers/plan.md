# Tick cast helpers and arithmetic boundaries

Continue the [tick-width migration](../tick-width/plan.md): eliminate unnecessary internal conversions without hiding overflow. This revision supersedes the previous four-task cast-only plan. It includes the note-end and grid-addition defects found against local `fork-main` at `996c6446`; it is not implementation evidence.

The behavioral decisions and numeric interfaces live in [spec.md](spec.md). In-domain edits and rounding stay unchanged; invalid upper-bound document edits now reject atomically, and display-domain conversions saturate. Do not describe those boundary fixes as behavior-neutral.

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Numeric helpers and span contract](task-1-brief.md) | SDD-track / sdd-implementer | Shared interfaces with signed-overflow and floating-boundary contracts | None |
| 2 | [TimeEditor position cutover](task-2-brief.md) | SDD-track / sdd-implementer | Preserve atomic preflights, tempo seams, and track ends | 1 |
| 3 | [Note mutation arithmetic and undo](task-3-brief.md) | SDD-track / sdd-implementer | New rejection boundaries across note transactions and command merging | 1 |
| 4 | [Range mutation arithmetic](task-4-brief.md) | SDD-track / sdd-implementer | Atomic mixed note/lane/tempo edits and track expansion | 1 |
| 5 | [Grid snapping and bounded iteration](task-5-brief.md) | SDD-track / sdd-implementer | First-candidate, stride, and snap-ceiling correctness | 1 |
| 6 | [Nudge feedback and group drag shifts](task-6-brief.md) | SDD-track / sdd-implementer | Rejected document moves and spacing-preserving drag limits | 1, 3 |
| 7 | [Scalar conversion sweep](task-7-brief.md) | SDD-track / sdd-implementer | Explicitly requested planned execution; mechanical per-file conversion batch | 1 |

Mapping from the previous plan: old Task 1 becomes Tasks 1–2; old Task 2 becomes Tasks 3–4, Task 6, and the selection-endpoint substitutions in Task 7; old Task 3 becomes Task 5; old Task 4 becomes Task 7. The note-end fixes belong to Tasks 3–4, not an omitted follow-up.

Every write set, including temporary probe files, is disjoint. Tasks 2, 3, 4, 5, and 7 may run concurrently after Task 1 is accepted. Task 6 consumes Task 3's rejection contract; it has no shared-file dependency on the other tasks. Numeric order is not a serial build schedule. Each judgment task has at most three files and five implementation steps. Task 7 alone uses the mechanical same-shape batching exception to the file cap.

## Global Constraints

- Work in the local `fork-main` checkout, `/Users/spencer/dev/cProjects/porydaw`, not the `time-editing` worktree. Verify the checkout before dispatch; use absolute file paths if tools are rooted elsewhere. Preserve unrelated and concurrently authored changes.
- Each brief's write set is closed. An additional source, declaration, build-registration change, or shared-file requirement is a brief defect; stop that slice and revise the contract instead of silently expanding it.
- Preserve the [tick-width spec](../tick-width/spec.md) representation: positions are the `uint32_t` alias `Tick`; durations remain `uint32_t`; signed deltas remain `int64_t`; computed note ends and overflow-capable products remain `uint64_t`. Samples, identities, indices, and revisions do not become `Tick`.
- Keep necessary widening before arithmetic and checked narrowing at storage boundaries. Do not replace explicit casts with equally unsafe implicit narrowing. No strong Tick wrapper, generic cast framework, optional sentinel migration, member reordering, new allocator, or file extraction.
- Preserve existing public mutation signatures, note identity, overlap resolution, xcmd identity handling, track remapping, and valid-operation undo/redo. The exact boundary-policy exceptions are in the spec; do not add dialogs, telemetry, new error channels, or unrelated validation.
- Requirements are symbol-based. Historical counts such as “11 shift sites” or “13 double conversions” are not acceptance criteria. Resolve current symbols and caller references before editing; a one-expression difference must not conceal an unhandled sibling.
- Production code is not being implemented by this planning change. Execution and Git persistence are separate permissions.

## Verification policy

The controller owns formatter/linter invocations and shared builds/tests. Concurrent implementers perform read-only local inspection and prepare their slice; they do not run shared validation while any writer is active. Pause all writers at a verification boundary. Build once for the settled source state and run the union of the applicable named checks rather than rebuilding once per task. No blanket instruction should prohibit implementers' read-only inspection.

Each brief ends with its named commands. All builds/checks use `deno task` from the checkout above. `verify` already builds checks and the app, so a separate immediately preceding `build:app` is not required. Filters are repeatable substring matches; `--filter rollcheck` includes `rollcheck-static`.

Boundary regressions must exercise actual production arithmetic and observable edits, not copied formulas or source-text assertions. Extend the existing test slots named in the briefs. Construct synthetic near-limit documents through `SongDocument::adoptSmf`; do not depend on a years-long playback run or on encoding an overlarge single SMF delta. A rejected mutation must leave stored events, tempo state, track count, document revision, and undo count/index unchanged. Valid boundary edits must retain their musical data through undo/redo. Capture a failing boundary reproduction before its fix where the existing code can execute it safely; the missing-helper probe instead establishes the newly introduced contract after Task 1.

Temporary probes are allowed only in the explicitly listed probe files. Remove them after capturing their results; retain only the named behavioral regressions. Exercise the changed nudge/drag paths through the actual UI or existing UI driver, including a rejected near-limit nudge. Report native versus offscreen coverage accurately; a software/offscreen run is not native raster proof. Do not change production rendering or weaken assertions to accommodate a test backend.

After all seven tasks and their review/fix gates, format the changed C++ files through `deno task format`, then run the final integration gate once:

```sh
deno task verify --verbose
```

The full gate is after all tasks, not merely after Task 7 finishes. Resolve every failing assertion/check before handoff; follow the repository's single-baseline procedure rather than repeatedly stress-running desktop input checks. Final evidence identifies the boundary scenarios, commands, results, and any actual environment limitation. A grep showing fewer casts is supplementary evidence only.

## Checkpoints

No commit, push, merge, or worktree operation is authorized by this plan. All task write sets are disjoint, so no mid-plan persistence checkpoint is required for file reuse. If execution discovers otherwise, revise ownership before reusing the file; do not manufacture a commit authorization.

When the user separately authorizes persistence, checkpoint the accepted final integrated change after the full verification gate. Follow the repository's requirement to push any authorized commit to its corresponding remote branch.
