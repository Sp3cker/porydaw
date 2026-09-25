# Brief 03 — Normalize the 6 non-private unannotated members

## Context

Finding A (audit §2) re-verified: exactly 6 non-private stored members of
`@QtBridgeable` classes have inferred types, so their QML visibility is an
accident of syntax (spec §1: the annotation gate is
`bindings.first?.typeAnnotation`). This task resolves each one deliberately
per spec R1-R3 so guard class `UNANNOTATED_MEMBER` is emptied (minus the one
member brief 07 deletes). The dispositions are decided here; the implementer
executes, they do not choose.

## Exact write set

- `/src/swift/app/eventlist/EventListPresenter.swift`
- `/src/swift/app/drawer/automation/AutomationPage.swift`

No `src/checks/**` file; no proof ledger is touched or affected.

## Prerequisites

01 (spec/rule published), 02 (guard produces the `UNANNOTATED_MEMBER`
baseline this task empties).

## Interface contract

| Member (verified site) | Disposition |
|---|---|
| `EventListRowHandle.isEndOfTrack` — `EventListPresenter.swift:14` (`public var isEndOfTrack = false`) | annotate `: Bool` — becomes an exposed read-only-ish model role |
| `EventListRowHandle.rowTint` — `EventListPresenter.swift:15` (`public var rowTint = ""`) | annotate `: String` — exposed role |
| `AutomationPage.publishedPointerGestureActive` — `AutomationPage.swift:330` | add `: Bool` **and** `@QtIgnored` (internal gesture flag, not QML-facing; access level unchanged) |
| `AutomationPage.panActive` — `AutomationPage.swift:332` | add `: Bool` and `@QtIgnored` |
| `AutomationPage.tapSession` — `AutomationPage.swift:336` | add `: AutomationTapTempoSession` and `@QtIgnored` (custom type; annotation required by R1, `@QtIgnored` keeps it unexposed) |
| `AutomationRampHandle.primitiveName` — `AutomationHandles.swift:83` | **not in this task** — brief 07 deletes the whole class; leave untouched |

Exposed-result note: annotating the two `EventListRowHandle` members
registers them as model roles with `<name>Changed` NOTIFY and write-time
`didSet` emission (spec §1). QML today reads them nowhere (verified: the
EventList delegates use `controller.isRowTinted(row)` /
`controller.rowTint(row)` methods), so this is additive surface, not a
behavior change. Row handles are plain `@QtBridgeable` rows, not
`QmlInstantiableStatus`, so init-time writes are safe.

## Implementation steps

1. Apply the five dispositions exactly; change nothing else in either file
   (no access-level changes, no reordering, no comment additions).
2. Local inspection: `lsp diagnostics` on both files; confirm the only
   declaration-level diffs are the annotations/attributes above.

Edge cases: if `AutomationTapTempoSession` is itself `@QtBridgeable`, the
`@QtIgnored` still suppresses exposure (spec §1 rule 3) — disposition
unchanged; if LSP shows an external (non-file) reference to any of the three
AutomationPage members, do not change access — `@QtIgnored` is orthogonal to
access level and the disposition stands.

## Acceptance predicate

NAMED CHECKS (controller): `deno task build:checks` green; `deno task
verify:bridge` reports no `UNANNOTATED_MEMBER` other than
`AutomationHandles.swift:83` (baseline entry remains until 07); `deno task
verify --filter swiftqtml --verbose` green (bridge registration primitives);
`deno task verify:qml --verbose` green (editor lane exercises the EventList
surface).

## Task-specific constraints

- Do not annotate the 18 `private` members (audit's overcount) — they are
  invisible by construction.
- Do not preview brief 04's strips here.
