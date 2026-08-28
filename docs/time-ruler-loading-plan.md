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

## Invariants

1. `SongView` always has a valid musical axis, including before its first `setSong()` call.
2. Fallback timing is defined once: 24 ticks per beat and implicit 4/4.
3. `m_pxPerBeat` is the canonical horizontal scale.
4. Pixels per tick is always derived:

   ```cpp
   pxPerTick = m_pxPerBeat / m_timeAxis.ticksPerBeat();
   ```

5. Changing ticks per beat alone does not change beat or bar pixel positions.
6. The time ruler paints its structural layers without a bound timeline.
7. Song-specific overlays are painted only when their source state exists.
8. Loading disables interaction without disabling the whole `SongView` presentation.
9. A reload retains the current axis and camera until the replacement timeline and sidecar are applied.
10. A newly opened tab starts at the ordinary pre-roll camera home.
11. Loading state is not persisted as a song sidecar snapshot.
12. No dummy `MidiTimeline`, ruler pixmap cache, loading ruler widget, or project-I/O change is introduced.

## Target interface

Add a private song-view module under `src/ui/songview/`:

```cpp
class TimeAxis {
  public:
    TimeAxis() noexcept;

    void bind(const MidiTimeline *timeline) noexcept;

    uint32_t ticksPerBeat() const noexcept;
    uint64_t lengthTicks() const noexcept;
    std::span<const TimeSigPoint> timeSignatures() const noexcept;
    uint64_t loopStartTick() const noexcept;
    uint64_t loopEndTick() const noexcept;

    GridSegment segmentAt(uint64_t tick) const;
    void forEachGridLine(/* existing grid callback inputs */) const;

  private:
    const MidiTimeline *m_timeline = nullptr;
};
```

The final names and callback types should follow the existing grid types. The interface must remain small: callers ask for resolved musical-axis behavior rather than reimplementing fallback or signature rules.

The module should borrow the current immutable timeline instead of copying signature vectors. `SongTab` continues to own the timeline lease. The existing paired-lifetime rule remains: the view's borrow is changed before the owning timeline is released.

`SongView` owns:

```cpp
TimeAxis m_timeAxis;
double m_pxPerBeat;
const MidiTimeline *m_timeline = nullptr; // loaded content only
```

Keep a derived accessor where current rendering code needs tick scale:

```cpp
double SongView::pxPerTick() const noexcept
{
    return m_pxPerBeat / double(m_timeAxis.ticksPerBeat());
}
```

Do not store a second mutable horizontal scale.

## Ruler paint layers

Rewrite `TimeRuler::paintEvent()` as ordered layers.

Always paint:

1. background chrome;
2. separator;
3. gutter controls;
4. pre-roll;
5. bar lines;
6. beat lines;
7. bar labels;
8. the implicit or actual signature chips available from `TimeAxis`.

Paint only when loaded song state exists:

1. non-default time-signature changes;
2. loop brackets;
3. selection;
4. edit cursor;
5. drag previews.

Remove the null-timeline early return and the `"No song loaded"` caption. There must be one ruler renderer, not a fallback renderer beside the existing one.

## Interaction seam

`SongTab` currently uses whole-widget `setEnabled(false)` while loading. That couples input readiness to presentation and changes child-control enabled styling.

Replace it with a narrow `SongView::setInteractionEnabled(bool)` interface:

- `SongView` and `TimeRuler` continue to paint normally;
- ruler editing, grid controls, selection, scrolling, and editor gestures are inert while loading;
- reload cannot edit or navigate retained old state;
- readiness enables interaction without changing structural ruler presentation.

Interaction entry points must use the explicit interaction state or require a bound document. Musical geometry must not use interaction readiness as an availability test.

## State transitions

### New tab

- Construct `SongView` with fallback `TimeAxis`.
- Initialize `m_pxPerBeat` from the normal editor default.
- Initialize horizontal scroll to `-leadPadPx()`.
- Paint the implicit 4/4 ruler immediately.
- Keep interaction disabled.

