---
status: accepted
---

# Practical tick limits

Accept simpler ordinary editing over complete numeric-extreme support. Retain
`uint32_t Tick`, `ViewNote` start+duration, wide derived ends, parser validation,
safe conversions, and whole-edit admission. This supersedes extreme-operation
requirements from `e253113f`, not the Tick narrowing in `996c6446`.

## Limits and accepted failures

`kNoTick = 2^32 - 1` is reserved; `kMaxTick = kNoTick - 1`.
At constant tempo, `seconds = kMaxTick * 60 / (PPQN * BPM)`.
At 120 BPM: 24 PPQN (default) reaches 2.84 years; 480 reaches 51.8 days;
960 reaches 25.9 days; 32,767 (maximum metrical division) reaches 18.2 hours.
There is no fixed wall-clock cap: high-resolution MIDI reaches the limit sooner.

- **Overflowing edits/files:** reject before mutation/narrowing; UI rejection may
  be silent. Valid representation does not guarantee an editable destination.
- **Upper-edge automation:** independent point clamps can collapse preview spacing;
  upper-edge group spacing and preview/commit consistency are not guaranteed.
- **Extreme snapping:** coarse snaps can return the reserved endpoint, causing
  rejected nudges. No terminal off-lattice policy or meaningful non-finite-coordinate
  snapping guarantee; safe conversions and visible-range validation remain.
- **Pathological undo history:** unchecked `int64_t` delta accumulation can cause
  **undefined behavior** after over two billion maximum-sized same-direction
  additions. We accept this constructed-input risk, not ordinary-use corruption.

These extreme outcomes are not behaviors tests must preserve. This decision does
not authorize removing unrelated validation or tolerating ordinary crashes, hangs,
partial edits, or broken undo.

## Preserve these branches

1. **Conversion/parser:** [`parseTrack`](../../src/core/smf.cpp) accumulates wide
   and rejects `tick >= kNoTick` before narrowing.
   [`shiftTickClamped` / `tickFromDouble`](../../src/core/timedefaults.h) classify
   bounds before unsafe addition, negation, or conversion.
2. **Notes:** [`moveNotes` / `moveNotesToPitches`](../../src/core/songdocument.cpp)
   enforce `dTick` within `[-kMaxTick, kMaxTick]` and batch start/end admission
   before history/mutation. `resizeNotes` checks headroom **before adding** and
   retains the one-tick minimum; derived ends stay wide.
3. **Range admission:** reject empty ranges and
   [`hasReservedEndpoint()`](../../src/core/songdocument.h).
   [`insertBlank` / `duplicate`](../../src/core/songdocument_timeeditor_insert.cpp)
   preflight track ends, covered events, and scoped tempo against `kMaxTick - span`;
   duplicate also admits `e + span`. Track ends can exceed the last event.
   [`buildTimeEditPlan`](../../src/core/songdocument_timeeditor.cpp) requires both
   selected endpoints of a terminated note; both must remain in the admission scan.
4. **Range arithmetic:** `span = e - s`; left shifts require `tick >= e`, proving
   `tick - span >= s`. Paired ends follow their note-on. Right shifts rely on the
   preflights above; clipped copies lie in `[s,e]`, bounded by admitted `e + span`.
   New paths must establish equivalent bounds or use the safe helper.
5. **Seams:** [`appendTimeEditMove`](../../src/core/songdocument_timeeditor.cpp)
   keeps `mode == SkipUnchanged && event.tick == tick`: a surviving stream winner
   can already be at `s`. This branch and `MoveMode` are live.
6. **Undo:** [`mergeWith`](../../src/core/songdocument.cpp) retains mergeability,
   output matching, rewind/rebuild/application order, and publication discipline.
   The two output matchers differ; do not assume both use `NoteId`.
7. **Grid:** [snapping](../../src/ui/songview/grid.cpp) preserves fractional
   comparisons, lower-candidate ties, exact-grid behavior, and signature seams.
   [Walking](../../src/ui/songview/detail.h) retains positive stride, wide
   candidates, `tick < segEnd`, segment termination, bounded narrowing, invalid-range
   rejection, and beat-line omission.
8. **UI:** [group drag](../../src/ui/editordrawer/nodelane/gesture.cpp) clamps the
   common delta against the earliest point to preserve spacing at zero.
   [Keyboard nudge](../../src/ui/songview/pianoroll_commands.cpp) checks revision
   before revealing: rejected/no-op moves must not pan.

## Maintenance

Keep ordinary edit/collision/seam/automation/undo coverage and compact rejection/
atomicity checks. Do not restore extreme fixtures merely to fill coverage gaps.
Revisit for long high-PPQN product requirements, scripting that makes pathological
histories plausible, or an ordinary-use failure; fix the relevant boundary.

Removal evidence: build, 79 non-window-system harnesses, and four offscreen/software
grid/keyboard scenarios passed; 12 native-window harnesses excluded. No native-input,
large-project performance, or arbitrary-input safety claim.
