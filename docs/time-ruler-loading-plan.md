# Static Time Ruler During Song Loading

## Goal

Keep the time ruler continuously visible and as visually static as possible while a song loads asynchronously.

A new tab must immediately show the same ordinary musical ruler that a default song shows:

- standard ruler chrome and separator;
- pre-roll;
- bar and beat lines;
- bar labels;
- an implicit 4/4 signature;
- the normal default horizontal scale and camera home.

Loading must not show the `"No song loaded"` caption or replace the ruler with a loading-specific widget. Binding a default 4/4 song at default zoom must not move bar positions. A MIDI file's ticks-per-beat resolution alone must never change visual beat or bar positions.

## Problem

`MidiTimeline *` currently has two roles:

1. optional loaded song content;
2. required musical coordinate system.

When song content is unavailable, the coordinate system also disappears. That forces null-timeline behavior into camera, grid, and ruler code. Adding fallback branches independently to those callers would make the ruler visible, but it would preserve the wrong seam and scatter timing knowledge.

The internal camera also stores pixels per tick even though the user-visible invariant is pixels per beat. Pixels per tick necessarily changes when MIDI resolution changes, which makes resolution-dependent movement easy to introduce.

## Decision

Introduce an always-valid `TimeAxis` module owned by `SongView`, and make pixels per beat the canonical horizontal scale.

`TimeAxis` owns the musical-axis policy used by camera, grid, and ruler code. It has two states:

- **Fallback:** 24 ticks per beat, implicit 4/4, zero known content length, and no loop markers.
- **Bound:** borrows the immutable `MidiTimeline` and exposes its timebase, signatures, length, and loop markers.

Callers consume the same non-null `TimeAxis` interface in both states. Only note, event, tempo, playback, and document-editing behavior depends on the optional `MidiTimeline` or `SongDocument`.

This module passes the deletion test: removing it would force fallback rules, signature segmentation, and timing calculations back into multiple painters and camera callers.

Project-I/O staging follows `docs/view-sidecar-removal-plan.md` as the prerequisite authority: the view sidecar is deleted, `EditorViewState` is an application-global preference (not a camera or time-ruler preference), `pxPerBeat` and other `SongView::ViewState` fields remain transient per-tab, and `MidiStage` applies directly without waiting for a sidecar.

## Invariants

1. `SongView` always has a valid musical axis, including before its first `setSong()` call.
2. Fallback timing is defined once in `TimeAxis`: 24 ticks per beat, no explicit signature
   events, an implicit opening 4/4 signature, zero known content length, and no loop markers.
3. `m_pxPerBeat` is initialized from `Geometry::editorDefaultPixelsPerBeat` in the `SongView`
   constructor and remains the transient per-tab canonical horizontal scale
   (`EditorViewState` is application-global via `QSettings` but is not a camera or time-ruler
   preference).
4. Pixels per tick is always derived:

   ```cpp
   pxPerTick = m_pxPerBeat / m_timeAxis.ticksPerBeat();
   ```

5. Changing ticks per beat alone does not change beat or bar pixel positions.
6. The time ruler paints its structural layers without a bound timeline.
7. Song-specific overlays are painted only when their source state exists.
8. Loading keeps `SongView` enabled for normal painting and styling. Whether input is accepted is
   derived from the song-tab load facts, never from a separately mutable interaction flag: a
   SongTab-owned, descendant-aware input gate reads `SongTab::isReady()` and blocks user input
   without gating programmatic state application.
9. `SongTab::isReady()` is the single readiness representation and is derived, not stored:
   `m_midiBound && m_voicegroupBound`. The stored `m_ready` member is deleted. Both facts are
   written only by `SongTab`'s private load-event reducer (`ReloadDispatched`, `MidiBound`,
   `VoicegroupBound`), which compares the derived value before and after each event and emits
   `readinessChanged()` only when it changes. A full MIDI reload dispatches `ReloadDispatched`
   when `ReloadSongInput` is dispatched, not when `MidiStage` eventually arrives; a bank-only
   voicegroup rebind dispatches no load event, so readiness never drops.
10. A reload retains the current axis, camera, and in-memory `ViewState` until the replacement
    timeline is applied at `MidiStage`; `prepareForSongReplacement()` must not bind fallback.
11. A fresh open or reopened tab starts at canonical transient `ViewState` defaults, including
    the ordinary pre-roll camera home.
