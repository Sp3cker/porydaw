# 21 — AutomationPage and AutomationArea

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/automation`  
**Worktree:** `21-automation`  
**Base:** `FOUNDATION_SHA` — the coordinator-recorded, approved integration
commit after the 10A → 10B/11 → DOCUMENT_SHA → 10C and 12A/12B/13 → 14A/14B foundation DAG.
`git-operations-runner` creates/verifies the `21-automation` worktree and `task/psg-velocity/automation` branch at its exact `FOUNDATION_SHA` base and initializes/verifies submodules before the `task` agent begins. Product tasks (20, 21, 22, and 23) remain parallel only at `FOUNDATION_SHA`.
Start at that exact SHA and work independently of packets 20, 22, and 23.

## Exact independent ownership

This packet owns exactly these five paths:

1. `src/ui/automationpage.h`
2. `src/ui/automationpage.cpp`
3. `src/ui/automationarea.h`
4. `src/ui/automationarea.cpp`
5. `src/rollcheckautomation.cpp`

The fifth path is the automation cpp-only focused harness; do not add a harness
header. Packet 05 conditionally registers precisely this complete group with
`PORYDAW_HAS_AUTOMATION_CHECK` and `porydaw --check-automation <scratch-project> <song-label> [screenshot]`. Once all five
files exist on this branch, that command must compile and be runnable here; no
source/build/dispatch edit or later host integration is needed to enable it.

Implement the module's `AutomationPage` atop, and consume without editing, the
generic Foundation `EditorPage`, `EditorPageContext`, `EditorPageHost`, and
`EditorViewState` contracts; the layout and `SongDocument` contracts; and the
existing `TimelineSurface` supplied by the context. It must not make an
independent timeline or alter the shared surface. Packet 30 alone edits
concrete `SongView`/`MainWindow` lifecycle wiring; packet 23 independently
owns the sidecar codec; packet 05 alone owns central registration and dispatch.

`AutomationPage`/`AutomationArea` are the sole automation display, state,
gesture, and drawing modules. They consume shared timeline/selection/track,
document, focus, status, follow-scroll, and remap services through the generic
page/context seam. They report typed view-state updates; `ViewSidecar` alone
encodes, decodes, or merges JSON.

## Deliver

- Extract the existing editor into the hostable page/area without an independent
  timeline, note-selection, scroll, zoom, cursor, or playback model. Preserve
  click focus and the vertical-only inner scroll contract.
- Own typed row policy: Tempo; conditional Voice; visible primary-track
  controllers sorted by controller with bend pseudo-controller `255` last.
  Own empty/hidden lanes, shared and per-row heights, ranges, and their
  consumption of complete document track remaps. Retain surviving state and
  drop only deleted owners.
- Implement the add-lane strip, exact order/omission/hidden-lane menu, all lane
  menu actions, enablement, confirmations, value-range rules, and required
  announcements. Keep view-only actions separate from document mutations.
- Implement divider, wheel, pan, point, sweep, ramp, time-selection, exact
  entry, and voice-row gestures; held-step/point/hover drawing; and one-command
  document edits/no-op suppression. Use only foundation layout values.
- Route every automation playhead-driven voice-context lookup through packet
  11's sole static `uint64_t EditorPageContext::drawerContextTick(double)`
  helper and consume its returned tick. Do not introduce an automation-local
  playhead conversion.
- Freeze appropriate gesture snapshots, render document edits as previews until
  commit, and cancel point/sweep/ramp/band gestures on page or drawer hide,
  track/song/document replacement, document mutation, Undo/Redo/reload,
  mouse-grab/window loss, and Escape. End pan/resize capture while retaining
  applied view state; clear cursor, hover, preview, and follow-scroll pause.

## Non-goals

Do not edit `EditorDrawer`, `VelocityPage`/`VelocityArea`, `VelocityAxis`, PSG
model, `ViewSidecar`, `SongView`, `MainWindow`, `TimelineSurface`,
`PlayheadOverlay`, layout, foundation page/context/view-state headers,
`CMakeLists.txt`, `src/main.cpp`, or `src/editorcheckdispatch.h.in`. Do not create
a second row codec, selection model, remap signal, sidecar merge, drawer
shortcut, lane reorder, row collapse control, tooltip, or unrelated
roll/event-list/playback change.

## Edge cases

- No document means no add-lane strip. Secondary header selection never creates
  a second row set; hidden lanes still join track-scoped range edits.
- Retain height/range through hide, remove, delete, reorder, and recreation;
  accept a valid non-menu range such as `91` through typed state.
- Omit existing/hidden add candidates, retain hidden ordering, and show the
  disabled all-present item before the hidden section.
- A blank double-click creates no interim point. Cancel/unchanged gestures and
  failed or stale document work create neither MIDI change nor Undo entry.
- Fast sweeps fill crossed cells; Shift ramp wins over point grab; nearby delete
  is time-axis-only; right-band selection is half-open and restores on Escape.
- Remaps from move/insert/duplicate/delete and metadata/engine transitions
  update each surviving owner once; deleted owners alone lose state.

## Focused checks and acceptance

Write only automation cases in `src/rollcheckautomation.cpp` for row order,
primary-track context, hidden/empty state, height/range/remap consumption,
add/lane menus, exact announcements, view-only MIDI/revision/Undo invariants,
and clear/delete/paste Undo cases. Cover point/sweep/ramp/voice/exact-entry/
time-selection behavior, fast motion, no-op/atomic cancel, painting/hover
layout alignment, and every listed lifecycle cancellation route.
Under **AUT-02**, at negative, below-half, half-tick, and above-half playback
inputs, set the expected query tick by calling
`EditorPageContext::drawerContextTick(playhead)` and assert the automation
voice-context query receives that returned tick. The stopped path uses the
edit cursor directly.
Exercise geometry and hit-test behavior only through `porydaw --check-automation <scratch-project> <song-label> [screenshot]`; no
repository-wide geometry source audit belongs to this packet.

This packet owns **AUT-01**, **AUT-02**, **AUT-03**, automation portions of
**DRW-05**, **LIFE-01**, **UX-03**, and **UX-04**. It contributes typed-state
consumer coverage to **DRW-04**; packet 23 owns codec validation and unknown
key preservation, while packet 30 proves the integrated save/load route. No
full native suite, formatter, linter, or review gate belongs here.

## Downstream host integration

The four product heads merge normally only after their reviews, producing
`PRODUCT_SHA`. 30C then starts from `PRODUCT_SHA`, owns the generic dynamic
timeline-band API and overlay-only playhead presentation, and undergoes review
against `PRODUCT_SHA..30C_HEAD`; its approved ordinary merge records
`RENDERING_SHA`. 30A then starts from `RENDERING_SHA`, constructs the page/area
through the generic host, and owns SongView lifecycle, shared callbacks,
sidecar-state routing, and dynamic-band requests; its review is against
`RENDERING_SHA..30A_HEAD`, and its approved ordinary merge records
`ADAPTER_SHA`. 30B then starts from `ADAPTER_SHA`, owns public MainWindow A/V
routing and persistence, and undergoes review against `ADAPTER_SHA..30B_HEAD`;
its approved ordinary merge records `HOST_SHA`. This packet neither edits nor
depends on another product packet before that integration.

## Commit handoff

The task agent implements the owned production paths and focused harness, then
makes one ordinary commit on `task/psg-velocity/automation`; it does not build,
run checks, format, lint, or review. After the parallel product commits, the
coordinator runs `porydaw --check-automation <scratch-project> <song-label> [screenshot]` once on this complete group before
parallel review. Hand off the commit SHA, changed-file list, host-seam inputs
and outputs, remap/Undo/cancellation matrices, and focused-check scope. Do not
use staged-tree transport or change the integration branch.
