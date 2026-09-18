# Spec — Swift backend Wave 1: view math

Agreed behavior, vocabulary, and frozen interfaces for the first Swift
backend epic. The production C++ sources named in §9 are normative; where
this spec and the source disagree, the source wins and this spec is a
defect. Everything here is decided — implementers make no design choices.

## 1. Purpose and recorded decisions

Port the pure view-math value types (Tick helpers, TimeMap/TimeAxis,
PitchProjection) to Swift so the later TimeCamera → Grid → PitchBendKernel
epics build on real math instead of throwaway lattices. Production C++
remains the oracle; nothing cuts over in this epic.

| # | Question | Decision |
| --- | --- | --- |
| D1 | Where Swift modules live | `src/ui/songview/quick/swift-grid-prototype/` top level — the existing `file(GLOB *.swift)` compile unit in the prototype CMake. No new build-system surface in this epic; the app-target move happens at production cutover, when a Swift host exists in the root build. New files: `Tick.swift`, `TimeAxis.swift`, `PitchProjection.swift`, `MathSelftest.swift`. |
| D2 | How Swift TimeAxis is fed | Copied value struct `TimeMap` (§3). No `MidiTimeline*` borrow, no C FFI peek into C++ objects. The only C boundary is the verification seam (§4) and, in a later epic, an `sgc_*`-style feed that copies fields across the same ABI. |
| D3 | How Wave 1 is verified | Two layers, both inside `deno task prototype:swift-grid --smoke`: (1) frozen oracle tables in Swift (§6) ported from production checks; (2) live dual-run parity — Swift queries `sgm_*` C functions that compute the same answer with production C++ `CoreTimeDefaults` / `songview::TimeAxis` / `songview::PitchProjection` (already compiled into the smoke via `swift_grid_curve`/`swift_grid_audio`). Swift drives; C++ never calls Swift, so the proven call direction (à la `sgc_*`, `installGridSmoke`) is reused and no linker risk is added. |
| D4 | `Tick` type | `typealias Tick = UInt32` with `kNoTick = UInt32.max`, `kMaxTick = kNoTick - 1`. Matches the C++ ABI and every existing seam cast (`Tick(start_tick)` in `curve_session.cpp`). `Int` would force conversions at every future boundary; rejected. |
| D5 | Task split | Three serial SDD tasks: seam + Tick, then TimeMap/TimeAxis, then PitchProjection. The orchestrator's "PitchProjection ∥ TimeAxis after Tick" is overridden: both would append to the same seam files, so parallelism would buy collisions, not time. One seam, grown serially, is the cohesive shape. |
| D6 | Epic boundary | Executable tasks stop at Wave 1. TimeCamera is out: its verification surface is the live `GridGeometry.swift`/QML prototype behavior, a different seam with its own design (this epic produces only the feed contract, §8). Grid, PitchBendKernel, MidiTimeline/SongDocument, audio are out per the orchestrator's rejections; no verification surface makes any of them one behavior with Wave 1. |

Rejected shapes (stay rejected): `TimeAxis` borrowing `MidiTimeline*`;
dual cameras (`GridGeometry` beside a Swift TimeCamera); fake 16th
SnapLattice for the kernel; parallel full ports of TimeCamera/Grid/TimeAxis.

## 2. Vocabulary

- **Tick** — canonical musical position; `UInt32` with the two sentinels
  (`kNoTick` absent-loop/parse bound, `kMaxTick` highest representable).
- **TimeMap** — the copied musical time a `TimeAxis` owns: timebase, known
  content length, loop markers, and the actual 0x58 signature events.
- **Unbound ≡ default TimeMap.** The C++ fallback axis (fresh tab,
  `setSong(nullptr)`) produces exactly the default `TimeMap`'s answers:
  24 TPB, implicit opening 4/4, `lengthTicks == 0`, `kNoTick` loops, no
  signatures. The Swift type therefore has no `isBound`; the later
  TimeCamera epic treats `lengthTicks == 0` as the unbound scroll case,
  which is already what the C++ camera outputs unbound.
- **GridSegment / ResolvedTimeSignature** — per-tick governing-signature
  shapes, identical semantics to `songview::TimeAxis` (§5).
