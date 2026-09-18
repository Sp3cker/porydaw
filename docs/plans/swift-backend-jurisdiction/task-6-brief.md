# Task 6: `editcommandtable.h` accessor header (drop unity include)

## Context

Task 3 extracted the canonical table into `editcommandtable.cpp` but
kept a `.cpp` include plus `HEADER_FILE_ONLY` so `EditActions` could
still see anonymous `CommandRow` / `kCommandTable`. That pairing is the
follow-up from the Task 3 review. This Direct task makes
`editcommandtable.cpp` a real TU: public header is declarations only,
the table stays anonymous in its TU, and neither `editactions.cpp` nor
`policy_smoke.cpp` includes a `.cpp`.

## Exact write set

Created:

- `src/ui/songview/editcommandtable.h` — accessor declarations only

Edited:

- `src/ui/songview/editcommandtable.cpp` — remain the table TU; no row
  value changes
- `src/ui/songview/editactions.cpp` — drop `#include "ui/songview/editcommandtable.cpp"`
- `src/ui/songview/editactions.h` — include the new header; do not
  redeclare `editCommandPolicy` if it moves
- `CMakeLists.txt` (root) — drop `HEADER_FILE_ONLY` on
  `editcommandtable.cpp`; keep it as a compiled `porydaw_app` source
- `src/checks/swiftgridprototype/policy_smoke.cpp` — include the
  accessor header (not the `.cpp`)

## Interface contract

- `editcommandtable.h` is declarations only. No `CommandRow`, no
  `kCommandTable`, no table data.
- Required: `const EditCommandPolicy &editCommandPolicy(SongView::EditCommand)`.
- Also declare the minimum host-column accessors `EditActions` already
  uses so it can iterate without seeing `CommandRow`: command count,
  keymap `id`, `checkable`, `windowObjectName`, `delivery`. Do not
  un-anonymize the table.
- Table, helpers, `kCommandTable`, and `CommandRow` stay in the
  anonymous namespace of `editcommandtable.cpp`.
- No signature, value, or row-order change. No Swift edits.

## Acceptance predicate

- `deno task prototype:swift-grid --smoke` — `policy-table-parity PASS`
  and final `SWIFT_GRID_SMOKE PASS` (Wave-1 / undo / cancel rows unchanged)
- Controller: `deno task build:app` and
  `deno task verify --filter selectionkey-core --filter selectionkey-gesture --filter selectionkey-window --filter selectionkey-local-input --filter editcheck --verbose`

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Charter
[docs/plans/swift-backend-charter.md](../swift-backend-charter.md) wins.
If dropping the unity include forces a non-mechanical `EditActions`
behavior change, stop and report. File-disjoint from Tasks 4 and 5.
Do not touch `grid_smoke.cpp` or other-agent visual-check files.
