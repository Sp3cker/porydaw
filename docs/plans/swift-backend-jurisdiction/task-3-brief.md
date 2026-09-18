# Task 3: EditCommandPolicy frozen table + `sgp_*` parity seam

## Context

`EditCommandPolicy` is the one interaction surface of this wave that is
pure data behind a callable function, so it takes the Wave-1 oracle
trick: port the 35-row canonical table to Swift as frozen data and lock
it with live C-ABI parity (`sgp_*`, spec §4). Linking production
`editactions.cpp` into the isolated prototype lane would drag the whole
`EditActions`/SongView widget web, so the table is first extracted into a
data-only production TU ([spec](spec.md) §1 D4, §5.3) — a behavior-preserving move
that is also the cutover direction (the policy data Swift will own,
separated from the widget class). Producer for Task 4 (resolver + parity
driver live on this seam).

## Exact write set

Created:
- `src/ui/songview/editcommandtable.cpp` (production)
- `src/ui/songview/quick/swift-grid-prototype/EditCommands.swift`
- `src/checks/swiftgridprototype/policy_smoke.h`
- `src/checks/swiftgridprototype/policy_smoke.cpp`
- `src/ui/songview/quick/swift-grid-prototype/PolicySelftest.swift`

Edited:
- `src/ui/songview/editactions.cpp` — remove the moved block (spec §5.3 list); `EditActions`, `liveRowEnabled`, and everything else stay
- `CMakeLists.txt` (root) — add `src/ui/songview/editcommandtable.cpp` beside `editactions.cpp` (~L346)
- `src/checks/swiftgridprototype/module.modulemap` — add `header "policy_smoke.h"`
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` — add `policy_smoke.cpp` to `swift_grid_smoke`; compile `editcommandtable.cpp` into the smoke's link (same pattern as `swift_grid_curve` compiling production sources)
- `src/ui/songview/quick/swift-grid-prototype/App.swift` — call `runPolicySelftestIfRequested()` after `runMathSelftestIfRequested()`

## Prerequisites

None at the interface level (serialize after Task 2 on the shared
prototype `CMakeLists.txt`, per plan execution order).

## Interface contract

- `editcommandtable.cpp`: `kCommandTable`, the four row helpers,
  `actionIndex`, `commandTableFollowsEnumOrder`, both `static_assert`s,
  and the `editCommandPolicy` definition move **verbatim** from
  `editactions.cpp` (spec §5.3). `editactions.h` is not edited; no
  signature, value, or row-order change.
- `EditCommands.swift` exactly as spec §3.3: `EditCommand` (35 values,
  `SongView::EditCommand` order, `copy = 0` … `gridTriplet = 34`), the
  six operation/routing enums + `EditDeliveryClass` with C++ raw values,
  `EditCommandPolicy` with all 14 fields under their C++ names, and
  `editCommandTable` / `editCommandPolicy(_:)`. Pure data; no behavior.
- `policy_smoke.h/.cpp` exactly as spec §4: `SGECommandPolicyRow`,
  `sgp_command_count` (35), `sgp_policy_row`; C++ side is thin
  conversion over the extracted table — no logic.
- `PolicySelftest.swift`: `runPolicySelftestIfRequested()` — no-op unless
  `PORYDAW_SWIFT_GRID_SMOKE == "1"`; asserts the `policy-table-parity`
  sweep (35 × 14 fields, FAIL names command/field/values, nonzero exit);
  output group naming per spec §4.

## Implementation steps

1. Extract the table block into `editcommandtable.cpp` verbatim; add the
   root CMake source line. The `static_assert`s must compile in the new
   TU (a future table/enum mismatch must still fail the production
   build).
2. Write `policy_smoke.h/.cpp` over the extracted table; register the
   header in the module map, the source in `swift_grid_smoke`, and the
   production TU in the smoke link.
3. Write `EditCommands.swift` mirroring every row from `editactions.cpp`
   (read the source, not this plan); write `PolicySelftest.swift` with
   the parity sweep; hook it into `App.init()` after the math selftest.
4. Run the acceptance checks.

## Acceptance predicate

`policy-table-parity` passes (every command, every field, Swift ==
production through `sgp_*`); the Wave-1 math groups, existing smokes,
Tasks 1–2 rows, and the final `SWIFT_GRID_SMOKE PASS` are unchanged; the
extraction changes no production behavior. Named checks (implementer
runs):

- `deno task prototype:swift-grid --smoke`

Controller runs after this writer settles (production-behavior gates for
the extraction — not implementer-run):

- `deno task build:app`
- `deno task verify --filter selectionkey-core --filter selectionkey-gesture --filter selectionkey-window --filter selectionkey-local-input --filter editcheck --verbose`

Covers: Swift table parity (the sweep), extraction behavior-preservation
(the selectionkey suites' catalog comments name keyboard routing tiers
that consume `editCommandPolicy` through `handleEditKey`; `editcheck`
names song document editing through `EditActions`), production compile
(`build:app`). Coverage gap, named: enablement presentation
(`liveRowEnabled` over live `SongView` state) is not exercised by these
filters beyond its callers — the extraction does not touch it, and any
failure there surfaces in the same suites' menu rows.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. This task is the
wave's only authorized production edit (plan Global Constraints): keep it
a pure move; if the compiler forces any non-mechanical adjustment, stop
and report rather than adapting. Do not touch `math_smoke.*` or
`MathSelftest.swift` — the module map gains one line, `App.swift` gains
one call, nothing else Wave-1 changes. `EditCommands.swift` is one
cohesive data file (~300L of table); do not split it per command family.
The parity sweep is the gate for the table — and only the table; it
claims nothing about undo/cancel (spec §1 D6).