- **Seam** — the C ABI in `src/checks/swiftgridprototype/math_smoke.h`:
  `sgm_*` oracle functions implemented in C++ over production types,
  imported by Swift through the `NativeGridSmoke` Clang module.
- **Oracle table** — a planner-frozen case/expected-value table (§6).
- **Parity** — running the same fixture through Swift and the `sgm_*`
  oracle and comparing every field.

## 3. Frozen Swift interfaces

Names mirror C++ (plan Global Constraints). All types are pure value types;
no Qt, no Foundation beyond what `MathSelftest.swift` needs.

```swift
// Tick.swift
typealias Tick = UInt32
let kNoTick: Tick = Tick.max
let kMaxTick: Tick = kNoTick - 1

/// Mathematical tick + delta saturated to [0, kMaxTick]; never emits kNoTick.
/// Headroom is classified before any arithmetic (spec §7).
func shiftTickClamped(_ tick: Tick, _ delta: Int64) -> Tick

/// Floating position to Tick: NaN and non-positive map to 0; values at or
/// above Double(kNoTick) (including +inf) saturate to kMaxTick; otherwise
/// truncate toward zero. The bounds check precedes the conversion (spec §7).
func tickFromDouble(_ tick: Double) -> Tick
```

```swift
// TimeAxis.swift
struct TimeSigPoint: Equatable {
    var tick: Tick
    var numerator: UInt8        // blank (0) reads as 4 via beatsPerBarFor
    var denomPow2: UInt8        // denominator = 1 << denomPow2
}

/// Copied musical time. Precondition (matching C++): timeSigs is tick-sorted
/// (non-decreasing); same-tick entries are legal and the last wins.
struct TimeMap: Equatable {
    var ticksPerBeat: UInt32 = 24
    var lengthTicks: Tick = 0
    var loopStartTick: Tick = kNoTick
    var loopEndTick: Tick = kNoTick
    var timeSigs: [TimeSigPoint] = []
}

struct GridSegment: Equatable {
    var start: Tick = 0                 // governing signature's tick
    var next: Tick = kNoTick            // next signature's tick
    var beatTicks: UInt32 = 24          // denominator-scaled beat length
    var beatsPerBar: UInt32 = 4
}

struct ResolvedTimeSignature: Equatable {
    var tick: Tick = 0
    var numerator: Int = 4
    var denomPow2: Int = 2              // RAW exponent, not clamped
    var implicit: Bool = true
}

struct TimeAxis: Equatable {
    let map: TimeMap
    init(map: TimeMap = TimeMap())      // default init = the fallback axis

    var ticksPerBeat: UInt32            // max(1, map.ticksPerBeat)
    var lengthTicks: Tick               // map value (0 unbound)
    var loopStartTick: Tick             // kNoTick when absent
    var loopEndTick: Tick               // kNoTick when absent
    var explicitTimeSignatures: [TimeSigPoint]  // actual events only, in order

    var hasImplicitOpeningSignature: Bool  // no event governs tick zero
    func signatureAt(_ tick: Tick) -> ResolvedTimeSignature
    func segmentAt(_ tick: Tick) -> GridSegment
    /// Bar/beat lines over [tickBegin, tickEnd): 1-based, bars counted
    /// across signature changes including partial measures.
    func forEachGridLine(from tickBegin: Tick, to tickEnd: Tick,
                         _ visitor: (Tick, _ isBar: Bool, _ bar: Int, _ beat: Int) -> Void)
}
```

```swift
// PitchProjection.swift
struct PitchProjection: Equatable {
    static let cMaxRows = 128
    static let cHiddenRow = -1

    init()                              // = buildChromatic()
    mutating func buildChromatic()      // 0–127, all rows scale rows
    /// Precondition: sorted strictly ascending, unique, ≤ 128, each < 128.
    mutating func buildFromPitches(_ pitches: [UInt8])

    var visibleRowCount: Int
    func visiblePitch(at row: Int) -> Int      // row 0 = highest pitch; precondition row in range
    func row(forPitch midiPitch: Int) -> Int   // cHiddenRow when hidden/out of 0–127
    mutating func setScalePitchClassification(_ isScalePitch: [Bool]) // indexed BY PITCH, count 128
    func isScalePitch(row: Int) -> Bool        // precondition row in range
    func nearestVisiblePitch(to midiPitch: Int) -> Int // tie → lower pitch; empty → cHiddenRow
    func totalHeight(keyHeight: Double) -> Double     // visibleRowCount * keyHeight

    func rowTop(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double
    func rowBottom(_ row: Int, keyHeight: Double, scrollY: Double, dpr: Double) -> Double
    func yToRow(_ y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int
    func yToPitch(_ y: Double, keyHeight: Double, scrollY: Double, dpr: Double) -> Int
}
```

