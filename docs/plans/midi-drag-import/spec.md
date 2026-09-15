# MIDI Drag Import Specification

## Purpose

Integrate MIDI-file dragging as another entry point into the current MIDI import flow without importing the source branch's obsolete `MainWindow`, track-budget, or input-routing architecture.

## Vocabulary

- **Source chunk:** an SMF track chunk in source order.
- **Note-bearing track:** any source chunk containing at least one importable Note On event, enumerated independently of the destination mapper and its hardware cap. One selectable item represents one source chunk.
- **Channel list:** distinct MIDI channels seen in channel events for one source chunk, in first-occurrence order; informational only.
- **Global event:** a well-formed tempo (`FF 51`, exactly 3 payload bytes), time-signature (`FF 58`, exactly 4 payload bytes), key-signature (`FF 59`, exactly 2 payload bytes), or marker meta event whose meaning is song-wide.
- **Append target:** the ready `SongTab` captured when the drop is accepted.
- **Available slot:** one hardware track slot: `track_limits::kHardwareCapacity - engineTrackCount()`.

## Accepted Drop

A drop is eligible only when all of these hold:

1. It reaches song-tab content or the empty/non-Quick tab content adapter, not the tab bar.
2. It carries exactly one local URL.
3. The local path has a case-insensitive `.mid` or `.midi` suffix.
4. The same open project is not busy, no dialog operation is already active, and the drop does not overlap project load/save.
5. The file parses and contains at least one note-bearing track.

`SongTab::InputGate` captures URL drag enter/move/drop events from the tab container, embedded `QQuickWindow`, and Quick root, then emits `urlsDropped` exactly once for the drop. It does not add focus memory, synthetic forwarding, a second dispatcher, or QML drop logic. A local tab-widget adapter covers empty/non-Quick content and leaves tab-bar drops unclaimed.

Ineligible input is ignored without a chooser. A parse failure, no-note file, vanished target, interlock change, or capacity change uses the existing workspace MIDI-import error presentation and produces no document, history, revision, publication, or project mutation. The source file is never modified.

## Chooser

The workspace presents one private modal chooser listing every note-bearing source chunk in source order with track name and channel information.

- Destinations are **Append to Current Song** and **New Song**.
- Append is available and initially selected only when the captured append target remains ready, `bankActionsEnabled()` permits history mutation, and at least one hardware slot is available. Otherwise New Song is selected and Append is unavailable.
- The initial checked selection is the longest source-order prefix that fits the selected destination's hardware capacity; a 17-track source still lists all 17 rows and initially checks only the first 16 for New Song.
- Confirmation requires at least one selected track and no more selected tracks than the currently selected destination can accept.
- Destination changes update capacity and selection validity without discarding still-valid user choices.
- Capture project identity before opening the chooser. At entry require `WorkspaceUi::m_dialogOps == 0`; immediately before `exec()`, increment it to 1 and call `WorkspaceUi::updateOpenGate()` using the existing balanced dialog-operation pattern.
- On every chooser return, first require the expected depth of exactly 1, then decrement to 0 and call `updateOpenGate()` before either document mutation or launching `NewSongWizard`/`WorkspaceUi::submitCreateSong`. Cleanup every early return through the same balanced scope without a second state flag.
- After guard release, perform one same-turn final check: same project remains open, `!projectBusy()`, `m_dialogOps == 0`, no load/save transition, and the selected destination's mutation gates. Append additionally revalidates the original `QPointer<SongTab>`, readiness, `bankActionsEnabled()`, selected track set, and current hardware slots.
- A stale target never falls through to a different active tab. If an entry gate fails, no chooser appears. If the dialog depth or another gate changes during the modal session, reject after balanced guard cleanup, present the existing workspace import error, and leave all state unchanged.

The chooser remains private implementation in `workspaceui_midi.cpp`. Stable `objectName` values expose destination controls, track rows, confirmation, and error text to Qt checks; these names are the only test-facing UI contract.

## Pure Selection Projection

