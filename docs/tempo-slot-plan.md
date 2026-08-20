# First-class Tempo data and lane refactor plan

## Goal

Make Tempo first-class global song data instead of presenting and editing it as a
fake track-owned automation lane. `SongDocument::tempoPoints` becomes the only
live Tempo source after load. The editor drawer keeps a Tempo lane, but draws and
edits it through a dedicated path.

Keep Voice and Control Change storage and editing unchanged in this refactor. Do
not add core `AutomationLaneKind`, `AutomationLaneId`, a unified
`SongDocumentEdit` for Notes/CC/Tempo, or another general automation model.

## Core data model

Declare the existing core model in `src/core/songdocument.h`:

```cpp
struct TempoPoint {
    uint64_t tick;
    uint32_t microsecondsPerQuarterNote;
};
```

`SongDocument` owns an ordered `std::vector<TempoPoint> m_tempoPoints` and exposes
it as read-only data. Tempo points have no SMF track, MIDI channel, engine track,
controller, or lane identity. There is no synthetic-versus-real flag. A point is
a point.

The vector obeys these rules:

- points are sorted by tick;
- at most one point exists at a tick;
- each point stores the exact integer MIDI microseconds-per-quarter-note value;
- values are limited to the equivalent of 20 through 255 BPM;
- after load the vector is never empty.

MIDI Tempo is global. Reading the local M4A and `mid2agb` source confirmed that an
emitted M4A `TEMPO` command changes global player state; its placement in the
first generated M4A track does not make it track-owned. The 255 BPM upper bound
also fits the one-byte M4A `TEMPO` argument in both normal and extended-clock
(`-X`) songs.

## Load and save

When `SongDocument` loads its normalized SMF format-1 data:

1. Read valid `FF 51` events from SMF chunk 0.
2. Convert each event into a `TempoPoint`.
3. If several Tempo events share a tick, keep the last effective event.
4. Clamp values below 20 BPM to 20 and values above 255 BPM to 255.
5. If the result is empty, insert `{tick: 0, microsecondsPerQuarterNote: 500000}`
   (120 BPM). Do not also invent a tick-0 point when the file already has a later
   Tempo event.
6. Store the result in `m_tempoPoints` and remove the raw `FF 51` events from the
   live `m_smf` event lists.

Opening and saving an out-of-range file therefore writes the clamped value.
Opening and saving a file that had no Tempo event writes the seeded tick-0 120
BPM point. A file whose first Tempo is after tick 0 keeps that first point where
it is; MIDI's implicit 120 BPM still applies from tick 0 until that point.

`publishMutation` must stop rebuilding `m_tempoPoints` from live SMF. Load is the
only SMF-to-vector path. After load, every mutation goes through
`replaceTempoPoints`.

When saving, build the serialized SMF from the document data and merge generated
`FF 51` events into chunk 0 in tick order. At a shared tick, emit Tempo first,
then the remaining raw metas in file order. Do not restore the generated events
to the live `m_smf`; that would create a second Tempo source of truth.

`insertRawEvent` / `modifyRawEvent` of an `FF 51` is rejected in every chunk.
Chunk 0 Tempo is only `tempoPoints`. Chunk ≠ 0 must not store a second live copy.

## Playback

`MidiTimeline::tempoMap` remains the derived playback map. Change timeline
building so it receives `SongDocument::tempoPoints` directly instead of scanning
raw SMF events in every chunk. Playback must use the implicit 120 BPM baseline
before the first explicit point.

Do not regenerate raw Tempo events merely to rebuild playback. Other SMF events
continue through the current timeline path.

## Tempo edits and undo

Private `replaceTempoPoints(next)` is the only writer of `m_tempoPoints`. It
sorts, enforces one point per tick (last-wins), and never leaves the vector
empty: a result that would be empty is re-seeded to tick-0 120 BPM.

Public `applyTempoEdit(edit)` builds that next vector, validates the 20–255 BPM
range, replaces an existing point on a destination tick, and always pushes one
`TempoEditCommand`. Tempo-only lane, Event List, and Clear Tempo gestures stop
there. Undo and redo restore the previous `m_tempoPoints` vector.

