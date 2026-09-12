# Task 3: xcmd vocabulary

## Context

Consumes Task 2’s `Tick`. Producer for Task 4 (xcmd / lanemoveplan tick fields). Identity preservation: `index` / `sourceIndex` / `removeEvents` stay `uint64_t`.

## Exact write set

- `src/core/xcmd.h`
- `src/core/xcmd.cpp`
- `src/core/lanemoveplan.h`
- `src/core/lanemoveplan.cpp`
- `src/core/songdocument_xcmd.cpp`
- `src/core/songdocument_timeeditor_xcmd.cpp`

## Prerequisites

2.

## Interface contract

`Tick` positions: `xcmd::{Event,Point,PointWrite,Relocation,Emission}::tick`, `LaneMovePoint::tick`, `LaneMoveRequest::toTick`, `LaneMoveWrite::tick`.

Stay `uint64_t`: xcmd `index` / `sourceIndex` / `removeEvents` / `consumed`.

`static_assert(sizeof(LaneMovePoint) == 8)`. Keep field order. Do not regroup `xcmd::Event` / `Point` members.

Do not change `songdocument.h` signatures (Task 4). Do not edit unlisted checks (`tst_xcmd.*` is Task 7).

## Implementation steps

1. Flip the named xcmd / lanemoveplan positions to `Tick` in this write set. Leave identity uint64s.
2. Apply the `LaneMovePoint` sizeof assert. Do not reorder.

## Acceptance predicate

xcmd identities still `uint64_t`; tick fields compile as `Tick`. Named checks: `deno task verify --filter xcmdcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: narrowing `Event::tick` while treating `index` as a tick (or the reverse) breaks xcmd identity. Do not start if time-editing is mutating `songdocument*`.