`noteBearingImportTracks` scans every source chunk, without the `mapSmfEngineTracks` hardware cap, and returns one `ImportTrackInfo` per note-bearing chunk in source order. `ImportTrackInfo::channels` is `std::vector<uint8_t>` in distinct first-channel-event occurrence order. A note chunk after 16 earlier channel-bearing/no-note chunks remains selectable; all 17 rows of a 17-note-track source remain selectable. Capacity is enforced only by the chooser/document.

Selection vectors contain unique valid source-chunk indices returned by that analysis.

A global classifier composes existing SMF helpers with these exact rules:

- Tempo, time-signature, and key-signature events are global only with the exact payload lengths in Vocabulary; malformed variants remain source-scoped metadata.
- In each source chunk, the first unprefixed `0x03` track-name event is the chunk name and never becomes a marker.
- Apply `SmfChannelPrefix` state per source chunk. A later/prefixed `0x03` is global only when `smfMetaIsMarker` classifies it as a marker.
- When a retained marker depends on channel-prefix context, emit an equivalent channel-prefix meta immediately before that marker in the conductor so the projected event is self-contained; prefix state never leaks between source chunks.

`selectedMidiForNewSong` returns:

1. One conductor chunk containing all valid global events from all source chunks, ordered by ascending tick, then source-chunk index, then original event index. A synthesized marker prefix is adjacent immediately before its marker.
2. A conductor `endTick` equal to the maximum source-chunk `endTick`, never earlier than its final retained event.
3. The selected note-bearing chunks in source order, with valid global events removed.
4. Original non-global channel events, malformed would-be globals, scoped text/meta events, sysex events, names, event order, and original meaningful `endTick` retained.

`selectedMidiForAppend` returns only the selected note-bearing chunks in source order. Valid destination-owned globals and their conductor-only prefix context are removed; names, malformed/scoped text/meta events, other meta/sysex/channel events, event order, and original meaningful `endTick` remain.

Projection does not mutate the parsed source. `mapSmfEngineTracks` remains canonical for validating each projected/destination SMF, not for source selection.
## Atomic Append

`SongDocument::availableImportTrackSlots()` reports hardware capacity only.

`SongDocument::appendImportedTracks(source, selectedTracks, error)` performs all fallible work before document mutation:

1. Validate a non-empty, unique, in-range selection and current hardware capacity.
2. Build append projection with `selectedMidiForAppend`.
3. Run current redundant-setter cleanup.
4. Checked-rescale a copy from source division to the destination division.
5. Validate every projected track can map and insert.

It then appends the tracks through existing `EditOp::InsertTrack`/`SongEditCommand` machinery as one history command. Existing stable note-ID minting, `TrackRemap`, revision accounting, and publication remain canonical. Success returns the first imported engine-track index; failure returns `-1`, sets `error`, creates no history entry, publishes nothing, and leaves the document byte-for-byte behaviorally unchanged.

One Undo removes the complete import; one Redo restores it with correct remapping and stable note identities.

## Workspace Commit

New Song projects with `selectedMidiForNewSong`, then calls the existing `NewSongWizard` and `WorkspaceUi::submitCreateSong` path. Current player-budget warnings remain unchanged.

Append is a workspace history mutation: entry and pre-commit both require the captured project/interlock predicates above and `bankActionsEnabled()`. It then calls `SongDocument::appendImportedTracks` on the captured target. After success, it activates that exact tab, selects the returned first imported engine track, inspects `notesForTrack(firstImported)`, and uses existing `SongView::revealNote`/`ensureTickVisible` behavior to reveal the earliest imported note at its rescaled destination tick. Do not add `earliestNoteTick` to the core interface.

## Non-goals

- No merge/cherry-pick of the source commit.
- No `MainWindow` drag/drop policy.
- No player-budget editing gate or `NewSongWizard` minimum-track overload.
- No QML `DropArea`, custom focus system, synthetic event forwarding, or second drop dispatcher.
- No directory, remote URL, multi-file, audio-file, or non-MIDI drop support.
- No changes to File-menu import semantics beyond sharing the extracted canonical workspace module.
