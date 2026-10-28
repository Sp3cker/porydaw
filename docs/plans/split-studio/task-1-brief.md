# Task 1 — PorydawSample: zero-crossing snap, slice render, rate policy

## Context

First task of the Split Studio plan (`docs/plans/split-studio/`); adds the
sample-layer capabilities the studios build on. Consumers: task 8's source
session renders every slice through `SampleSlice.render`, snaps marker
positions with `SampleZeroCrossing.nearest` (Sample Studio's waveform gets
no snap toggle — see task 6), and picks each source's target rate with
`SampleRatePolicy`; task 6 rewires Sample Studio's rate computation onto the
same policy (R16 — one implementation, two callers). The zero-crossing
search is a bounded port of the deleted C++ `nearestZeroCrossing`
(`git show 5b8dcc9e^:src/audio/sampledsp.cpp` lines 144–162: alternating
outward search for a sign change between consecutive samples).

## Exact write set

- Create `src/swift/sample/SampleZeroCrossing.swift`
- Create `src/swift/sample/SampleSlice.swift`
- Create `src/swift/sample/SampleRatePolicy.swift`
- Edit `src/checks/samplecheck/RenderPipelineChecks.swift` (append rows to
  `runRenderPipelineChecks`)

Controller-owned (NOT in this write set): the three `src/swift/sample/
CMakeLists.txt` source lines.

## Prerequisites

None (first task). Tasks 6 and 8 consume this task's interface contract only.

## Interface contract

`spec.md → PorydawSample (task 1)` — exact signatures:
`SampleZeroCrossing.nearest(buffer:index:windowFrames:)` and
`SampleSlice.render(source:params:fadeIn:fadeOut:)`. Behavioral pins:

- `nearest`: a crossing sits between i−1 and i exactly when
  `(x[i-1] < 0 && x[i] >= 0) || (x[i-1] >= 0 && x[i] < 0)`; search distances
  d = 0, 1, 2, … alternate `index - d` then `index + d`; stop at the first
  crossing within `windowFrames`; return the clamped input index when the
  buffer has < 2 samples or no crossing is found. `index` is clamped to
  `0..<count` first. `windowFrames <= 0` returns the clamped index (snap
  disabled degenerates to identity).
- `render`: crop via `params.cropStart`/`cropEnd` on `source`, full existing
  `SampleRender.render` pipeline (resample, normalize per params), then bake
  half-cosine edge fades on the rendered output. Named contract (R24): the
  fade shape is identical to `SampleRender`'s `fadeIn`/`fadeOut` blocks
  (`SampleRender.swift:113-129`) — the same half-cosine weighting those
  loops apply — with fade-out applied tail-ward (first affected tail frame
  keeps ≈ its original value, last frame reaches exact 0) and fade-in the
  head-ward mirror. Length bound for both:
  `min(4 ms at the render's output rate, half the slice)`; only the length
  bound differs from `SampleRender`. Loop metadata from the render is
  preserved; callers pass `loopOn = false` (slices are one-shot) but the
  function does not force it.
- `SampleRatePolicy` (R16/F6): `rates` is the fixed GBA PCM table moved
  from `SampleStudioPresenter.swift:10`; `targetRate(gbaReady:
  sourceRate:)` returns the source rate when GBA-ready, else
  `ImportedSample.gbaDefaultRate` (13379 Hz); `rateOptions(sourceRate:)`
  returns the source rate first (when finite > 0), then `rates` — the
  option list both studios' rate controls bind. Pure; the single
  implementation of the decisions' rate rule.

## Implementation steps

1. Write `SampleZeroCrossing.swift`: one `public enum` with the single
   `nearest` static function over `Span<Float>`; no allocation.
2. Write `SampleSlice.swift`: one `public enum` with the single `render`
   static function. It calls `SampleRender.render(source:params:)` with the
   caller's params untouched, then applies the two fade loops on the rendered
   grid only when the respective flag is set and `fade > 0`. Never let a fade
   exceed half the slice. Do not re-implement resampling, normalization or
   clipping — those stay in `SampleRender`/`SampleDsp`.
3. Write `SampleRatePolicy.swift`: one `public enum` — `rates`,
   `targetRate`, `rateOptions` — per the contract, with the fixed table
   moved from `SampleStudioPresenter.swift:10`. No other rate logic is
   added anywhere in this plan (R16).
4. Append check rows to `runRenderPipelineChecks` (follow the file's existing
   fixture style; `cppID` label prefix `swiftcore/SampleSlice::` and
   `swiftcore/SampleZeroCrossing::`). Assert at least:
   - snap: exact crossing found on a synthetic sine's zero indices; tie
     (crossings both sides at equal distance) resolves to the lower index
     (outward order i−d before i+d); bound respected — a crossing farther
     than `windowFrames` is not taken and the clamped input index returns;
     index clamping at 0 and count−1; empty/1-sample buffer identity;
     `windowFrames = 0` identity; 3 ms at 13379 Hz and at 44100 Hz give the
     caller-computed frame counts 40 and 132
     (`Int((0.003 * rate).rounded())`: 40.137 → 40, 132.3 → 132; F2; the
     function itself is rate-free).
   - render: a mono source cropped to a known range renders byte-identical
     to `SampleRender.render` with identical params when both fades are off;
     fade-out leaves the length unchanged and ends at exact 0 with the first
     tail frame sign-preserved; fade-in off by default (default-args call has
     no fade-in); fade length is `min(4 ms, half)` for a slice shorter than
     8 ms (assert against a computed expected length); fadeIn+fadeOut
     combined on a mid-length slice; a silent region renders without NaN.
   - rate policy: gbaReady keeps the source rate; not gbaReady yields 13379
     for any source rate; `rateOptions` lists the source rate first (when
     finite > 0) then the 12 fixed rates (label
     `swiftcore/SampleRatePolicy::`).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter samplecheck-render`
  — runs `runRenderPipelineChecks` including the new rows. Covers: snap
  correctness/bounds/edge cases and slice render + declick bounds, and the
  untouched-pipeline path being byte-identical when fades are off.
- `uv run --no-sync dev checks --filter samplecheck-processing`
  — regression neighbor (the DSP-kernel suite shares `SampleDsp` inputs).
- `uv run --no-sync dev checks --filter samplecheck-editor`
  — regression: Sample Studio's presenter/waveform suites unaffected.

Runtime prerequisites: none beyond the worktree's synced state; the lane is
offscreen. Added rows are budgeted at 0.05 s (plan.md budget table).

## Task-specific constraints

- Deltas on Global Constraints: none. Do not edit `SampleRender.swift`,
  `SampleDsp.swift`, or any existing declaration — fades are applied to the
  render *output*; existing fade code is the shape reference only.
- No transient detection, no beat-grid logic, no marker management here —
  those live in tasks 6/8.
- `SampleSlice.render` stays pure (no I/O, no globals) so checks call it
  directly.

## Controller verification

1. Add the three source lines to `src/swift/sample/CMakeLists.txt`.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter samplecheck-render`
3. `uv run --no-sync dev checks --filter samplecheck-processing`
4. `uv run --no-sync dev checks --filter samplecheck-editor`
5. `uv run --no-sync dev format --check` on changed lines.