### Fresh song load

- Retain the fallback ruler while MIDI, sidecar, and voicegroup stages arrive.
- MIDI resolution does not alter visual beat spacing because `m_pxPerBeat` remains canonical.
- When the coalesced MIDI and sidecar state is applied, bind the new timeline and apply saved view state atomically.
- Enable interaction only after the existing readiness requirements are satisfied.

### Reload or replacement

- `prepareForSongReplacement()` cancels transient interactions and disconnects the document.
- Retain the old axis and camera while replacement stages are in flight.
- Do not clear or replace the ruler with fallback state.
- Bind the replacement timeline and apply its sidecar together at the existing staged-load seam.

### Close and reopen

- Closing destroys the tab-local axis and camera.
- Reopening the same song creates a fresh tab at the normal pre-roll home unless its persisted sidecar supplies song view state.

## Implementation plan

Execution must use workflowz. Each step has an explicit agent role. Shared-file edits are serialized through one integration owner. Agents skip project-wide formatters and verification; the integration owner runs those once at the named verification points.

### Step 1 — Establish focused regression coverage

**Role:** `task` implementation agent

Files:

- `src/checks/rollcheck/` focused ruler/grid/camera scenario files;
- `src/checks/rollcheck/rollcheck.h` and `src/checks/rollcheck/rollcheck.cpp` only if scenario registration requires them;
- `CMakeLists.txt` only when adding a new scenario source.

Add checks that fail against current behavior:

- a fresh `SongView` paints ruler bar and beat content before `setSong()`;
- the loading caption is absent;
- default 4/4 binding preserves sampled bar positions pixel-for-pixel;
- 24-TPB and 48-TPB default timelines produce identical beat and bar positions;
- non-4/4 input changes only signature-dependent grid positions;
- ruler interaction is inert before a real document and timeline are bound;
- the loading camera starts at normal pre-roll home.

Verify with the focused rollcheck filter. Do not weaken existing scenarios.

### Step 2 — Implement the `TimeAxis` module

**Role:** `task` implementation agent

Files:

- `src/ui/songview/timeaxis.h`;
- `src/ui/songview/timeaxis.cpp`;
- `src/ui/songview/grid.cpp`;
- `src/ui/songview.h`;
- `CMakeLists.txt`.

Move fallback timebase, signature segmentation, grid-segment resolution, and grid-line iteration behind `TimeAxis`. Reuse existing grid behavior rather than creating a parallel implementation.

Acceptance:

- fallback values appear in one implementation location;
- grid and ruler callers no longer branch on `timeline() == nullptr` to obtain musical geometry;
- no copied timeline collections or owning pointer enters `SongView`;
- existing loaded-song grid behavior remains unchanged.

### Step 3 — Canonicalize horizontal scale and camera home

**Role:** `task` implementation agent

Files:

- `src/ui/songview.h`;
- `src/ui/songview.cpp`;
- `src/ui/songview/camera.cpp`;
- grid/rendering callers that directly consume the old stored `m_pxPerTick`.

Replace stored `m_pxPerTick` with stored `m_pxPerBeat`. Preserve a derived `pxPerTick()` accessor where needed. Update coordinate conversion, zoom, scrollbar limits, view-state capture/application, and visibility calculations to use the canonical scale.

For a timeline-less fresh view:

- `minHScroll()` returns `-leadPadPx()`;
- resize keeps the provisional camera at that home;
- `maxHScroll()` may remain `0` while content length is unknown.

Acceptance:

- ticks-per-beat changes cannot alter beat spacing by construction;
- no second mutable scale remains;
- existing sidecar zoom semantics remain pixels per beat;
- loaded-song camera limits and zoom bounds remain unchanged.

### Step 4 — Review the coordinate-system cutover

**Role:** `thermo-nuclear-reviewer`

Review Steps 2–3 against this plan and the project-I/O ownership contract. Treat these as blockers:

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
- `src/ui/songview/timeruler.h` if the resolved axis interface requires it.

