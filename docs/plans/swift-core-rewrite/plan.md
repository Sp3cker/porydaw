# Swift core rewrite → piano grid

Status: implementation underway. The coverage reconciliation, Swift 6.4 and
test-language amendments apply before acceptance of affected work; none
requires restarting the implementation. This replaces the M1/M2 sequence in
[swift-ownership-cutover](../swift-ownership-cutover/plan.md).

## Scope and stop

Rewrite all 33 files currently under `src/core/` as native Swift responsibilities,
then make the existing piano grid their first direct document consumer. Stop.
No header, ruler, drawer, browser, tab, or other consumer port; no new QML feature.
The rewrite application intentionally excludes those unmigrated surfaces from
construction and compilation. Their MIDI data is still loaded, edited by core
operations, saved, and played correctly. No reverse C++ document adapter.

The core includes MIDI storage/import, all document edits, history, tempo,
track/time/velocity/XCMD semantics, timeline projection **and the sequencer**.
`TimelinePlayer` is rewritten, not moved to `audio/` to make the inventory look
complete. Native device/DSP, instrument loading, project-file services, and a
small Qt host remain. See [spec.md](spec.md) for interfaces and file disposition.

The first consumer is PianoGrid because it already exists in Swift but still
receives copied C feeds and sends C intents. Replacing that dependency proves
actual ownership without first implementing another view. The end-to-end gate
is real project/song open → existing note gestures → undo/redo → save/reopen →
playback. Unconverted editors are absent, not misleadingly read-only.

## Global Constraints

- Inherit the [amended charter](../swift-backend-charter.md) and
  [QtBridge integration contract](../qtbridge-integration-contract.md). The
  latter is the capability evidence ledger, not proof of this rewrite.
- Optimize maintained code and concepts. One lossless event store, one history,
  direct Swift calls, no mirror document, C-shaped domain API, command bus,
  general observer framework, or compatibility modes. Do not transliterate
  `EditOp`/`QUndoCommand` class machinery. Public declarations come first.
- Core independence is the governing priority: C++ testability must never
  constrain Core's Swift API, representation, ownership or concurrency model.
  Apply the charter's [Swift implementation policy](../swift-backend-charter.md#swift-implementation-policy).
  Runner/envelope reuse is subordinate to that rule. A demonstrated host
  limitation requires a test-integration correction, not a Core compromise.
- Preserve normal-use behavior and real file errors. Do not add impossible-state
  stress matrices, repeated token guards, synthetic race frameworks, or new
  product features. Existing meaningful assertions remain reference contracts;
  implementation-pinning assertions are removed, not re-pinned.
- Until final cutover, the old application remains its own sole authority and
  Swift is exercised independently by checks. At cutover the new application
  links no old core or unconverted editor. No writable twin in one application.
- Use exact commands in the briefs; change them only for an evidenced scope or
  runner mismatch. New check names are explicitly marked prospective. All
  shared builds, tests, formatting, and native smoke runs belong to the
  controller after writers settle. Writers still inspect their own code.
