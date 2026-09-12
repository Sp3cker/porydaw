# Tick cast helpers and arithmetic boundaries

## Goal and scope

Stored musical positions use `Tick`; internal APIs pass them without gratuitous conversions. Different numeric domains stay different. This sequel fixes the arithmetic exposed by narrowing, not just the spelling of casts. Task ownership is in [plan.md](plan.md); exact source inventories live only in the owning briefs.

`kNoTick` is reserved and must not be emitted as a musical event position. `kMaxTick` is the highest valid position. A computed mathematical note end may exceed it and therefore remains `uint64_t`; a persisted note-off may not.

## Numeric interfaces

### Saturating signed shift

```cpp
constexpr Tick CoreTimeDefaults::shiftTickClamped(Tick tick, int64_t delta)
```

Return the mathematical sum of `tick` and `delta`, saturated to `[0, kMaxTick]`. This contract covers the full representable input types, including `INT64_MIN`, `INT64_MAX`, and a sentinel-valued `tick`; the result is never `kNoTick`.

Classify the delta against lower/upper headroom before addition. Neither overflowing `int64_t(tick) + delta` nor negating `INT64_MIN` is permitted. Adding first and then calling `std::clamp` does not implement the contract.

| Inputs | Result |
| --- | --- |
| `0, -1` | `0` |
| `8, -3` | `5` |
| `kMaxTick - 1, 1` | `kMaxTick` |
| `kMaxTick, 1` | `kMaxTick` |
| `1, INT64_MAX` | `kMaxTick`, without signed overflow |
| `kMaxTick, INT64_MIN` | `0`, without negating the delta |
| `kNoTick, 0` | `kMaxTick` |
| `kNoTick, -1` | `kMaxTick` |

This is a saturating scalar operation, not admission control for an edit transaction. Document callers must reject an invalid upper-bound edit before invoking it; they must not turn rejection into a shortened note, collapsed selection, or partially applied batch.

### Floating position conversion

```cpp
inline Tick CoreTimeDefaults::tickFromDouble(double tick)
```

| Input | Result |
| --- | --- |
| NaN, negative finite values, negative infinity | `0` |
| Finite value in `[0, double(kNoTick))` | Truncate toward zero |
| `double(kNoTick)` or greater, positive infinity | `kMaxTick` |

No out-of-range floating-to-integer conversion may execute. `nextafter(double(kNoTick), 0.0)` converts to `kMaxTick`, not the sentinel.

Rounding remains at each caller: floor for lower coverage/clock quantization, ceil for upper coverage, round or `+ 0.5` for nearest context positions, and no added rounding for truncating hover positions. Remove an inner zero clamp only if it exists solely to make the conversion nonnegative. Preserve enclosing boundary ternaries and selection-specific bounds.

The helper is not a fractional snap-input clamp: nearest-grid tie comparisons still need the original fraction.

### Time range span

```cpp
Tick SongDocument::TimeRange::span() const
```

Return zero for an empty/reversed range, otherwise `endTick - startTick`. An ordered difference of two `Tick` values fits in `Tick`. Do not change `empty`, `contains`, `overlaps`, or the layout of `TimeRange`.

`span()` does not validate sentinel-valued endpoints. TimeEditor entry points reject such ranges before subtracting the span from `kMaxTick`.

## TimeEditor behavior

Use `Tick` for endpoint/span locals and values read directly from stored events. Use the shift helper for already-preflighted source-plus/minus-span mappings. Preserve the existing clipping of notes to a selected range; do not narrow a genuinely unbounded `start + duration` sum to achieve a zero-cast count.

Insert and duplicate retain whole-transaction upper-headroom checks before planning removals, tempo changes, or track-end movement. Remove retains its seam/default behavior. Reject a range containing a `kNoTick` endpoint before arithmetic; do not preserve the old unsigned underflow in `kMaxTick - span` for invalid ranges. A legal shift ending exactly at `kMaxTick` succeeds; a shift producing the sentinel or beyond returns false without mutation.

## Note and range mutation policy

These requirements cover the named add, move, right-resize, and range-edit paths in Tasks 3–4, not an unbounded audit of every public raw-event setter.

