# rollcheck Swift migration — plan

Re-point the original C++ piano-roll check assertions recorded in
`src/checks/rollcheck/proof.*.txt` (22 ledgers, including `static/`) at
executing Swift assertions, and record the coverage as `MATCHED` in the
ledgers. Behavior contract and vocabulary: [spec.md](spec.md). The
[Swift backend charter](../swift-backend-charter.md) governs where it applies
(S-1 especially: never retune reference expectations to conceal a mismatch).

## Success criteria

1. 979 addressable sites (799 GAP + 180 PARTIAL) flip to `MATCHED`, each
   citing an `S###` Swift predicate that a green run executed.
2. All 274 `NATIVE` sites remain `NATIVE`, including the named blockers
   (spec.md §Blockers).
3. `deno task verify --filter swiftcore --verbose` and
   `deno task verify:qml-roll --verbose` pass on the controller's final gate.
4. No C++ check source, C++ harness, or new QML file is touched; existing
   QML adapted only where a Swift backend requires it.

## Current state (evidence)

- 22 proof ledgers audit 21 surviving C++ sources; `header_reconciliation.cpp`
  was deleted in `91cab247` (its proof remains, sites A002/A006 are blockers).
- Swift lane mechanics (verified in tree): `SwiftCoreTest::projectSession`
  runs `pdc_suite_run(PDC_SUITE_PROJECT_SESSION=10, …)` in
  `src/checks/support/corecheck/tst_swiftcore.cpp:71`; the Swift dispatch is
  `pdcSuiteRun` in `src/checks/support/corecheck/CoreCheckSupport.swift:89`;
  `runProjectSessionSuite` (`src/checks/workspace/SessionChecks.swift:10`)
  already calls `runEditorCameraChecks` (:11) and `runEditorGridCameraChecks`
  (:45). Swift check sources register in the `swift_core_check` target list in
  `src/checks/CMakeLists.txt` (~:150, :194-195).
- QML roll lane (commit `4c0f9215`): `roll_qml_tests` runs
  `src/checks/rollqml/RollQmlTests.swift` over the existing
  `tst_SwiftRoll*.qml` / `tst_TimelinePan.qml`; dispatched by
  `deno task verify:qml-roll --verbose` (tools/cli.ts VERIFY_LANES).
- Swift production owners exist for every family (spec.md owner map):
  `PianoGrid`, `GridGesture`, `GridScene`, `NoteCommands`, `EditorCamera` +
  `PitchProjection`, `GridGeometry`, `EditKeyArbiter`/`EditCommands`,
  `DocumentSession` selection, `VelocityPage`/`VelocityPromptPolicy`,
  `TrackHeaders`, `NoteEditing`/`NoteMovement`.
- Disposition baseline (controller-verified counts): 1253 sites = 799 GAP +
  274 NATIVE + 180 PARTIAL + 0 MATCHED. Per-file counts live in the ledgers;
  reconcile with `deno task proof list --area rollcheck`.

## Tasks

All tasks are SDD-track / `sdd-implementer`. Justification is identical in
kind and cited once here: each port judgment-transcribes original C++
assertions (fixture values, action sequence, transaction boundaries) into
Swift scenarios and reconciles proof dispositions — mechanical transcription
is impossible without inventing correspondence, and review independence
requires the brief not dictate bodies. No task is Qt-heavy C++ (no C++ is
written); seat stays `sdd-implementer` throughout.

| # | Task | Sites | Route / seat | Prereqs (interfaces) |
| --- | --- | --- | --- | --- |
| 1 | [Camera transform, zoom, panning](task-1-brief.md) | 104 | SDD / sdd-implementer | none |
| 2 | [Fallback grid & tick ceiling bounds](task-2-brief.md) | 40 | SDD / sdd-implementer | none |
| 3 | [Pointer draw, velocity latch, double-press delete](task-3-brief.md) | 72 | SDD / sdd-implementer | 1, 2 |
| 4 | [Edge resize, minimum clamping, abutting pairs](task-4-brief.md) | 28 | SDD / sdd-implementer | 1, 2 |
| 5 | [Note commands: split, join, duplicate, undo](task-5-brief.md) | 60 | SDD / sdd-implementer | 3 |
| 6 | [Keyboard transpose, snap nudges, timeline insertion](task-6-brief.md) | 94 | SDD / sdd-implementer | 3 |
| 7 | [Selection mechanics, duplicate identity, gesture interlock](task-7-brief.md) | 79 | SDD / sdd-implementer | 3 |
| 8 | [Track remap, header presentation, reconciliation](task-8-brief.md) | 118 | SDD / sdd-implementer | 5 |
| 9 | [Velocity, time-signature, ruler/loop menus](task-9-brief.md) | 282 | SDD / sdd-implementer | 5, 6 |
| 10 | [Scale folding & scale editing invariants](task-10-brief.md) | 54 | SDD / sdd-implementer | 2 |
| 11 | [Note rendering geometry, insets, border bounds](task-11-brief.md) | 39 | SDD / sdd-implementer | 1 |
| 12 | [Ready/gated channel transitions](task-12-brief.md) | 9 | SDD / sdd-implementer | 1 |