Do not add a new unified `SongDocumentEdit`. Mixed song-time operations already
have `RangeEdit`, `moveRange`, and `TimeEditor`. Those commands grow a typed
Tempo payload (`TempoEdit`, or `removeTempo` / `addTempo` as
`std::vector<TempoPoint>`) and apply it with `replaceTempoPoints` inside the
same `redo()` that applies their SMF `EditOp`s. They must not call
`applyTempoEdit`; that would push a second undo item. They must not use
`QUndoStack::beginMacro`: each child `redo()` would `publishMutation` twice.

One completed Tempo-only gesture is one undo step. One mixed paste, nudge,
ripple, insert-blank, or duplicate is one undo step and one `documentChanged`.

Moving a point only in time preserves its exact stored
`microsecondsPerQuarterNote`. Entering a value or changing it vertically accepts
whole BPM only and stores the nearest valid integer microseconds value. Imported
in-range fractional BPM remains exact until a value-changing edit. Display may
show that BPM rounded to two decimal places. After a vertical or typed edit the
exact fractional value is gone unless the user undoes.

Clear Tempo and deleting the last remaining point re-seed `{0, 500000}`. The
lane always has a node.

Put `TempoEdit`, `TempoEditCommand`, and `replaceTempoPoints` in a `src/core`
sibling of `songdocument.cpp`. Do not grow that file.

### Replacement identities

Tempo is not encoded as `DOC_CC_TEMPO`, `{track, controller}`, a negative track,
or dummy track 0.

| Site | After this refactor |
|---|---|
| `TimeScope` / time selection | existing track and Voice/CC lanes, plus `bool tempo` |
| `coversTempo` | `wholeSong \|\| tempo \|\|` (track scope and every used track selected) |
| `SongView::Clip` | existing note/CC lanes, plus `std::vector<TempoPoint> tempo` (µs, not BPM) |
| `RangeEdit` | typed `removeTempo` / `addTempo`; no `engineTrack == -1` lane write |
| `EditorViewState` | Tempo height may stay keyed `"tempo"`; hide and value-range for Tempo go away |

A Tempo clipboard pastes only onto Tempo. A CC clipboard does not land on Tempo.
A mixed clip pastes Tempo only when the destination scope includes Tempo.

Track select, delete, duplicate, and remap ignore Tempo.

## Dedicated Tempo lane

Add `src/ui/editordrawer/tempolane.h` and `tempolane.cpp` as a dedicated helper
owned by `AutomationArea`; it is not a separate `QWidget`.

`AutomationArea` keeps one canvas and draws:

1. the dedicated Tempo lane first;
2. the existing generic Voice and Control Change rows below it.

The important split is data, not a second widget. Tempo stays first in the
canvas stack. `TempoLane` owns its header and body rect and offsets the generic
rows. It reads `SongDocument::tempoPoints()` directly. It shares the current
timeline geometry, scrolling, grid, tick projection, theme, curve and node
painting, hover labels, snapping, and gesture calculations where those helpers
do not assume a track or controller. It owns Tempo conversion, hit testing,
selection, previews, and `applyTempoEdit` submission.

The plot scale is fixed 20–255 BPM. That is both the data range and the vertical
scale. Do not add a new range or zoom control.

Draw every point as a node with an extending line (current look). If the first
point is after tick 0, paint the implicit 120 BPM line into that node. There is
always at least one node because the vector is never empty after load.

Hover and node labels may show two decimal places when the stored BPM is not an
integer. The value prompt and draw/drag gestures stay whole numbers from 20
through 255. They do not accept floating-point input.

### Collapsible header

The Tempo lane has an always-visible header with an arrow to the left of the
label. It starts collapsed. The arrow points right while collapsed and down
while expanded.

The state belongs to the current editor session:

- switching songs does not change it;
- it is not stored in a song, `EditorViewState`, or a sidecar;
- collapse is only vertical shrink: the header stays, the curve is not painted,
  and point or drawing gestures are not accepted;
