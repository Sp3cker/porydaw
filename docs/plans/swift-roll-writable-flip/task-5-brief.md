# Task 5 — TrackHeaders Swift presenter

## Context

The second consumer: `PORYDAW_SWIFT_HEADERS` swaps the C++
`TrackHeaderModel` presenter for a Swift presenter behind the unchanged
`TrackHeaderBand.qml`. Proves `sgc_`/`sgs_` generalize past the grid.
Surface mirror FIXED against `trackheadermodel.h`; behavior FIXED in
[spec.md §5](spec.md).

## Exact write set

- `src/ui/songview/trackheaderswift.{h,cpp}` (new) — presenter shell:
  the Q_PROPERTY surface `TrackHeaderBand.qml` binds (`model.*` names,
  signals) delegating to Swift state + seams.
- `src/ui/songview/quick/swift-grid-prototype/TrackHeaders.swift` (new) —
  Swift presenter logic: layout rects via the same `layout::` font
  primitives exposed through the existing native bridge, revision-guarded
  menu snapshots (the `PendingHeaderMenu` pattern, already ported), feed
  consumption (`sgd_` tracks/titles, `sgs_` masks/selection).
- `src/ui/songview/songtab.cpp` or the presenter construction site (one
  wiring point): flag-based presenter selection.
- Harness `src/checks/swiftheadersgated/` (new) + registrations.

## Prerequisites

Tasks 1–3 (intents, session state, key seam for header band keys).

## Interface contract

- QML unchanged: `TrackHeaderBand.qml` compiles and runs against either
  presenter; property names/signals are the contract (enumerate from
  `trackheadermodel.h` at implementation start; deviations are defects).
- Mute/solo clicks submit `SGC_TRACK_MUTE`/`SGC_TRACK_SOLO`; masks render
  from `sgs_` pushes, never local state.
- Track add/duplicate/delete/reorder submit document intents — one undo
  entry each; list order refreshes via `sgd_`.
- Rename: host-side text entry (charter local-input exception) commits
  `SGC_TRACK_RENAME`; revision guard discards stale commits.
- Header band keys (navigation, audition) arrive via `sgk_` exactly as
  the grid's — the presenter is a band peer, not a separate path.
- Flags off: `TrackHeaderModel` path byte-identical to ship state.

## Implementation steps

1. Presenter shell mirroring the property surface; flag wiring at the
   construction site.
2. Swift logic consuming the feeds; geometry via the shared typography
   bridge (no new font code).
3. Harness `swiftheadersgated`: flag-on boot; property parity rows
   against the C++ presenter on the same fixture (row rects, masks,
   titles); mute/solo round-trip; rename commit + stale-guard; track op
   undo entries; header keys via `sgk_`.

## Acceptance predicate

- `deno task verify --filter swiftheadersgated --verbose` green.
- `deno task verify --filter selectionkey-core --verbose` green both
  flags off and on.
- `deno task build:app` + canaries green.

## Task-specific constraints

- `TrackHeaderModel` is read-only reference this task — no edits; it
  stays the flag-off presenter.
- No activity meters this wave (`TrackActivity` feed is a later surface;
  render placeholders stay C++-side).
- One wiring point only; presenter selection is a single construction
  branch, not scattered conditionals.