Execution order (waves; within a wave, tasks have disjoint Swift/proof write
sets — the two shared integration files excepted, see Global Constraints):

```text
A: 1 ∥ 2          (coordinate foundation)
B: 3 ∥ 4          (gestures)
C: 5 ∥ 6 ∥ 7      (commands, keyboard, selection)
D: 8 ∥ 10         (remap/presentation, scale)
E: 9              (prompts & menus — largest single writer)
F: 11 ∥ 12        (rendering, gate) + final gate
```

### Sizing exceptions (named)

Tasks 1, 3, 6, 7, 8, 9, 10, 11 exceed the 3-file triage signal. Each is one
behavior family with one verification surface (one swiftcore run, plus the
QML lane where the family is QML-observable); splitting at a proof-file
boundary would invent seams and multiply shared-build verification. Task 9 is
additionally the plan's largest (282 sites, 4 stems) and is deliberately
scheduled as a serial wave of its own.

## Global Constraints

- **Worktree (absolute):** all edits happen in
  `/Users/spencer/dev/cProjects/porydaw/.worktrees/swift-qml-grid-rollqml-checks`
  (branch `feature/swift-qml-grid-rollqml-checks`). Nothing edits the main
  checkout. `AGENTS.md` is a dirty user edit — never touch it.
- **Scope:** `src/checks/rollcheck/**` including `static/`, its
  `proof.*.txt` ledgers, the `src/checks/rollqml/**` lane files it
  exercises, and exactly two integration points:
  `src/checks/CMakeLists.txt` (append Swift sources to `swift_core_check`
  only) and `src/checks/workspace/SessionChecks.swift` (suite calls only).
  Production Swift under `src/swift/**` may be edited only to fix behavior a
  covered assertion exposes. `src/checks/trackheaders/**` is read-only
  reuse (helpers/fixtures), never a write target.
- **No new C++; no edits to C++ check sources** — nothing under
  `src/checks/rollcheck/*.cpp|*.h`, `static/*.{cpp,h}`, `harness.cpp`,
  `rollcheck.h`, `tst_pianoroll*.h`, `src/checks/support/**`, or any other
  C++ in the repo. Consequently every new stem registers into the existing
  `projectSession` suite (10); no new suite slots or `PDC_SUITE_*` enums.
- **No new QML files.** Adapt existing QML (check lane
  `src/checks/rollqml/**`, production `src/ui/songview/quick/**`) only when
  a Swift backend requires it; each adaptation is justified in the task
  report.
- **Swift behavior follows the C++ piano roll.** Port fixture values,
  sequences, and transaction boundaries verbatim from the proof sites'
  recorded original context. Never retune an expectation to match Swift
  output; a failing assertion means the Swift implementation (or the check
  driver, never the expectation) is fixed to follow C++. No workarounds
  (AGENTS.md): stop, name the root cause, request approval.
- **Proof edits:** flip a site to `MATCHED` only when the new Swift
  assertion covers that original assertion and a green run executed it;
  `PARTIAL → MATCHED` only by discharging the site's explicit unproved
  condition. Leave `NATIVE` sites `NATIVE` (all 274) and GAP/PARTIAL sites
  untouched otherwise. Never touch the spec.md blockers
  (`header_reconciliation` A002/A006, `gate` A076–A082, framebuffer-pixel
  NATIVE sites). Every disposition change rewrites the site's
  Mapping/Mapping-reason line and cites its `S###` predicate; tallies and
  header verification evidence are refreshed in the same edit.