Deliberately deferred (§8): `rowRect`, `buildRowEdges`, `revision()`,
`isBound`, `bind`.

## 4. Frozen seam ABI — `src/checks/swiftgridprototype/math_smoke.h`

Plain C, `extern "C"`, imported by Swift via the `NativeGridSmoke` module
(the module map gains `header "math_smoke.h"`). Declared incrementally:
Task 1 declares only the tick pair; Tasks 2–3 append their groups.

```c
#include <stddef.h>
#include <stdint.h>

typedef struct SGSigPoint {          // fixture mirror of TimeSigPoint
    uint32_t tick;
    uint8_t numerator;
    uint8_t denomPow2;
} SGSigPoint;

typedef struct SGTimeMapFixture {    // fixture mirror of TimeMap
    uint32_t ticksPerBeat;
    uint32_t lengthTicks;
    uint32_t loopStartTick;
    uint32_t loopEndTick;
    const SGSigPoint *timeSigs;      // tick-sorted; may be NULL when count == 0
    size_t timeSigCount;
} SGTimeMapFixture;

typedef struct SGTimeAxisAnswer {    // every scalar query in one struct
    uint32_t ticksPerBeat, lengthTicks, loopStartTick, loopEndTick;
    uint32_t segStart, segNext, segBeatTicks, segBeatsPerBar; // segmentAt(tick)
    int32_t sigNumerator, sigDenomPow2, sigImplicit;          // signatureAt(tick); implicit 0/1
} SGTimeAxisAnswer;

typedef struct SGGridLine {
    uint32_t tick;
    uint8_t isBar;
    int32_t bar;
    int32_t beat;
} SGGridLine;

/* Task 1 */ uint32_t sgm_shift_tick_clamped(uint32_t tick, int64_t delta);
/* Task 1 */ uint32_t sgm_tick_from_double(double tick);
/* Task 2 */ void sgm_timeaxis_answer(const SGTimeMapFixture *map, uint32_t tick,
                                      SGTimeAxisAnswer *out);
/* Task 2 */ size_t sgm_timeaxis_grid_lines(const SGTimeMapFixture *map, uint32_t begin,
                                            uint32_t end, SGGridLine *out, size_t capacity);
/* Task 3 */ int32_t sgm_pitch_row_for_pitch(const uint8_t *pitches, size_t count, int32_t pitch);
/* Task 3 */ int32_t sgm_pitch_nearest_visible(const uint8_t *pitches, size_t count, int32_t pitch);
/* Task 3 */ double sgm_pitch_row_top(const uint8_t *pitches, size_t count, int32_t row,
                                      double keyHeight, double scrollY, double dpr);
/* Task 3 */ int32_t sgm_pitch_y_to_pitch(const uint8_t *pitches, size_t count, double y,
                                          double keyHeight, double scrollY, double dpr);
```

Semantics: `pitches == NULL` (count 0) selects the chromatic build;
otherwise `buildFromPitches` over the ascending list. `sgm_*` implement
with production C++ types (`CoreTimeDefaults::`, `songview::TimeAxis`
bound to a stack `MidiTimeline` filled field-by-field from the fixture,
`songview::PitchProjection`) and convert results. `sgm_timeaxis_grid_lines`
follows the `sgc_copy_curve_points` convention: writes at most `capacity`
entries and returns the full needed count; the Swift caller passes its own
count as capacity and treats `returned != swiftCount` as a failure.

Swift selftest driver (Task 1 creates, Tasks 2–3 append):

```swift
// MathSelftest.swift — imported by App.swift's module; no Qt
func runMathSelftestIfRequested()  // no-op unless PORYDAW_SWIFT_GRID_SMOKE == "1"
```

