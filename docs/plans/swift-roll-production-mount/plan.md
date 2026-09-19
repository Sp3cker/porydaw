# Swift backend Wave 3 — production mount (gated read-only Swift roll)

> Historical Wave 3 dispatch record — do not resume these tasks.
> Read-only scope, frozen write sets and old verification commands below
> belong to that wave. The [current charter](../swift-backend-charter.md)
> and [ownership design](../swift-ownership-cutover/design.md) govern new
> work and adapter retirement; retained behavior still needs replacement
> acceptance. No claim below makes a feed or QWidget host permanent.

This wave puts the Swift note grid inside the production application for the
first time: the prototype's grid compiles as a library linked into
`porydaw` itself, a document feed seam (`sgd_*`, the `TimeMap` value-struct
pattern) delivers real `SongDocument` snapshots into Swift, and
`PORYDAW_SWIFT_ROLL=1` mounts a read-only Swift roll overlay into the
production `TimelineQuickView` window. Scope locks: **read-only** — no key
delivery, no gestures into the document, no undo crossing, no TimeCamera /
Grid / PitchBendKernel work. Decisions recorded in
[swift-backend-charter.md](../swift-backend-charter.md) bind every task,
especially S-2 (value feeds, no object borrows), INV-3 (Swift never sees
the window), and the platform decision (APPLE-gated target; no MinGW
accommodations). Behavior contract: [spec.md](spec.md).

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Swift grid library in the production build](task-1-brief.md) | SDD-track / sdd-implementer | Shared QtBridge extraction, approved registration API patch, APPLE-only import/link ownership | 2's declared module/ABI paths (co-developed; no file overlap) |
| 2 | [`sgd_` document feed seam + revision guard](task-2-brief.md) | SDD-track / sdd-implementer | Per-lifetime identity, routing/lifecycle and real Swift revision guard | 1's agreed module/link target for settled verification |
| 3 | [Swift grid consumes the document (read-only mode)](task-3-brief.md) | SDD-track / sdd-implementer | Mutation boundary, demo initialization removal and real timebase/signature rendering | 2's value receiver; 1's build interface |
| 4 | [Gated production mount + integration harness](task-4-brief.md) | SDD-track / qt-cpp-reviewer | QML model ownership, production window lifecycle and concurrent-tab isolation | 1's public registration API/target; 2's observer; 3's read-only model |

Execution order: **{1 ∥ 2} → 3 → 4.** Task 1 solely owns root/prototype
CMake import/link/feed-source registration and initial dependency patch; Task 2 owns
new feed files/module map/Swift values and checks registration. Their writers
share no files; integrated verification waits for both. Task 3 never edits
`SgdDocument.swift`. Task 4 reuses prototype CMake for host-source/resources
only and checks registration for its harness, after the accepted prior writers
are checkpointed. It owns the real `timelinequickview_window.cpp` teardown
path as well as the constructor/header.

Sizing exceptions: Task 3's grid, geometry/scene/typography, explicit demo/audio
initialization and nullable factory bridge form one real-document-rendering
change proved by the existing native smoke surface. Task 4's model registration, mount, resources and
integration harness form one production behavior proved by `swiftrollgated`.
Both exceed the file-count signal deliberately; no artificial microtasks.

## Global Constraints

- Every brief inherits this section, the linked [spec.md](spec.md), and
  [swift-backend-charter.md](../swift-backend-charter.md). Where they
  disagree, the charter wins.