- **Filenames:** new Swift check files use the C++ counterpart stem — the
  authoritative list in spec.md §"New Swift check stems". Do not rename
  existing Swift files.
- **Verification:** implementers skip shared builds, formatters, and
  project-wide suites (siblings edit concurrently). Implementer-local,
  allowed and required: `deno task proof …` / `deno task proof:edit …`
  (scoped to `src/checks`), `deno task proof check`, and read-only source
  inspection. The controller runs the covering gates:
  `deno task verify --filter swiftcore --verbose` (narrow form
  `deno task verify --filter swiftcore --qt projectSession`) and
  `deno task verify:qml-roll --verbose` for QML-surface tasks, plus
  `deno task lsp:swift` at milestones after Swift/CMake edits. Reuse the
  briefs' recorded commands without re-discovering; reassess only if scope
  changes or a command proves stale, and report the mismatch.
- **Shared integration files:** `src/checks/CMakeLists.txt` and
  `SessionChecks.swift` are re-edited by most tasks. Each task appends only
  its own registration lines; the execution loop serializes same-file
  writers or checkpoints the prior writer first (see Checkpoints).
- **Charter Swift conventions:** declarations before implementation bodies;
  identifiers mirror C++ counterparts where parity demands; no defensive
  frameworks or test-only production APIs.
- **Commits:** the controller (and only the controller) commits and pushes
  green milestones. Before each commit the controller dispatches a
  thermo-nuclear maintainability review of that milestone's uncommitted
  work and commits only after the audit is accepted or its findings are
  fixed and re-reviewed. Implementers and this planner never commit.

## Verification policy (stated once)

- Per-task covering commands are recorded in each brief's Acceptance
  predicate / Controller verification. swiftcore-only tasks: one command.
  QML-surface tasks: swiftcore + `verify:qml-roll`.
- Final whole-plan gate (controller, once, after Task 12):
  `deno task verify --filter swiftcore --verbose`;
  `deno task verify:qml-roll --verbose`;
  `deno task proof check`;
  `deno task proof list --area rollcheck` (expect 979 MATCHED, 274 NATIVE,
  0 GAP/PARTIAL outside the retained blockers);
  `deno task lsp:swift`.
- Per AGENTS.md, any failing assertion is surfaced to the user before
  handoff; pre-existing failures are reported, not hidden or widened.

## Checkpoints (milestones, not task bookkeeping)

Each milestone: wave accepted → controller gate (verification policy) →
thermo-nuclear review → commit + push. Earlier accepted writers are
checkpointed before a later task re-edits the shared integration files.

- **M1 — coordinate foundation:** Tasks 1–2.
- **M2 — editing core:** Tasks 3–7.
- **M3 — remap & scale:** Tasks 8, 10.
- **M4 — prompts & menus:** Task 9.
- **M5 — rendering & gate + final handoff:** Tasks 11–12 and the final
  whole-plan gate.

## Source anchors

| Owner | Current |
| --- | --- |
| Suite dispatch | `src/checks/support/corecheck/tst_swiftcore.cpp:71-74`, `CoreCheckSupport.swift:89-149`, `core_check.h:18-25` |
| Roll suite home | `src/checks/workspace/SessionChecks.swift:10-48` |
| Swift source registration | `src/checks/CMakeLists.txt` `swift_core_check` target list (~:149-198) |
| Existing roll check idioms | `src/checks/rollcheck/EditorGridCameraChecks.swift` (`cppID` ids, `check*` scenarios), `src/checks/rollcheck/static/camera.swift`, `src/checks/rollcheck/velocity_prompt.swift` |
| QML lane | `src/checks/rollqml/RollQmlTests.swift`, `tst_SwiftRoll*.qml`, `tst_TimelinePan.qml`; lane dispatch `tools/cli.ts` VERIFY_LANES (`verify:qml-roll` → `roll_qml_tests`) |
| Proof tooling | `tools/proof_reader.ts` (list/show/sites/search/check), `tools/proof_editor.ts` (exact-entry edits) |
| Parity discipline | `docs/plans/swift-cpp-check-parity-audit.md` (gap queue, ledger rules), `docs/plans/swift-cpp-check-parity-handoff.md` (pairing conventions) |
| Production Swift owners | spec.md owner map |
