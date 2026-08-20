# Node lanes and Voice Change lane plan

## Goal

One painting, hovering, and interaction model for the node lanes — Tempo and
Control Change. Voice Change is a separate, non-node lane with its existing
held-segment labels and picker interaction. This is a
`src/ui/editordrawer` remodel; core storage stays unchanged. Tempo remains
typed in `tempoPoints`, while Voice Change and CC remain raw-SMF-backed
through the existing `SongDocument` lane interface. The tempo-slot core
boundary is preserved — the seam is presentation.

## Naming

"Automation" is the umbrella word — the shared editing model and the drawer
page — and each kind gets its own name: **Tempo lane**, **Voice Change lane**,
**CC lane**. "CC lane" names the controller-backed per-track lanes (volume,
pan, expression, bend); it never stands in for the whole family. The
vocabulary lives in `CONTEXT.md`.

Renames when CC-only code stops wearing the umbrella name (phase 5, unless
noted):

- `automationrows.{h,cpp}` → `cclanes.{h,cpp}` — the CC lane table and
  `CCLaneAdapter`.
- `AutoLane` (`songviewmodel.h`) → `CcLane` — the view-model CC lane struct.
- CC row menu and add-lane strings: "+ Add CC lane", "Added %1 CC lane",
  "Delete CC lane", "Hide CC lane", "Remove empty CC lane", "Hidden CC
  lanes", "All parameters already have CC lanes", and the copy/paste/hide
  announcements that name a lane. These are CC-only today, so the timing is
  free; batch them with phase 5.
- `EditorAutomationRowKind` and `EditorAutomationRowId` keep their names and
  persisted shape. Renaming saved editor state or changing sidecar data is
  outside this plan.

Stay "automation" (umbrella-correct): `AutomationArea`, `AutomationPage`,
`AutomationProjection`, `AutomationGeometry`, `AutomationHoverState`,
`automationgesture.*`, `automationpaint.*`, the drawer toggle,
`EditorDrawerPage::Automations`, and "automation point(s)" announce strings
that count across kinds.

One trap: `AutomationLaneEdit` is not CC-specific. `replaceHeldSpan` is a
generic node-lane concept; only its `Target` is CC-shaped, and this plan
re-keys that to `LaneHandle`. If it ever renames, it is `LaneEdit`, never
`CcLaneEdit`. ("Note automation" in the pitch-bend editor is note-attached
and unrelated; it stays.)

## Model

Define one contract the widget layer talks to — a **node lane**:

- identity and title
- a body rect in the canvas
- effective points: `(tick, int value)`, sorted, one visible node per tick.
  Tempo stores at most one point per tick. CC may retain several matching raw
  events at one tick; its adapter exposes the last event as the effective
  value.
- value range `[minimum, maximum]` and `valueText(value)`
- time-selection membership per tick
- a commit back-end with exactly three operations

Painting, hovering, hit testing, gestures, previews, and value labels become
generic over that contract. The commit back-end stays per-kind behind it:
Tempo builds `TempoEdit` and pushes one `TempoEditCommand`; CC calls
`writeLanePoints` / `moveLanePoints` / `deleteLanePoints`.

```cpp
// ui/editordrawer/nodelane.h
struct LanePointMove {
    uint64_t fromTick = 0;   // identifies the point (one per tick per lane)
    ValuePoint to;           // destination tick + value
};

class NodeLane {
  public:
    virtual ~NodeLane() = default;

    virtual QString title() const = 0;
    virtual std::vector<ValuePoint> points() const = 0;
    virtual int minimumValue() const = 0;
    virtual int maximumValue() const = 0;
    virtual QString valueText(int value) const = 0;
    virtual bool pointSelected(uint64_t tick) const = 0;

    // Commit back-end. Each call is one user gesture -> one undo step.
    virtual void deletePoints(const std::vector<uint64_t> &ticks) = 0;
    virtual void movePoints(const std::vector<LanePointMove> &moves) = 0;
    virtual void replaceSpan(uint64_t first, uint64_t last,
                             const std::vector<ValuePoint> &points) = 0;
};
```

Contract notes:

- A tick identifies a point within its lane. Node-drag identities become
  `(lane, tick)`; `LaneNodeIdentity` and tempo's `m_activeNodeIdentities`
  dissolve into that.
- Deleting a node removes every underlying event for that same lane and tick.
  It does not remove notes or events belonging to another lane at that tick.
- Tempo's `movePoints` must resolve the original `TempoPoint` at `fromTick`
  and keep its exact microseconds when the value is unchanged.
- The revision guard stays: completions carry `expectedRevision`; commits
  verify `document->revision()` before applying.
- Value domain is `int` everywhere: BPM (20–255) and CC (0–127). Tempo
  converts BPM ↔ microseconds only inside its adapter.

## Lane table

`AutomationArea` builds one ordered lane stack on every rebuild:

```
[0] TempoLane       (implements NodeLane over SongDocument::tempoPoints())
[1] VoiceChangeLane (non-node lane over the primary track's voice changes)
[2…] CCLaneAdapter  (implements NodeLane over {track, controller})
```

A `LaneHandle` (table index) replaces `rowIndex` as the cross-cutting key in
layout and selection. Node painting, gestures, previews, and completions use
it only after resolving the entry as a `NodeLane`; `VoiceChangeLane` handles
its own non-node interaction. `TempoLane` stops faking `row = 0`.

## Voice Change stays a non-node lane

