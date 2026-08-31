# Live Voice Change on Selection — Implementation Plan

## Outcome

Changing the current row in a `VoicePickerDialog` must preview that voice in the
open document immediately. The preview is deliberately **outside** undo history:
the undo stack, its current `SongHistory` identity, and dirty state do not change
while a picker is open. Accepting commits the already-previewed result as zero or
one ordinary document-history entry; cancelling restores the exact pre-picker SMF
state and commits nothing.

This is a voice-specific `SongDocument` module, not a generic transaction
framework and not a `QUndoStack` macro. A raw macro would mutate history during
preview, destroy a pre-existing redo tail on its first push, and make cancellation
depend on crossing stack state that never represented a confirmed document state.

## Scope and non-goals

- Modify only the existing files named below. Do not add source files or CMake
  entries.
- Leave `SongHistory` unchanged. Its `pushDocument()` path remains the only way
  an accepted live change enters history; there is no preview identity or second
  undo stack.
- Keep `SongView::pickVoice()` and the Add Track picker acceptance-only.
- Remove the unused `AutomationPage::pickVoice` forwarding declaration and
  definition rather than extending it. Its only references are its declaration
  and definition.
- Do not add a generic picker live-change parameter to `SongView::pickVoice`, a
  generic transaction/callback layer, or a full-SMF preview snapshot.

## Contract

### History and preview invariants

1. One accepted visit produces either no top-level `SongHistory::Entry`
   (an existing marker accepted at its original value) or exactly one entry.
   Row changes never create commands or a `QUndoStack` macro.
2. While previewing, `SongHistory::currentDocumentIdentity()`, undo-stack
   `index()` and `count()`, and `SongDocument::isDirty()` remain unchanged.
   Preview is a direct document mutation followed by normal map rebuilding and
   publication; it may advance `SongDocument::revision()`.
3. Cancelling restores byte-exact program-event state. An existing marker gets
   its saved, verbatim `SmfEvent` back; an empty tick loses the one provisional
   insert and regains its saved track end tick.
4. A redo tail already present when the dialog opens survives cancellation
   structurally, because no history push occurs until Accept.
5. `findLanePoint()` defines the target: the last voice event at a tick wins.
   The session holds the resolved SMF-track/index location, not a
   `DocLanePoint` that can become stale after a preview mutation.

### `SongDocument` live-session interface

In `src/core/songdocument.h`, add one public entry point and one nested public
value type:

```cpp
class VoiceChangeLiveSession;
VoiceChangeLiveSession beginVoiceChangeLiveSession(int engineTrack, uint64_t tick);
```

`VoiceChangeLiveSession` is non-copyable and movable. Keep its state out of the
already-large header with a `std::unique_ptr<Impl>`; define its destructor and
move operations out of line in `songdocument_xcmd.cpp`. Its complete public
interface is:

```cpp
bool active() const;
void select(int voice);
void commit(int finalVoice);
```

The destructor cancels an active, uncommitted session. `beginVoiceChangeLiveSession`
returns an inactive value when the engine track is unmapped or the SMF has no
tracks. Otherwise it captures:

- the mapped SMF track, channel, target tick, and initial `TrackMapState`;
- the document revision it expects to own;
- either the last-wins marker's index, value, and **verbatim** `SmfEvent`, or
  the absence of a marker and the track's original `endTick`; and
- provisional insertion/index/preview state as it becomes necessary.

Forward-declare a private nested `VoiceChangeCommand` in the header. It is the
only new command type and is defined beside the existing lane operations in
`src/core/songdocument_xcmd.cpp`. Include `<memory>` for the session pimpl.

### Session behavior

`DOC_CC_VOICE` is a normal program-change lane: `makeLaneEvent()` creates a
`0xC` channel event. Do not route this feature through the XCMD descriptor
planner.

For every effective preview mutation, use the document's normal mutation
quartet:

1. capture `trackMapState()` before the operation;
2. `applyOps()`;
3. `rebuildTrackMap()`;
4. `publishMutation(trackRemap(before, ops))`.

The resulting remap is the ordinary identity remap for a program-event-only
operation, but it must still be produced through the standard path.

