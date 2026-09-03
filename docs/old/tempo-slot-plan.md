# Node lanes and Voice Change lane plan

**Status:** Authoritative implementation and behavior record for the Tempo
and CC node lanes. The Voice Change material below is superseded by
[`voice-change-drawer-page-plan.md`](old/voice-change-drawer-page-plan.md):
Voice Change is now an independent editor-drawer page owned by
`VoiceChangeArea`, not an `AutomationCanvas` strip, and `AutomationCanvas`
keeps only the Tempo and CC lanes. Historical decision context remains in
[`tempo-slot-minutes.md`](tempo-slot-minutes.md); the abandoned
standalone-strip plan is not retained separately.

## Goal

The completed drawer design uses one painting, hovering, and interaction model
for the node lanes — Tempo and Control Change. Voice Change remains a separate,
non-node lane with its existing held-segment labels and picker interaction.
Core storage is unchanged: Tempo stays typed in `tempoPoints`, while Voice
Change and CC remain raw-SMF-backed through the existing `SongDocument` lane
interface. Presentation keeps Tempo in `AutomationCanvas` as node-stack slot 0
and resolves it as a sticky viewport-bottom overlay.

## Naming

"Automation" is the umbrella word — the shared editing model and the drawer
page — and each kind gets its own name: **Tempo lane**, **Voice Change lane**,
**CC lane**. "CC lane" names the controller-backed per-track lanes (volume,
pan, expression, bend); it never stands in for the whole family. The
vocabulary lives in `CONTEXT.md`.

`AutomationPage`, `AutomationCanvas`, `AutomationProjection`,
`AutomationGeometry`, the drawer toggle, and `EditorDrawerPage::Automations`
remain the page-level coordination vocabulary. `AutomationPage` owns the scroll
container and application routing. `AutomationCanvas` is its scrollable child:
it owns the node-lane stack, Voice Change strip, scrollable CC content, final
paint order, hit testing, and input dispatch.

The leaf modules now own the concerns their names describe:

- `nodelane/nodelane.{h,cpp}` defines the NodeLane contract and edit
  preparation. Its private paint, hover, gesture, pencil, and batch-commit
  files serve both Tempo and CC.
- `nodelane/paint.{h,cpp}` owns normal and active-gesture node-body painting.
  Whole-page grid and selection chrome remain with `AutomationCanvas`;
  `VoiceChangeLane` owns Voice painting; `TempoLane` owns only its header,
  collapse, BPM prompt, and adapter concerns.
- `cclanes.{h,cpp}` owns the CC lane table and `CCLaneAdapter`. It depends on
  the NodeLane contract but not on node paint, hover, gesture, or Voice code.
- `EditorAutomationRowKind` and `EditorAutomationRowId` retain Tempo and CC
  persisted state. Loading discards legacy `voice:<track>` entries and never
  writes them again. The Tempo key remains the stable custom-height/range key.

"Automation point(s)" announce strings may stay when they count across node
lane kinds. "Note automation" in the pitch-bend editor is note-attached and
unrelated.

`cclanes` dependency contract:

- `cclanes.h` includes `nodelane/nodelane.h` plus only the standard-library
  and Qt types exposed by its own declarations. Forward-declare document,
  model, and owner types where a declaration is sufficient.
- `cclanes.cpp` includes `core/songdocument.h` for the CC commit back-end,
  `ui/songviewmodel.h` for the current CC point data, `ui/editorviewstate.h`
  for visible, hidden, and explicit empty CC lanes, and
  `ui/m4asemantics.h` for controller names and value formatting.
- `cclanes` does not include node painting, hover, gesture, Voice Change, or
  voicegroup headers. Those belong to their owning modules.

- `CcLane` (`songviewmodel.h`) is the view-model CC lane struct.
- CC row menu and add-lane strings are CC-only: "+ Add CC lane", "Added %1 CC
  lane", "Delete CC lane", "Hide CC lane", "Remove empty CC lane", "Hidden CC
  lanes", "All parameters already have CC lanes", and the CC-specific
  copy/paste/hide announcements.

`EditorAutomationRowKind` and `EditorAutomationRowId` retain Tempo and CC
persisted state; the `Voice` enum value is removed. `viewsidecar.cpp` discards
legacy `voice:<track>` entries while loading and never writes them again.

