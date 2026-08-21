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

Keep `automation` only on the page-level coordinator while the drawer page is
still named Automations. `AutomationPage`, `AutomationCanvas`,
`AutomationProjection`, `AutomationGeometry`, the drawer toggle, and
`EditorDrawerPage::Automations` stay because they lay out or route both node
and non-node lanes. Rename `AutomationArea` to `AutomationCanvas`, including
`automationarea.{h,cpp}` and its `_input`, `_menu`, and `_gesture`
implementation files. `AutomationPage` owns the scroll container and
application routing; `AutomationCanvas` is the required scrollable child and
owns the node-lane stack, the Voice Change strip, painting, hit testing, and input dispatch. An
`automationcanvas_*.cpp` file stays only while it implements cross-lane
dispatch; node-only or Voice-only code moves to the owning lane module.

Rename leaf code by what it actually owns:

The NodeLane module lives under `src/ui/editordrawer/nodelane/`. Its public
front door is `nodelane/nodelane.h`; `nodelane.cpp` implements the shared
contract and edit preparation. Paint, hover, and gestures are private parts of
that same module.

- `automationpaint.{h,cpp}` and `automationpaintpreview.cpp` →
  `nodelane/paint.{h,cpp}`. Normal and active-gesture preview painting stay in
  this one paint module. Whole-page grid or selection chrome stays with
  `AutomationCanvas`; Voice painting moves to `VoiceChangeLane`. Delete
  `tempolanepaint.cpp`: the shared NodeLane painter owns the complete Tempo and
  CC node bodies, while the small collapsible Tempo header stays in
  `tempolane.cpp`.
- `automationhover.{h,cpp}` → `nodelane/hover.{h,cpp}` once Voice hover is owned
  by `VoiceChangeLane`.
- `automationgesture.{h,cpp}` → `nodelane/gesture.{h,cpp}` and
  `automationpencilgesture.{h,cpp}` → `nodelane/pencilgesture.{h,cpp}`. Voice
  does not use these gestures.
- Fold `automationlaneedit.{h,cpp}` into `nodelane/nodelane.{h,cpp}` and rename
  the type `NodeLaneEdit`. Its canonicalization, held-span restoration, no-op
  detection, completion types, and revision data are part of the shared
  NodeLane contract; do not create separate `edit.{h,cpp}` files.
- `automationrows.{h,cpp}` → `cclanes.{h,cpp}` — the CC lane table and
  `CCLaneAdapter`.

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

- `AutoLane` (`songviewmodel.h`) → `CcLane` — the view-model CC lane struct.
- CC row menu and add-lane strings: "+ Add CC lane", "Added %1 CC lane",
  "Delete CC lane", "Hide CC lane", "Remove empty CC lane", "Hidden CC
  lanes", "All parameters already have CC lanes", and the copy/paste/hide
  announcements that name a lane. These are CC-only today, so the timing is
  free; batch them with phase 5.

`EditorAutomationRowKind` and `EditorAutomationRowId` keep their names for the
remaining Tempo and CC persisted state, but remove the `Voice` enum value.
`viewsidecar.cpp` discards legacy `voice:<track>` row entries while loading and
never writes them again; no migration or replacement Voice-row state is added.
"Automation point(s)" announce strings may stay when they count across node
lane kinds. "Note automation" in the pitch-bend editor is note-attached and
unrelated; it stays.

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

Painting, hovering, hit testing, gestures, previews, and value labels become
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

- A tick identifies a point within its lane. Node-drag identities become
  `(lane, tick)`; `LaneNodeIdentity` and tempo's `m_activeNodeIdentities`
  dissolve into that.
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

## Lane table

`AutomationCanvas` lays out, top to bottom, Tempo, then Voice Change, then
the CC lanes. Only Tempo and CC form the node-lane stack:

```
[0] TempoLane       (implements NodeLane over SongDocument::tempoPoints())
[1…] CCLaneAdapter  (implements NodeLane over {track, controller})
```

`VoiceChangeLane` is a sibling strip in that y-order: not a stack entry, not
a `NodeLane`, and not a `LaneHandle`. A `LaneHandle` is an index into the
node-lane stack only. Node painting, hover, gestures, previews, and
completions take `NodeLane &` from that stack. Hit-testing is: Voice rect →
`VoiceChangeLane`; else `nodeStack.laneAt(y)`. Every rebuild cancels the
active gesture before replacing the stack or the Voice strip, so a
`LaneHandle` never survives a rebuild. `TempoLane` stops faking `row = 0`.