12. `WorkspaceUi` applies application-global `EditorViewState` when it creates a tab. `MidiStage`
    does not stage or reapply it.
13. No per-song view or editor state persists anywhere; loading, camera, and ruler state are
    transient and never written to disk.
14. No dummy `MidiTimeline`, ruler pixmap cache, loading ruler widget, or project-I/O transport
    change is introduced (project-I/O staging follows `docs/view-sidecar-removal-plan.md`).

## Target interface

Add a private song-view module under `src/ui/songview/`. It resolves fallback and bound musical
time without owning or copying timeline collections:

```cpp
class TimeAxis {
  public:
    struct GridSegment {
        uint64_t start = 0;
        uint64_t next = UINT64_MAX;
        uint64_t beatTicks = 24;
        uint64_t beatsPerBar = 4;
    };

    struct ResolvedTimeSignature {
        uint64_t tick = 0;
        int numerator = 4;
        int denomPow2 = 2;
        bool implicit = true;
    };

    using GridLineVisitor = std::function<void(uint64_t tick, bool isBar, int barNumber,
                                               int beatNumber)>;

    TimeAxis() noexcept;

    void bind(const MidiTimeline *timeline) noexcept;
    bool isBound() const noexcept;

    uint32_t ticksPerBeat() const noexcept;
    uint64_t lengthTicks() const noexcept;
    uint64_t loopStartTick() const noexcept;
    uint64_t loopEndTick() const noexcept;

    // Actual 0x58 events only. Fallback returns an empty span; storage remains
    // borrowed from the bound immutable timeline.
    std::span<const TimeSigPoint> explicitTimeSignatures() const noexcept;
    // True in fallback and whenever no actual signature governs tick zero.
    bool hasImplicitOpeningSignature() const noexcept;
    ResolvedTimeSignature signatureAt(uint64_t tick) const noexcept;

    GridSegment segmentAt(uint64_t tick) const noexcept;
    void forEachGridLine(uint64_t tickBegin, uint64_t tickEnd,
                         const GridLineVisitor &visitor) const;

  private:
    const MidiTimeline *m_timeline = nullptr;
};
```

`TimeAxis` owns fallback constants, normalized signature lookup, signature segmentation, bar
numbering, and beat/bar iteration. Same-tick explicit signature duplicates retain the existing
"last event wins" behavior. `hasImplicitOpeningSignature()` and `signatureAt()` are the only
places that synthesize implicit 4/4; `TimeRuler` must not infer fallback from an empty span.

Keep zoom- and editor-dependent subdivision in `SongView`: `gridTicksIn`, `gridTicksAt`,
`gridTicksAtScale`, `snapTicksAt`, `visibleGridCellContaining`, and the snap helpers depend on
`m_pxPerBeat`, document clock resolution, grid feel, minimum denominator, and geometry. Retain
the existing `SongView::GridSeg` name as an alias of `TimeAxis::GridSegment`, and make
`SongView::gridSegAt()` and `SongView::forEachGridLine()` thin facades over the owned axis so
existing child painters do not learn a second interface.

The module borrows the current immutable timeline instead of copying signature vectors.
`SongTab` continues to own the timeline lease. The existing paired-lifetime rule remains: the
view's borrow is changed before the owning timeline is released.

`SongView` owns:

```cpp
TimeAxis m_timeAxis;
double m_pxPerBeat;
const MidiTimeline *m_timeline = nullptr; // loaded content only
```

Initialize `m_pxPerBeat` from the already-resolved `m_geometry.editorDefaultPixelsPerBeat` in the
`SongView` constructor. Keep one derived accessor:

```cpp
double SongView::pxPerTick() const noexcept
{
    return m_pxPerBeat / double(m_timeAxis.ticksPerBeat());
}
```

`contentX()`, `tickAtContentX()`, and every rendering or camera calculation consume this accessor.
Do not store a second mutable horizontal scale.

## Ruler paint layers

Rewrite `TimeRuler::paintEvent()` as one ordered structural path.

Always paint:

1. background chrome;
2. separator;
3. pre-roll;
4. bar lines;
5. beat lines;
6. bar labels;
7. signature chips resolved by `TimeAxis` — implicit opening 4/4 in fallback, then the
   implicit/explicit opening and actual changes of a bound song.

