# Swift backend Wave 2 — input jurisdiction (undo, cancel reasons, command policy)

After the frozen Wave 1 view math, this wave gives the Swift piano-grid
prototype the three input-jurisdiction properties a production cutover
demands: **undoable gesture commits** (SongDocument contract: one undoable
command per gesture, monotonic revision, exact restore), **four-way
cancel-reason parity** (`FocusLost` / `PointerUngrabbed` / `Hidden` /
`WindowDeactivated` with distinct teardown semantics), and the
**EditCommandPolicy table ported as data** locked by a live `sgp_*`
parity seam, with the selectionkey scenario dimensions and a single Swift
Escape arbiter as acceptance surfaces. The architectural decision this
wave records: Swift owns gesture math and policy data; arbitration (focus
chain, pointer grabs, popup stack, window activation) stays in the C++/QML
host — no second dispatcher. No TimeCamera / Grid / PitchBendKernel work
(sequence lock). Behavior: [spec.md](spec.md).

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Undoable PianoGrid gesture commits](task-1-brief.md) | SDD-track / sdd-implementer | Cross-language contract port (command granularity, revision, exact-restore semantics) with a new smoke surface; judgment work, not mechanical | none |
| 2 | [Four-way cancel-reason parity](task-2-brief.md) | SDD-track / sdd-implementer | Distinct per-reason teardown semantics ported from five production cancellers plus QML entry wiring; behavior differences are observable only through real event delivery | 1 (revision/undo surface used by cancel rows) |
| 3 | [EditCommandPolicy frozen table + `sgp_*` parity seam](task-3-brief.md) | SDD-track / sdd-implementer | Production table extraction (behavior-preserving move) + 35-row Swift mirror + live C-ABI parity sweep; production-behavior gates required | none |
| 4 | [Edit-key policy dimensions (ported selectionkey matrix)](task-4-brief.md) | SDD-track / sdd-implementer | Routing-decision port of `SongView::handleEditKey` policy branches with a six-dimension frozen scenario matrix; decision ordering is contract | 3 (policy table + seam) |
| 5 | [Single Escape arbiter](task-5-brief.md) | SDD-track / sdd-implementer | Consolidates the independent QML Escape handlers into one Swift policy entry taking full surface state; precedence table is a design decision, not mechanics | 2 (reason-taking cancel API) |

No Direct-route tasks: every task creates or extends a verification seam
and freezes semantics; all five are judgment work.

Execution order: **1 → 2 → 3 → {4 ∥ 5}**. The chain 1 → 2 → 3 is forced
by file reuse, not interfaces: Tasks 1 and 2 both edit `PianoGrid.swift`,
`jurisdiction_smoke.cpp`, `grid_smoke.h`, `grid_smoke.cpp`; Task 3 and
Tasks 1/2 both edit the prototype `CMakeLists.txt`. Tasks 4 and 5 share no
files (Task 4: `EditKeyArbiter.swift`, `PolicySelftest.swift`; Task 5:
`PianoGrid.swift`, prototype QML, `jurisdiction_smoke.cpp`) and may run in
parallel after 3 settles (Task 5 needs only Task 2's interface, but runs
after 3 to keep `jurisdiction_smoke.cpp` single-writer).

## Global Constraints

- Every brief inherits this section and the linked [spec.md](spec.md).
  Write sets are closed; preserve unrelated changes; refresh source
  sections before editing. An unlisted file the compiler or tool names is
  a brief defect — escalate, do not expand.
- **Wave 1 is frozen.** No edits to `Tick.swift`, `TimeAxis.swift`,
  `PitchProjection.swift`, `math_smoke.h/.cpp`, `MathSelftest.swift`, or
  anything under `docs/plans/swift-backend-view-math/`. This wave creates
  its own seam files (`policy_smoke.*`, `PolicySelftest.swift`); the only
  shared Wave-1 files touched are `module.modulemap` (one added header
  line) and `App.swift` (one added selftest call), both in Task 3.
- **Production C++ stays the oracle and stays authoritative.** The only
  production edits this wave authorizes are Task 3's behavior-preserving
  table extraction (`editactions.cpp` → new `editcommandtable.cpp`, plus
  one root `CMakeLists.txt` source line) — no behavior change, gated by
  the named production checks. Everything else in `src/core/**` and
  `src/ui/**` is read-only for this wave.