Output convention (matches the C++ smoke's `fail`/`pass` style):
each passing group prints `SWIFT_GRID_SMOKE math-<group> PASS`; any
mismatch prints `SWIFT_GRID_SMOKE math-<group> FAIL: <case>` to stderr and
exits nonzero. `App.swift` calls `runMathSelftestIfRequested()` in `init()`
**before** `installGridSmoke()` (fail fast, before any window). The final
`SWIFT_GRID_SMOKE PASS` line still comes from the existing C++
`exercise()`; the Deno matcher needs exit 0 plus that line.

## 5. Contract notes (normative)

TimeAxis — every rule is the C++ behavior on a copied map:

- `ticksPerBeat` = `max(1, map.ticksPerBeat)`; the fallback axis is 24.
- Blank numerator (0) reads as 4 in `signatureAt`, `segmentAt`, and
  `forEachGridLine` (`beatsPerBarFor`).
- `beatTicksFor(tpb, denomPow2) = max(1, (UInt64(tpb) * 4) >> min(Int(denomPow2), 31))`
  — the shift clamp keeps every beat length a valid stride; `denomPow2`
  raw up to 255 is legal input.
- `signatureAt` keeps the RAW `denomPow2` exponent (even 255) and marks
  `implicit == false` for every actual event; the implicit opening 4/4
  (`tick 0, numerator 4, denomPow2 2, implicit true`) governs only when no
  event at-or-before the tick exists.
- Last same-tick signature wins everywhere (the maps are tick-sorted, so a
  simple overwrite loop with a `ts.tick > tick` break is exact).
- `segmentAt(t).next` is the first signature strictly after the governing
  one; unbound/fallback yields `(0, kNoTick, ticksPerBeat, 4)`.
- `hasImplicitOpeningSignature` = no signatures, or first signature tick
  != 0.
- `forEachGridLine(from:to:)`:
  - empty range when `to <= from`; the range is half-open `[from, to)`;
  - the opening segment consumes every tick-0 signature (last wins);
  - the first emitted line of a segment starts at
    `from + k * beatTicks` when `from > seg.start` (skip below-range beats
    without visiting);
  - `isBar` = beat index % beatsPerBar == 0; bar numbers are 1-based and
    carry across segments by `bar += ceil(segTicks / barTicks)` — partial
    measures count, so mid-measure signature changes do not renumber bars;
  - all stride math in `UInt64` (beatTicks ≥ 1 always, so division and
    ceil are safe); loop advance guard is `beatTicks >= clampedEnd - tick`.

PitchProjection:

- Row 0 is the TOP row = HIGHEST pitch; chromatic build fills rows 0…127
  with pitches 127…0 and marks every row a scale row; `buildFromPitches`
  reverses the ascending input the same way and marks exactly the visible
  rows as scale rows.
- `row(forPitch:)` returns `cHiddenRow` for pitches outside 0–127 and for
  hidden pitches; `visiblePitch(at:)` / `isScalePitch(row:)` take row
  indices (Swift `precondition` on range — release-crash parity with the
  C++ asserts is intended).
- `nearestVisiblePitch`: lower pitch wins ties (`|q - lower| <= |higher - q|`);
  below range → lowest visible; above range → highest visible; empty
  build → `cHiddenRow`.
- `setScalePitchClassification` is indexed BY PITCH (`isScalePitch[pitch]`),
  not by row — mirror the C++ `m_scalePitchRow[row] = isScalePitch[m_visiblePitches[row]]`.
- DPR-snapped edge: `snappedRowEdge(row) = round((row * keyHeight - scrollY) * scale) / scale`
  with `scale = dpr > 0 ? dpr : 1`; rounding is half **away from zero**
  (Swift `.rounded(.toNearestOrAwayFromZero)` — NOT `.toNearestOrEven`).
  `rowTop(row)` = edge(row); `rowBottom(row)` = edge(row + 1).
- `yToRow`: `y < rowTop(0)` or `y >= rowBottom(count - 1)` → `cHiddenRow`;
  rows are half-open `[top, bottom)`; binary search over snapped edges.
  `yToPitch` = `visiblePitch(at: yToRow(...))` or `cHiddenRow`. Row 0 is
  checked against the top edge inclusively (y == rowTop(0) is row 0).

## 6. Oracle tables (frozen expected values)

Swift-side assertions use these literals; the parity driver passes the same
fixtures to the `sgm_*` oracles. Provenance in brackets.

### T1 — Tick helpers

`shiftTickClamped(tick, delta) → expected`:

| tick | delta | expected |
| --- | --- | --- |
| 0 | 0 | 0 |
| 100 | 28 | 128 |
| 100 | −100 | 0 |
| 100 | −1000 | 0 |
| 50 | −49 | 1 |
| 50 | −51 | 0 |
| 0 | Int64.min | 0 |
| kMaxTick | 0 | kMaxTick |
| kMaxTick | 1 | kMaxTick |
| kMaxTick | Int64.max | kMaxTick |
| kNoTick | 5 | kMaxTick (never emits kNoTick) |

`tickFromDouble(x) → expected`:

| x | expected |
| --- | --- |
| NaN | 0 |
| −1.5 | 0 |
| 0.0 | 0 |
| 0.9 | 0 |
| 127.9 | 127 |
| Double(kMaxTick) | kMaxTick |
| Double(kNoTick) | kMaxTick |
| .infinity | kMaxTick |

### T2 — TimeAxis fixtures (map + queries)

Notation: map `(tpb, len, loopS, loopE, sigs)`; sigs as `(tick, num, pow2)`.

**F0 fallback** — default `TimeAxis()` (and default `TimeMap()`):
ticksPerBeat 24, length 0, loops kNoTick/kNoTick; `hasImplicitOpeningSignature` true;
`signatureAt(0)` and `signatureAt(kMaxTick)` = (0, 4, 2, implicit);
`segmentAt(0)` and `segmentAt(4_000_000_000)` = (0, kNoTick, 24, 4).

**F0b fallback grid walk** [rollcheck-static `fallbackGrid`]:
`forEachGridLine(0, 384)` on F0 emits exactly 16 lines,
line i = `(24·i, i % 4 == 0, i/4 + 1, i % 4 + 1)` for i in 0…15.

**F1 zero timebase** — map `(0, 0, kNoTick, kNoTick, [])`:
ticksPerBeat 1; `segmentAt(0)` = (0, kNoTick, 1, 4);
`forEachGridLine(0, 4)` = (0,T,1,1) (1,F,1,2) (2,F,1,3) (3,F,1,4).

**F2 mid-song 3/4 over implicit 4/4, partial-measure carry** — map
`(24, 0, kNoTick, kNoTick, [(0,4,2), (60,3,2)])`:
- `segmentAt(0)` = (0, 60, 24, 4); `segmentAt(59)` = same; `segmentAt(60)` =
  (60, kNoTick, 24, 3); `segmentAt(95).next` = 60.
- `hasImplicitOpeningSignature` false.
- `signatureAt(10)` = (0, 4, 2, false); `signatureAt(100)` = (60, 3, 2, false).
- `forEachGridLine(0, 200)` emits, in order:
  (0,T,1,1) (24,F,1,2) (48,F,1,3) (60,T,2,1) (84,F,2,2) (108,F,2,3)
  (132,T,3,1) (156,F,3,2) (180,F,3,3).
- `forEachGridLine(25, 200)` = the same list minus the first two lines
  (first line (48,F,1,3)) — below-range beats skipped without visits.
- `forEachGridLine(0, 60)` = (0,T,1,1) (24,F,1,2) (48,F,1,3) — half-open end.
- `forEachGridLine(96, 96)` and `forEachGridLine(200, 100)` emit nothing.

**F3 last same-tick wins** — map `(24, 0, kNoTick, kNoTick, [(0,3,2),(0,7,3),(0,2,4)])`:
`segmentAt(0)` = (0, kNoTick, 12, 7); `signatureAt(0)` = (0, 7, 3, false);
`forEachGridLine(0, 12)` = (0,T,1,1) only.
Mid-song duplicates — map `(24, 0, kNoTick, kNoTick, [(0,4,2),(96,4,2),(96,3,2)])`:
`segmentAt(96)` = (96, kNoTick, 24, 3); `segmentAt(95)` = (0, 96, 24, 4).

**F4 blank numerator** — map `(24, 0, kNoTick, kNoTick, [(0,0,2)])`:
`signatureAt(5)` = (0, 4, 2, false); `segmentAt(5)` = (0, kNoTick, 24, 4).

**F5 denominator clamp** — tpb 24, single tick-0 sig:
- (0,4,31): `segmentAt(0).beatTicks` = 1 (`(24·4) >> 31` = 0 → floor 1).
- (0,4,0): beatTicks = 96.
- (0,4,255): beatTicks = 1 (shift clamped to 31) while
  `signatureAt(0).denomPow2` = 255 (raw exponent preserved).

**F6 7/8 acceptance** [rollcheck `time_signature_prompt`]:
map `(48, 0, kNoTick, kNoTick, [(0,4,2),(96,7,3)])`:
`segmentAt(96)` = (96, kNoTick, 24, 7) — beatTicks == ticksPerBeat/2,
beatsPerBar == 7.

**F7 loops and length passthrough** — map
`(24, 384, 48, 192, [])`: lengthTicks 384, loopStartTick 48, loopEndTick 192;
absent loops (F0) stay kNoTick.

**F8 odd mid-measure seam** [view-buckets-grid `clockLatticeCrossesSignatureSeam`]:
map `(48, 0, kNoTick, kNoTick, [(0,4,2),(37,5,3)])`:
`segmentAt(36)` = (0, 37, 48, 4); `segmentAt(37)` = (37, kNoTick, 24, 5);
`forEachGridLine(30, 44)` emits exactly one line, (37,T,2,1) — the implicit
48-tick beat lattice has no line in [30, 37), and bar 1's partial measure
(rounded up from 37/96) carries into the seam.

### T3 — PitchProjection

**Chromatic** (default init):
- visibleRowCount 128; `visiblePitch(at: 0)` = 127, `visiblePitch(at: 127)` = 0;
  `row(forPitch: 127)` = 0, `row(forPitch: 0)` = 127, `row(forPitch: 60)` = 67.
- `row(forPitch: −1)` = cHiddenRow; `row(forPitch: 128)` = cHiddenRow.
- `nearestVisiblePitch(to: x)` = x for x ∈ {0, 60, 127}.
- All rows scale rows; `totalHeight(keyHeight: 13)` = 1664.

**Folded [60, 64, 67]**:
- rowCount 3; `visiblePitch(at: 0)` = 67; `visiblePitch(at: 2)` = 60.
- `row(forPitch:)`: 60→2, 64→1, 67→0, 61→cHiddenRow.
- `nearestVisiblePitch(to: 62)` = 60 (tie 2v2, lower wins);
  `to: 65` = 64 (1v2); `to: 59` = 60 (below → lowest visible);
  `to: 68` = 67 (above → highest visible).
- After build every visible row is a scale row; then
  `setScalePitchClassification` with 128 entries where only pitch 64 is
  true → `isScalePitch(row: 0)` false (pitch 67), `row: 1` true,
  `row: 2` false — pins the by-pitch indexing.

**Empty fold** `buildFromPitches([])`: rowCount 0;
`nearestVisiblePitch(to: 60)` = cHiddenRow; `yToPitch(any)` = cHiddenRow.

**DPR-snapped edges** (chromatic unless noted):
- keyHeight 13, scrollY 0, dpr 1: rowTop(0) = 0, rowBottom(0) = 13;
  `yToPitch(12.9)` = 127; `yToPitch(13.0)` = 126 (half-open rows).
- keyHeight 13, scrollY 6.5, dpr 2: rowTop(0) = −6.5; rowBottom(0) = 6.5;
  `yToPitch(−6.5)` = 127 (top edge inclusive); `yToPitch(−6.51)` = cHiddenRow;
  `yToPitch(6.49)` = 127; `yToPitch(6.5)` = 126.
- keyHeight 1.25, scrollY 0, dpr 2: rowTop(1) = 1.5
  ((1.25 · 2) = 2.5 rounds half-away-from-zero to 3 → 1.5; a
  to-nearest-or-even port would produce 1.0 and must fail).
- keyHeight 13, scrollY 0, dpr 0: rowTop(5) = 65 (dpr ≤ 0 → scale 1).

### T4 — Parity sweeps (fixture × query grid against `sgm_*`)

- Tick: every T1 row through `sgm_shift_tick_clamped` / `sgm_tick_from_double`.
- TimeAxis: F0–F8 through `sgm_timeaxis_answer` at ticks
  {0, 1, 24, 36, 37, 48, 59, 60, 95, 96, 100, 384, 1_000_000, kMaxTick};
  `sgm_timeaxis_grid_lines` element-wise for the five F2/F0b/F8 walks plus
  F0 `(0, 5000)`, F1 `(0, 4)`, F3 `(0, 12)`, F5 `(0, 200)` at (0,4,31),
  and `(kMaxTick − 5, kMaxTick)` on map `(1, kMaxTick, kNoTick, kNoTick, [])`.
- Pitch: chromatic full sweeps `row(forPitch:)` 0…127 and
  `nearestVisiblePitch(to:)` −2…129; folded [60,64,67], [0,127], and [69]
  over the same nearest sweep plus `row(forPitch:)` at every pitch;
  `sgm_pitch_y_to_pitch` / `sgm_pitch_row_top` over keyHeight
  {13, 1.25, 7} × scrollY {0, 6.5, 100.75} × dpr {1, 2, 1.5, 3, 0} at rows
  {0, 1, 5, 127} and y offsets {top, top + ε, bottom − ε} for row 0 and the
  last row (chromatic and folded [60,64,67]).

A sweep mismatch names the fixture, query, Swift value, and C++ value in
the FAIL line.

## 7. Swift trap-avoidance rules (normative)

- `shiftTickClamped`: classify before arithmetic —
  `if delta <= -Int64(tick) { return 0 }` (safe: tick ≥ 0 ≤ kMaxTick, so
  negation cannot overflow), then
  `if delta >= Int64(kMaxTick) - Int64(tick) { return kMaxTick }`
  (subtraction of small non-negatives cannot overflow), then add. Never
  negate `Int64.min`; never add before classifying.
- `tickFromDouble`: `if !(x > 0) { return 0 }`; `if x >= Double(kNoTick)
  { return kMaxTick }`; only then `Tick(x)` — Swift traps on out-of-range
  Double→UInt32 conversion, so the guard order is load-bearing.
- `beatTicksFor`: widen `tpb` to `UInt64`, multiply by 4, clamp the shift
  to `min(Int(denomPow2), 31)` BEFORE shifting, floor at 1.
- `forEachGridLine` stride math (k, segTicks, barTicks, tick advance) in
  `UInt64`; narrow to `Tick`/`Int` only where §5 proves the value in range.
- Edge snapping: `((row * keyHeight - scrollY) * scale).rounded(.toNearestOrAwayFromZero) / scale`.

## 8. Deferred interfaces (forward contracts, not this epic)

- **TimeCamera feed (next epic):** the C seam copies `TimeMap` fields from
  `MidiTimeline` exactly like `SGTimeMapFixture`; camera clamps treat
  `lengthTicks == 0` as unbound (identical to C++ outputs today).
  `GridGeometry.swift` stays the live prototype camera until then.
- **Paint-seam composites:** `rowRect` (Qt geometry), `buildRowEdges`
  (buffer fill), and `revision()` (cache invalidation — replaced by
  `Equatable` on the value type) return at production cutover, where their
  consumers (painters, view caches) convert. Their math is already pinned
  by `rowTop`/`rowBottom` parity.
- **Grid / PitchBendKernel / MidiTimeline / SongDocument / audio:** not in
  this epic; consume TimeAxis/PitchProjection through the value interfaces
  above.

## 9. Normative sources

| File | Role |
| --- | --- |
| `src/core/timedefaults.h` | Tick helpers oracle |
| `src/core/miditimeline.h` | TimeSigPoint + viewer-field defaults |
| `src/ui/songview/timeaxis.h` / `.cpp` | TimeAxis oracle (fallback, last-wins, beatTicksFor, grid walk) |
| `src/ui/pitchprojection.h` / `.cpp` | PitchProjection oracle (snappedRowEdge, searches) |
| `src/checks/swiftgridprototype/grid_smoke.{h,cpp}` | seam pattern + smoke entry |
| `src/checks/rollcheck/static/geometry.cpp` (`fallbackGrid`) | F0b provenance |
| `src/checks/rollcheck/time_signature_prompt.cpp` (7/8 accept) | F6 provenance |
| `src/checks/eventviews/viewbuckets_grid.cpp` (`clockLatticeCrossesSignatureSeam`) | F8 provenance |