The gutter grid controls are always-present child widgets, not paint layers. They remain visible
and normally styled while the interaction gate makes them inert.

Paint only when loaded song state exists:

1. loop brackets and band;
2. selection;
3. edit cursor;
4. drag previews.

Remove the null-timeline early return and the `"No song loaded"` caption. There must be one ruler
renderer, not a fallback renderer beside the existing one.
## Interaction seam

`SongTab` currently calls `m_view->setEnabled(false)` while loading and `m_view->setEnabled(true)`
in `updateReadiness()`. That couples input readiness to presentation, changes child-control
enabled styling, and keeps two independent readiness sources (the widget's enabled bit and a
stored `m_ready`) that must be hand-synchronized.

Replace them with one derived source and one mutation seam. `SongTab` keeps its two load facts —
`m_midiBound` and `m_voicegroupBound` — and derives `isReady()` from them
(`m_midiBound && m_voicegroupBound`); the stored `m_ready` member is deleted. A private reducer,
`SongTab::applyLoadEvent(LoadEvent)`, is the only code that writes either fact and the only code
that emits readiness. It takes one semantic event — `ReloadDispatched`, `MidiBound`, or
`VoicegroupBound` — applies that event's fact transition, compares `isReady()` before and after,
and emits `readinessChanged()` automatically only when the derived value changed. The stage
handlers (`beginMidiReload()`, `applyMidiStage()`, `applyVoicegroupBound()`) dispatch exactly one
semantic event and neither mutate a fact nor emit readiness themselves; there is no
`updateReadiness()` and no remembered `emit` beside a fact write.

`SongView` stays enabled. Because `SongTab` already owns both the view subtree and the readiness
facts, `SongTab` owns the descendant-aware input gate: a small `QObject` event filter held as a
`SongTab` member and installed recursively on `m_view` and its descendant `QObject` tree after
construction. The gate holds a non-owning `SongTab *` back-pointer and, on every user-input event,
reads `m_tab->isReady()` directly — no predicate is injected into the view, and `SongView`
exposes no readiness or interaction interface at all. The gate handles `QEvent::ChildAdded` on
every watched object and installs itself on the added subtree, so later-created descendants cannot
escape the gate; installing a filter only on `SongView` is insufficient because child input events
do not bubble to the parent.

`SongTab` connects its `readinessChanged()` signal to the gate's reaction slot. That slot is the
only place the gate reacts to a state change, and only for the ready-to-not-ready transition: it
re-reads `isReady()` and, when it is now false, invokes `SongView::cancelTransientInput()`, a
narrow one-shot operation that cancels active gestures and previews, closes an active popup owned
by the subtree, and clears subtree focus. It sets no persistent state. A not-ready-to-ready
transition is a no-op: input is neither synthesized nor replayed. Gating itself never consults the
signal — it always reads `isReady()` — so cancellation is a consequence of observing a dropped
fact, never a toggled source of truth.

While `isReady()` is false, the gate consumes user-originated mouse press/release/move,
double-click, wheel, context-menu, key press/release, shortcut/shortcut-override, input-method,
focus-in, tablet, touch, and gesture events for the SongView subtree. Paint, layout, resize, timer,
model, child-management, and programmatic state-update events continue normally.

The fixed coverage list is:

- `TimeRuler`, including marker/signature editing, wheel navigation, and both grid combo boxes;
- `PianoRoll`, `EventListView`, and `OtherStrip`;
- track headers and their inline editors;
- automation, velocity, and voice-change drawer surfaces and controls;
- horizontal and vertical scrollbars;
- SongView keyboard editing, shortcuts, and focus-entry helpers.

Do not scatter `if (!isReady())` branches through geometry or paint code, and do not mirror
readiness into the view. Programmatic `applyViewState()`, `applyEditorViewState()`, song binding,
and staged-load updates remain available while user input is gated. The Qt review in Step 7 must
reject any uncovered loading-reachable input surface.

## State transitions

Project-I/O staging follows `docs/view-sidecar-removal-plan.md` as the prerequisite authority.
MIDI applies directly at `MidiStage` without waiting for a sidecar stage.

### New tab

- Construct `SongView` with fallback `TimeAxis` and
  `m_pxPerBeat = m_geometry.editorDefaultPixelsPerBeat`.
- After the child scrollbars exist, initialize the fallback camera with
  `setHScroll(minHScroll())`.