- Normalize inserted zero durations to the existing one-tick minimum before checking the end.
- Calculate note ends by widening an operand before addition. Returning `uint64_t` or assigning to a wide local does not widen a 32-bit addition retroactively.
- An inserted or rewritten terminated note must have its stored start and end at or below `kMaxTick`. Check end headroom before writing. A one-tick note beginning at `kMaxTick` is invalid; a note ending exactly there is valid.
- Preserve existing lower-zero-clamp behavior of note/range shifts. Reject a requested upper overflow rather than saturating stored note positions or changing the requested duration. For right resize, preserve the one-tick lower duration limit and reject an upper overflow; evaluate even extreme signed duration deltas without signed overflow or premature `uint32_t` narrowing.
- Preflight the entire eligible batch before overlap planning, track expansion, history push, or mutation publication. One invalid upper destination rejects every member, including simultaneous pitch changes, lane points, tempo moves, and removals. Existing invalid-track and unterminated-note participation rules remain unchanged.
- Void APIs reject by returning without mutation. `moveNotesToPitches` returns false on an invalid upper destination. No public signatures or new UI error channels are introduced.
- Move command identity comparisons and builders use the same shifted-position policy. If accumulated deltas cannot be represented safely, decline undo-command merging before rewinding either command; keep the valid commands separate. Do not overflow `m_dTick` while merging.
- Keep `resizeNotesLeft` and its variable-upper-bound clamps unchanged. Its computed end is not a `Tick` maximum, and it must not be routed through the scalar saturating helper. Likewise leave the corresponding geometry clamps unchanged. This plan does not claim to harden those separate variable-bound operations against arbitrary malformed inputs.

Concrete regressions: start `4294967284`, duration `20` must not produce an end at `8`; start `4294967293`, duration `2` must not write reserved `4294967295`. `noteEndTick` must report the wide mathematical end for a synthetic terminated `DocNote` even when that end is not persistable.

## Grid boundary behavior

### Snapping

Keep the current signatures, fractional nearest-tie rule, time-signature segment resets, and ordinary lattice results. Clamp raw input to `[0, double(kMaxTick)]` without truncating its fractional part; NaN maps to zero, and infinities clamp to the corresponding endpoint.

Compute the coarse upper candidate as the mathematical minimum of `lo + g`, the next real segment boundary, and `kMaxTick`, without evaluating a wrapping 32-bit addition. At the final domain edge, `kMaxTick` is the saturating terminal candidate even when it is not on the grid. Down-snap remains the greatest lattice candidate at or below the clamped input; up-snap reaches the terminal candidate rather than wrapping. Nearest chooses between the bounded candidates using its unchanged fractional tie rule. The fine branch passes its rounded result through `tickFromDouble`.

Clamping only the raw input is insufficient: `lo = 4294967280`, `g = 24` must yield terminal upper candidate `4294967294`, never `8` or `kNoTick`.

### Subgrid iteration

Keep half-open range semantics, callback order, and beat-line omission. Prove the first ceiling-aligned candidate is inside the segment/range before narrowing or adding it to the segment start; skip a segment whose first candidate lies at or beyond its end. Guarding only the increment leaves the initial ceiling calculation vulnerable.

Every advancement uses the existing TimeAxis break-before-increment pattern. A beat line skips the callback, not the advancement guard: the old `continue` must not bypass the guard/increment after the loop's increment clause is removed. Do not replace this with a wide running stride and per-callback narrowing. Bounded one-time arithmetic for the first candidate is allowed.

## UI movement behavior

A rejected note nudge must not scroll to a fabricated destination. Determine whether the document actually changed using its existing revision before publishing reveal feedback; keep the normal mergeable nudge and refresh behavior. Derive display bounds without narrowing a wide note end before the display-domain ceiling is applied.

A node group drag applies one common tick delta. Extend its existing earliest-point lower limit with latest-point upper headroom; clamp the common delta once, then shift every original point through `shiftTickClamped`. Do not clamp points individually into the same tick at the upper edge. Preview, finish delta, and committed point destinations must agree; retain value limits and collision rules.

## Non-goals

Do not widen stored positions back to 64 bits, add a strong Tick class, unify samples/identities/durations/fractional coordinates into Tick, alter SMF wire encoding, remove parser/rescale preflights, or perform an unrelated repository-wide cast purge. Necessary computed-end casts, resize-left bounds, width-floor probes, and double-to-double snap arguments remain. `smf.cpp` identity-cast cleanup and unrelated cast sites outside the closed write sets are intentionally excluded.