- **No TimeCamera, Grid, or PitchBendKernel work** in any task (user
  sequence lock; the numeric epic ladder resumes only after this wave
  lands).
- Swift identifiers mirror their C++ counterparts (`editCommandPolicy`,
  `EditCommandPolicy` field names, `TimelineInputCancelReason` reason
  names, `handleEditKey` branch names). Port parity outranks Swift naming
  convention.
- New Swift files land at `src/ui/songview/quick/swift-grid-prototype/`
  top level only (the build GLOBs `*.swift` exactly there). New check
  sources land in `src/checks/swiftgridprototype/`. The new production TU
  (Task 3) lands at `src/ui/songview/editcommandtable.cpp` — the wave's
  only addition under `src/ui/` outside the prototype directory.
- Host-arbitration rule (spec §1 D1) binds every task: Swift receives
  already-arbitrated plain values and returns decisions/mutations; QML
  never re-implements decision logic; Swift never observes Qt directly;
  no second dispatcher, synthetic forwarding, or focus memory.
- Use `deno task` for every named command; never invoke `cmake` directly.
  Never `grep` the repo root without a path.
- Implementers run only their task's named checks. Skip project-wide
  format/verify; local read-only inspection stays allowed. Reuse the
  recorded verification commands without repeating discovery; reassess
  only if scope changes or a command proves stale, and report the
  mismatch.
- **No commit is authorized by this plan.** Git persistence waits for
  explicit user approval (see Checkpoints).

## Verification policy

Two surfaces, decided once here:

1. **Prototype smoke — the gate for every task:**
   `deno task prototype:swift-grid --smoke` — configure + build the Swift
   host, then run the native smoke (`PORYDAW_SWIFT_GRID_SMOKE=1`): the
   Wave-1 math selftest groups, the new policy selftest groups (Task 3+),
   the existing grid/audio/interaction smokes, and the new
   `jurisdiction_smoke.cpp` rows (undo in Task 1, cancel in Task 2,
   escape in Task 5) driving real Qt event delivery (mouse
   press/move/release, `ungrabMouse()`, focus changes, `visible` toggles,
   a synthesized `QEvent::WindowDeactivate`). Compile-only fallback:
   `deno task prototype:swift-grid --build-only`. Runtime prerequisites:
   cmake ≥ 3.29, Ninja, Swift 6.2+, Qt 6.10+, normal desktop session
   (the smoke launches the real app bundle; native macOS is fine).
2. **Production behavior gates — Task 3 only** (the one task that touches
   production C++): `deno task build:app` (new TU compiles and links) and
   `deno task verify --filter selectionkey-core --filter selectionkey-gesture --filter selectionkey-window --filter selectionkey-local-input --filter editcheck --verbose`
   (the suites whose catalog comments name keyboard routing and document
   editing — they consume `editCommandPolicy`/`EditActions` and prove the
   extraction changed nothing). The controller runs these once after
   Task 3 settles, not per implementer.

Controller's final gate after Task 5 (run once, whole plan):
`deno task prototype:swift-grid --smoke` and
`deno task verify --filter rollcheck-static --filter view-buckets-grid --verbose`
(Wave 1 regression, per the sequence lock).

**The dual-run numeric oracle is NOT the gate for undo or cancel.** The
`sgm_*`/`sgp_*` parity pattern covers exactly one surface of this wave:
the EditCommandPolicy table (frozen data behind a callable function).
Undo and cancel state lives in the Qt focus chain, grabber, and popup
stack — no callable C++ function arbitrates it — so their acceptance is
the prototype smoke's event-driven rows (spec §6), never a parity sweep.
Any brief or review claiming parity-oracle coverage for undo/cancel is a
defect.

## Checkpoints

No commit is authorized yet. When the user authorizes persistence:

- After Task 1 (Task 2 re-edits `PianoGrid.swift`,
  `jurisdiction_smoke.cpp`, `grid_smoke.h`, `grid_smoke.cpp`; Task 3
  re-edits the prototype `CMakeLists.txt`).