- In fallback, `minHScroll()` returns `-leadPadPx()`, `maxHScroll()` returns `0`, and
  `updateScrollbars()` keeps the provisional camera at `minHScroll()` as resize changes the lead
  pad. A fresh view therefore paints pre-roll before `setSong()`.
- Initialize the remaining canonical transient `ViewState` defaults: default key height,
  clock-grid floor, straight feel, and event list off.
- Paint the implicit 4/4 ruler immediately.
- Input starts inert because `isReady()` is false: `m_midiBound` and `m_voicegroupBound` default
  false, so the gate reads not ready until both stages land.

### Fresh song load

- Retain the fallback ruler while `MidiStage` and voicegroup stages arrive.
- `WorkspaceUi::createTab()` has already applied the current application-global
  `EditorViewState`; this feature must not apply it again in `SongTab` or `MidiStage`.
- MIDI resolution does not alter visual beat spacing because `m_pxPerBeat` remains transient
  per-tab and canonical for horizontal geometry.
- When `MidiStage` arrives, `applyMidiStage()` binds the new timeline, applies canonical
  transient `ViewState` defaults and camera home, and dispatches the `MidiBound` load event; the
  reducer sets `m_midiBound` true, leaving `isReady()` false because `m_voicegroupBound` is still
  false, so input stays inert.
- `isReady()` becomes true only when the terminal `VoicegroupBound` makes `applyVoicegroupBound()`
  dispatch `VoicegroupBound`, so the reducer sets `m_voicegroupBound` and emits
  `readinessChanged()`; the gate's reaction is a no-op and input is simply no longer gated. No
  enable call is made.

### Reload or replacement

- Immediately before dispatching a full `ReloadSongInput`, `WorkspaceUi` calls
  `SongTab::beginMidiReload()`. That method captures the complete live `ViewState` into
  `m_pendingReloadState` and dispatches the `ReloadDispatched` load event; the reducer clears
  `m_midiBound` and `m_voicegroupBound`, so `isReady()` drops immediately, and emits
  `readinessChanged()`. The gate reacts to that ready-to-not-ready transition by cancelling active
  gestures, previews, popups, and focus. `beginMidiReload()` does not change the timeline,
  `TimeAxis`, camera, or the old voicegroup lease/identity. The owner publishes the existing
  selected-song-state notification so window actions follow readiness. The bank-only voicegroup
  rebind path does not call this method.
- Retain the old timeline lease, axis, ruler, camera, and captured state while replacement stages
  are in flight.
- `prepareForSongReplacement()` disconnects the document when `MidiStage` arrives, but must not
  call `TimeAxis::bind(nullptr)` or otherwise replace the retained ruler with fallback state.
- `SongTab::applyMidiStage()` consumes `m_pendingReloadState` (absent only on a fresh open, which
  uses canonical defaults instead), binds the replacement timeline via `setSong()`, reapplies the
  complete transient `ViewState` atomically, and dispatches the `MidiBound` load event; the
  reducer sets `m_midiBound` true while `m_voicegroupBound` stays false, so `isReady()` remains
  false.
- The new timeline local owns the replacement while the view borrow is changed; only then may the
  old member-owned timeline lease be released.
- `isReady()` stays false until the terminal `VoicegroupBound` makes `applyVoicegroupBound()`
  dispatch `VoicegroupBound`, which the reducer turns into `m_voicegroupBound = true` and
  `readinessChanged()`; the gate's reaction is a no-op and input is no longer gated. A fatal
  full-load failure follows the existing close-tab path, so no stale loading tab ever re-derives
  readiness true.

### Close and reopen

- Closing destroys the tab-local axis, camera, and transient `ViewState`.
- Reopening creates a fresh tab at canonical transient `ViewState` defaults and pre-roll home with
  the current application-global `EditorViewState`; no per-song view state is loaded or persisted.

## Implementation plan

Execution must use workflowz. Each step has an explicit agent role. Shared-file edits are serialized through one integration owner. Agents skip project-wide formatters and verification; the integration owner runs those once at the named verification points.

### Step 1 — Establish focused regression coverage

**Role:** `task` implementation agent

Files:

- new `src/checks/rollcheck/loading_ruler.cpp`;
- `src/checks/rollcheck/rollcheck.h` for the scenario declaration;
- top-level `src/checks/rollcheck.cpp` for runner invocation — do not create
  `src/checks/rollcheck/rollcheck.cpp`;