`select(voice)` is a no-op unless the session is active, owns the expected
revision, and `voice` is in `[0, 127]`. It is also diff-gated: selecting the
already-previewed value does not mutate or publish.

- **Existing marker:** build one `ModifyEvent` at the captured index using the
  canonical `makeLaneEvent(DOC_CC_VOICE, channel, tick, voice)`, apply it with
  the quartet, and remember the preview value and new expected revision. This
  matches the in-place, same-tick `moveLanePoints()` behavior and preserves
  same-tick duplicate/shadowing semantics.
- **Empty tick, first distinct selection:** apply one `InsertEvent` for the
  canonical program event. Keep the applied op, including its insertion index
  and recorded old end tick, as the provisional insertion.
- **Empty tick, later selection:** modify that provisional event in place at
  its recorded index. Do not insert another event.

`commit(finalVoice)` has the same active/revision/value guards and is the sole
place that may call `m_history.pushDocument()`.

- For an **existing marker**, accepting its original value is a no-op. If
  browsing changed it, first restore the captured verbatim event with a normal
  publication, then deactivate without pushing. If the final value differs,
  create one pre-applied `ModifyEvent` whose `oldEvent` is the captured
  verbatim event and push one command with text `change voice`.
- For an **empty tick**, Accept must create a marker even if the initial row
  never changed. When no provisional insert exists, apply the canonical insert
  at commit time and retain its resulting index and original end tick. Create
  one pre-applied `InsertEvent` with text `add voice change`. This preserves
  the current empty-tick behavior rather than mistaking unchanged acceptance
  for a no-op.

For a push case, calculate and store the remap against the `TrackMapState`
captured at session start, construct `VoiceChangeCommand`, push it through
`SongHistory::pushDocument()`, and deactivate the session. The session has
already placed the document in the command's final state.

`VoiceChangeCommand::redo()` must have an inert first invocation:
on the first redo from `QUndoStack::push()`, it only disarms itself and returns.
It must not apply operations, rebuild the map, or publish; doing any of those
would double-apply the live result. Later redo operations apply the stored
operations, rebuild, and publish once with the stored remap. `undo()` reverts,
rebuilds, and publishes once with the inverse remap. Leave `id()` at the
default `-1`, so accepted visits never merge.

On reject or scoped destruction before commit, an active session restores only
when its expected revision still matches:

- replace an existing marker with the captured verbatim event; or
- call `revertOps()` on the recorded provisional insertion.

Then rebuild and publish. If an unexpected external mutation changed the
revision, `select()`, `commit()`, and destruction abandon without a restore or
push rather than applying captured indices to a different document. This is a
last-resort corruption guard, not the normal replacement path.

## UI orchestration

### Picker callback

In `src/ui/songview/voicepicker.h` and `.cpp`, add a trailing optional
`std::function<void(int)> onRowChange = {}` constructor parameter and member.
Keep the existing audition callback unchanged.

Connect `QListWidget::currentRowChanged` only **after**
`setCurrentRow()` and `scrollToItem()` have established the initial row. The
callback must reject rows outside `[0, VOICEGROUP_SIZE)`. This prevents opening
the dialog from previewing its initial row while allowing a facet-filter
replacement row to act as a genuine live selection.

### One purpose-specific `SongView` seam

Declare and implement:

```cpp
void SongView::editVoiceChange(int track, uint64_t tick, int initialVoice,
                               const QString &title);
```

`editVoiceChange()` owns the stack-scoped
`SongDocument::VoiceChangeLiveSession` and the modal `VoicePickerDialog`:

1. Capture `SongDocument *sourceDocument = m_document`, begin the session, and
   return if it is inactive.
2. Create the picker with its row callback. Each callback first verifies
   `m_document == sourceDocument`, then calls `session.select(voice)`.
3. If `exec()` rejects, return. RAII cancellation restores the preview during
   frame unwinding.
4. Before accepting, verify the same source-document guard again, then call
   `session.commit(dialog.selectedVoice())`.

The document guard prevents callbacks or acceptance from committing through a
replaced view document. It complements, rather than replaces, the session's
revision guard.

