# Automation (Volume, Pan, Tempo & More)

## What automation is

<!-- TODO: Values that change over time instead of staying fixed — fade-outs,
panning sweeps, tempo changes, vibrato depth. Drawn as line/step lanes under
the piano roll. The Automation page holds only the tempo and CC lanes; voice
changes have their own Voice Changes page (see
[The Main Window](main-window.md)). -->

## Adding a lane

<!-- TODO: Per-track lane picker from the m4a parameter list; the tempo lane
always available at the top level. -->

## The parameters you can automate

<!-- TODO: Friendly table of the m4a-meaningful controls with plain-language
descriptions and typical ranges:
- Volume, Pan
- MOD (LFO depth) / MODT (LFO type: 0=vibrato, 1=tremolo, 2=autopan)
- TUNE (fine tune, bipolar — 64 is center/no detune)
- BEND (pitch bend) / BENDR (bend range)
- LFOS / LFODL (LFO speed / delay; LFODL takes effect from the next note-on)
- Tempo (top-level lane)
Flag which ones quantize on GBA hardware. -->

## Drawing and editing values

<!-- TODO: Click/drag to draw, step vs. line rendering, snapping, deleting
points; undoable like everything else. -->

## The value axis and zooming

- **LFO type (MODT):** edits are limited to 0–2. Imported values of 3 or
  higher remain stored until edited, but modulate no axis.
- **Fine tune (TUNE):** the value editor shows −64–63, with 0 as the
  center. MIDI stores 0–127, with 64 as the center.
- **LFO delay (LFODL):** values range from 0–127 and take effect at the
  next note-on.

MODT, TUNE, Pan, and Pitch bend use fixed value ranges; they do not offer
value-range zoom.

<!-- TODO: Gutter menu → Value range (auto-fit or fixed 0–16/32/64/127);
display-only — data is never clipped; MOD auto-fits because its useful
range is small. -->

## Tempo changes

<!-- TODO: The tempo lane; BPM; how tempo interacts with the position display
and loops. -->
