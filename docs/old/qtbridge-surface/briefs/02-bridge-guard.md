# Brief 02 — Bridge surface guard (`verify:bridge`)

## Context

Highest-leverage item (audit §3.2): nothing today can answer "is this member
QML-visible?" — the macro plugin writes no manifest and the runtime property
list is `internal` to QtBridge. This task adds a static guard that
cross-references QML against Swift declarations, with a shrink-only baseline
so the current tree passes while normalization (03/04) and deletions (05-08)
empty it. Full contract: spec.md §4.

## Exact write set

- `/tools/qtbridge_surface.ts` (new)
- `/tools/cli.ts` (Subcommand union `:29-37`, `help()` case, dispatch case,
  pre-build hook at the top of `runVerify()` — `tools/cli.ts:310`, before
  the `runBuild` call at `:365`)
- `/deno.json` (new `verify:bridge` task)
- `/tools/qtbridge_surface_baseline.json` (new; generated, never hand-edited)

No `src/` file is touched. No proof ledger is touched. Note the pre-hook
makes every `verify*` lane run the guard — that is the point.

## Prerequisites

None. Parallel with 01.

## Interface contract

- CLI: `deno task verify:bridge [--update-baseline]`; exit 0 when every
  finding is in the baseline and no baseline entry is stale; exit 1
  otherwise. `--update-baseline` rewrites the baseline to current findings.
- Finding line format: `<CHECK> <repo-relative-path>:<line> <detail>` where
  CHECK ∈ {`UNREACHABLE_QML`, `UNANNOTATED_MEMBER`, `REDUNDANT_TRACKED`,
  `UNTRACKED_CUSTOM_TYPE`, `REDUNDANT_IGNORED`, `SUGAR_OPTIONAL_RETURN`,
  `SIGNAL_NEVER_OBSERVED`, `HANDLER_NEVER_EMITTED`, `STALE_BASELINE`}.
- Baseline schema: `{ "pin": "<qtbridge pin sha>", "findings": ["<CHECK> <path>:<line> <detail>", …] }`
  — entries must match finding lines exactly.

## Implementation steps

1. **Swift model.** Reuse `tools/proof_anchor.ts` (`:68-590` — lexical
   scanner that already handles Swift `var`/`let` stored properties,
   strings, comments). If a needed helper isn't exported, prefer adding an
   `export` in `proof_anchor.ts` only when the change is that keyword;
   otherwise write local helpers in `qtbridge_surface.ts`. Do not refactor
   proof tooling. Locate `@QtBridgeable` class bodies; classify each stored
   instance member per spec §1: skip `private`/computed/`didSet`; flag
   non-private members without a type annotation (`UNANNOTATED_MEMBER`);
   supported type + `@QtTracked` → `REDUNDANT_TRACKED`; non-supported type
   without `@QtTracked`/`@QtIgnored` → `UNTRACKED_CUSTOM_TYPE`;
   `@QtIgnored` on `private`/`static`/computed → `REDUNDANT_IGNORED`.
   The supported-type set is a named constant mirroring
   `Extensions.swift:139-155` (basic six, `[String]`, `[String:
   QVariantSettable]` incl. `Array`/`Dictionary` spellings, `QListModel<`,
   `QTableModel<`) with the pin `407714006dd…` recorded beside it.
   Public funcs returning sugar-optionals (`T?`) where `T` is an identifier
   → `SUGAR_OPTIONAL_RETURN`.
2. **Signals (B2).** Collect `@QtSignal func <name>` declarations; collect
   `on<CapitalizedName>` function handlers in QML (skip comments/strings via
   the scanner) and Swift `connect`-style subscriptions (`.connect(`,
   closure-hook bindings of the form `on<Name> =`); collect emission call
   sites (`name(` on the declaring instance + `emitSignal(for:)` forms).
   Signal with no observer → `SIGNAL_NEVER_OBSERVED`; handler with no
   matching declaration or no emission site → `HANDLER_NEVER_EMITTED`.
   Only names that resolve to bridged classes are reported (element types
   come from `instantiableTypes` arrays —
   `src/swift/app/shell/PorydawShellApp.swift:18` — plus types reached via
   annotated class-typed properties; unresolvable handlers are silent).
3. **QML universe (B0).** Registered set = parse the `QML_FILES` block
   (`CMakeLists.txt:211-268`) plus `src/ui/shell/PorydawApplication.qml`
   (`CMakeLists.txt:394`). Path-loaded set = string operands of
   `QmlEngineAccess.moduleResourcePrefix + "…"` in `src/swift`. Reference
   edges = component type names used in any QML under `src/ui` or
   `src/checks` (incl. relative-file test compositions) and component path
   strings in `src/checks/**/*.swift` staging tables
   (`EditorQmlTests.swift:73-92`). A `src/ui` QML file in none of these →
   `UNREACHABLE_QML`.
4. **Baseline + wiring.** Implement `--update-baseline`, `STALE_BASELINE`
   on non-reproducing entries, the exit contract; add the cli.ts subcommand
   (help text in the style of `:74-82`), dispatch, and the `runVerify()`
   pre-hook that runs the guard before building and exits non-zero on
   failure; add the deno.json task with permissions mirroring siblings
   (read `src/`, `CMakeLists.txt`, `tools/`; write only `tools/` for
   baseline updates).

Edge cases: findings inside `src/checks/**` count (check QML observes
production types); a handler on a `Connections` target that is a plain QML
type is not a bridge finding; `model.X` reads are out of scope; multiple
declarations per line are out of scope (report file-level).

## Acceptance predicate

NAMED CHECKS (controller): `deno check tools/qtbridge_surface.ts
tools/cli.ts` clean; `deno task format:check` green; `deno task
verify:bridge` exits 0 on a freshly generated baseline whose findings
include the known population (≥ 6 `UNANNOTATED_MEMBER`-class entries incl.
`AutomationHandles.swift:83`, the 5 dead QML files +
`quick/TrackHeaderBand.qml` as `UNREACHABLE_QML`, and the 7 dead signals as
`SIGNAL_NEVER_OBSERVED`/`HANDLER_NEVER_EMITTED`); negative probe — add
`public var zzGuardProbe = 1` to any `@QtBridgeable` class body, `deno task
verify:bridge` exits 1 naming it, revert, exits 0; `deno task verify:qml
--verbose` green (proves the pre-hook composes with a real lane).

## Task-specific constraints

- Std-library Deno only; no new dependencies, no `npm:` imports.
- Do not gate `format`/`build` tasks on the guard — only `verify*`.
- Never special-case file paths or symbol names inside the guard logic;
  the baseline is the only exemption mechanism.
