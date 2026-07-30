# 23 — ViewSidecar codec

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/sidecar`  
**Worktree:** `23-sidecar`  
**Base:** `FOUNDATION_SHA` — the coordinator-recorded, approved integration
commit after the 10A → 10B/11 → DOCUMENT_SHA → 10C and 12A/12B/13 → 14A/14B foundation DAG.
`git-operations-runner` creates/verifies the `23-sidecar` worktree and `task/psg-velocity/sidecar` branch at its exact `FOUNDATION_SHA` base and initializes/verifies submodules before the `task` agent begins. Product tasks (20, 21, 22, and 23) remain parallel only at `FOUNDATION_SHA`.
Start from that SHA exactly and do not absorb any parallel product packet.

## Exact independent ownership

This packet owns exactly these three paths:

1. `src/ui/viewsidecar.h`
2. `src/ui/viewsidecar.cpp`
3. `src/viewsidecarcheck.cpp`

The third path is the sidecar's cpp-only focused harness; do not add a harness
header. Packet 05 conditionally registers precisely this complete group with
`PORYDAW_HAS_SIDECAR_CHECK` and `porydaw --check-sidecar <scratch-project> <song-label>`. Once all three files
exist on this branch, that command must compile and be runnable here; no
source/build/dispatch edit or later host integration is needed to enable it.

Consume the Foundation `SongView::ViewState` capture/apply snapshot DTO and its
`EditorViewState` cosmetic value without editing either. Packet 14A defines
that compatible DTO and its capture/apply path before this product packet
exists; fresh `MainWindow` and `ViewSidecar` callers must remain buildable
without packet 23. Packet 23 only consumes the completed Foundation types.

This codec deliberately does not own or serialize generic `EditorPage`,
`EditorPageContext`, `EditorPageHost`, or the existing `TimelineSurface`;
those remain runtime page/context services rather than persistent cosmetic
state. Packet 30 owns all concrete `SongView`/`MainWindow` lifecycle wiring and
codec calls; packet 21 owns automation state policy; packet 20 owns drawer
state interaction; packet 05 alone owns central registration and dispatch.

`ViewSidecar` is a lossless file codec for a detached `SongView::ViewState`
snapshot plus its `EditorViewState` cosmetic value. Its interface loads a fresh
decoded snapshot or default/failure result and merges a snapshot into an
existing JSON root. It does not mutate a live view, apply a snapshot to
`SongView`, own a widget, apply remaps, clamp layout-dependent values, or
decide when to save. Serialization must not make either value live authority.

## Deliver

- Read and write `<project-root>/.porydaw/<song-label>.json` under root `view`,
  using `QSaveFile`. Missing, unreadable, malformed, or write-failed files fail
  quietly so callers can retain defaults and continue editing.
- Decode every known `SongView::ViewState` snapshot field and every known
  `EditorViewState` cosmetic field, including existing roll fields plus
  `drawerVisible`, `drawerPage`, legacy `splitter`, `laneHeight`,
  `laneHeights`, `laneRanges`, `emptyLanes`, and `hiddenLanes`. A decoded
  snapshot replaces—not appends to—the caller's prior snapshot.
- Validate every known snapshot and cosmetic entry independently. Accept only
  canonical row keys `tempo`, `voice:<track>`, and
  `cc:<track>:<controller>`; track is `0...15`, controller is `0...127` or
  `255`, and `128...254`, leading-zero, malformed, non-canonical, and
  out-of-range forms are rejected. Lane entries require object integer
  `track`/`cc` values in the same domains. Validate scalar and array JSON types
  rather than relying on lossy Qt conversions.
- Treat an unknown drawer page as Automations; retain typed valid non-menu range
  values such as `91`. Leave layout-bound clamping and row-state/remap policy
  to packet 21 and host restoration to packet 30.
- Preserve every unrelated root key and every unknown `view` key byte-for-value
  through a save, including unknown snapshot/cosmetic peers. Replace only
  codec-owned known view fields, so a valid save cannot discard future view
  fields or other sidecar users' data.

## Non-goals

Do not edit `SongView`, `MainWindow`, `EditorDrawer`, automation, velocity,
`TimelineSurface`, `PlayheadOverlay`, layout, document state, remapping,
gestures, Undo, foundation page/context/view-state types, `CMakeLists.txt`,
`src/main.cpp`, or `src/editorcheckdispatch.h.in`. Do not add JSON schemas,
migrations, UI fallbacks, a second row/lane codec, or save-on-drag behavior.
- Do not make, cache, or apply a `SongView::ViewState` snapshot as live
  `SongView` state; only an explicit caller-controlled capture/apply operation
  may cross that boundary.

## Edge cases

- One invalid row key or lane entry is ignored without discarding valid
  siblings. An absent/short splitter is represented as absent for the host's
  one-fifth fallback; the codec never resizes a roll.
- A valid root with non-object or malformed `view` yields default typed state;
  a later valid save preserves unrelated root fields while replacing `view`.
- Unknown root and unknown view fields, including nested objects/arrays, survive
  unchanged. Known fields supersede stale values on write.
- Two disjoint sequential loads replace both lane lists and the entire detached
  snapshot; no stale entries leak from the first value. Invalid I/O leaves the
  caller's provided snapshot untouched.
- A codec round trip changes no MIDI bytes and creates no Undo entry; it does
  not apply to a live view, and callers—not the codec—choose snapshot
  application and save timing.

## Focused checks and acceptance

Write only sidecar cases in `src/viewsidecarcheck.cpp` for detached snapshot
and cosmetic-state round trips; root/view unknown-key preservation; typed
snapshot/cosmetic scalar/array validation; canonical and rejected row/lane
identity matrices; per-entry tolerance; malformed/missing/I/O fallback;
unknown-page fallback; valid range `91`; legacy splitter shape; and disjoint
sequential-load replacement. Verify a round trip is JSON/view-only with no
live `SongView`, document, or Undo operation. Run any focused geometry/hit-test
behavior only through `porydaw --check-sidecar <scratch-project> <song-label>`; no repository-wide geometry source audit
belongs to this packet.

This packet owns the detached snapshot/cosmetic-codec portion of **DRW-04**,
**DRW-05**, and **UX-10**. Packet 21 owns the typed automation-state policy,
and packet 30 owns end-to-end persistence wiring. No full native suite,
formatter, linter, or
review gate belongs here.

## Downstream host integration

The four product heads merge normally only after their reviews, producing
`PRODUCT_SHA`. From it, 30C first owns generic dynamic timeline bands and
overlay-only playhead presentation, producing `RENDERING_SHA`; 30A then owns
SongView adapter/lifecycle and sidecar-state routing from `RENDERING_SHA`,
producing `ADAPTER_SHA`; 30B finally owns public MainWindow persistence
boundaries from `ADAPTER_SHA`, producing `HOST_SHA`. The codec does not acquire
a runtime page or host dependency anywhere in that serial host chain.

## Commit handoff

The task agent implements the owned production paths and focused harness, then
makes one ordinary commit on `task/psg-velocity/sidecar`; it does not build, run
checks, format, lint, or review. After the parallel product commits, the
coordinator runs `porydaw --check-sidecar <scratch-project> <song-label>` once on this complete group before
parallel review. Hand off the commit SHA, changed-file list, decode/validation
table, before/after JSON preservation fixtures, replacement and silent-I/O
evidence, and focused-check scope. Do not use staged-tree transport or modify
the integration branch.