- `CMakeLists.txt` for `porydaw_checks` source registration;
- `src/checks/mainwindowroutingcheck.cpp` for staged full-reload readiness.

Add `runLoadingRulerScenarios(Harness &check)` and invoke it from the existing top-level runner.
The fresh-view portion constructs a bare `SongView` directly rather than using
`SongViewRig::create()`, because that factory binds a timeline before returning. Resize and show
the view, locate its actual `TimeRuler`, and exercise observable geometry/raster behavior before
the first `setSong()`.

Use synthetic default `MidiTimeline` values for the resolution comparison: 24 TPB and 48 TPB,
equivalent musical length, empty explicit signature lists, and otherwise identical state. Compare
beat and bar pixel positions through public SongView geometry and the actual ruler render path.

Add checks that fail against current behavior:

- a fresh `SongView` paints ruler bar and beat content before `setSong()`;
- the loading caption is absent;
- fallback reports an implicit opening 4/4 while explicit signature storage remains empty;
- default 4/4 binding preserves sampled bar positions pixel-for-pixel;
- 24-TPB and 48-TPB default timelines produce identical beat and bar positions;
- non-4/4 input changes only signature-dependent grid positions;
- ruler, grid controls, scrollbars, roll, headers, strip, event list, and drawer input are inert
  before readiness while paint and programmatic state application still work;
- the loading camera starts at normal pre-roll home and remains there after resize;
- a full reload becomes non-interactive when dispatched, retains its old ruler/camera before
  `MidiStage`, and restores the captured state after binding;
- a bank-only voicegroup rebind does not enter full MIDI loading state.

Verify with the focused `rollcheck` and `mainwindow-routing` filters. Do not weaken existing
scenarios.

### Step 2 — Implement the `TimeAxis` module

**Role:** `task` implementation agent

Files:

- `src/ui/songview/timeaxis.h`;
- `src/ui/songview/timeaxis.cpp`;
- `src/ui/songview/grid.cpp`;
- `src/ui/songview/detail.cpp`;
- `src/ui/songview.h`;
- `CMakeLists.txt`.

Move fallback timebase, implicit/explicit signature resolution, signature segmentation,
grid-segment resolution, and bar/beat iteration behind `TimeAxis`. Reuse the exact existing
same-tick signature, bar-number, and grid behavior rather than creating a parallel implementation.
Keep zoom- and editor-dependent subdivision in `SongView` as specified by the target interface.

Replace the three timeline-less `return 24` branches in `gridTicksAt`, `gridTicksAtScale`, and
`snapTicksAt` with normal `TimeAxis::segmentAt()` input, and replace
`forEachGridLine()`'s null-timeline early return with the axis-backed iteration. In
`detail.cpp`, remove `drawGrid()`'s null-timeline guard so the fallback grid paints; retain
`drawOverlays()`'s timeline guard because loops, selections, and cursors are loaded-song overlays.
`detail.h::forEachSubGridLine` continues through the SongView grid facade.

Acceptance:

- fallback values and implicit-signature policy appear in one implementation location;
- grid and ruler geometry no longer branches on `timeline() == nullptr`;
- no copied timeline collections or owning pointer enters `SongView`;
- subdivision still has one owner and does not migrate into `TimeAxis`;
- existing loaded-song grid behavior remains unchanged.

### Step 3 — Canonicalize horizontal scale and camera home

**Role:** `task` implementation agent

Files:

- `src/ui/songview.h`;
- `src/ui/songview.cpp`;
- `src/ui/songview/camera.cpp`;
- grid/rendering callers that directly consume the old stored `m_pxPerTick`.

Replace stored `m_pxPerTick` with stored `m_pxPerBeat`, initialized in the `SongView` constructor
from `m_geometry.editorDefaultPixelsPerBeat`. Preserve only the derived `pxPerTick()` accessor.
Update `contentX()`, `tickAtContentX()`, zoom anchoring, `setEditorTimeZoom()`, scrollbar limits,
`ensureTickVisible()`, `ensureRangeVisible()`, view-state capture/application, visibility
calculations, and every direct old-field consumer.

