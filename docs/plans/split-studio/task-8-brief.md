# Task 8 — `KitSourceSession`: sources, markers, slices, minting, rates

## Context

Eighth task of the Split Studio plan; split from the former task 8 at its
interface seam (R17) — the source/slicing state machine is independently
verifiable and has its own check rows in the `kitstudio-draft` lane.
Consumer: task 9's presenter drives every session method and publishes its
rows; task 10's save pipeline renders pending slices through it. Producers
consumed: task 1 (`SampleZeroCrossing.nearest`, `SampleSlice.render`,
`SampleRatePolicy`), task 5 (`PorydawSampleUI` module), task 6
(`MarkerWaveformModel` — the session feeds marker frames to it via the
presenter), task 7 (module + draft types for zone-name queries via the
presenter boundary only). Decisions carried: multiple sources per session
with per-source markers/slices/rate (§13), marker interactions (§14), snap
default ON bounded 3 ms (§15), declick defaults + per-slice overrides
(§16), `<source>_NN` minting + rename validation (§17, via the R20 adapter
injected by task 10).

## Exact write set

- Create `src/swift/kitstudio/KitSourceSession.swift`
- Edit `src/checks/kitstudio/KitDraftChecks.swift` (append
  `runKitSourceSessionChecks` into `runKitDraftSuite`'s lane runner)

Controller-owned: module source line, no new lane (rows join
`kitstudio-draft`).

## Prerequisites

Tasks 1, 5, 6, 7 (interfaces only).

## Interface contract

`spec.md → PorydawKitStudio (task 8)` — the `KitSourceSession` surface
(`Slice` struct, `addSource`, `setMarker(source:frame:snap:)`,
`removeMarker(source:frame:)`, `renderSlice(source:slice:)`,
`validateName` closure, `mintSliceName(source:)`,
`renameSlice(source:slice:to:)`, `canClose(source:usedNames:)`). Pinned
behavior:

- Sources are identified by a monotonic session-local id; each carries its
  `ImportedSample`, ordered marker list, slices (bounded by adjacent
  markers), and per-slice fade overrides (`fadeOut` default true,
  `fadeIn` default false).
- `setMarker(..., snap: true)` snaps the frame with
  `SampleZeroCrossing.nearest(buffer:index:windowFrames:)` where
  `windowFrames = Int((0.003 * sampleRate).rounded())` — 40 frames at
  13379 Hz, 132 at 44100 Hz (the 3 ms bound, §15; F2).
- `renderSlice` calls `SampleSlice.render(source:params:fadeIn:fadeOut:)`
  with crop = the slice's marker bounds and the source's target rate from
  `SampleRatePolicy.targetRate(gbaReady:sourceRate:)` (R16 — no local rate
  logic). Renders are pure; the session does no disk I/O.
- `mintSliceName(source:)` returns the first free `<sanitizedSource>_NN`
  (two digits, 00–99; sanitize via `SampleNames.sanitize`). `renameSlice`
  accepts only a nil refusal from `validateName`; on refusal the old name
  stands and the call returns false.
- `canClose(source:usedNames:)` is true iff no slice of the source has a
  name in `usedNames` (the caller passes the union of zone sample names).
- The session performs no engine, project, or file calls; `validateName`
  is the only outward seam.

## Implementation steps

1. Write `KitSourceSession` per the contract: one file, value-ish state on
   `@MainActor`, no bridged members (the presenter publishes rows).
2. Append `runKitSourceSessionChecks` rows (labels
   `swiftcore/KitSourceSession::`): marker add/move/remove ordering; snap
   on/off behavior incl. the exact window-frame counts above; slice
   creation from marker pairs and selection bounds; minting sequence
   (`src_00`, `src_01`, first-free after delete); rename refused by the
   injected validator keeps the old name; renderSlice output matches a
   direct `SampleSlice.render` call for the same bounds/overrides (byte
   equality over `s8`); rate selection via `SampleRatePolicy` for gbaReady
   and non-gbaReady sources; `canClose` gating. Keep rows ≤ 0.10 s
   (plan.md budget).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks --filter kitstudio-draft`
  — the lane now also runs the source-session rows. Covers: marker/slice
  state machine, snap bounds, minting/uniqueness/rename gating, render
  equivalence, rate policy use, closability.
- `uv run --no-sync dev checks --filter samplecheck-render`
  — regression: `SampleSlice`/`SampleZeroCrossing` rows from task 1 stay
  green (the session is a pure consumer).

Runtime prerequisites: none; offscreen. Added rows budgeted at 0.10 s
(plan.md budget table).

## Task-specific constraints

- No presenter, no QML, no workflow types; the session is driver-logic the
  presenter owns views for.
- No local rate computation and no local zero-crossing search — both call
  task 1's functions (R16/R24 spirit: one implementation).
- Renders are computed on demand; the session keeps no PCM caches beyond
  the source buffers (render caching is task 10's workflow concern if
  needed for save; do not add one here).

## Controller verification

1. Add the source line to `src/swift/kitstudio/CMakeLists.txt`.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks --filter kitstudio-draft`
3. `uv run --no-sync dev checks --filter samplecheck-render`
4. `uv run --no-sync dev format --check` on changed lines.
