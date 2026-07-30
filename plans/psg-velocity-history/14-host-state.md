# 14 — Shared host state and event-list remap

**Wave:** parallel foundation descendants 14A and 14B  
**Base:** `CONTRACT_SHA`, produced by the foundation entry chain
`10A → parallel 10B/11 → DOCUMENT_SHA → 10C → CONTRACT_SHA`.
**Integration branch:** `feature/psg-velocity-history-upstream`

## Entry contract

Start neither task until `CONTRACT_SHA` exists and the existing `--rollcheck`
and `--eventviewcheck` dispatch routes remain available. Before each task agent begins,
`git-operations-runner` creates/verifies each named worktree/branch at its exact `CONTRACT_SHA` base
and initializes/verifies submodules. Packet 05 MUST NOT
use either existing source set as a completion predicate: both tasks extend
their existing harness and run through its existing named route. That
registration boundary is infrastructure, not work for this wave: 14A and 14B
MUST NOT edit `CMakeLists.txt`, `src/main.cpp`, or `src/editorcheckdispatch.h.in`.

Each task agent implements its focused coverage and makes one ordinary commit,
but does not build, run checks, format, lint, or review.  After both commits,
the coordinator runs the extended existing harnesses once, in parallel, against
the respective committed heads:

```text
<porydaw> --rollcheck <scratch-project> mus_lovely <roll-screenshot>
<porydaw> --eventviewcheck <scratch-project> mus_lovely <event-screenshot>
```

Only then do independent reviewers inspect those exact heads and their focused
evidence.  Every review result names the exact commit SHA it approves or
rejects, its `CONTRACT_SHA` base, and the named existing command it inspected.
Merge approved commits normally; do not cherry-pick, stage a transport tree, or
synthesize a candidate.  The coordinator then integrates 12A, 12B, 13, 14A,
and 14B and records that ordinary merged result as `FOUNDATION_SHA`.

## 14A — SongView shared selection/remap migration

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/shared-host-state`  
**Worktree:** `14a-shared-host-state`  
**Base:** `CONTRACT_SHA`

### Exclusive ownership

- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/rollcheck.cpp`

Migrate the concrete piano-roll host to the accepted 10/11 contracts while
preserving current roll behavior:

- Make the roll's one shared note-selection state opaque `NoteId`, not the
  defective `(tick, key)` surrogate.  It is the selection consumed by future
  velocity work; do not create a drawer-local or velocity-local selection.
- Migrate only typed persistent **cosmetic** values into the accepted
  `EditorViewState`; it must not acquire runtime authority.
- Retain `SongView::ViewState` as a compatible capture/apply snapshot DTO for
  fresh `MainWindow` and `ViewSidecar` callers. It may explicitly capture and
  apply runtime-derived host values with cosmetics, but it is not live
  authority: selected track, scrolling/zoom, cursor, grid/snap, and every
  equivalent host field remain live `SongView` state between those explicit
  operations. Live document, selection, timeline, voice, and playback state
  likewise remain on the existing host/context path.
- Consume every complete `TrackRemap` before the general document-change
  notification to re-address all `SongView`-owned track state: primary
  selected track, multi-track scope, mute/solo state, and any other retained
  track-owner state.  Drop deleted owners and give inserted owners their
  normal defaults.  Do not retain a move-only remapping path.
- Keep `SongView` as the concrete selection/remap consumer.  Do not move
  `TimelineSurface`, `PlayheadOverlay`, page hosting, `MainWindow`, layout,
  automation, velocity, CMake, or command dispatch into this task.  Packet
  30A later owns drawer/page adaptation and lifecycle wiring.

Extend `rollcheck.cpp` with focused regression coverage for duplicate notes
sharing one tick/key, shared selection continuity, track-header selection
clearing, compatible `ViewState` capture/apply of the retained runtime-derived
host fields, and complete remap handling on apply, Undo, and Redo for move,
insert, duplicate, delete, and metadata-only/engine-track transitions. Assert
remap-before-general-change ordering, deleted-owner dropping, and inserted
owner defaults.  This proves 14A's parts of **CORE-01**, **CORE-02**,
**VEL-01**, and **UX-04**; it does not implement velocity gestures or batch
mutation.
The coverage remains reachable through the existing `--rollcheck` route above;
do not add a packet-05 predicate, conditional command, or alias for 14A.

## 14B — Event-list remap migration

**Agent:** `task`  
**Setup Agent:** `git-operations-runner`  
**Branch:** `task/psg-velocity/event-list-remap`  
**Worktree:** `14b-event-list-remap`  
**Base:** `CONTRACT_SHA`

### Exclusive ownership

- `src/ui/eventlistview.h`
- `src/ui/eventlistview.cpp`
- `src/eventviewcheck.cpp`

Consume the same complete `TrackRemap` in the raw MIDI event list.  Re-anchor
its selected/visible SMF-chunk owner using the old-to-new SMF-chunk mapping on
apply, Undo, and Redo, before its general document-change handling.  A deleted
chunk loses its anchor; inserted chunks use normal unselected/default behavior.
Remove the move-only route so inserts, duplicates, deletes, and raw-edit
metadata-only/engine-track transitions use the one complete-remap path.

`eventviewcheck.cpp` must characterize all of those apply/Undo/Redo cases and
signal ordering.  It owns only event-list anchoring; it must not alter event
editing semantics, SongView state, mute/solo behavior, follow-playhead
behavior, layout, CMake, or main dispatch.  This is the event-list consumer
portion of **CORE-01**, not a reason to import unrelated reference-branch
behavior.
The coverage remains reachable through the existing `--eventviewcheck` route
above; do not add a packet-05 predicate, conditional command, or alias for
14B.

## Wave acceptance

The coordinator rejects either head before review if its committed harness
extension is not reachable through its named existing command.  The two exact
commands above must pass once after the commits, and reviewers must confirm the
exclusive path sets, the single complete-remap route, opaque shared selection,
cosmetic-only `EditorViewState`, live `SongView` runtime state, and the
compatible non-authoritative `ViewState` snapshot DTO. After the normal merges,
only foundation handoff to the parallel product wave.