### Projection dissolution

`AutomationProjection` bundles two roles: the page-level time axis
(`rawTickAt`, `displayX`, `snapTickAt`, `fineSnapTick`, grid cells) and
row-stack layout (`rowIndexAt`, `rowTop`, `rowHeight`, `valuePlotBounds`,
row-keyed `pointY` / `valueAtY` / `pointerMapping`). Only the layout role
is row-keyed, and the node-lane stack replaces it consumer by consumer:

- Phase 2: the canvas owns layout. Voice has its own body rect; node
  `laneAt(y)` and each NodeLane body rect replace `rowIndexAt` /
  `rowTop` / `rowHeight` for Tempo and CC.
- Phases 3–4: hover and paint read the lane's body rect and value range
  through the static `valueY` / `valueAtY` and use the projection only for
  the time axis. This is the pattern `TempoLane` already runs today: it
  constructs the projection with an empty row list.
- Phase 5: `pointerMapping` becomes lane-keyed and, with its last consumer
  gone, every row-keyed member plus the rows vector and `topInset`
  constructor inputs are deleted. What remains is the time axis and the
  statics.

Each phase removes its consumers'
dependence on the row-keyed members, and the members die in phase 5 when
the last consumer migrates. The in-phase removal rule's unit is the
consumer's dependency; shared plumbing whose remaining consumers are
scheduled for later phases survives until then.

## Voice Change stays a non-node lane

Add `voicechangelane.h` and `voicechangelane.cpp` as the concrete owner of
the existing Voice Change row behavior:

- Preserve the current held-voice segments and per-segment name labels from
  `paintVoiceRow`.
- Preserve the current voice picker and Voice-specific menu/input behavior.
- Do not add nodes, vertical value dragging, sweep, pencil, or ramp editing.
- Capture the lane's track when the Voice strip rebuilds instead of repeatedly
  resolving the ambient `primaryTrack()`.
- Voice is identified by its body rect, not a `LaneHandle`. Core edits
  continue through the existing raw-SMF-backed `DOC_CC_VOICE` lane functions.
  Persisted `EditorAutomationRowId` data stays unchanged.

## Migration

| Site | Today | After |
|---|---|---|
| `AutomationProjection` row-keyed mapping | `rowIndexAt`, `pointY(row, rowIndex, …)`, `pointerMapping` borrow `vector<AutomationRow>` | lane body rect + the existing static `valueY` / `valueAtY(bounds, geometry, min, max, …)`; pointer mapping takes the lane |
| `AutomationHoverState` | keys on `hover.row`, calls `rows.pointsFor` / `valueTextFor` | becomes `NodeLaneHoverState`, keys on `LaneHandle`, reads the `NodeLane` |
| `ActiveGesture` variants | `int row` (`TempoLane` fakes 0) | `LaneHandle` |
| `AutomationLaneEdit::Completion::Target` | `{engineTrack, controller, expectedRevision}` | `NodeLaneEdit::Completion::Target{LaneHandle, expectedRevision}`; commit routing resolves the lane |
| `TempoLane` | own `hitPoint`, own `m_hoveredPoint` hover, own `finishActiveGesture`, own paint file | `NodeLane` adapter + header/collapse shell + BPM text provider |
| `paintRow` Voice branches | `paintVoiceRow` dispatch, Voice grid tint, `SummaryKind::VoiceChanges` | `VoiceChangeLane` owns the existing segment paint |
| Voice input guards | `automationarea_input.cpp` `kind == Voice` branches (menu, delete guard, row-boundary guard) | move into `VoiceChangeLane`; do not route through node gestures |
| `AutomationRows::{rowTarget, rowIdentity}` | Voice re-resolves `primaryTrack()` | lane addresses captured at rebuild |
| Node-drag identities | `LaneNodeIdentity{engineTrack, controller, documentPoint}` / `std::vector<TempoPoint>` | `(LaneHandle, tick)` |

## Implementation order

Each phase builds and passes checks on its own. The pre-phase establishes the
adapter seam behind its executable contract; phase 1 establishes the canvas;
phase 2 extracts Voice Change before phases 3–5 simplify the remaining
node-only path. A phase is not complete until its replacement is the
only live path: remove the superseded handlers, branches, adapters, and state
in that same phase instead of leaving parallel paths for later cleanup.
Shared plumbing is the one exception: starve it consumer by consumer and
delete it when its last consumer migrates (see Projection dissolution).
Each phase also updates `CMakeLists.txt` and the affected check-source manifests,
passes its focused gate, is audited by a thermo-nuclear code quality review
whose findings are addressed, and ends at a clean commit checkpoint before
the next phase begins.

