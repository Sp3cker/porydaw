# Task 1: Tick helpers + parity seam

## Context

First task of the Swift Wave 1 epic ([plan](plan.md), [spec](spec.md)).
Ports the `timedefaults.h` tick helpers to Swift (`Tick.swift`) and builds
the verification seam every later Wave-1/TimeCamera task locks against: a
C ABI (`sgm_*`) implemented in C++ over production types, imported by Swift
through the `NativeGridSmoke` module, driven by a Swift selftest hooked
into the existing prototype smoke. Producer for Task 2 and Task 3 (they
append time-axis and pitch groups to this seam and selftest).

## Exact write set

Created:
- `src/ui/songview/quick/swift-grid-prototype/Tick.swift`
- `src/ui/songview/quick/swift-grid-prototype/MathSelftest.swift`
- `src/checks/swiftgridprototype/math_smoke.h`
- `src/checks/swiftgridprototype/math_smoke.cpp`

Edited (one small change each):
- `src/checks/swiftgridprototype/module.modulemap` — add `header "math_smoke.h"` to `NativeGridSmoke`
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` — add `"${SWIFT_GRID_SMOKE_DIR}/math_smoke.cpp"` to the `swift_grid_smoke` sources
- `src/ui/songview/quick/swift-grid-prototype/App.swift` — call `runMathSelftestIfRequested()` in `init()` before `installGridSmoke()`

## Prerequisites

None (first task).

## Interface contract

- `Tick.swift` exactly as spec §3: `typealias Tick = UInt32`, `kNoTick`,
  `kMaxTick`, `shiftTickClamped(_:_:)`, `tickFromDouble(_:)` with the
  spec §5/§7 semantics and ordering. Pure Swift; no imports.
- `math_smoke.h` (spec §4): the four fixture structs may be declared now or
  with Task 2 (they cost nothing); the `sgm_shift_tick_clamped` /
  `sgm_tick_from_double` declarations and C++ implementations over
  `CoreTimeDefaults` are this task's deliverable. `extern "C"` throughout;
  header usable from both C++ and the Clang importer.
- `math_smoke.cpp`: includes `core/timedefaults.h` (include path comes
  from `swift_grid_curve`/`swift_grid_audio`'s PUBLIC `src` dir); thin
  forwarding only — no logic of its own.
- `MathSelftest.swift`: `runMathSelftestIfRequested()` — no-op unless
  `PORYDAW_SWIFT_GRID_SMOKE == "1"` (read via `ProcessInfo`); asserts spec
  §6 table T1 as literals AND runs the same rows through the `sgm_*`
  oracles (parity); output convention spec §4 (`SWIFT_GRID_SMOKE math-tick
  PASS` / `… FAIL: <case>` + nonzero exit).

## Implementation steps

1. Write `Tick.swift` per the frozen interface; the guard ordering of
   `shiftTickClamped` and `tickFromDouble` is spec §7, verbatim decisions —
   a reorder is a defect even when tests pass.
2. Write `math_smoke.h` + `math_smoke.cpp` with the two tick oracles;
   register the header in the module map and the source in
   `swift_grid_smoke`. Keep declarations tick-only — time-axis and pitch
   groups belong to Tasks 2–3.
3. Write `MathSelftest.swift` with the T1 literal table and the parity
   loop over the same rows; hook it into `App.swift` before
   `installGridSmoke()`. A FAIL must exit nonzero before any window opens.
4. Run the acceptance check.

## Acceptance predicate

`shiftTickClamped` and `tickFromDouble` match every T1 row as literals and
through live `sgm_*` parity; the existing grid/audio/interaction smokes are
unchanged and still pass; the smoke still ends with `SWIFT_GRID_SMOKE
PASS` and exit 0. Named checks (implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: Swift tick contracts (T1 literals), C++↔Swift parity on the same
rows, seam wiring (module map, CMake, App hook — a broken wire fails the
build or the smoke), and prototype regression. Compile-only fallback:
`deno task prototype:swift-grid --build-only`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: the
module map is a single-header Clang module today; adding a second header
that C++-only code includes must not change what Swift sees from
`grid_smoke.h`. Do not add `@_cdecl` or any C++→Swift call — Swift drives,
C++ answers (spec §1 D3). Do not touch `grid_smoke.cpp`; the selftest runs
from `App.init` before the pre-routine path.
