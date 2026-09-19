# Swift backend Wave 1 — view math (Tick, TimeMap/TimeAxis, PitchProjection)

> Historical Wave 1 dispatch record — do not resume these tasks.
> Read-only oracle write sets and prototype commands below were wave-local,
> not a permanent prohibition on migrating/deleting C++ implementations.
> New work follows the [current charter](../swift-backend-charter.md) and
> [ownership design](../swift-ownership-cutover/design.md); preserve the
> relevant behavioral evidence until its replacement gate passes.

First executable epic of the Swift production-backend conversion: port the
three pure value-math modules the destination DAG roots — the `Tick`
helpers (`timedefaults.h`), `TimeAxis` as a **value type over a copied
`TimeMap`** (no `MidiTimeline*` borrow), and `PitchProjection` — into the
Swift host, locked against the production C++ implementations by a live
parity oracle in the existing prototype smoke. Behavior:
[spec.md](spec.md).

Production C++ `TimeAxis`/`PitchProjection`/`timedefaults` stay untouched as
the oracle. No production cutover, no `GridGeometry.swift` changes, no
TimeCamera/Grid/kernel/MidiTimeline/audio work (see spec §1 decisions).

## Tasks

| Task | Requirement brief | Route / seat | Triage justification | Interface prerequisites |
| --- | --- | --- | --- | --- |
| 1 | [Tick helpers + parity seam](task-1-brief.md) | SDD-track / sdd-implementer | Cross-language verification seam plus trap-sensitive numeric port (Int64 headroom ordering, Double bounds before conversion); not mechanical | none |
| 2 | [TimeMap + TimeAxis value type](task-2-brief.md) | SDD-track / sdd-implementer | Algorithmic port (last-same-tick wins, denominator clamp, bar carry across partial measures) with live dual-run parity | 1 |
| 3 | [PitchProjection value type](task-3-brief.md) | SDD-track / sdd-implementer | Rounding-mode + binary-search port (half-away-from-zero DPR edges, lower-pitch-wins ties) with live dual-run parity | 1 |

No Direct-route tasks: every task creates or extends the numeric-contract
seam that later epics build on; all three are judgment work under one
verification surface.

Task 3 consumes only Task 1's interfaces, but Tasks 2 and 3 **serialize**
(1 → 2 → 3): both append to the seam files `math_smoke.h` / `math_smoke.cpp`
/ `MathSelftest.swift`. That file reuse is the deliberate cost of keeping
ONE seam instead of per-domain fragment headers; do not invent per-domain
seam files to buy parallelism.

File-count exceptions (single behavior change, one verification surface,
named here per sizing rule): Task 1 touches 7 files (five created, two
one-line edits); Tasks 2 and 3 touch 4 files each (one created, three
appended). Splitting at these boundaries would create an empty scaffold or
an uncompilable partial seam.

## Global Constraints

- Every brief inherits this section and the linked [spec.md](spec.md).
  Write sets are closed; preserve unrelated changes; refresh source
  sections before editing. An unlisted file the compiler or tool names is a
  brief defect — escalate, do not expand.
- **Production C++ is a read-only oracle.** No edits to `src/core/**`,
  `src/ui/**`, or existing `src/checks/**` files except the seam files a
  brief lists. In particular `timedefaults.h`, `miditimeline.h`,
  `timeaxis.{h,cpp}`, `pitchprojection.{h,cpp}` are never modified.
- Swift identifiers mirror their C++ counterparts exactly (`Tick`, `kNoTick`,
  `kMaxTick`, `shiftTickClamped`, `tickFromDouble`, `TimeSigPoint`,
  `buildFromPitches`, `cHiddenRow`, `nearestVisiblePitch`, …). Port parity
  outranks Swift naming convention; do not rename while porting.
- Trap-avoidance ordering is contract, not style: classify `Int64` headroom
  before any arithmetic; bound-check `Double` before any `UInt32`
  conversion; clamp shift amounts to ≤ 31 before `>>`; do all stride math
  in `UInt64`. Swift traps where C++ had UB — the ordering is what prevents
  the trap. Spec §7 restates the full list.
- Expected values in the spec §6 oracle tables are frozen. A parity
  mismatch is a defect report (port bug or stale oracle claim), never a
  silent edit of the expected value.