0. **NodeLane contract and matrix, no behavior change.** Add
   `nodelane/nodelane.{h,cpp}` holding `NodePoint`, `NodePointMove`, and the
   `NodeLane` contract. Implement `NodeLane` in `TempoLane` — BPM ↔ µs
   conversion stays inside the adapter — and add a `CCLaneAdapter` over
   `(track, controller)` in the current `automationrows` module; phase 2
   renames that module after Voice leaves it. No widget path changes:
   rowIndex keying stays and the adapters take no production callers yet.

   The matrix is their first and only caller. Add a `node-contract` domain
   to the existing `automation-gestures` harness in a new
   `src/checks/automationgesturecheck/contract.cpp`; it calls both adapters
   through `NodeLane` directly, with no canvas and no widget, and every row
   runs against both adapters from one table:

   - `points()` returns the lane's effective points: sorted by tick, one
     node per tick. A CC lane holding several same-tick raw events exposes
     the last event's value. Tempo returns `tempoPoints()` as-is — no
     synthetic tick-0 120 node.
   - `minimumValue()` / `maximumValue()` are `CoreTimeDefaults` for Tempo
     (20–255) and `laneValueMinimum` / `laneValueMaximum` for CC (0–127,
     bend −8192–8191). `valueText()` formats CC values with their controller
     semantics and Tempo values as integer BPM. `pointSelected()` reports
     time-selection membership.
   - `deletePoints(ticks)` removes exactly the points at those ticks —
     every underlying event for that lane and tick — and advances revision
     and undo index exactly once. Empty or unknown ticks advance neither.
   - `movePoints(moves)` resolves each point by its `fromTick`. A Tempo
     move whose value is unchanged keeps the exact microseconds. A CC move
     carries every underlying event for that lane and source tick as one
     group, preserving order at the destination tick and leaving no event
     at the source tick. One revision and one undo step.
   - `replaceSpan(first, last, points)` replaces the lane's points in that
     tick range. Empty Tempo stays empty. One revision and one undo step.

   Verify: build, the new domain green for both adapters, zero behavior
   delta in the running app.

1. **Canvas rename and edit fold, no behavior change.** Rename
   `AutomationArea` and its implementation files to `AutomationCanvas`. Move
   `AutomationLaneEdit` into the pre-phase's `nodelane/nodelane.{h,cpp}` as
   `NodeLaneEdit`. Keep rowIndex keying; the widget path is untouched and the
   adapters still have no production callers. Rename
   `src/checks/automationgesturecheck/tempo.cpp` to `nodelane.cpp`.
   Verify: build, checks, zero behavior delta, the pre-phase contract matrix
   still passes for both adapters, no separate NodeLane edit file remains,
   and no `AutomationArea` symbol or `automationarea*` source file remains.
2. **Voice Change extraction, no behavior change.** Add
   `voicechangelane.{h,cpp}` and make it the sole owner of Voice segment
   painting, label layout, hover handling, picker double-click, the Voice
   context menu, and Voice input guards. Capture its track identity when
   `AutomationCanvas` rebuilds the Voice strip; all later Voice paint, input,
   and commit work uses that captured identity instead of resolving the
   ambient primary track again. The node-lane stack born here is Tempo plus
   CC only: `laneAt(y)` returns a `LaneHandle` into that stack and does not
   name Voice. `VoiceChangeLane` owns its own body rect between Tempo and
   the first CC lane. Keep `DOC_CC_VOICE` and the existing core lane
   functions. Remove `EditorAutomationRowKind::Voice`, discard legacy
   `voice:<track>` sidecar row entries on load, and stop writing them. Once
   the mixed row owner contains only CC lanes, rename
   `automationrows.{h,cpp}` to `cclanes.{h,cpp}` and rename the view-model
   `AutoLane` type to `CcLane`. Update stale documentation and harnesses.
   Verify that no Voice paint, label-layout, hover, picker, menu, or input
   branch remains outside
   `VoiceChangeLane`; `VoiceChangeLane` contains no `primaryTrack()` call or
   other track re-resolution; a repository-wide search finds no
   `EditorAutomationRowKind::Voice` occurrence; and loading a legacy entry
   neither restores nor re-serializes it. Gate the phase with
   `automation-popup-menus`, `automation`, `host-seams`, and
   `mainwindow-routing`. Using the same fixture, geometry, theme, and device
   pixel ratio, the Voice segment-and-label canvas region must match its
   pre-phase capture pixel for pixel. Picker and menu checks must preserve the
   same trigger, contents and order, target, commit, and undo behavior; do not
   compare platform-rendered Qt dialog or menu chrome pixel for pixel.