Add `voicechangelane.h` and `voicechangelane.cpp` as the concrete owner of
the existing Voice Change row behavior:

- Preserve the current held-voice segments and per-segment name labels from
  `paintVoiceRow`.
- Preserve the current voice picker and Voice-specific menu/input behavior.
- Do not add nodes, vertical value dragging, sweep, pencil, or ramp editing.
- Capture the lane's track when the stack rebuilds instead of repeatedly
  resolving the ambient `primaryTrack()`.
- The transient `LaneHandle` identifies the Voice Change lane in the shared
  editor layout. Core edits continue through the existing raw-SMF-backed
  `DOC_CC_VOICE` lane functions. Persisted `EditorAutomationRowId` data stays
  unchanged.

## Migration

| Site | Today | After |
|---|---|---|
| `AutomationProjection` row-keyed mapping | `rowIndexAt`, `pointY(row, rowIndex, …)`, `pointerMapping` borrow `vector<AutomationRow>` | lane body rect + the existing static `valueY` / `valueAtY(bounds, geometry, min, max, …)`; pointer mapping takes the lane |
| `AutomationHoverState` | keys on `hover.row`, calls `rows.pointsFor` / `valueTextFor` | keys on `LaneHandle`, reads the `NodeLane` |
| `ActiveGesture` variants | `int row` (`TempoLane` fakes 0) | `LaneHandle` |
| `AutomationLaneEdit::Completion::Target` | `{engineTrack, controller, expectedRevision}` | `{LaneHandle, expectedRevision}`; `commitLaneEdit` routes to the lane's commit |
| `TempoLane` | own `hitPoint`, own `m_hoveredPoint` hover, own `finishActiveGesture`, own paint file | `NodeLane` adapter + header/collapse shell + BPM text provider |
| `paintRow` Voice branches | `paintVoiceRow` dispatch, Voice grid tint, `SummaryKind::VoiceChanges` | `VoiceChangeLane` owns the existing segment paint |
| Voice input guards | `automationarea_input.cpp` `kind == Voice` branches (menu, delete guard, row-boundary guard) | move into `VoiceChangeLane`; do not route through node gestures |
| `AutomationRows::{rowTarget, rowIdentity}` | Voice re-resolves `primaryTrack()` | lane addresses captured at rebuild |
| Node-drag identities | `LaneNodeIdentity{engineTrack, controller, documentPoint}` / `std::vector<TempoPoint>` | `(LaneHandle, tick)` |

## Implementation order

Each phase builds and passes checks on its own. Phases 1–4 establish the node
lane path; phase 5 extracts the separate Voice Change lane. A phase is not
complete until its replacement is the only live path: remove the superseded
handlers, branches, adapters, and state in that same phase instead of leaving
parallel paths for later cleanup.

1. **Adapters, no behavior change.** Add `nodelane.h`; implement `NodeLane`
   in `TempoLane` (BPM ↔ µs inside) and a `CCLaneAdapter` over
   `(track, controller)`. Keep rowIndex keying. Verify: build, checks, zero
   behavior delta.
2. **Hover parity.** Re-key `AutomationHoverState` from
   `(AutomationRows&, rowIndex)` to `(NodeLane&, LaneHandle)`. `TempoLane`
   adopts it and deletes `m_hoveredPoint` and the caption-only hover paint:
   tempo gets the insertion line, held-BPM ghost, node ring, label cache, and
   dirty-bounds diffing the CC rows already have.
3. **Paint unification.** The generic row path becomes
   `paintNodeLane(painter, lane, …)`: grid, step curve, nodes, selection
   rings, hover chrome, gesture previews. `tempolanepaint.cpp` shrinks to the
   shell plus tempo-specific text. The Voice branch in `paintRow` moves to
   `VoiceChangeLane`.
4. **Input and commit unification.** One input dispatcher resolves the lane
   from the cursor and runs the generic press/move/release logic; tempo's
   `mousePress` / `mouseMove` / `mouseRelease` / `mouseDoubleClick` handlers
   dissolve. Gesture `row` fields become `LaneHandle`; completions target the
   handle; `nodeDragGestureAt` / `collectSelectedNodeDrags` unify behind the
   `NodeLane` contract.
5. **Voice Change extraction, no behavior change.** Add
   `voicechangelane.{h,cpp}` and move the current Voice paint, picker, menu,
   and input branches into it. Keep `DOC_CC_VOICE` and the existing core lane
   functions. Update harnesses only for the ownership move.

## Verification

Per phase: `cmake --build build -j"$(nproc)"` and
`deno task checks build/porydaw_checks`. Manual pass over the running app:

- Hover chrome identical on Tempo and CC lanes: insertion line,
  held-value ghost, node ring, value label.
- Node drag, sweep, ramp, pencil, band select, stationary delete, and
  selection drag behave identically on Tempo and CC; each gesture is one undo
  step.
- A moved fractional imported tempo point keeps its exact MIDI value.
- Tempo still paints first and collapses via its header. With no explicit
  points, its body is blank while playback uses the implicit 120 BPM default;
  save emits no Tempo event until the user creates one. A later first point
  still gets the node-free 120 BPM lead-in.
- Voice Change keeps its held-segment labels, double-click picker, and current
  context menu, with no node gestures added.

## Non-goals

- Unified core storage or a unified `SongDocumentEdit`
- Tempo re-entering the generic row list
- New track identity model or track-limit changes
- Event List changes
- New lane y-zoom or value-range UI
- Sidecar, persisted `EditorViewState`, or lane-height storage changes