`rebuildAfterSongChange()` must not derive and store a new scale from timeline resolution.
Fresh-song defaults come from the constructor/default `ViewState`; reload zoom comes from the
captured `ViewState`. Binding a timeline changes the derived tick scale but never the canonical
beat scale.

For a timeline-less fresh view:

- `minHScroll()` returns `-leadPadPx()`;
- `maxHScroll()` returns `0`;
- after scrollbars exist, construction initializes `m_scrollX` to `minHScroll()`;
- while `TimeAxis::isBound()` is false, resize/update-scrollbar work keeps the provisional camera
  at the newly resolved `minHScroll()`;
- once bound, normal camera movement and loaded-song limits apply.

Acceptance:

- `pxPerBeat` remains transient per-tab and canonical for horizontal geometry;
- ticks-per-beat changes cannot alter beat spacing by construction;
- no second mutable scale remains;
- fallback construction and resize paint pre-roll at the normal home;
- in-memory view-state capture and reload restore zoom semantics in pixels per beat without any
  view sidecar;
- loaded-song camera limits and zoom bounds remain unchanged.

### Step 4 — Review the coordinate-system cutover

**Role:** `thermo-nuclear-reviewer`

Review Steps 2–3 against this plan and the project-I/O staging contract in `docs/view-sidecar-removal-plan.md`. Treat these as blockers:

- fallback constants or time-signature formulas remain scattered;
- `TimeAxis` is a shallow pass-through;
- camera and axis establish competing scale authorities;
- cyclomatic complexity grows through repeated fallback branches;
- timeline data is copied unnecessarily;
- raw borrowed state can outlive the owning `SongTab` timeline;
- files cross the repository's size/cohesion thresholds without a justified split.

The integration owner resolves all blocking findings before continuing.

### Step 5 — Rewrite ruler painting into layers

**Role:** `task` implementation agent

Files:

- `src/ui/songview/timeruler.cpp`;
- `src/ui/songview/timeruler_paint.cpp`;
- `src/ui/songview/timeruler.h` if the resolved axis interface requires it;
- `src/ui/songview/detail.cpp`.

Remove the caption and null-timeline return. Paint structural ruler layers from `TimeAxis`. Route
`sigChips()`, `sigAtTick()`, signature hit-testing, and grid iteration through the resolved axis
interface; no direct `timeline()->timeSigs` dereference remains. Build the implicit opening chip
only from `hasImplicitOpeningSignature()`, then iterate `explicitTimeSignatures()` for actual
chips. Gate only overlays whose song-specific state is absent.

The grid combos are child widgets, not a paint layer: they stay visually present and normally
styled while the interaction gate makes them inert.

Acceptance:

- a fresh view and default loaded view use the same painter path;
- implicit 4/4 uses the same chip layout and collision rules as actual signatures while retaining
  its `implicit` presentation flag;
- `drawGrid()` uses fallback axis geometry and `drawOverlays()` remains loaded-state gated;
- no loading-only widget, renderer, or pixmap cache exists;
- paint complexity remains layered and linear rather than nested by loading state.

### Step 6 — Reduce load facts into derived readiness

**Role:** `task` implementation agent

Files:

- `src/ui/songtab.h`;
- `src/ui/songtab.cpp`;
- `src/ui/songview.h`;
- `src/ui/songview.cpp`;
- `src/ui/songview/timeruler.cpp` only if cancelling an active grid-control popup requires a
  narrow helper;
- `src/ui/workspaceui_tabs.cpp`;
- `src/checks/mainwindowroutingcheck.cpp`.

Delete the stored `SongTab::m_ready` member and derive `isReady()` as
`m_midiBound && m_voicegroupBound`. Introduce a private load-event reducer as the single mutation
seam:

```cpp
enum class LoadEvent { ReloadDispatched, MidiBound, VoicegroupBound };
void SongTab::applyLoadEvent(LoadEvent event);
```

`applyLoadEvent()` is the only code that writes `m_midiBound` or `m_voicegroupBound` and the only
code that emits `readinessChanged()`. It captures `isReady()` before the event, applies the one
fact transition the event names (`ReloadDispatched` clears both, `MidiBound` sets `m_midiBound`,
`VoicegroupBound` sets `m_voicegroupBound`), and emits `readinessChanged()` only when the derived
value changed. Delete `updateReadiness()`; there is no separate enable/disable step and no
remembered `emit` beside a fact write.