Rewrite `SongView::editTrackVoice()` to retain its current first-tick,
last-wins lookup, derive its target tick (or `0`) and initial voice, and call
`editVoiceChange()` with `Track %1 voice`. Remove its direct
`moveLanePoints()`/`addLanePoint()` acceptance branch.

In `VoiceChangeArea::showPicker()`, retain the hit test, snapped tick, current
voice, and marker-sensitive title calculation, then delegate to
`m_owner.editVoiceChange(...)`. Delete the accept-time `findLanePoint()`,
`moveLanePoints()`, and `addLanePoint()` branch and delete its explicit
`refreshAllDrawerPages()` call: the session's document publication already
drives refresh.

Leave `SongView::pickVoice()` as the simple acceptance-only helper used by Add
Track. Delete `AutomationPage::pickVoice()` from
`src/ui/editordrawer/automationpage.h` and `.cpp`; no caller needs forwarding
after the voice-change area delegates directly to `SongView`.

### Synchronous replacement cancellation

As the first statement in both:

- `SongView::prepareForSongReplacement()`, and
- the `m_document != document` branch of `SongView::setDocument()`,

call `cancelTransientInput()`.

Its owned-modal loop rejects an active `QDialog` synchronously. Therefore the
picker's nested `exec()` returns and the session destructor restores the
preview before `disconnectDocument()` or `SongDocument::adoptSmf()` can replace
the underlying SMF. Retain the existing later interaction cancellation; the
duplicate call is harmless. The readiness-drop path already reaches
`cancelTransientInput()`, so it supplies the same boundary for an in-place
reload.

## Focused checks

Extend the existing modal-driver pattern in
`src/checks/rollcheckvoicechange.cpp` (`QTimer::singleShot`, active modal
dialog, and its `QListWidget`) rather than adding a new harness.

1. **Existing-marker preview and history:** Drive rows `3 → 5 → 7` on the
   seeded tick-48 marker. After each row change, assert the live lane point
   equals that row while undo-stack index/count, current document identity,
   and dirty state equal their pre-dialog values. On Accept, assert exactly
   one new `change voice` entry and a new identity. Round-trip both
   `history().requestUndo()/requestRedo()` and direct
   `undoStack()->undo()/redo()` to verify the original/final values and
   ordinary document-entry behavior.
2. **Exact cancellation and redo-tail preservation:** Begin with a redo tail,
   select multiple rows, and reject. Assert SMF serialization is byte-identical
   to its pre-dialog snapshot; the marker, stack index/count, history identity,
   dirty state, and redo availability are unchanged. Do not require the
   revision number to return: preview and synchronous rollback legitimately
   publish revisions.
3. **Empty-tick acceptance:** Cover both accepting the inherited row without
   a row change and accepting after multiple row changes. Each case must create
   exactly one `add voice change` entry at the snapped tick; undo removes the
   point and redo restores the final value.
4. **Caller coverage and detachment:** Exercise `editTrackVoice()` through
   several selections and acceptance, including its tick-zero insertion case,
   and verify one-entry undo/redo. Verify Add Track remains unmutated before
   acceptance. While an area picker has a live preview, call
   `view.setDocument(nullptr)`; assert the modal is synchronously rejected,
   the original SMF/history state is restored before reattachment, and later
   scheduled row/accept actions cannot create a command.
5. **Revision-abandon guard:** In a direct document-level check, start a
   session and preview a value, apply an unrelated document edit, then verify
   later `select()`/`commit()` calls do nothing and destruction does not revert
   the unrelated edit.

Extend the ready-reload section of `src/checks/tabcheck.cpp`: open a
track-voice picker, select a live row, then request an in-place reload of that
tab's song. Assert the readiness transition synchronously rejects the modal
and restores the pre-preview SMF/history state before the asynchronous MIDI
stage lands. Preserve the existing assertion that the completed reload clears
history.

## Completion criteria

- Browsing a voice picker updates playback/document projection immediately,
  without touching undo history.
- Cancel, detachment, and reload leave no preview mutation or history entry.
- Accept records exactly the documented zero-or-one entry behavior, including
  explicit insertion on untouched empty-tick acceptance.
- No raw undo macro, `SongHistory` modification, AutomationPage forwarding, or
  generic live-transaction surface remains in the implementation.