- After Task 3 (Task 4 re-opens `PolicySelftest.swift`; Tasks 4/5 inherit
  the extraction's production gates).
- Final handoff after Task 5 review (covers Tasks 4 and 5's accepted
  work; the controller's final gate runs before it).

## Source anchors

| Owner | Current |
| --- | --- |
| [PianoGrid.swift](../../../src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift) | `endPointer` (in-place note mutation, ~L352), `cancelPointer`/`cancelRightPointer` (undifferentiated), `deleteSelection`, `doublePointer`, `commitPitchCurves`, `resetDemo` |
| [GridGesture.swift](../../../src/ui/songview/quick/swift-grid-prototype/GridGesture.swift) | six gesture kinds; `isRight` split; `updated(x:y:metrics:)` |
| [timelineinput.h](../../../src/ui/songview/quick/timelineinput.h) | `TimelineInputCancelReason` (order: FocusLost, PointerUngrabbed, Hidden, WindowDeactivated); `TimelineBandInteraction::cancelInteraction` default → `inputCancelled(PointerUngrabbed)` |
| [timelineinputitem.cpp](../../../src/ui/songview/quick/timelineinputitem.cpp) | per-item entry: `focusOutEvent`→FocusLost, `mouseUngrabEvent`→PointerUngrabbed, `ItemVisibleHasChanged`→Hidden (+focus drop, hover teardown) |
| [timelinequickview_window.cpp](../../../src/ui/songview/quick/timelinequickview_window.cpp) / [timelinequickview_keyrouting.cpp](../../../src/ui/songview/quick/timelinequickview_keyrouting.cpp) | window-level `Hide`/`WindowDeactivate` → `cancelActiveGestures()` (once per interaction; foreign/popup grabs protected) |
| [pianoroll_interaction.cpp](../../../src/ui/songview/pianoroll_interaction.cpp) / [pianoroll.cpp](../../../src/ui/songview/pianoroll.cpp) | roll cancel semantics: velocity-only via `inputCancelled`; strong `cancelPointerInteraction` via `cancelInteraction`; Hidden/WindowDeactivated also invalidate cursor + end keyboard audition |
| [timeruler_interaction.cpp](../../../src/ui/songview/timeruler_interaction.cpp), [voicechangearea.cpp](../../../src/ui/editordrawer/voicechangearea/voicechangearea.cpp), [drawerchrome.cpp](../../../src/ui/editordrawer/drawerchrome.cpp), [automationcanvas_input.cpp](../../../src/ui/editordrawer/automationcanvas_input.cpp) | per-surface reason tables (FocusLost keeps pointer delivery; menu-session protection; uniform chrome reset) |
| [editactions.h](../../../src/ui/songview/editactions.h) / [editactions.cpp](../../../src/ui/songview/editactions.cpp) | `EditCommandPolicy` (14 fields), `CommandRow`, `kCommandTable` (35 rows, enum order), `editCommandPolicy()`, `static_assert` pinning |
| [editkeyrouting.cpp](../../../src/ui/songview/editkeyrouting.cpp) | `SongView::handleEditKey` policy branches (Escape arbiter + ordered gates), `editCommandAvailable`, `resolveSelectionTarget` |
| [songdocument.h](../../../src/core/songdocument.h) | undo contract: one command per mutation, `undoStack()`, `revision()`, `documentChanged`; `moveNotes(…, mergeable)` |
| [songview.h](../../../src/ui/songview.h) | `SongView::EditCommand` (35 values, Copy…GridTriplet) |
| [interaction_smoke.cpp](../../../src/checks/swiftgridprototype/interaction_smoke.cpp) | QTest row pattern, `resetDemo` invoke, `ungrabMouse()` cancel drive, PASS naming |
| [Main.qml](../../../src/ui/songview/quick/swift-grid-prototype/Main.qml), [NoteMenu.qml](../../../src/ui/songview/quick/swift-grid-prototype/NoteMenu.qml), [PitchBendPopup.qml](../../../src/ui/songview/quick/swift-grid-prototype/PitchBendPopup.qml), [PitchBendGraph.qml](../../../src/ui/songview/quick/swift-grid-prototype/PitchBendGraph.qml) | current pointer wiring (`onCanceled` → no-arg cancels); the three independent Escape handlers + ShortcutOverride claims |
| [checkcatalog.cpp](../../../src/checks/checkcatalog.cpp) | coverage comments for `selectionkey-*` (routing tiers) and `editcheck` (document editing) |
| [CMakeLists.txt (prototype)](../../../src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt) | `swift_grid_smoke` explicit source list; Swift/QML GLOBs |
| [CMakeLists.txt (root)](../../../CMakeLists.txt) | `porydaw_app` explicit source list (~L346 `editactions.cpp`) |
