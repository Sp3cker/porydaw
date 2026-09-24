# Task 5 — Note commands: split, join, duplicate, undo

## Context

`proof.note_commands.txt` carries 60 GAP sites (A001–A052, A057–A064)
auditing note duplication, splitting, joining, and context-menu popup
commands with their transaction boundaries. Owner: `NoteCommands` in
`src/swift/app/roll/NoteCommands.swift` (`.copy`, `.cut`, `.duplicate`,
`.delete`, `.split`, `.join`, `.lengthenNote`, `.shortenNote`,
`.setVelocity`) over `DocumentSession` history. Related existing coverage:
`EditorGridCameraChecks.checkCommandRouting`. Producer for Tasks 8–9
(remap and menu tasks cite the command-transaction idiom established
here).

## Exact write set

- `src/checks/rollcheck/note_commands.swift` (new)
- `src/checks/rollcheck/proof.note_commands.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)

## Prerequisites

Task 3 (selection/gesture interface for creating the fixture notes).

## Interface contract

- `@MainActor func runNoteCommandChecks(_ report: CheckReport, session:
  DocumentSession)`; one `check*` scenario per original command case;
  `cppID: "swiftcore/PianoRoll::<scenario>"` per proof header.
- Each command scenario asserts: document result, selection result, and
  one-undo restoration (charter S-3), using public history traversal only
  (no test-only history accessors — existing corpus caveat).

## Implementation steps

1. Read `deno task proof sites rollcheck/note_commands.cpp`; reproduce
   each command's fixture selection, expected splits/joins, and undo
   round-trip exactly.
2. Write `note_commands.swift`; menu-invoked variants go through the same
   `NoteCommands` entry the production menu uses, not a parallel path.
3. Register per spec.md §Registration.
4. Flip all 60 sites GAP→MATCHED with `S###`-citing Mapping lines;
   4 NATIVE sites stay; refresh evidence + Tally.

## Acceptance predicate

All 60 listed sites MATCHED; NATIVE unchanged (4); `deno task proof
check` passes. NAMED CHECKS — controller: `deno task verify --filter
swiftcore --verbose`; implementer-local: `deno task proof check`.

## Task-specific constraints

- swiftcore-only surface: no QML adaptation is in scope for this task;
   popup *behavior* sites that are QML-observable belong to Task 9's menu
   surface — if a site here proves QML-only, leave it GAP and report it
   for Task 9 instead of forcing a model-level stand-in.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task lsp:swift`.
