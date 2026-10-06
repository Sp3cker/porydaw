# Event identity: objects get IDs, curves are keyed by position

Status: **idea** — not implemented. Prompted by the revision-stamp work
(`DocumentRevisions`, `DocumentWorkspace.moved(since:)`,
`DocumentProjectionCache` keyed per track), which contains *publication* to
the edited chunk and kind but cannot contain *projection validity* below the
chunk. This idea removes that floor.

## Problem

`MidiChunk.events` is one interleaved array and the file's truth. Only
note-ons carry a stable identity (`MidiEvent.noteID`, minted in
`SongDocument.init` / `mintNoteID`, resolved through `NoteProjection.index`).
Every other reference to an event is a raw position into that array:
`Note.onIndex`/`endIndex`, `LanePoint.eventIndex`,
`AutomationPointIdentity.occurrence`, event-list selection,
`RangeEdit.removePoints`, `Xcmd.Patch.sourceIndex` (93 `eventIndex` sites in
19 files at the time of writing).

Consequence: deleting a note shifts the offset of every lane point after it in
the same chunk. Any projection that may be *edited through* must therefore be
invalidated by any event edit in its chunk, so `ChunkRevisions.events` (the
any-kind stamp), not `.lanes`, keys `DocumentProjectionCache` and the
automation page's frozen facts still gate on the global `revision`. Kind
scoping is honest only for what gets published, not for what gets edited.

## What other DAWs do

- **Ardour** (`libs/evoral/evoral/Event.h`): every `Evoral::Event` has
  `event_id_t _id` from `next_event_id()`; undo commands store
  `note_id`/`sysex_id`/`patch_id`. Separately, controllers are not events in
  `MidiModel` at all: they live in per-parameter `AutomationList`s ordered by
  time, so a note edit cannot move a controller point.
- **Zrythm** (`src/structure/arrangement/arranger_object.h`): every arranger
  object (`MidiNote`, `AutomationPoint`, `MidiControlEvent`, markers, tempo)
  is `UuidIdentifiableObject`, referenced by `ArrangerObjectUuidReference`.
  Zrythm 1.x addressed by region + index and migrated away from it.
- **LMMS** (`include/AutomationClip.h`): automation is
  `QMap<int, AutomationNode>` keyed by position; notes are pointer-identified
  objects in a separate vector.

Preferred shape: Ardour's two decisions, not its code. *Identity for the
things that are objects; position for the things that are curves.*

## Idea

1. **`EventID` for object-like events.** Generalize `MidiEvent.noteID` to an
   `id` minted for note-ons, program changes, meta and sysex, preserved
   through COW copies and undo exactly as `noteID` is today (`DocumentChangeSet`
   stores whole `MidiEvent`s, so IDs ride along). One per-chunk `id → offset`
   index, generalized from `NoteProjection.index`. `Note`, voice-change
   points, event-list selection and `RangeEdit` removals address by ID.
2. **Lanes stay positional.** CC and pitch-bend points are curve samples: the
   natural key is `(parameter, tick, occurrence-at-tick)`, which is what
   `AutomationNodeResolver` already resolves by. `LanePoint` drops
   `eventIndex`; lane edits resolve `(tick, occurrence)` against the chunk at
   apply time.
3. **Stamps become fully honest.** `DocumentProjectionCache` keys notes on
   `chunks[i].notes` and lanes on `chunks[i].lanes`; the automation page's
   commit gate reduces to "these keys still resolve", the way `moveNotes` by
   `NoteID` already behaves when a note was deleted underneath it.

## Scope

Core: `MidiFile` (`noteID` → `id`), `SongDocument` minting, `NoteProjection`
index, `EventEditing`/`TimeEditing`/`RangeEdit` addressing, `PlaybackTimeline`
and `Sequencer` keep positional iteration. App: event list selection and
model, voice-change lane policy, automation identities. Comparable in size to
the `PorydawAppPresentation` split; worth doing as its own surface-first
change, not bolted onto a refresh-scoping branch.