3. **Hover parity.** Rename `AutomationHoverState` to `NodeLaneHoverState` and
   store only its `LaneHandle`; resolve the current lane from the stack and
   pass it as `const NodeLane&` when hover calculation needs points or value
   text. Start `nodelane/paint.{h,cpp}` with the shared hover chrome so this
   phase does not duplicate CC paint inside `TempoLane`. Delete Tempo's
   `m_hoveredPoint`, caption-only hover paint, and private hover-tracking
   branches while retaining hit testing still used by menus and gestures.
   Tempo gains the insertion line, held-BPM ghost, node ring, label cache, and
   dirty-bounds diffing used by CC. Hover reads the lane's body rect and
   value range through the static `valueY` / `valueAtY`, using the
   projection only for the time axis — the pattern `TempoLane` already
   runs. Grow the widget-level parity matrix with the hover and
   insertion-preview cases for both Tempo and CC. This phase also routes
   tempo-region mouse moves into the shared hover update: the tempo
   dispatch's early return becomes a lane-resolved hover call. That
   input-routing change is expected here, ahead of full input unification in
   phase 5. Gate the phase with `automation-gestures`, `automation`, and
   `rendering-playhead`.
4. **Paint ownership and unification.** Complete `nodelane/paint.{h,cpp}` by
   moving normal node curves, selection rings, and every active-gesture
   preview (node drag, sweep/ramp, and Pencil), including its value label, out
   of `automationpaint.*` and `automationpaintpreview.cpp` behind
   `paintNodeLane(painter, lane, leadIn, …)`. `leadIn` is an optional
   `(tick, value)` that is not a node: Tempo passes `{0, 120}` only when
   `points()` is non-empty and has no tick-0 point; empty Tempo and every CC
   lane pass none. Voice painting is already owned by
   `VoiceChangeLane` from phase 2; move true whole-page grid and selection
   chrome into `AutomationCanvas`. Delete `automationpaint.*` when those moves
   leave it empty, and delete `tempolanepaint.cpp` after moving its small
   header/collapse shell into `tempolane.cpp`. Tempo and CC must have no
   other lane-specific node-body paint path. Gate the phase with `automation` and
   `rendering-playhead`, then prove by source search that no Tempo- or CC-only
   node-body painter remains.
5. **Input and commit unification.** One input dispatcher resolves a
   `NodeLane` from the cursor (Voice is already excluded by hit-test) and runs
   the generic press/move/release logic; tempo's
   `mousePress` / `mouseMove` / `mouseRelease` / `mouseDoubleClick` handlers
   dissolve. Tempo gains Pencil with the unified dispatcher — Pencil belongs
   to every node lane — and that is intended new behavior from this plan,
   not a pre-existing behavior to preserve. Gesture `row` fields become
   `LaneHandle`; completions target the handle; `nodeDragGestureAt` /
   `collectSelectedNodeDrags` unify behind the `NodeLane` contract.
   `pointerMapping` becomes lane-keyed — grid cells
   from the page, value mapping from the lane — and with its last consumer
   gone, the row-keyed `AutomationProjection` members plus its rows vector
   and `topInset` constructor inputs are deleted; what remains is the time
   axis and the static `valueY` / `valueAtY`. Rename the now node-only
   gesture and Pencil files
   listed under **Naming**, and land the CC-only UI strings. Hover, paint,
   `cclanes`, and `CcLane` already have their final names from their owning
   earlier phases; do not defer those renames to this cleanup. Preserve the
   lane-stack-rebuild cancellation rule and run release-after-rebuild against
   both adapters: neither release may commit through the stale handle. Gate
   the phase with `automation-gestures`, `automation-popup-menus`, and
   `automation`. Then require a source-name scan to find no node-only
   implementation under an `automation*` leaf filename; only page-level
   cross-lane coordinators and persisted-state names may retain `automation`.

## Verification

Before phase 1, add a named-check selector to `tools/run_checks.ts` with this
form:

```sh
deno task checks build/porydaw_checks --only=check-a,check-b
```

Prove the selector runs exactly the requested names and rejects an unknown
name. Then run this untouched-branch baseline and require it to pass before
changing production code:

