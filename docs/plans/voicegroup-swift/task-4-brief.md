# T4 — `KeysplitTables` parser

## Context

Port of `native-loader-spec.md` §3. Consumer: T7 (`BankBuildInputs.keysplits`),
T8 picker (keysplit kinds).

## Exact write set

- `src/swift/voicegroup/KeysplitTables.swift` (new)
- `src/checks/projectstore/KeysplitTablesChecks.swift` (new; `runKeysplitTablesSuite`)

## Prerequisites

T1.

## Interface contract

`spec.md` → "T4 — keysplit tables", verbatim. Plus:

```swift
public struct KeysplitParseError: Error, Equatable { public let file: String; public let line: Int; public let reason: String }
```

Semantics are §3 exactly: `keysplit <Name>, <start>` stores `keysplit_<Name>`;
`.set <name>, . - <start>` stores `<name>` verbatim; `split <index>, <endNote>`
fills `[lastNote, endNote)` and validates per `keysplit_split_values_are_valid`;
`.byte` lists store sequentially from `lastNote`; `current`/`lastNote` carry
across the file; INVALID lines throw; unknown lines are ignored; no dedupe;
`table(named:)` is first-wins. Tables are zero-filled before writes.

## Implementation steps

1. Read §3 and the cited C lines (`voicegroup_loader.c:1529-1760`).
2. Tokenize with `AsmLine` (strip comment, rtrim, ltrim as C does per line);
   match the literal prefixes with the exact single-space rule.
3. Checks: fixture `sound/keysplit_tables.inc` yields the two fixture tables
   (`keysplit_fixture`, `keysplit_fixture_bass`) with the §3-derived contents for
   `split 0,48 / split 1,96 / split 2,128` and `split 0,64 / split 1,128`
   (assert exact 128-byte arrays); `.set`/`.byte` form parses to the same table
   as the macro form; `split` with `endNote < lastNote` throws with the right
   line; `.byte 200` throws; first-wins on duplicate names; unknown directives
   ignored.

## Acceptance predicate

Controller registers `projectstore-keysplits` (argv `keysplitTables`) and runs:

```
deno task build:checks
deno task checks --filter projectstore-keysplits
```

## Task-specific constraints

Pure value code; no file I/O beyond `ProjectFileStore.read` per path.
