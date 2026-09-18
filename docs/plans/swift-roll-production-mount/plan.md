# Swift backend Wave 3 — production mount (gated read-only Swift roll)

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
| 1 | [Swift grid library in the production build](task-1-brief.md) | SDD-track / sdd-implementer | Cross-build-system surgery (QtBridge ExternalProject lift + Swift mixed target in root CMake, APPLE-gated); wrong shapes silently fork the Swift sources | none |
| 2 | [`sgd_` document feed seam + revision guard](task-2-brief.md) | SDD-track / sdd-implementer | New C-ABI seam porting the `PendingHeaderMenu` staleness pattern to a document snapshot; contract work, not mechanics | none |
| 3 | [Swift grid consumes the document (read-only mode)](task-3-brief.md) | SDD-track / sdd-implementer | Grid mutation paths must be provably inert under `readOnly` while pan/zoom/hover stay alive; behavior-boundary judgment | 2 (SgdDocument + delivery contract) |
| 4 | [Gated production mount + integration harness](task-4-brief.md) | SDD-track / qt-cpp-reviewer | QQuickWindow content ownership, engine registration, and event absorption inside the production embed path — Qt ownership/lifecycle heavy | 1 (library target), 3 (read-only grid) |

Execution order: **{1 ∥ 2} → 3 → 4.** Tasks 1 and 2 share no files (1:
root `CMakeLists.txt`, `cmake/`, prototype `CMakeLists.txt`; 2: new
`src/ui/songview/quick/swiftgrid/`, new harness `src/checks/swiftdocfeed/`,
catalog registrations). Task 3 re-edits nothing from Task 1 and consumes
Task 2's header; Task 4 consumes the Task 1 target and Task 3 behavior,
and is single-writer on `timelinequickview.{h,cpp}`.

Sizing exception: Task 4 closes over more files than the triage default
(mount point, QML, qrc, harness, registrations) but is one behavior
change with one verification surface (`swiftrollgated`) — planned over
the count, single dispatch.

## Global Constraints

- Every brief inherits this section, the linked [spec.md](spec.md), and
  [swift-backend-charter.md](../swift-backend-charter.md). Where they
  disagree, the charter wins.
- **Single Swift source set.** The production library target and the
  prototype lane compile the SAME files under
  `src/ui/songview/quick/swift-grid-prototype/`; the production target's
  exclusion list (App entry + selftest drivers) is fixed in Task 1's brief
  and is the only permitted divergence. No `#if`-style production forks of
  Swift sources.
- **Production C++ write set is closed for this wave:** root
  `CMakeLists.txt`, `cmake/QtBridge.cmake` (new), new files under
  `src/ui/songview/quick/swiftgrid/`, `src/ui/songview/quick/timelinequickview.{h,cpp}`
  (mount point only), new harness dirs under `src/checks/`, and the three
  registration points (`src/checks/CMakeLists.txt`,
  `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp`). Everything else
  under `src/` is read-only. An unlisted file the compiler names is a
  brief defect — escalate, do not expand.
- **Read-only scope lock.** No key events cross to Swift; the overlay
  takes no focus; no Swift-originated document mutation exists in any
  code path this wave; `sgd_` delivery is C++→Swift values only.
- **Seam naming:** this wave owns the `sgd_` prefix. `sgm_`/`sgp_`/
  `sga_`/`sgw_` seams and the Wave-1 math sources are frozen (no edits);
  the only shared prototype files this wave may edit are
  `PianoGrid.swift` (Task 3, read-only mode) and the prototype
  `CMakeLists.txt`/`module.modulemap` (Task 1 lift, behavior-preserving).
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
  Implementers run only their task's named checks and reuse the recorded
  commands without repeating discovery; reassess only if scope changes or
  a command proves stale, and report the mismatch. Read-only local
  inspection stays allowed; shared-tree builds and formatter runs belong
  to the controller.
- **No commit is authorized by this plan.** Git persistence waits for
  explicit user approval (see Checkpoints).

## Verification policy

Two new harnesses plus the existing surfaces, decided once here:

1. `swiftdocfeed` (Task 2): `sgd_` snapshot correctness + revision-guard
   semantics against a fixture `SongDocument`.
2. `swiftrollgated` (Task 4): production `WorkspaceUi` boot with
   `PORYDAW_SWIFT_ROLL=1`, overlay mount, snapshot render of the fixture
   song, track-follow, input absorption.
3. Production canaries after any production-file edit:
   `deno task build:app`,
   `deno task verify --filter selectionkey-core --verbose`,
   `deno task verify --filter rollcheck-static --verbose`.
4. Prototype regression (Tasks 1, 3): `deno task prototype:swift-grid
   --smoke` — the wave must not change any existing row outcome.

Controller's final gate after Task 4: all four above, run once, whole plan.

## Checkpoints

No commit is authorized yet. When the user authorizes persistence:

- After Task 2 is accepted (Task 3 consumes `document_feed.h` and
  `SgdDocument.swift` — checkpoint the seam before file reuse).
- After Task 4 acceptance + final gate green (wave close; charter and
  this plan updated with results).

## Source anchors

| Owner | Current |
| --- | --- |
| Prototype build lane | `tools/swift_grid_prototype.ts`, `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` |
| QtBridge fetch + patch | prototype `CMakeLists.txt` ExternalProject + `qtbridge-object-return.patch` |
| C-ABI seam precedent | `src/checks/swiftgridprototype/policy_smoke.h` (`sgp_*`), `native/window_cancel.{h,cpp}` (`sgw_*`) |
| Staleness-guard precedent | `PendingHeaderMenu` in `src/ui/songview/trackheadermodel.h:208-217` |
| Production embed path | `timelinequickview_window.cpp` (`takeWindowForEmbedding`, eventFilter), `timelinequickscene.cpp` |
| Harness patterns | `src/checks/selectionkey/windowtier_keyboard.cpp`, catalog entries in `src/checks/checkcatalog.cpp:669+` |
