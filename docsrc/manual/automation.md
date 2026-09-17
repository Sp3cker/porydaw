# Automation (Volume, Pan, Tempo & More)

## What automation is

<!-- TODO: Explain time-varying parameter curves in the shared Automation plot; Voice Changes use their own page. -->

## Adding a lane

<!-- TODO: Explain choosing any supported per-track parameter or song-global Tempo from the parameter list. -->

## The parameters you can automate

<!-- TODO: Describe Modulation, Volume, Pan, Bend range, LFO speed, Echo volume, Echo length, Pitch bend, and Tempo, including ranges and hardware quantization. -->

## Drawing and editing values

<!-- TODO: Explain drawing, snapping, deleting, curve behavior, and undo. -->

## The value axis and zooming

- **LFO type (MODT):** edits are limited to 0–2. Imported values of 3 or
  higher remain stored until edited, but modulate no axis.
- **Fine tune (TUNE):** the value editor shows −64–63, with 0 as the
  center. MIDI stores 0–127, with 64 as the center.
- **LFO delay (LFODL):** values range from 0–127 and take effect at the
  next note-on.

MODT, TUNE, Pan, and Pitch bend use fixed value ranges; they do not offer
value-range zoom.

<!-- TODO: Explain display-only automatic and fixed value ranges without implying data clipping. -->

## Tempo changes

<!-- TODO: Explain editing song-global Tempo in the shared plot, BPM limits, position display, and loops. -->
