# Brief 01 — QtBridge surface rule file + contract-doc reconciliation

## Context

Finding I (audit §2): the only document describing QtBridge mechanism and
declaration contracts lives under `docs/plans/` (not agent-loaded), and its
ownership table is C++-era (`RewriteWindow` no longer exists in `src/`).
This task makes the convention agent-loaded. It produces the rule file that
every later task and every future contributor is reviewed against; spec.md
§2 remains the full normative text.

## Exact write set

- `/.omp/rules/qtbridge-surface.md` (new)
- `/docs/plans/qtbridge-integration-contract.md` (header note only)

No `src/` file is touched. No proof ledger is touched (no `src/checks/**`
write at all).

## Prerequisites

None. Parallel with 02 (disjoint files).

## Interface contract

`/.omp/rules/qtbridge-surface.md`:

- Front matter shaped exactly like sibling rules (compare
  `/.omp/rules/text-contrast.md`: `name`, `description`, `scope`). Scope
  covers Swift and QML edits (`tool:edit`/`tool:write` on `*.swift`,
  `*.qml`).
- Body ≤ 80 lines, stating — in the rule voice of the siblings, no RFC
  prose: exposure requires an explicit supported type (list them);
  `@QtTracked` only for non-supported (class/custom) types; `@QtIgnored` to
  opt out public members, never on `private`/`static`/computed; `private(set)`
  and extension members never expose; signals need observers, closures are
  the Swift-side channel (no closure→signal forwarding); every `src/ui` QML
  file must be module-registered or contentUrl-loaded; sugar `T?` slot
  returns are silently unregistered (use `Optional<T>`); returned objects
  must be retained Swift-side; emissions are queued (next event-loop turn);
  never mutate published state from `init` of a `QmlInstantiableStatus`
  class. Close with: full normative text + enforcement in
  `docs/plans/qtbridge-surface/spec.md`; guard = `deno task verify:bridge`.

`/docs/plans/qtbridge-integration-contract.md`: insert one short paragraph
immediately after the existing Status paragraph (line 3): the declaration
convention and its enforcement now live in `.omp/rules/qtbridge-surface.md`
and `docs/plans/qtbridge-surface/spec.md`; the lifetime ownership table and
`RewriteWindow`/context-property rows are historical records of the retired
C++ shell; the verified mechanism/evidence rows below remain authoritative
for bridge capability. Do not rewrite any other part of the document.

## Implementation steps

1. Read `/.omp/rules/text-contrast.md` and `/.omp/rules/swift-standards.md`
   for front-matter and voice; read spec.md §1-§4.
2. Write the rule file per the contract above. Rules are assertions with a
   one-line reason each; no examples longer than one line; no code blocks.
3. Add the contract-doc header note.

Edge cases: do not duplicate spec.md verbatim (the rule is the distillation
agents see on every edit; the spec is the reference); do not restate
`AGENTS.md` content; do not mention findings/audit numbers in the rule file
(rules are timeless).

## Acceptance predicate

NAMED CHECKS (controller): `deno task format:check` green (no formatted
surface touched); structural review confirming the rule file's front-matter
keys match a sibling rule and every spec §2/§3 rule id R1-R10/Q1-Q4 is
represented or consciously subsumed; `grep -n "RewriteWindow"
docs/plans/qtbridge-integration-contract.md` still shows the historical rows
plus the new scope note. Implementer runs no commands (SHARED_TREE).

## Task-specific constraints

- Do not edit `AGENTS.md` (requires human permission).
- Do not delete or reword existing contract-doc rows — additive note only.