## Model

Define one contract the widget layer talks to — a **node lane**:

- identity and title
- a body rect in the canvas
- effective points: `(tick, int value)`, sorted, one visible node per tick.
  Tempo stores at most one point per tick and never a synthetic tick-0 120.
  CC may retain several matching raw events at one tick; its adapter exposes
  the last event as the effective value.
- value range `[minimum, maximum]` and `valueText(value)`
- time-selection membership per tick
- a commit back-end with exactly three operations

Painting, hovering, hit testing, gestures, previews, and value labels are
generic over that contract. The commit back-end stays per-kind behind it:
Tempo builds `TempoEdit` and pushes one `TempoEditCommand`; CC calls
`writeLanePoints` / `moveLanePoints` / `deleteLanePoints`.

```cpp
// ui/editordrawer/nodelane/nodelane.h
struct NodePoint {
    uint64_t tick = 0;
    int value = 0;
};

struct NodePointMove {
    uint64_t fromTick = 0;   // identifies the point (one per tick per lane)
    NodePoint to;            // destination tick + value
};

class NodeLane {
  public:
    virtual ~NodeLane() = default;

    virtual QString title() const = 0;
    virtual std::vector<NodePoint> points() const = 0;
    virtual int minimumValue() const = 0;
    virtual int maximumValue() const = 0;
    virtual QString valueText(int value) const = 0;
    virtual bool pointSelected(uint64_t tick) const = 0;

    // Commit back-end. Each call is one user gesture -> one undo step.
    virtual void deletePoints(const std::vector<uint64_t> &ticks) = 0;
    virtual void movePoints(const std::vector<NodePointMove> &moves) = 0;
    virtual void replaceSpan(uint64_t first, uint64_t last,
                             const std::vector<NodePoint> &points) = 0;
};
```

Contract notes:

- A tick identifies a point within its lane. Node-drag identities are
  `(lane, tick)`; `LaneNodeIdentity` and Tempo's `m_activeNodeIdentities`
  are gone.
- Deleting a node removes every underlying event for that same lane and tick.
  It does not remove notes or events belonging to another lane at that tick.
- Moving a CC node moves every underlying event for that same lane and source
  tick as one group. Their order is preserved at the destination tick, so the
  same last event remains effective and no hidden same-tick event reappears at
  the source tick.
- Tempo's `movePoints` must resolve the original `TempoPoint` at `fromTick`
  and keep its exact microseconds when the value is unchanged.
- Tempo's `valueText` displays integer BPM. A fractional imported point
  shows its rounded BPM — the decimal is discarded from drawer display —
  while storage and commits keep the exact microseconds. Replacing a
  fractional value through an edit discards the microseconds by design:
  the user changed the value. The Event List keeps its two-decimal BPM
  display; it is a different surface outside this plan.
- The revision guard stays: completions carry `expectedRevision`; commits
  verify `document->revision()` before applying.
- Value domain is `int` everywhere. Tempo uses `CoreTimeDefaults`
  (`kMinTempoBpm`–`kMaxTempoBpm`). CC and bend use
  `laneValueMinimum` / `laneValueMaximum` (CC 0–127, bend −8192–8191).
  `NodeLane::minimumValue` / `maximumValue` are that edit domain; display
  zoom (`laneRanges`) is not. Tempo converts BPM ↔ microseconds only
  inside its adapter.

## Resolved canvas layout

`AutomationCanvas` has two layout layers in one widget.

1. **Scrollable content** is laid out in canvas-content coordinates: Voice
   Change starts at y=0 when present, CC bodies follow at
   `contentTopInset()`, and the add-lane strip follows the final CC body.
   `contentTopInset()` is Voice-only.
2. **Pinned Tempo** is also a canvas rectangle, but its top is recomputed from
   vertical scroll position and viewport height. Its canvas-to-page position
   therefore remains at the viewport bottom. Page-space code maps through the
   canvas; it must not compare page-space points directly with a lane body.

Tempo remains the first node-stack entry even while collapsed:

```
[0] TempoLane       (NodeLane over SongDocument::tempoPoints())
[1…] CCLaneAdapter  (NodeLane over {track, controller})
```

