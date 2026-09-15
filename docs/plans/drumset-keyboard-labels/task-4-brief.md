# Task 4: Unclipped hover-chip overlay across gutter and plot

## Context

Task 3 publishes a scene-level full-width hover chip: `hoverChipRect` is
measured from the full pad name and its left edge clamped at 0, so wide
names legitimately extend past the gutter into the plot. But both chip items
(`timelineQuickPianoHoverChip` background, `timelineQuickPianoHoverChipText`)
are parented to `root.gutterSide` (PianoRollCanvas.qml:109-120, :156-175),
which is the roll band's `gutterBox` — fixed `gutterWidth` with
`clip: true` (TimelineCanvas.qml:138-144). The wide chip stays visibly
clipped at the gutter edge. This task moves only the chip background and
text to an unclipped roll-band overlay spanning gutter+plot; gutter labels
and pointer input stay inside the clipped gutter. Consumes Task 3's
scene/geometry contract (`hoverChipRect`/`hoverChipText`/`hoverChipFont`
from `keyboardHoverGeometry`); the band root itself does not clip
(TimelineCanvas.qml:119-136 — "Both fixed and scrolling children clip to
their own band bounds"), and `gutterBox` sits at band-local x = 0, so the
existing gutter-local chip coordinates are already band-local: no coordinate
mapping is needed.

## Exact write set

- `src/ui/songview/quick/PianoRollCanvas.qml`
- `src/ui/songview/quick/TimelineCanvas.qml`
- `src/checks/timelinepan/tst_timelinepan.cpp`

## Prerequisites

Task 3 interface: the scene-level hover contract (`hoverChipText` carries
the full un-elided label; `hoverChipRect` width is measured from it, left
edge ≥ 0) and its `tst_timelinepan.cpp` drum-bank rig, checkpointed at CP2
(this task re-edits that file after its prior writer was checkpointed).

## Interface contract

- `TimelineSceneBand` (TimelineCanvas.qml:118-136) gains
  `property alias bandSide: sceneBand` beside the existing
  `gutterSide`/`plotSide` aliases; the roll instantiation
  (:256-259) passes `bandSide: rollBand`. No other band changes —
  `gutterBox`/`plotBox` keep `clip: true`, `timelineRollGutterInput`
  (:146-151) and `timelineRollInput` stay where they are.
- `PianoRollCanvas.qml` gains `required property Item bandSide` beside
  `gutterSide`/`plotSide` (:7-8). The chip background Rectangle
  (`timelineQuickPianoHoverChip`) and chip Text
  (`timelineQuickPianoHoverChipText`) change `parent: root.gutterSide` →
  `parent: root.bandSide`. Their `x`/`y`/`width`/`height`/`visible`/text/
  font bindings are unchanged (band-local == gutter-local because
  `gutterBox` has no x offset). Z-order: background `z: 8`, text `z: 9` —
  above the z-0 `gutterSide`/`plotSide` siblings and all their inner layers
  (max inner z 7), below canvas-root chrome (the scrollbar siblings sit at
  the canvas root with z 3 over the z-0 bands) and popups. The overlay items
  declare no input handlers and accept no hover or mouse events.
- Everything else in both QML files — gutter key/highlight layers, gutter
  label Repeater, plot layers — is byte-identical.

## Implementation steps

1. `TimelineCanvas.qml`: add the `bandSide` alias to `TimelineSceneBand`;
   pass `bandSide: rollBand` into the `PianoRollCanvas` instantiation.
2. `PianoRollCanvas.qml`: add `required property Item bandSide`; reparent
   the two chip items to it with z 8/9; leave every binding as-is.
3. `tst_timelinepan.cpp`: new `TimelinePanTest` slot
   `hoverChipOverlayUnclipped()` reusing Task 3's drum-bank rig and gutter
   input: hover the long-named pad via `checks::events::sendMouse` on
   `timelineRollGutterInput`, then through the Quick window find
   `timelineQuickPianoHoverChip` and assert (a) its `parentItem()` equals
   the roll band root — reached as
   `findChild<QQuickItem *>("timelineQuickRollPlot")->parentItem()` — and
   that parent's `clip() == false`; (b) the gutter box
   (`"timelineQuickRollGutter"`) still has `clip() == true` and still
   contains the keyboard-label delegate parent and `timelineRollGutterInput`;
   (c) the chip item's width (bound to `hoverChipRect`) exceeds the roll
   `pianoKeyboardWidth` for the long name, and its scene-mapped right edge
   lies beyond the gutter width — the full-width chip is geometrically
   realized on the unclipped overlay.
4. Restore state: move the pointer off the gutter (`QEvent::Leave`) and
   restore the original bank pointer as Task 3's scenarios do.

## Acceptance predicate

The chip is parented to the unclipped roll-band overlay, the gutter keeps
clipping its own labels/input, and a full-width pad-name chip extends past
the gutter into the plot — the visible-full-hover acceptance moved here from
Task 3. Named checks (controller runs them, from the Porydaw root, after
Task 4 settles; `timelinepancheck` needs no desktop focus):

```sh
deno task verify --filter timelinepan --verbose
```

What the scenario proves: chip overlay reparenting with unchanged
coordinates, unclipped band-root parent while the gutter box still clips,
z placement above roll content, and the wide-chip geometry Task 3's C++
publishes. `timelinepan-native` (windowed) re-runs the suite under the
real render loop with native desktop access.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Only the two chip
items move — do not touch the gutter label Repeater, key/highlight layers,
input items, or any TimelineSceneBand clipping; no new objectNames (the
check reaches the band root through the plot box's parent). No C++ changes:
`keyboardHoverGeometry`, `synchronizeHoverChip`, and `TimelineQuickScene`
are Task 3's frozen surface. Run only after CP2 has checkpointed Task 3's
accepted edits to `tst_timelinepan.cpp`.
