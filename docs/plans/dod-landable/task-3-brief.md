# Task 3 — Hoist shared work + single prefix-count pass in `Sequencer.prepareLive`

## Context
In `Sequencer.prepareLive` (src/swift/playback/Sequencer.swift) the per-track
loop (up to 16 tracks, per callback block) recomputes identical values for
every track: `source.tick(for: position)`, a linear tempo-segment scan from
index 0, and the full meter loop. On discontinuity (`!flags.isEmpty`) each
track additionally rescans the timeline from event 0 just to rebuild its
per-pitch onset/off ordinal counts — up to 16 whole-song prefix scans per
seek. Hoist the shared values and do ONE prefix-count pass for all flagged
tracks. This is NOT the full per-track published index; the per-track window
fill (events within one block) stays.

## Exact write set
- `src/swift/playback/Sequencer.swift` (`prepareLive` and, only if needed, a
  new private helper in the same file)

## Prerequisites
None.

## Interface contract
- No external signature changes. `LiveInsertCall` contents per track are
  byte-identical to today: same tick, tempoBPM, numerator,
  denominatorPowerOfTwo, barStartTick, same input events with same FIFO
  noteIds `(ordinal - 1) * 128 + key + 1`, same overflow counts, same
  missed/boundary reporting.
- Ordinal semantics preserved exactly: reset of a flagged track's
  `inputOns`/`inputOffs` happens before counting; an off increments only
  while `offs < ons`; events before `position` count but are not emitted;
  window is half-open `[position, position + frames)`.

## Implementation steps
1. Before the per-track loop, compute once: tick at position, the tempo
   segment index/BPM, meter numerator/denominator/barStartTick. Fill each
   `call` from these.
2. If any active track has discontinuity flags this block: reset those
   tracks' ordinal rows, then run ONE pass over events with
   `sample < position` updating counts for flagged tracks only (same
   on/off counting rule, distributed by `event.track`).
3. Per-track fill then starts at `lowerBound(in: source, sample: position)`
   for flagged and unflagged tracks alike (counts already include the
   prefix), and no longer needs the `guard event.sample >= position`
   counting path. Unflagged tracks' counts are untouched, as today.
4. Determine "active/flagged" from the same conditions the current loop uses
   to enter a track's call construction — read the full `prepareLive`
   (including the part before the call fill: slot lookup, `flags`,
   `playing` edge handling around `liveWasPlaying`) and preserve which
   tracks get calls and which get resets. Tracks not playing keep today's
   behavior exactly (no counting, no reset).

## Acceptance predicate
Identical `LiveInsertCall` streams for scripted live checks including seek/
loop discontinuities. Controller: `build:checks` + `checks --filter
swiftcore` (LiveInsertChecks, PlaybackChecks). SHARED_TREE: DEFERRED_TO_CONTROLLER.

## Task-specific constraints
- No allocation added to the callback path; reuse existing fixed storage
  (`inputOns`/`inputOffs` are already 16×128).
- Do not change `chase`, loop-wrap note handling, or `PlaybackTimeline`.
- If per-track flag/playing conditions make the single-pass reset
  non-equivalent for some track subset, restrict the hoist to the subset
  where it is provably equivalent and say so in the result — do not guess.
