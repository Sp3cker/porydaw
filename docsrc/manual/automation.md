# Automation (Volume, Pan, Tempo & More)

## What automation is

<!-- TODO: Explain time-varying parameter curves in the shared Automation plot; Voice Changes use their own page. -->

## Adding a lane

<!-- TODO: Explain choosing any supported per-track parameter or song-global Tempo from the parameter list. -->

## The parameters you can automate

<!-- TODO: Describe Modulation, Volume, Pan, Bend range, LFO speed, Echo volume, Echo length, Pitch bend, and Tempo, including ranges and hardware quantization. -->

## Drawing and editing values

- In the Automation drawer, left-click a written node to delete it, or drag it
  to move it. This also works with the Pencil tool active. A double-click
  deletes only the clicked node; Undo restores it.
- Pencil and sweep gestures preview the curve and points that releasing the
  pointer will write, using the lane's ink. Existing nodes covered by the draw
  are hidden until the gesture finishes. Escape cancels the draft and restores
  the unchanged lane.
- Live drafts and committed nodes use hollow circular markers with the same
  font-relative radius and outline. Selection adds a larger circular ring.
  Normal curves are two logical pixels wide; drag and sweep preview lines
  are one logical pixel wide.
- Right-click an insertion ghost between nodes to enter the value to insert
  at that position.

### Note pitch bend, modulation, and LFO speed

Select a note and press **G** to open its pitch-bend, modulation, and LFO-speed
graphs. Press **G** again, or **Escape**, to close.
The draggable **LFO speed** input edits the note-start value without removing
interior curve points. Dragging the graph's note-start point updates that input.
LFO speed ranges from 0 to 127; its Reset restores 22 while preserving the
note-off value. Graph and input edits support Undo and Redo.
Clicking an existing node selects it without changing its tick or value.
Dragging vertically changes its value without snapping its time to the grid.
Dragging an interior node horizontally snaps its time; hold **Alt** for fine snapping.
Hold **Alt** (**Option** on macOS) while dragging in any of the three graphs
for quarter-speed vertical value adjustment. The live readout shows **FINE**
while active. Pressing or releasing the modifier keeps the current value;
pitch bend still uses the audio engine's playable 128-unit steps.
If the destination tick already has a node, the dragged node keeps its original
tick rather than overwriting that node or jumping to a distant empty tick.

## The value axis and zooming

Pinned reference curves draw behind the active curve in half-opacity automation
ink. Each reference uses its own value range, including Tempo's BPM scale,
regardless of which parameter is active.

- **LFO type (MODT):** edits are limited to 0–2. Imported values of 3 or
  higher remain stored until edited, but modulate no axis.
- **Fine tune (TUNE):** the value editor shows −64–63, with 0 as the
  center. MIDI stores 0–127, with 64 as the center.
- **LFO delay (LFODL):** values range from 0–127 and take effect at the
  next note-on.
- **Pan:** Sample voices pan continuously from left to right. Square,
  Programmable Wave, and Noise voices render only hard-left, center, or
  hard-right, so wherever the track's current voice is one of those, the
  Pan lane is three-stop: the axis is labeled Left/Center/Right, points
  draw on the nearest stop, and dragging, drawing, or typing a value
  stores the nearest stop (0, 64, or 127). Imported in-between values keep
  their stored value until you edit them. A program change to a sample
  voice makes the rest of the lane continuous again.

MODT, TUNE, Pan, and Pitch bend use fixed value ranges; they do not offer
value-range zoom.

<!-- TODO: Explain display-only automatic and fixed value ranges without implying data clipping. -->

## Tempo changes

<!-- TODO: Explain editing song-global Tempo in the shared plot, BPM limits, position display, and loops. -->

A first Tempo event after tick zero draws a 120 BPM lead-in up to that event.
A written tick-zero event supplies the starting tempo instead. An empty Tempo
store draws no curve or origin marker.
