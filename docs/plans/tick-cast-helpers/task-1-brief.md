# Task 1: Numeric helpers and span contract

## Context

Produce the numeric interfaces consumed by Tasks 2–7. The representation has already narrowed; this task defines safe conversions instead of merely abbreviating casts. Shared behavior is in [Numeric interfaces](spec.md#numeric-interfaces).

## Exact write set

- `src/core/timedefaults.h`
- `src/core/songdocument.h`
- `src/checks/editcheck/tst_songdocument_songtime.cpp` — temporary helper probe only; no lasting change

## Prerequisites

None.

## Interface contract

Add `constexpr Tick CoreTimeDefaults::shiftTickClamped(Tick, int64_t)` and `inline Tick CoreTimeDefaults::tickFromDouble(double)` beside the existing numeric utilities. Implement the full input-domain contracts in the spec, with no additional maximum parameter. Change only the return type and body of `SongDocument::TimeRange::span()` to the specified Tick difference. No other public signatures change.

## Implementation steps

1. Implement the signed shift by testing headroom before arithmetic. Keep the helper allocation-free and constexpr-capable; do not negate an unrestricted negative delta.
2. Implement the floating conversion with classification before narrowing. Do not put a rounding policy in the helper.
3. Change `TimeRange::span()` and confirm its existing consumers, including `rangeedit.cpp`, remain well-typed. Do not edit consumers in this task or remove their necessary wide arithmetic.
4. Temporarily exercise the actual helpers and span inside the existing `EditCheckTest::songTimeSignature` slot before its normal fixture assertions. Cover the spec's signed extremes, zero crossings, sentinel input, NaN/infinities, fractional truncation, `nextafter` below the sentinel, and empty/reversed/full-width ranges. Include ordinary signed shifts in constexpr assertions in this temporary probe. Capture the result, then remove only the probe; the existing slot remains unchanged.

## Acceptance predicate

The helpers satisfy the complete spec edge table without overflowing intermediate arithmetic or performing an invalid floating conversion, `span()` has the Tick contract, and all existing callers compile. The temporary probe passes and leaves no lasting harness change. Named checks:

```sh
deno task verify --filter editcheck --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. This task does not rewrite TimeEditor bodies, mutations, grid behavior, or UI call sites. Do not treat a saturating helper as permission to delete a consumer's rejection preflight.