- **Retirement scope:** the charter's
  [Compatibility and retirement decision](../swift-backend-charter.md#compatibility-and-retirement-decision-2026-09-18)
  is authoritative; its table is not duplicated here. This wave removes
  standalone app/selftest entry points from the production library and
  replaces demo fixture content with document-fed content on the production
  path. It does not delete the standalone acceptance lane or fixtures it
  still needs. Local undo is inactive in production read-only mode, not
  rewritten or retired globally. The flag, old renderer, duplicate sandbox
  behavior checks, and callable parity adapters remain only until their
  named charter gates; this mount does not claim editable/default cutover.
  Production grid/feed/host integration is built to stay; only the table's
  enumerated verification/mount machinery is migration-only. No demo API
  or smoke row creates a backward-compatibility promise.
- **Single Swift source set.** The production library target and the
  prototype lane compile the SAME files under
  `src/ui/songview/quick/swift-grid-prototype/`; the production target's
  exclusion list (App entry + selftest drivers) is fixed in Task 1's brief
  and is the only permitted divergence. No `#if`-style production forks of
  Swift sources.
- **Production C++ write set is closed for this wave:** root
  `CMakeLists.txt`, `cmake/QtBridge.cmake` (new), new files under
  `src/ui/songview/quick/swiftgrid/`,
  `src/ui/songview/quick/timelinequickview.{h,cpp}` and
  `timelinequickview_window.cpp` (mount/lifecycle only), new harness dirs under
  `src/checks/`, existing `swiftgridprototype/grid_smoke.{h,cpp}`, and the three
  check registration points. Swift/build/QML edits are limited to each brief's
  exact write set. Any other source needed is a brief defect, not an implicit
  write-set expansion.
- **Read-only scope lock.** No key events cross to Swift; the overlay
  takes no focus; no Swift-originated document mutation exists in any
  code path this wave; `sgd_` delivery is C++→Swift values only.
- **Seam naming:** this wave owns `sgd_` values/routing and
  `sg_register_grid_types` registration only. `sgm_`/`sgp_`/`sga_`/`sgw_`
  native seams and Wave-1 Tick/TimeAxis/PitchProjection sources remain frozen.
  GridGeometry/GridScene/GridTypography may consume real document timebase and
  signatures with viewport-bounded marks and on-demand label measurement while
  preserving demo-default raster behavior; no TimeCamera/Grid/PitchBendKernel
  conversion or duplicate math. AudioSession may stop eager demo initialization,
  not migrate production audio.
- **Approved QtBridge correction (2026-09-18):** expose existing
  `QmlInstantiable.registerQmlElement` as public through the preserved dependency
  patch mechanism. QML owns the nonvisual model. No package/private proxy access,
  manually retained grid factory or second app/engine. Task 1 owns this patch.
  Task 3 additionally owns user-approved nullable QObject QVariant conversion:
  rejected editor factories return a typed null, not a dummy object or an
  invalid variant. Existing generic Optional syntax needs no macro extension.
- **Exact identity boundary:** minted nonzero UInt64 per feed lifetime; copied
  document snapshots only. The active endpoint routing table retains no document
  or snapshot and erases entries on unmount; no singleton active document.
- APPLE gating is platform-conditional enablement, not a MinGW
  accommodation (charter platform decision): `if(APPLE)` around the Swift
  target and mount; nothing is added for MinGW.
- Production access symbols this wave relies on (verified):
  `SongDocument::revision()` / `SongDocument::documentChanged()`
  (src/core/songdocument.h:147,452), `SongView::selectedTrack` /
  `selectedTrackChanged(int)` (src/ui/songview.h:170,672),
  `TimelineQuickView` embed path (src/ui/songview/quick/timelinequickview.h:100-210).
- Swift identifiers mirror their C++ counterparts; port parity outranks
  Swift naming convention.
- Use `deno task` for every named command; never invoke `cmake` directly.
  Reuse the briefs' recorded checks without repeating discovery; reassess only
  when scope changes or a command proves stale. Read-only local inspection is
  implementer-owned; all shared-tree builds/tests/formatters belong to the
  controller after writers settle.
- User authorized verified checkpoint commits and pushes on 2026-09-18.
  Persistence follows acceptance/review, not merely a finished writer.

## Verification policy

Two new harnesses plus the existing surfaces, decided once here:

1. `swiftdocfeed` (Task 2): fixture snapshot/observer correctness plus an actual
   `SwiftGrid.DocumentFeed` check-only Swift entry point linked to shared code;
   monotonic revisions, interleaved identities, and disconnected teardown.
2. `swiftrollgated` (Task 4): production initial render, track-follow,
   mutation/undo/redo refresh, two-tab isolation/unmount, input inertness with
   live pan/zoom/hover, and flag-off absence.
3. Production canaries after any production-file edit:
   `deno task build:app`,
   `deno task verify --filter selectionkey-core --verbose`,
   `deno task verify --filter rollcheck-static --verbose`.
4. Prototype regression (Tasks 1, 3): `deno task prototype:swift-grid
   --smoke` — the wave must not change any existing row outcome.

Controller's final gate after Task 4: all four above, run once, whole plan.

## Checkpoints

User approved checkpoint commits and pushes. Batch coherent accepted work:

- Checkpoint the accepted prerequisite focus fix, retirement contracts and
  repaired wave contracts before implementation.
- Checkpoint accepted Tasks 1–2 before Task 3 extends the dependency patch for
  nullable factories. Task 3 consumes Task 2 values without editing that seam.
- Checkpoint accepted Task 3 before Task 4 reuses prototype CMake and the check
  registration files.
- Checkpoint remaining accepted work after Task 4 and the final gate.

## Source anchors

| Owner | Current |
| --- | --- |
| Prototype build lane | `tools/swift_grid_prototype.ts`, `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` |
| QtBridge fetch + patch | prototype `CMakeLists.txt` FetchContent + `qtbridge-object-return.patch` / `PatchQtBridge.cmake` |
| C-ABI seam precedent | `src/checks/swiftgridprototype/policy_smoke.h` (`sgp_*`), `native/window_cancel.{h,cpp}` (`sgw_*`) |
| Staleness-guard precedent | `PendingHeaderMenu` in `src/ui/songview/trackheadermodel.h:208-217` |
| Production embed path | `timelinequickview_window.cpp` (`takeWindowForEmbedding`, eventFilter), `timelinequickscene.cpp` |
| Harness patterns | `src/checks/selectionkey/windowtier_keyboard.cpp`, catalog entries in `src/checks/checkcatalog.cpp:669+` |
| Document values | `songdocument.h`: `smf().division`, `engineTrackCount`, `notesForTrack`, `timeSigs`, `revision`; `timedefaults.h`: unsigned `Tick` |
| Supported QML ownership | QtBridge `QmlInstantiable.swift:53-56` (approved visibility change), `QMetaObjectBuilder.swift:368-388` (retained creation/deleter), `QmlInstantiableStatus.swift:26-29` |
| Disproved extraction route | QtBridge `QObjectHolder.swift:13` package proxy, `QVariant.swift:155` internal cppVariant; neither is used |
| Real data assumptions | `GridGeometry.swift` fixed 24/96; `GridScene.swift` fixed bars/signature; Task 3 parameterizes these existing owners |
| Eager demo audio | `AudioSession.swift:25-44`; Task 3 moves fixture/native session creation to explicit prototype initialization |