Add `SongTab::beginMidiReload()` and `std::optional<SongView::ViewState> m_pendingReloadState`.
`beginMidiReload()` captures the complete live `ViewState` into `m_pendingReloadState` (leaving the
timeline lease, axis, camera, and `m_voicegroupId` untouched) and dispatches `ReloadDispatched`.
`WorkspaceUi` calls it immediately before dispatching a full in-place `ReloadSongInput`, and
publishes the readiness change so window actions stop targeting the old document. Do not call it
from the bank-only `startVoicegroupRebind()` path, which dispatches no load event.
`applyMidiStage()` consumes `m_pendingReloadState`, rebinds the replacement timeline, reapplies
the transient `ViewState`, and dispatches `MidiBound`; `applyVoicegroupBound()` sets the identity
and dispatches `VoicegroupBound`. Neither handler writes a fact or emits readiness itself.

Replace the whole-widget enable/disable lockstep with a SongTab-owned descendant-aware input gate.
The gate is a private `QObject` event filter member of `SongTab`, holds a non-owning `SongTab *`,
and is installed recursively on `m_view` and its descendant `QObject` tree after construction; it
handles `QEvent::ChildAdded` on every watched object to install itself on the added subtree. On
every user-input event it reads `m_tab->isReady()` directly and consumes the event when false. It
connects to `readinessChanged()` and, only on the ready-to-not-ready transition (re-reading
`isReady()`), calls a new `SongView::cancelTransientInput()` — a one-shot cleanup that cancels
active gestures and previews, closes an owned popup, and clears subtree focus, setting no
persistent state. `SongView` exposes no readiness or interaction setter; `setEnabled` is never
called in the load path.

Audit the fixed coverage list rather than adding defensive checks to unrelated editor logic.
Programmatic projection/state application must remain functional while user input is gated.

Acceptance:

- structural ruler and child-control visuals do not change across readiness transitions;
- `applyLoadEvent()` is the only writer of both facts and the only readiness emitter; no
  `updateReadiness()`, stored `m_ready`, view-side mirror, or enable/disable call remains;
- fresh loading and the entire full-reload interval cannot mutate or navigate retained state;
- bank-only rebind dispatches no load event, remains interactive, and does not disturb the camera;
- normal loaded-song input behavior remains unchanged.

### Step 7 — Verify staged-load transitions

**Role:** `qt-cpp-reviewer`

Review QObject lifetime, gate/filter ownership and removal, focus behavior, borrow lifetime, staged
application ordering, and paint/input separation. Confirm:

- `TimeAxis` cannot retain a dangling timeline borrow;
- replacement ordering repoints both `m_timeline` and `TimeAxis` before the old timeline lease is
  released;
- full reload drops `isReady()` at dispatch — the reducer emits `readinessChanged()` and the gate
  cancels transient input via `cancelTransientInput()` as a consequence — while retaining the old
  bound axis until `MidiStage`; no enabled bit or interaction flag is stored anywhere;
- bank-only rebind never enters the full-reload gate and dispatches no load event;
- the gate holds only a non-owning `SongTab *` and reads `isReady()` directly, never storing a
  mutable interaction flag, and its lifetime is bound to `SongTab` (which owns the view), with Qt
  removing the filter when any watched object is destroyed;
- the gate's `ChildAdded` handling installs itself on every later-created descendant and the event
  filter blocks no paint, resize, timers, or programmatic state application;
- active popups, focus, gestures, and queued input cannot leak across a readiness transition;
- repaint requests do not introduce reentrant state mutation.

The integration owner resolves all correctness findings before final verification.

### Step 8 — Focused behavioral verification

**Role:** `task` integration owner

Run:

```sh
deno task format --check <changed-files>
deno task verify --filter rollcheck --verbose
deno task verify --filter mainwindow-routing --verbose
```

Use the actual registered filter names if they differ. `rollcheck` must cover fallback geometry,
rendering, and subtree interaction. `mainwindow-routing` must cover dispatch-time full-reload
gating, retained pre-stage ruler/camera, post-stage restoration, fresh-tab readiness, and the
bank-only rebind exception without changing project-I/O transport.

Launch the built application through the repository-supported `deno task` build flow. Open a song
through the asynchronous path and visually inspect the actual native window:

