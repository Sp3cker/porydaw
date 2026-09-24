# Brief 04 — Strip redundant annotations, annotate tracked members

## Context

The audit's §1 table found three coexisting declaration styles on bridged
classes; the macro source proves the distinctions are imaginary for
supported types (plan.md deltas table: explicit `@QtTracked` on a supported
type is a strict expansion no-op, `QtBridgeableMacro.swift:395-438`;
`@QtIgnored` on `private`/`static`/computed members never reaches the
macro's ignore check). One convention (spec R1-R3) survives; the redundant
annotations go. This is a mechanical, behavior-neutral batch — the guard
enumerates the edit list, counts are expectations, not targets.

## Exact write set

Every `src/swift/**/*.swift` file the guard lists — expected population:
files carrying the 65 redundant `@QtTracked` (explicit supported types), the
156 no-op `@QtIgnored` (131 `private`, 23 `private(set)`, 2 `static`, plus
any computed-property strays the guard flags), and the `@QtTracked` members
still lacking type annotations (audit estimated ~197 inferred `@QtTracked`,
incl. 7 class-typed initializers like `scene = GridScene()`). No `src/checks`
file; no proof ledger.

## Prerequisites

03 (dispositions settled; do not re-edit its five members beyond their
recorded state). Serialized after 03 because the write sets overlap the same
class bodies.

## Interface contract

Three edit shapes, nothing else:

1. **Strip `@QtTracked`** where the member's annotation is a spec §1
   supported type (guard class `REDUNDANT_TRACKED`). Registration and
   emission are identical without it.
2. **Add the missing type annotation** to every `@QtTracked` member that
   lacks one — the annotation is the inferred type's exact spelled-out form;
   after annotating, if the type is supported, also strip the `@QtTracked`
   (shape 1 applies); if class/custom, keep `@QtTracked` (it is required).
3. **Strip `@QtIgnored`** from `private`, `static`, `private(set)`,
   computed, or `didSet`-carrying members (guard class `REDUNDANT_IGNORED`).

## Implementation steps

1. Run read-only inspection to enumerate: controller supplies the current
   `deno task verify:bridge` finding list with the task dispatch (the
   baseline). Group shapes 1-3 per file.
2. Apply edits file-by-file; each edit touches exactly one declaration; no
   access-level changes; initialization expressions and surrounding
   declarations preserved verbatim.
3. Self-review against the enumeration: every finding addressed or
   explicitly out of scope (`AutomationHandles.swift:83` — owned by 07;
   anything inside members briefs 05-08 will delete is still normalized —
   do not skip them, stripping is cheap and deletion removes the whole
   declaration later).

Edge cases: multi-variable declarations (`public var a = 1, b = 2`) — skip
and report; the guard reports them file-level. Attribute placement differs
(`@QtTracked public var` vs `public @QtTracked var`) — preserve the
surviving shape's existing placement style per file.

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:checks` green; `deno task
verify:bridge` reports zero `REDUNDANT_TRACKED`, zero `REDUNDANT_IGNORED`,
zero `UNANNOTATED_MEMBER` except `AutomationHandles.swift:83`; `deno task
verify --filter swiftqtml --verbose`, `deno task verify:qml --verbose`,
`deno task verify:qml-roll --verbose` green (three lanes exercise presenter
properties end-to-end, covering the no-op claim at runtime).

## Task-specific constraints

- Mechanical batch over the file cap — per-file list from the guard output;
  reviewed as one unit (triage-rule exemption, named here).
- Never delete a `@QtIgnored` from a **public stored** member — those are
  intentional opt-outs (R3); only the no-op placements listed in shape 3.
- If any strip coincides with a member brief 05 deletes (session signal
  plumbing closures etc.), strip anyway; 05 deletes wholesale.