- Existing C++ QTest cases and checked-in fixtures are the behavioral oracle,
  not the required language of replacement tests. Apply
  [test-language ownership](spec.md#test-language-ownership): Swift owns domain
  scenarios, direct production calls, comparisons and expected-result assertions.
  C++ is limited to runner/reporting glue, temporary oracle access and genuine
  native integration checks. No permanent C++ domain driver or per-operation
  Swift test ABI; no production `SongDocument` facade. Preserve coverage rather
  than retaining obsolete test bodies or a permanent duplicate suite.
- Required coverage accounting is defined in
  [spec.md](spec.md#case-by-case-coverage-reconciliation). Task 1 creates
  `docs/plans/swift-core-rewrite/coverage-ledger.json`; every task's exact write
  set additionally permits updates to its own rows in that file. The controller
  serializes ledger integration alongside other shared files. This is evidence,
  not a second test framework. Each task's acceptance includes independent
  reconciliation of its due rows against executed Swift-backed assertions.
  Passing suite names or equal test counts cannot substitute for this gate.
  No C++ core/oracle deletion is authorized while the retirement gate is open.
- Each accepted task and each cumulative milestone receives independent,
  read-only thermo-nuclear review, plus the SDD task/spec gate. Review settled
  scope against its recorded base, interface/deletion contract, verification,
  and known gaps. No dependent task consumes a materially changed interface
  before acceptance. One review may satisfy both gates when scope is identical.
  Review cohesion, duplicate state, wrapper count, callback ownership, COW
  cost, and retired code—not arbitrary file-size targets. Resolve material
  findings or reject them with source evidence; recheck material fixes. After
  two unsuccessful fix rounds, stop dependent dispatch and revisit the design.
  Reviewers do not run shared validation or modify the reviewed scope.
- Checkpoint accepted work at the milestones below and before later tasks
  re-edit an earlier uncommitted write set. Batch ready work at each checkpoint;
  no separate commit chore in each brief. Push every resulting commit.
- Apply [Swift 6.4 qualification](#swift-64-qualification) before accepting
  affected work. Each task's write set additionally permits its own qualification
  evidence in this plan and the integration contract; the controller serializes
  those shared documentation edits. Production write sets remain closed.
- The test-language amendment applies to active work before acceptance. Migrate
  already-written C++ domain assertions to the task-owned Swift checks without
  restarting production implementation. Every task's check write set also
  permits `src/checks/swiftcore/{CoreCheckSupport.swift,oracle_check.h,oracle_check.cpp,module.modulemap}`
  for its bounded runner/oracle integration; shared edits remain serialized.
  This is not permission for new C++ domain scenarios.

## Swift 6.4 qualification

Swift 6.4 is installed (user-reported), but installation is not project
qualification. Preserve the recorded 6.3.3 evidence as historical. The controller
records the selected compiler executable/version, SDK, deployment target,
language/interoperability flags, QtBridge pin/patch and macro compiler in the
[integration contract](../qtbridge-integration-contract.md#swift-64-qualification).
Ensure CMake and QtBridge macros select the intended compatible toolchain and
rebuild affected compiler-dependent artifacts. Keep `Swift_LANGUAGE_VERSION 6`;
it selects a language mode, not compiler release 6.4.

After writers settle, run:

```sh
deno task build:app
deno task verify --filter swiftqtml --filter swiftcore --verbose
```

These qualify app/macro compilation, real QML bridge capability primitives, and
the currently implemented Swift core checks. They do not prove an unexercised
new API, deployment on another OS, realtime safety, or final consumer behavior.
Task-specific checks and case-by-case coverage gates remain mandatory.

Before changing an accepted storage or ABI choice, complete a bounded disposable
comparison on the selected toolchain with the actual deployment/interop flags.
Task 5 owns the playback storage/export comparison; task 7 consumes its accepted
decision rather than reopening it. Record the candidate, exact probe command,
observed result, removed/added ownership and adapter concepts, and the decision.
Freeze any changed representation in the affected brief before implementation;
retain correct existing code when no concrete simplification is demonstrated.
Do not retain alternate implementations or introduce a benchmark framework.

Use new syntax, borrowing iteration, safe memory APIs or concurrency facilities
only where they remove existing work or express a required contract. Do not
replace useful snapshot/history sharing with unique ownership, add async work to
the render path, suppress upgrade diagnostics, retry failing tests until green,
or adopt unverified 6.5/proposal-only APIs. New library availability must be
proven for the deployment target; do not raise it or add fallback branches
without approval.

The app remains Deno/CMake-driven. Audit any SwiftPM invocation in the actual
QtBridge macro build for artifact discovery and compiler selection; do not
migrate the app to SwiftPM or preemptively select its legacy build system.
Report a required build fix outside a task's closed write set before editing it.

Feature references: [Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/),
[UniqueArray acceptance and rejected RigidArray/Containers scope](https://forums.swift.org/t/accepted-in-principle-se-0527-uniquearray/86943),
[UniqueBox](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0517-uniquebox.md).

## Tasks

All tasks use SDD-track: they introduce or consume a domain/native interface.
The larger write sets close one behavior boundary rather than manufacture
microtasks for individual C++ files.

| Task | Deliverable / brief | Prerequisites | Seat and sizing exception |
| --- | --- | --- | --- |
| 1 | [Lossless MIDI and musical primitives](task-1-brief.md) | None | `sdd-implementer`; codec, semantics and its comparison harness form one storage boundary. |
| 2 | [Document, note edits and history](task-2-brief.md) | 1 | `sdd-implementer`; one mutation/history boundary, including gesture grouping and save identity. |
| 3 | [Tracks, raw events and value streams](task-3-brief.md) | 2 | `sdd-implementer`; all changes share ordered-event mutation and one document transaction. |
| 4 | [Range and time transforms](task-4-brief.md) | 3 | `sdd-implementer`; one cross-stream transform boundary, not separate lane-specific implementations. |
| 5 | [Swift timeline and realtime sequencer](task-5-brief.md) | 1 | `sdd-implementer`; projection and scheduler are verified together against existing rendered behavior. |
| 6 | [Real project persistence and session](task-6-brief.md) | 2–5 | `qt-cpp-reviewer`; native project ownership and Swift persistence/session integration. |
| 7 | [Core runtime cutover and native host](task-7-brief.md) | 6; cumulative semantic gate | `qt-cpp-reviewer`; native clients, build membership and reference retirement are one core-runtime cutover. |
| 8 | [Direct piano-grid consumer, then stop](task-8-brief.md) | 7; core milestone | `qt-cpp-reviewer`; one existing view's direct model/input/host integration and transport retirement. |

Task 5's algorithm work is independent of tasks 2–4 after task 1. Shared build
and check-registration edits are serialized by the controller; no concurrent
writers touch those files. Do not parallelize coupled document mutation work
merely to increase the agent count.

## Milestones

1. **Storage accepted:** task 1 establishes types, the comparison path and the
   complete baseline coverage inventory; its own due rows are reconciled.
2. **Core accepted:** tasks 2–7 provide all old core responsibilities, real
   persistence/playback and the native application host. The old core is gone;
   the editor area is intentionally absent until the next task. Record final
   core comparisons before retirement.
   Retirement additionally requires the case-by-case gate in spec.md, followed
   by post-cutover proof that the mapped retained cases still execute on Swift.
3. **One consumer accepted:** task 8 converts the grid, repoints its actual-surface
   checks and removes obsolete transport. This is the terminal milestone.
   Do not dispatch a second consumer.

Shared CMake/check registration files can require an earlier checkpoint before
reuse; combine it with all other accepted work. Milestone labels do not require
empty or redundant commits.

## Evidence and reduction ledger

Inspected source baseline: `src/core/` has **33 files, 9,409 lines** (including
headers/comments; counted during planning). The scope inventory in spec.md is
exhaustive. Existing covering registrations are in
[`checkcatalog.cpp`](../../../src/checks/checkcatalog.cpp); runner selection
supports repeatable substring `--filter`, exact `--exclude`, and `--qt` for one
selected harness. It does **not** support `--no-build`.

Record actual commands/results with accepted task evidence here during
implementation. No planned command below is claimed to have run.

At core and final gates report three separate quantities:

1. Original core implementation versus replacement Swift core/playback code.
2. Removed feed/executor/mount code versus added necessary native-service/host
   code, including test-driver cost separately.
3. Unconverted UI excluded from the binary. **Do not count excluded features as
   successful code simplification.**

Review a net increase in core-plus-required-glue code before acceptance; explain
what behavior earns it or simplify. There is no arbitrary percentage target and
no pressure to compress readable code into fewer lines. A rename or exclusion
alone is not a Swift rewrite.

## Final verification boundary

The exact retained/deferred test policy is in [spec.md](spec.md#verification).
A default green rewrite suite is not a claim that absent-surface suites passed.
Run the real app with a staged project, not a duplicate demo. Capture a native
window and exercise existing gestures, keyboard priority, save/reopen and audio.
Keep ordinary close/reopen, cancellation and save-failure checks; do not invent
unreachable internal sequences. Planning-only validation checks paths, links,
brief completeness, inventory and registered command names—not application builds.

## Planning review

Independent core-design and native-integration reviews completed. Their findings
are incorporated: timing query, history-token ownership, snapshot/bank lifetimes,
save/close completion, registered-action boundaries and audition routing.
The final module graph and native clipboard/scene-lifetime contracts were also
checked. The later coverage, Swift 6.4 and test-language amendments add
acceptance requirements; the original reviews do not establish their execution
or coverage completeness.

Planning validation covers all 33 source files, eight bounded briefs, local links/
anchors, source-path declarations and verification filter names. `swiftcore`
is now registered; `build:render` remains prospective. No application build,
runtime check or native-window smoke is claimed by this planning review.

Post-amendment `evidence-plan-architect` audit: initially NEEDS_REVISION; final
targeted recheck PASS after restoring 22 task-1 rows to pending with historical
evidence preserved, correcting SE-0527 acceptance/deployment assumptions, and
fixing module-map/registration drift. The wider audit found the Swift-owned
test design and retained native boundaries implementable and consistent.
Mechanical validation passed for 11 Markdown documents, 41 local links/anchors,
eight brief schemas and ledger totals; all 834 baseline identities and historical
per-row evidence were preserved. This closes the planning findings, not task
acceptance: Swift-body execution, storage comparison and retirement gates remain.