- fallback ruler and pre-roll visible immediately;
- no caption flash;
- grid controls retain normal styling but accept no input before readiness;
- default song binding causes no bar movement;
- full reload becomes inert immediately while retaining ruler and camera;
- non-default signature changes only signature-dependent layers.

Capture and inspect the native macOS application window if direct visual comparison is needed.

### Step 9 — Final architecture and complexity review

**Role:** `thermo-nuclear-reviewer`

Review the complete change for intent alignment, cyclomatic complexity, file cohesion, duplication, and deletion-test depth. Reject:

- a second loading renderer;
- scattered fallback branches;
- song-loading policy entering painter code;
- multiple mutable zoom representations;
- unexplained guards or over-protected code;
- unrelated piano-roll or project-I/O changes;
- tests coupled to implementation text rather than observable behavior.

Resolve all blockers, rerun affected focused checks, then run:

```sh
deno task verify
```

## Verification matrix

| Contract | Evidence |
|---|---|
| Fresh view paints a complete ruler and pre-roll home | Bare-view rollcheck geometry/raster scenario and native window inspection |
| Loading caption is gone | Paint scenario plus native window inspection |
| Fallback signature is resolved implicit 4/4 | `TimeAxis` signature scenario and ruler chip raster/hit-test |
| Default load does not move bars | Pixel-position assertions before and after binding |
| TPB alone cannot move beats | Equivalent synthetic 24-TPB and 48-TPB geometry scenario |
| Non-4/4 changes only signature-dependent geometry | Focused signature-grid comparison |
| Input inertness is derived from `isReady()`, not a stored flag | Descendant-surface input scenario before and after readiness |
| No imperative toggle, remembered `emit`, or mirrored readiness bit | Qt/C++ specialist review of the reducer and load path |
| Full reload gates at dispatch and retains state | Main-window routing staged-load scenario |
| Bank-only rebind remains interactive | Main-window routing rebind scenario |
| Reload restores current ruler and camera | Main-window routing post-`MidiStage` scenario and native smoke |
| Borrow and event-filter lifetimes are safe | Qt/C++ specialist review |
| No architectural fallback duplication | Final thermo-nuclear review |
| Existing behavior remains intact | Full `deno task verify` |

## Non-goals

- Project-I/O transport or ownership redesign (project-I/O staging and sidecar removal are
  governed by `docs/view-sidecar-removal-plan.md`).
- A separate loading presentation module.
- An imperative interaction toggle (`setInteractionEnabled`, `applyReadiness`, or whole-widget
  `setEnabled` during load), a remembered readiness `emit`, or a view-side readiness interface:
  input readiness is derived from load facts by the reducer and consumed by a SongTab-owned gate,
  never manually switched.
- Dummy MIDI data.
- Ruler image caching.
- Piano-roll note, velocity, automation, or playback behavior changes outside the loading input
  gate.
- Reading, writing, migrating, or introducing any view or editor sidecar (`ViewState` is transient per-tab; `EditorViewState` is application-global via `QSettings`).
- Persisting loading-placeholder or camera state.

## Completion criteria

The work is complete only when:

1. all geometry and structural paint consumers use the always-valid axis seam;
2. fallback signature synthesis exists only in `TimeAxis`;
3. `m_pxPerBeat` is initialized and stored as the transient per-tab canonical horizontal scale
   with no secondary mutable scale;
4. a fresh unbound view paints the ordinary pre-roll home, and resolution-only changes do not move
   beats or bars;
5. the loading caption and null-timeline ruler/grid exits are deleted while loaded-only overlay
   gates remain;
6. input readiness is derived from `isReady()` — a pure function of `m_midiBound` and
   `m_voicegroupBound` with the stored `m_ready` deleted — and mutated only by the private
   `applyLoadEvent()` reducer, which emits `readinessChanged()` solely on change; a SongTab-owned
   descendant-aware gate reads `isReady()` directly and blocks every fixed input surface with no
   stored interaction flag, no view-side readiness interface, and no enable/disable call;
7. full reload dispatches `ReloadDispatched` at dispatch (dropping the derived readiness),
   retains the old axis/camera until `MidiStage`, and restores the captured state; bank-only
   rebind dispatches no load event and stays outside that path;
8. global `EditorViewState` remains owned and pre-applied by `WorkspaceUi`, with no new staging or
   persistence;
9. focused checks, native application verification, specialist reviews, and the full verification
   suite pass;
10. no blocking reviewer finding remains.