Remove the caption and null-timeline return. Paint structural ruler layers from `TimeAxis`. Gate only overlays whose song-specific state is absent.

Acceptance:

- a fresh view and default loaded view use the same painter path;
- implicit 4/4 chip layout uses the same chip layout and collision rules as actual signatures;
- no loading-only widget, renderer, or pixmap cache exists;
- paint complexity remains layered and linear rather than nested by loading state.

### Step 6 — Separate interaction from presentation readiness

**Role:** `task` implementation agent

Files:

- `src/ui/songview.h`;
- `src/ui/songview.cpp`;
- `src/ui/songview/timeruler_interaction.cpp`;
- other SongView interaction entry points reached while loading;
- `src/ui/songtab.cpp`;
- `src/ui/songtab.h` only if state storage requires it.

Add the explicit interaction gate and replace loading-time whole-widget disabling. Audit every loading-reachable interaction entry point. Do not add defensive checks to unrelated editor logic.

Acceptance:

- structural ruler visuals do not change because the parent widget becomes disabled;
- loading and reload gestures cannot mutate retained state;
- readiness changes interaction only;
- normal loaded-song input behavior remains unchanged.

### Step 7 — Verify staged-load transitions

**Role:** `qt-cpp-reviewer`

Review QObject lifetime, widget enabled/focus behavior, borrow lifetime, staged application ordering, and paint/input separation. Confirm:

- `TimeAxis` cannot retain a dangling timeline borrow;
- replacement ordering updates the borrow before the old timeline lease is released;
- disabled interaction cannot leak through child widgets or queued input;
- repaint requests do not introduce reentrant state mutation;
- no focus behavior regresses when readiness changes.

The integration owner resolves all correctness findings before final verification.

### Step 8 — Focused behavioral verification

**Role:** `task` integration owner

Run:

```sh
deno task format --check <changed-files>
deno task verify --filter rollcheck --verbose
deno task verify --filter mainwindow-routing --verbose
```

Use the actual registered filter names if they differ. The rollcheck must cover geometry and interaction. The routing check must cover staged new-tab and reload readiness without changing project-I/O behavior.

Launch the built application through the repository-supported `deno task` build flow. Open a song through the asynchronous path and visually inspect the actual native window:

- fallback ruler visible immediately;
- no caption flash;
- default song binding causes no bar movement;
- reload retains ruler and camera;
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
| Fresh view paints a complete ruler | Focused rollcheck paint/geometry scenario and native window inspection |
| Loading caption is gone | Paint scenario plus native window inspection |
| Default load does not move bars | Pixel-position assertions before and after binding |
| TPB alone cannot move beats | Equivalent 24-TPB and 48-TPB geometry scenario |
| Non-4/4 changes only signature-dependent geometry | Focused signature-grid comparison |
| Loading interaction is disabled | Mouse/keyboard interaction scenario before and after binding |
| New tab starts at pre-roll home | Camera scenario |
| Reload retains current ruler and camera | Main-window routing staged-load scenario and native smoke |
| Borrow lifetime is safe | Qt/C++ specialist review and staged replacement check |
| No architectural fallback duplication | Final thermo-nuclear review |
| Existing behavior remains intact | Full `deno task verify` |

## Non-goals

- Project-I/O transport or ownership redesign.
- A separate loading presentation module.
- Dummy MIDI data.
- Ruler image caching.
- Piano-roll note, velocity, automation, or playback behavior changes.
- Sidecar schema changes beyond preserving existing pixels-per-beat semantics.
- Persisting fresh loading-placeholder camera state.

## Completion criteria

The work is complete only when:

1. all geometry and paint consumers use the always-valid axis seam;
2. pixels per beat is the sole mutable horizontal scale;
3. the loading caption and null-timeline ruler exit are deleted;
4. loading affects input readiness without replacing or disabling ruler presentation;
5. focused checks, native application verification, periodic specialist reviews, and the full verification suite pass;
6. no blocking reviewer finding remains.