```sh
deno task checks build/porydaw_checks --only=automation-gestures,automation-popup-menus,automation,editor-drawer,mainwindow-routing,rendering-playhead,host-seams
```

During the migration, build after every phase and run only the focused checks
that exercise the automation drawer code changed by that phase:

| Phase | Focused checks |
|---|---|
| 0. NodeLane contract and matrix | `automation-gestures`, `automation`, `editor-drawer` |
| 1. Canvas rename and edit fold | `automation-gestures`, `automation`, `editor-drawer`, `mainwindow-routing`, `rendering-playhead` |
| 2. Voice Change extraction | `automation-popup-menus`, `automation`, `host-seams`, `mainwindow-routing` |
| 3. Hover parity | `automation-gestures`, `automation`, `rendering-playhead` |
| 4. Paint unification | `automation`, `rendering-playhead` |
| 5. Input and commit unification | `automation-gestures`, `automation-popup-menus`, `automation` |

Before phase 2 changes production code, use the phase 1 `automation` check
build and its screenshot output to retain an untracked baseline under
`build/check-artifacts/`. The phase 2 check renders the same fixture and crops
the Voice lane with the same resolved geometry, then compares the two `QImage`
pixel buffers exactly. Keep both captures as build artifacts, not repository
assets.

The pre-phase adds a direct `node-contract` domain to the existing
`automation-gestures` harness, detailed in the implementation order. It
calls both adapters through `NodeLane` without routing through
`AutomationCanvas` and verifies the resulting document data plus revision
and undo changes. This is the adapters' executable interface contract
before the widget path changes; every later phase must keep it green.

The widget-level automated acceptance gate lives in that same harness; do not
add another top-level check. Refactor the current separate Tempo and CC cases
into one table-driven NodeLane parity matrix. Run each synthetic pointer/key
sequence once against `TempoLane` and once against `CCLaneAdapter`:

- hover and insertion preview
- stationary-click delete
- node drag, including horizontal and vertical axis lock
- multi-node selection drag and delete
- sweep and Shift-ramp
- Pencil stroke — the Tempo half of this row first applies in phase 5, when
  the unified dispatcher delivers Pencil to the Tempo lane as intended new
  behavior
- right-drag band selection
- Escape cancellation, lane-stack-rebuild cancellation, and semantic no-op

For every scenario, both adapters must produce the same interaction-state
transitions and the same normalized node result. A completed gesture must
advance the document revision and undo index exactly once; a preview,
cancellation, or no-op must advance neither. Only the lane value range,
displayed value text, and commit back-end may differ. Add one negative case
proving `VoiceChangeLane` never enters a NodeLane gesture. Preserve the
pre-phase CC same-tick group case. Preserve the existing active-gesture
document refresh cancellation check and run that scenario against both
Tempo and CC;
release after the rebuild must not commit through the old handle.

Do not run unrelated checks between phases. After phase 5 and the source-name
cleanup check pass, run the full suite once as the final regression gate:

```sh
deno task checks build/porydaw_checks
```

Manual pass over the running app:

- Hover chrome identical on Tempo and CC lanes: insertion line,
  held-value ghost, node ring, value label.
- Node drag, sweep, ramp, pencil, band select, stationary delete, and
  selection drag behave identically on Tempo and CC; each gesture is one undo
  step.
- A moved fractional imported tempo point keeps its exact MIDI value. A
  fractional point displays as integer BPM — rounded, decimal discarded —
  while its stored microseconds stay exact.
- Tempo still paints first and collapses via its header. With no explicit
  points, its body is blank while playback uses the implicit 120 BPM default;
  save emits no Tempo event until the user creates one. A later first point
  still gets the node-free 120 BPM lead-in from `paintNodeLane`'s optional
  lead-in, not from a synthetic `points()` entry.
- Voice Change keeps its held-segment labels, double-click picker, and current
  context menu, with no node gestures added.
- A source-name check finds no node-only paint, hover, gesture, Pencil, edit,
  row, or adapter implementation left in an `automation*` leaf file. Remaining
  `automation*` files must belong to the page-level coordinator or persisted
  editor state named under **Naming**.

## Non-goals

- Unified core storage or a unified `SongDocumentEdit`
- Tempo re-entering the generic row list
- New track identity model or track-limit changes
- Event List changes
- New lane y-zoom or value-range UI
- New Voice Change sidecar state, persisted collapse state, or lane-height
  storage changes. Phase 2 only discards the obsolete persisted Voice-row
  entries.