- the collapsed header remains a time-selection target, so whole-song and
  Tempo-scoped time edits still include Tempo.

The Tempo context menu keeps Copy, Paste, and Clear Tempo. It does not offer
Delete Lane or Hide Lane because the global Tempo lane always exists and its
header already supplies collapse behavior.

## Event List

Keep Tempo visible and editable in SMF chunk 0 of the Event List. Those rows are
a projection of `SongDocument::tempoPoints`, not entries from live raw SMF data.
The table row key is a tagged value: raw event index, or Tempo tick. Select a
row after an edit by tick.

Show BPM, with two decimals when the stored value is not an integer. Do not show
or edit the `FF 51` payload as hex. Editing, inserting, or deleting a Tempo row
submits `applyTempoEdit`. It never calls the raw-event mutation functions for an
`FF 51` event.

Other Event List rows remain raw SMF event views. At a shared tick, Tempo is
listed first, then the remaining raw metas in file order. Tempo cannot be
reordered inside a tick.

Type-changing a Tempo row to another kind is a Tempo delete plus a raw insert.
Type-changing a raw row to Tempo is a raw delete plus a Tempo add; an occupied
tick replaces. Duplicating a Tempo row onto the same tick replaces. Deleting the
last Tempo row re-seeds tick-0 120 BPM.

Tempo stays visible under the existing Tempo/Meta summary filter.

## Remove obsolete Tempo machinery

Deletion is part of this refactor, not later cleanup. The lists below are the
current call sites. After the conversion, scoped searches must find no Tempo
identity encoded as `DOC_CC_TEMPO`, `{track, controller}`, a negative track, or
a dummy track 0.

### Delete

These exist only to disguise Tempo as track-owned automation:

- `src/core/songdocument.h:DOC_CC_TEMPO` (`0xFE`) and the `RangeEdit` comment
  that `engineTrack == -1` means Tempo
- `src/core/songdocument.cpp:SongDocument::laneValue` Tempo branch (FF 51 blob
  to integer BPM)
- `src/core/songdocument.cpp:SongDocument::lanePoints` Tempo branch (scan chunk
  0 for FF 51 into `DocLanePoint`)
- `src/core/songdocument.cpp:SongDocument::makeLaneEvent` Tempo branch
  (synthesize FF 51 from integer BPM)
- Tempo-only `smfTrack = cc == DOC_CC_TEMPO ? 0` routing in
  `addLanePoint`, `writeLanePoints`, `deleteLanePoints`, `moveLanePoints`, and
  `applyRangeEdit`
- `src/core/songdocument.cpp:SongDocument::publishMutation` calling
  `rebuildTempoPoints()` on every mutation
- `src/ui/songviewmodel.h:SongViewModel::tempoLane` and the
  `buildSongViewModel` loop that fills it from `tl.tempoMap`
- `src/ui/editordrawer/automationrows.cpp:tempoRow` and
  `AutomationRows::rebuildRows` appending that fake
  `{Tempo, 0, DOC_CC_TEMPO}` row into the generic list
- Tempo branches in `AutomationRows::{pointsFor, titleFor, valueTextFor,
  rowTarget, rowIdentity}` (`primaryTrack()` + `DOC_CC_TEMPO`,
  `{-1, DOC_CC_TEMPO}`)
- Tempo branches in `AutomationProjection::{rowMinimum, rowMaximum,
  pointerMapping}` (prompt 1–999, scale `max(200, point+20)`)
- Tempo branches in `AutomationArea::{promptPointValue,
  mouseDoubleClickEvent, paintContent}` and
  `automationgesture.cpp` value clamps
- `EditorSelectionModel::timeSelectionCoversLane` sentinel
  `track == -1 && controller == DOC_CC_TEMPO && selected == used`
- `rangeedit.cpp` `query = track < 0 ? primaryTrack() : track` aliases in
  copy, delete, and nudge
- `rangeedit.cpp` / `trackvoiceops.cpp` `track < 0` “tempo is global”
  remappers that keep a negative-track `ClipLane`

