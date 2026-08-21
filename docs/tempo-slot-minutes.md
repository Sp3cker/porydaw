# Tempo Slot Design Minutes

**Date:** 2026-08-19

**Status:** Historical decision log. For current implementation and behavior,
use [`tempo-slot-plan.md`](tempo-slot-plan.md).

## Settled decisions

- Tempo is global MIDI data. It does not belong to a track or channel. Inspection of the local M4A and `mid2agb` source confirmed that the emitted tempo command acts globally, so the core model does not need an M4A track identity for tempo.
- `SongDocument` owns ordered `TempoPoint` values as the authoritative Tempo data after load. Each value contains `tick` and `microsecondsPerQuarterNote`. Loading parses the `FF 51` events from SMF chunk 0 into this vector; editing and playback read and write the vector directly; saving regenerates the chunk-0 `FF 51` events from it. The raw Tempo events are not retained as a second live source of truth.
- `tempoPoints` contains only explicit Tempo events; loading does not synthesize a point at tick 0. The effective Tempo is the MIDI default of 500,000 microseconds per quarter note (120 BPM) from tick 0 until the first explicit point. The Tempo lane draws that implicit lead-in without a node when a later explicit point exists, but its body is blank when there are no points. Playback still uses 120 BPM in the empty case. Saving does not emit an implicit default as an `FF 51` event unless the user creates an explicit point.
- `tempoPoints` strictly contains at most one point at any tick. When loading an SMF file with several Tempo events at the same tick, keep only the last event because it is the effective value. Adding, moving, pasting, or drawing onto an occupied tick replaces the existing point rather than stacking another one.
- Voice and CC may retain several matching raw events at one tick. Their node-lane view shows one effective node using the last matching event's value. Node deletion is identified by lane and tick and removes every matching event represented by that node; it does not remove notes or events from another lane at the same tick.
- Loading clamps imported Tempo below 20 BPM to 20 BPM and above 255 BPM to 255 BPM; the clamped value becomes authoritative and is what saving writes. Imported Tempo within that range retains and plays its exact `microsecondsPerQuarterNote` value even when the derived BPM has a fractional part, and the UI displays that BPM rounded to two decimal places. Users may enter or vertically draw only whole-number values from 20 through 255 BPM; 255 is the highest value that fits the M4A `TEMPO` byte in both normal and extended-clock (`-X`) songs. Converting one of those edits stores the nearest valid integer `microsecondsPerQuarterNote`. Moving a point only in time preserves its exact stored Tempo value without BPM rounding.
- Voice and program-change storage remains deferred and is outside this tempo-focused change.
- The non-node Voice module is named `VoiceChangeLane`, implemented in `voicechangelane.h` and `voicechangelane.cpp`. It keeps the current held-segment labels, picker, and Voice-specific input behavior; it does not implement `NodeLane` or gain node, sweep, pencil, ramp, or vertical-drag editing.
- This refactor does not add `AutomationLaneKind` or `AutomationLaneId` to core. An automation lane remains a UI concept; the existing Voice and Control Change models and identities stay unchanged except that Tempo is removed from their generic row machinery.
- Tempo remains `AutomationCanvas` node-stack slot 0 (`LaneHandle{0}`), ahead of
  the CC adapters but outside the generic `CCLanes` collection. Its visual
  placement is a sticky overlay at the bottom of the automation drawer
  viewport, not the first scrollable row.
- `AutomationCanvas` owns one scrollable content coordinate space: Voice Change
  starts at its origin, CC rows and the add-lane strip follow, and the Tempo
  header/body is resolved into canvas coordinates at the viewport bottom. The
  canvas paints that Tempo layer after the scrollable content; it does not use a
  second widget.
- The dedicated Tempo path reads `SongDocument::tempoPoints()` directly,
  converts tempo values to BPM only for display, and submits a `TempoEdit`
  command through a Tempo-specific `SongDocument` entry point.
- Preserve the Tempo lane's current vertical scaling and appearance; the
  20–255 BPM rule constrains loaded and edited values but does not add new
  value-range or zoom behavior.
- The Event List continues to show and edit Tempo entries in SMF chunk 0. Those
  rows are a view of the authoritative `SongDocument::tempoPoints()` data, and
  Event List edits submit `TempoEdit` commands; the Event List does not directly
  mutate raw `FF 51` events.
- Obsolete track-owned Tempo branches and legacy Voice-row sidecar entries are
  removed. The stable `EditorAutomationRowId{Tempo, 0, 0}` and `"tempo"`
  sidecar key retain Tempo's custom height/range state.
  `MidiTimeline::tempoMap` remains the playback-timing map.
- The Tempo header is always available at the viewport bottom and controls
  collapse. It starts collapsed, with only the caption strip visible; its
  expanded/collapsed state belongs to the current editor session, is not stored
  per song, and remains unchanged while the user switches songs. When expanded,
  the header occupies the label gutter and the body uses the shared automation
  paint and interaction primitives at the same pinned position. The expanded
  body height uses the persisted Tempo row height; a collapsed body paints no
  curve and accepts no node or drawing gestures.
- The Tempo lane context menu keeps Copy, Paste, and Clear Tempo. It does not
  offer Delete Lane or Hide Lane because the global Tempo lane always exists and
  its header already provides collapse behavior.
- For this Tempo-focused refactor, `SongDocument` exposes one Tempo-specific
  entry point that accepts a typed `TempoEdit` command. One completed Tempo
  gesture submits one command containing the full add, move, delete, or
  range-replacement change; `SongDocument` applies it directly to the
  authoritative `tempoPoints` vector and pushes one undo step. A wider unified
  edit interface for Notes, Voice, Control Change, and Tempo remains deferred
  rather than expanding this change into a full `SongDocument` rewrite.