`LaneHandle{0}` is Tempo's stable identity. When collapsed, that slot has an
empty body but remains in the stack; the header is still the collapse target.
Expanded, the body fills the pinned Tempo row. CC handles are one-based because
they follow slot 0. `VoiceChangeLane` is neither a stack entry nor a
`LaneHandle`.

The collapsed Tempo total height is `AutomationGeometry::addLaneStripHeight`.
The expanded total height is the persisted Tempo row height, keyed by
`EditorAutomationRowId{Tempo, 0, 0}` and clamped to the normal automation-row
limits. `m_expanded` is current-editor-session state: it starts collapsed and
is not persisted per song. The canvas adds Tempo's current total height to its
minimum height, leaving trailing clearance so the last CC body and add-lane
strip can scroll clear of the overlay.

### Node-lane contract

The shared `NodeLane` contract remains the widget-facing model:

- identity and title;
- a resolved body rectangle in canvas-content coordinates;
- effective, sorted `(tick, int value)` points, with one visible node per tick;
- value range and value text;
- time-selection membership; and
- delete, move, and replace-span commits, each representing one user gesture.

Tempo's adapter reads `tempoPoints()` directly, exposes BPM only for display,
and commits a typed `TempoEdit`. It preserves exact microseconds when a move
changes only tick. CC's adapter exposes the effective last same-tick event and
commits through the existing lane operations. Revision-guarded completions and
the one-undo-step rule apply to both adapters.

## Paint and hit-test order

The draw order is intentional:

1. The canvas paints its background/grid, then Voice, CC rows, selection chrome,
   and the add-lane strip in normal scrollable-content order.
2. It paints Tempo's header last. If expanded, it clips Tempo's shared
   NodeLane body and reticle to the resolved pinned body after all CC paint.

CC content can occupy the same canvas-space y-range while it scrolls, but the
opaque Tempo layer is the final visible layer in that range. Its input order
matches its paint order:

1. Tempo header or pinned body is recognized first and clears Voice hover.
2. A header click toggles collapse. A body event resolves `LaneHandle{0}` for
   node hit testing, menus, gestures, and band-selection endpoints.
3. Only outside Tempo can Voice, a CC resize boundary, the add-lane strip, or
   another node lane receive the event.

This keeps an occluded CC control from responding through Tempo. Rebuilds
cancel active gestures before stack/body replacement, so a stale handle cannot
commit after a geometry or document refresh.

## Completed implementation waves

1. **NodeLane unification.** Shared point, hover, paint, gesture, preview, and
   commit preparation moved behind `NodeLane`; Tempo retained its BPM and
   `TempoEdit` adapter and CC retained its existing storage back-end.
2. **Voice separation.** `VoiceChangeLane` became the non-node owner of Voice
   paint and input. `CCLanes` became CC-only; legacy Voice sidecar rows are
   discarded.
3. **Stable Tempo slot.** `AutomationCanvas` retained `m_tempoLane` as
   `LaneHandle{0}` and made all remaining CC adapters follow it.
4. **Sticky in-drawer composition.** `tempoTop`,
   `syncPinnedTempoLayout`, trailing minimum-height clearance, final-pass Tempo
   paint, and header/body-first routing produced the viewport-bottom overlay.
5. **Behavioral coverage.** Geometry, scrolling, collapse, paint occlusion,
   and shared Tempo gesture coverage were added to the existing automation
   checks.

## Verification coverage

- `rollcheckautomation` verifies slot 0 has no body while collapsed, restores
  the persisted Tempo row height when expanded, remains pinned across vertical
  scroll, leaves CC/add-lane trailing clearance, and returns the reserved space
  on collapse.
- `rollcheckautomation_paint` verifies a Tempo reticle changes the pixels of a
  CC body geometrically beneath the pinned body, proving final paint z-order.
- The automation-gesture harness expands Tempo through its header and runs
  shared NodeLane mapping, hover, parity, and gesture scenarios against
  `LaneHandle{0}`.

## Non-goals

- No unified core storage or universal `SongDocument` edit interface.
- No Tempo-specific widget, timeline band, or input framework.
- No change to Tempo's typed storage, global selection semantics, session
  collapse, or persisted custom-height/range state.
- No node, sweep, pencil, ramp, or vertical-drag behavior for Voice Change.