### Rewrite in place

Keep the feature. Drop the sentinel.

| Site | Current disguise | After |
|---|---|---|
| `TimeScope` / `coversLane` | `lanes` hold `{-1, DOC_CC_TEMPO}` | `bool tempo`; `coversTempo()` |
| `RangeEdit` | `engineTrack = -1`, `cc = DOC_CC_TEMPO` | `removeTempo` / `addTempo` as `vector<TempoPoint>` |
| `moveRange` | Tempo inside `vector<DocLanePoint>` | typed Tempo payload |
| `TimeEditor` (`laneForEvent`, `eventCovered`, `timeEditAffectedSmfTracks`, `buildTimeEditPlan`, `buildSyntheticEvent`, `m_tempoLaneScope`) | maps `0x51` to `DOC_CC_TEMPO` and scans chunk 0 | `scope.tempo`; plan and apply against `m_tempoPoints` |
| `SongDocument::save` / `MidiTimeline::build` via `SongDocument` | live chunk-0 / all-track `0x51` | serialize / consume `tempoPoints`; Tempo first in its tick group |
| `SongDocument::moveTrack` | migrates raw `0x51` with chunk 0 | ignore Tempo |
| `Clip` / `ClipLane` | `track == -1` means Tempo | `ClipLane` is Voice/CC only; `Clip` has `vector<TempoPoint> tempo` |
| `TimeSelection` | `lanes` hold `{-1, DOC_CC_TEMPO}` | Voice/CC lanes plus `bool tempo` |
| `rangeedit.cpp` copy/delete/nudge/paste | `lanePoints` / `DOC_CC_TEMPO` | `tempoPoints` and typed `RangeEdit` fields |
| `EventTableModel::m_rows` | `vector<size_t>` into live SMF | tagged `{rawIndex} \| {tempoTick}` |
| Event List `data` / `setData` / add / copy / delete | hex blob + `insertRawEvent` / `modifyRawEvent` / `deleteRawEvents` for `0x51` | BPM display; `applyTempoEdit`; last-point re-seed |
| Event List same-tick drop | reorder raw metas including Tempo | Tempo locked first; no intra-tick Tempo move |
| `rebuildTempoPoints` | post-mutation SMF scan | load-only ingest (last-wins, clamp, empty-file seed), then delete the function |
| `insertRawEvent` / `modifyRawEvent` | can write `FF 51` | reject `0x51` in every chunk |

`EditorAutomationRowKind::Tempo` and the sidecar key `"tempo"` stay for
cosmetic height. They must not carry a controller or track.

### Checks to retarget

Do not add a new harness. Change the existing ones so they stop encoding Tempo
as a fake CC:

- `src/checks/editcheck.cpp`: `lanePoints(-1, DOC_CC_TEMPO)`,
  `addLanePoint(..., DOC_CC_TEMPO)`, `TimeScope.lanes = {{-1, DOC_CC_TEMPO}}`,
  `RangeEdit` / `moveRange` / ripple / `moveTrack` Tempo-as-lane cases
- `src/checks/hostcheck.cpp`: automation range menu scope
  `{-1, DOC_CC_TEMPO}`
- `src/checks/selectioncheck.cpp`: `timeSelectionCoversLane(-1, DOC_CC_TEMPO)`
  and remap preserving that pair
- `src/checks/rollcheckautomation.cpp`:
  `EditorAutomationRowId{Tempo, 0, DOC_CC_TEMPO}`

Keep checks that only assert Tempo is first, sidecar `"tempo"` height parsing,
or playback `TIMELINE_EVT_TEMPO` counts. Ordinary SMF `0x51` fixtures stay
fixtures.

### Keep

- `TempoPoint`, `m_tempoPoints`, `tempoPoints()`
- `MidiTimeline::tempoMap`, `TIMELINE_EVT_TEMPO`, tick/sample conversion
- Shared drawer paint, geometry, and gesture helpers used by Voice, CC, and
  the new `TempoLane`