- Use `deno task` for every named command; never invoke `cmake` directly.
  Never `grep` the repo root without a path.
- New Swift files land at `src/ui/songview/quick/swift-grid-prototype/`
  top level only — the build GLOBs `*.swift` in exactly that directory and
  no subdirectory. New check sources land in `src/checks/swiftgridprototype/`.
- Implementers run only their task's named checks. Skip project-wide
  format/verify; local read-only inspection stays allowed. Reuse the
  recorded verification commands without repeating discovery; reassess only
  if scope changes or a command proves stale, and report the mismatch.

## Verification policy

One verification surface for the whole epic: the prototype smoke.

- `deno task prototype:swift-grid --smoke` — configure + build the Swift
  host, then run the native smoke (`PORYDAW_SWIFT_GRID_SMOKE=1`): the math
  selftest (Swift tables and live `sgm_*` parity against production C++
  `CoreTimeDefaults` / `songview::TimeAxis` / `songview::PitchProjection`)
  plus the existing grid/audio/interaction smokes as regression proof that
  the prototype UI is unchanged.
- `deno task prototype:swift-grid --build-only` — compile/type-check gate
  only; the fallback when windowing is unavailable.
- Runtime prerequisites: cmake ≥ 3.29, Ninja, Swift 6.4+, Qt 6.10+
  (`tools/swift_grid_prototype.ts` auto-resolves the local Qt prefix and
  the main checkout's poryaaaa); the smoke launches the real app bundle, so
  it needs a normal desktop session (native macOS is fine).

Coverage gaps, named: production `rollcheck`/`view-buckets-grid` exercise
C++ TimeAxis consumers, not Swift — their 7/8, seam, and fallback-grid
cases are ported as frozen literals (spec §6 F0b, F6, F8) instead of
running widget checks per task; `pitch-bend-editing` / `pitch-bend-raster`
exercise the widget PitchBendEditor, not the projection numeric core, and
claim no coverage here. The controller's final gate proves the untouched
production oracles still stand.

## Checkpoints

No commit is authorized by this plan. When the user authorizes persistence:

- After Task 1 (Tasks 2 and 3 re-edit `math_smoke.h`, `math_smoke.cpp`,
  `MathSelftest.swift`, and the module map).
- After Task 2 (Task 3 re-opens the same seam files).
- Final handoff after Task 3 review (covers Task 3's accepted work).

## Source anchors

| Owner (historical snapshot; retired paths available in Git history) | Behavior at that wave |
| --- | --- |
| [timedefaults.h](../../../src/core/timedefaults.h) | `Tick = uint32_t`, `kNoTick`, `kMaxTick`, `shiftTickClamped`, `tickFromDouble` |
| [miditimeline.h](../../../src/core/miditimeline.h) | `TimeSigPoint {tick, numerator, denomPow2}`; viewer fields `ticksPerBeat=24`, `lengthTicks=0`, `loopStartTick/loopEndTick=kNoTick`, `timeSigs` sorted |
| [timeaxis.h](../../../src/ui/songview/timeaxis.h) / [timeaxis.cpp](../../../src/ui/songview/timeaxis.cpp) | bind/borrow C++ oracle; fallback 24 TPB implicit 4/4; `beatsPerBarFor`, `beatTicksFor` |
| [pitchprojection.h](../../../src/ui/pitchprojection.h) / [pitchprojection.cpp](../../../src/ui/pitchprojection.cpp) | C++ oracle; `snappedRowEdge`, binary searches |
| Retired `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` | GLOB `*.swift`; `swift_grid_smoke` linked production math/audio sources |
| Retired `src/checks/swiftgridprototype/grid_smoke.h` / `module.modulemap` | `installGridSmoke` pattern; single-header Clang module |
| Retired `src/checks/swiftgridprototype/grid_smoke.cpp` | `installGridSmoke` → `prepareSmoke` → `exercise` → printed `SWIFT_GRID_SMOKE PASS` |
| Retired `src/ui/songview/quick/swift-grid-prototype/App.swift` | Standalone `@main` entry invoked `installGridSmoke()` |
| Retired `tools/swift_grid_prototype.ts` | Historical `--build-only` / `--smoke` runner; not a current command |
| [checkcatalog.cpp](../../../src/checks/checkcatalog.cpp) | coverage comments for `view-buckets-grid`, `rollcheck`, `rollcheck-static` |
