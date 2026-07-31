# Polyphony & GBA Sound Limits

<!-- THE mystery-solver page. Newcomers' #1 confusion: "why did my note not
play / cut out?" Write for a musician, not a programmer. -->

## Why notes disappear

<!-- TODO: The hook — symptoms first: a chord loses its bottom note, a
melody clips off when a sound effect plays. Then the cause: the GBA can
only play N sounds at once. -->

## How many sounds a GBA can play

<!-- TODO: The sampled-voice pool (the project's maxChans setting, typically
8–12, shared by ALL sampled notes) + the 4 dedicated chiptune channels
(square 1, square 2, wave, noise) which have their own one-note-each rule.
A diagram earns its keep here. -->

## Who gets cut: how the engine chooses

<!-- TODO: Priority and note-stealing in plain words: newer/higher-priority
sounds steal from older/lower ones; song priority (link to Song Settings)
and track order effects. Dropped vs. Cut Off vs. Tail Cut, defined simply. -->

## The polyphony meter

<!-- TODO: The transport-bar meter: usage vs. the project's limit; the
warning flash when something was lost. -->

## The Polyphony Debugger

<!-- TODO: View → Polyphony Debugger, tour of the dock:
- The live channel grid (including the "shadow" lost sounds)
- "Solo overflow (invert audio)" — hear ONLY what's being lost
- The per-track overflow table (Dropped / Cut Off / Tail Cut)
- The event log — double-click an entry to jump to the exact note in
  the roll
-->

## Fixing polyphony problems

<!-- TODO: Practical recipes: thin chords, shorten releases (ADSR link),
stagger attacks, move a part to a chiptune channel, raise maxChans (and
its CPU cost in-game), adjust song priority. -->

## Other GBA limits worth knowing

<!-- TODO: Quantized volumes/velocities, coarse PSG volume steps, sample-rate
ceiling, mixing sample rate — one paragraph each, with the "Porydaw already
shows you the quantized value" reassurance. -->