- `EditorAutomationRowKind::Tempo` and viewsidecar `"tempo"` as a height key
- `m4asemantics` Tempo classification for labels
- `songregistry` writing a tick-0 120 `FF 51` into a new blank SMF
- Event List chunk combo, playhead, and non-Tempo meta formatting
- `DOC_CC_VOICE` / `DOC_CC_BEND` and real CC lane code

## Preserved behavior

- Tempo remains the first item in the automation drawer.
- Tempo works without a Primary Track.
- Tempo is unaffected by track selection, deletion, duplication, or reordering.
- Copy, paste, clear, add, draw, move, and delete remain undoable.
- Song-wide time edits keep Tempo aligned with the rest of the song even when its
  lane is collapsed.
- Copying or moving a fractional imported point without changing its value keeps
  the exact MIDI Tempo value.
- Existing Voice and Control Change rows retain their current model and behavior.
- Saving produces valid `FF 51` events in SMF chunk 0 for `mid2agb`.

## Implementation order

Do not strip live `FF 51` until every writer uses `replaceTempoPoints`. Do not
leave a window where the drawer, Event List, or time edits still mutate raw
Tempo events after the strip.

1. Add `replaceTempoPoints`, `TempoEdit`, and `applyTempoEdit`. Stop
   `publishMutation` from rebuilding the vector off SMF. Verify seed, clamp,
   last-wins, never-empty, and Tempo-only undo.
2. Point load, playback timeline construction, and SMF save at `tempoPoints`.
   Strip live `FF 51`. Reject raw `FF 51` inserts. Verify playback and
   Tempo-first chunk-0 round-trip.
3. Give `RangeEdit`, `moveRange`, `TimeEditor`, `TimeScope`, and `Clip` typed
   Tempo fields. Apply those payloads through `replaceTempoPoints` in the
   existing mixed command. Verify one undo step for mixed edits.
4. Add the dedicated `TempoLane`, fixed 20–255 scale, shared-session collapse,
   and context menu. Verify Voice and Control Change stay on the generic path.
5. Project Tempo into the Event List (tick key, BPM display, Tempo first at a
   tick) and route edits through `applyTempoEdit`.
6. Delete every site in **Remove obsolete Tempo machinery**. Retarget the
   listed checks. Confirm the scoped searches in that section are clean.
7. Run focused checks, searches, formatting, and the normal suite.

## Verification

Extend focused existing checks; do not add a new broad harness.

- Core edit checks: load order, duplicate ticks, 20/255 clamps, empty-file seed
  of tick-0 120 BPM, no extra tick-0 point when the file already has a later
  Tempo, exact in-range values, add/move/delete/replace, occupied-tick
  replacement, last-point delete re-seeds, and one-step undo/redo.
- Save and playback checks: timeline timing comes from `tempoPoints`; implicit
  120 BPM before the first point when that point is after tick 0; save emits the
  correct chunk-0 `FF 51` bytes with Tempo first in its tick group and does not
  restore a live raw copy.
- Automation drawer checks: Tempo is first and dedicated, has no track or
  controller identity, works without a Primary Track, uses a fixed 20–255 scale,
  always has a node, and keeps collapse state while switching songs. Collapse
  still participates in time selection.
- Event List checks: projected Tempo rows show BPM (not hex), edit through
  `applyTempoEdit`, and sort Tempo first at a shared tick.
- Track and range checks: track operations leave Tempo unchanged; mixed range
  and whole-song time edits stay one undo step and retain their existing Tempo
  alignment behavior.
- Scoped source searches: no `DOC_CC_TEMPO`, `SongViewModel::tempoLane`,
  `tempoRow()`, or `track < 0` Tempo alias remains.

Run the configured Deno checks for the affected harnesses, the normal incremental
build, the formatter, and the normal check suite.

## Out of scope

- Typed or authoritative Voice and Program Change storage
- Changes to Control Change storage
- A unified SongDocument edit interface for all musical data
- Core automation lane identity types
- Unlimited tracks or a new track identity model
- Changes to M4A player track limits
- New Tempo lane scaling or value-range controls
- Persisting Tempo collapse state in songs or sidecars
