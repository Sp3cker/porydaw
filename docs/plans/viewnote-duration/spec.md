# ViewNote duration model

## Decision

`ViewNote` is a musical-time note, not a pixel or end-tick encoding: start tick
plus duration, the same shape as LMMS `Note` (pos + length) and Rosegarden
`Event` (time + duration). `DocNote` — the document note — already uses this
shape (`uint64_t tick` + `uint32_t duration`, with `unterminated()` as a derived
predicate over `endIndex`, src/core/songdocument.h:69-82); `ViewNote` now
matches it instead of inventing a parallel `endTick` + `unterminated` encoding.

Pixel geometry is not stored on the note. `PianoRoll::noteRect` /
`TimeCamera::displayX` convert ticks to pixels at the paint/hit seam, as both
reference DAWs do (Rosegarden `MatrixElement::reconfigure`,
src/gui/editors/matrix/MatrixElement.cpp:125-131, local tree).

Do not invent a second duration encoding (`unterminated` flag, song-end
`endTick`, 1-tick stub, `uint64_t` end field for `UINT32_MAX+1`). Do not vendor
PortSMF — both adoption gates fail; see
[Alternatives considered](#alternatives-considered).

## Struct

```cpp
struct ViewNote {
    NoteId noteId; // source document identity; unassigned for ordinary timeline notes
    uint32_t startTick;
    uint32_t duration; // 0 = unpaired note-on or same-tick pair
    uint8_t key;
    uint8_t velocity;
    uint8_t track;

    uint64_t endTick() const { return uint64_t(startTick) + duration; }
};
```

Half-open span is `[startTick, endTick())`. When `duration == 0` the span is
empty.

## Projection (`buildSongViewModel`)

- Note-on: append `ViewNote` with `startTick = ev.tick`, `duration = 0`.
- Matching note-off: `duration = ev.tick - startTick` for every note still open
  on that (engine track, key) — the existing stack close. A same-tick pair
  yields `duration == 0` (the zero-length note it really is); a mis-ordered
  same-tick end/on stays zero-length instead of being papered over (the
  pairing comment in songviewmodel.cpp; mirrors `SongDocument::notesForTrack`
  and mid2agb).
- Unpaired note-ons: leave `duration = 0`; increment `unpairedNoteOns`; stay in
  `model.notes`. Do not write `lengthTicks`, `startTick + 1`, or a strip row. Do
  not synthesize a MIDI note-off.
- Orphan note-offs stay in the strip (unchanged).
- `DocNote::unterminated()` and SMF/document pairing are unchanged.

## Roll geometry

`PianoRoll::noteRect(const ViewNote &)` returns a null `QRectF` when
`duration == 0`, before `pianoRollNoteMinimumWidth` is applied (LMMS's piano
roll skips `length == 0` for paint and hit-test). Hit-test, fills, borders,
labels, and band audition through that overload therefore miss empty spans.
Zero-duration notes are unreachable through hit-testing; `displayedNoteRect`
drag math does not handle them.

Draw-preview uses `noteRect(x0, x1, key)`, not the `ViewNote` overload.

Pending draw notes set `duration = m_drawDur`, not an end field. `announceNote`
reports `note.duration` as the tick length.

Note borders are solid; the dashed unterminated border is deleted
(`noteBorderDashLength` / `noteBorderDashGap` absent from pianoroll.h; Quick
`addNoteBorder` has no unterminated parameter). `addDashedFrame` itself stays —
the time-selection edge band still uses it
(timelinequickview_pianoroll.cpp:358).

## Unpaired note-on policy and precedents

`duration 0` (empty span) is the policy. This is not an invented rule:

| System | Note time model | Unmatched note-on at EOF |
| --- | --- | --- |
| PortSMF/allegro `Alg_note` | `double time`, `double dur` in beats after SMF read | Kept in the track with `dur = 0`: `Mf_on` initializes `dur = 0` (allegrosmfrd.cpp:185,197) and only `Mf_off` ever writes it (:205-230); the reader destructor frees the open-note list nodes only (:81-91) |
| LMMS `Note` | `TimePos m_pos`/`m_length`, int32 ticks (include/Note.h:263-268) | The model allows length 0; the SMF importer clamps ticks < 1 to 1 when baking its own copy (plugins/MidiImport/MidiImport.cpp:406-414) and the piano roll skips length 0 |
| Rosegarden `Event` | `timeT` absolute time + duration (src/base/Event.h:509-511, local tree) | `consolidateNoteEvents` extends an orphan note-on to the last event time on the track (src/sound/MidiFile.cpp:1583-1672) — because it bakes an editable copy; Porydaw must not (M2 round-trip) |

Porydaw reads the document's SMF; it cannot synthesize note-offs the way
import-baking DAWs do (SPEC.md M2: load → save with no edits is semantically
identical through mid2agb). An empty span plus the counter is the honest
projection. The user has confirmed unpaired-note visibility does not matter.

## Event coverage (M1)

Unpaired note-ons leave the roll surface, but nothing becomes silently
invisible: they remain in `model.notes`, are counted in `unpairedNoteOns`
(pinned by the eventviews harness, viewbuckets_grid.cpp), and the raw note-on
stays a legible row in the MIDI Event List (SPEC.md M1). The roll is the
paired-note surface.

## Pitch-bend popup flag — stays

`PitchBendGraph::Initial::unterminated` (pitchbendgraph.hpp:98-99) is not this
bug. It is scoped-popup state derived from `DocNote::unterminated()`
(pitchbendeditor.cpp:81) — a true document predicate (no matching note-off
exists in the SMF) — and only bounds the popup graph and labels its end
"Song end" (pitchbendgraph.cpp:296). It stores no fabricated end on a note
model and never reaches the document. Leave it.

## Alternatives considered

### Vendor PortSMF (rejected — both gates fail)

User gate: adopt PortSMF only if (1) it saves us from writing/maintaining our
own pairing/duration tests, and (2) adoption is small — nothing becomes
PortSMF-shaped.

**Gate 1 fails — no test is deleted.** The pairing tests Porydaw maintains pin
mid2agb/document semantics, not generic SMF pairing, and none are expressible
over `Alg_note`:

- `src/checks/midi/tst_midismf.cpp:576-624` — `complexInterleavedNotesPairExactly`
  and `unterminatedNotePairingStaysLinear` (300k note-ons, linearity budget)
  assert `DocNote` pairing over `SmfTrack` indices and `NoteId` identity.
- `src/checks/editcheck/tst_songdocument_timerange.cpp:136-162` —
  `timeRangeUnterminated` asserts SMF-level splitting of unterminated ons.
- `src/checks/eventviews/viewbuckets_grid.cpp` — view-projection quirks
  (dropped-tracks clamp, unpaired/orphan counters).

PortSMF's own suite (test/test.cpp with Allegro-text `.gro` fixtures; the
legacy tree uses a checksum runner) tests allegro's reader; coverage of the
unmatched-note-on case is unverified upstream. Vendoring adds a second corpus
next to ours and deletes nothing: `Alg_note` has no integer ticks, no event
indices, no note identity, and no track field, so the mid2agb invariants cannot
be pinned through it.

**Gate 2 fails — adoption is not small.** `Alg_event`/`Alg_note` store
`double time`/`double dur` (beats after SMF read: ticks/PPQ in
allegrosmfrd.cpp `get_time()`), `float pitch`, `float loud`, `long chan`; the
track is the owning container, not a field. `ViewNote` feeds a `uint32_t`-tick
editor with `uint8_t key/velocity/track` and `NoteId`. Using Alg types as the
presentation model would push beat↔tick double conversion into every roll
consumer — exactly the PortSMF-shaped outcome the gate forbids.

The only small-adoption shape is LMMS's: PortSMF confined to the SMF import
seam — a submodule compiled reader-only into the MidiImport plugin, Alg→`Note`
conversion in one function, no Alg type crossing the plugin boundary. Porydaw
has no seam to gain: `SmfFile` must stay the document parser (M2 byte-faithful
round-trip: running-status resets, EOT `endTick`, format-0 coercion, loop-marker
text metas, channel-prefix scoping, engine-track mapping — src/core/smf.h), and
`MidiTimeline` must stay the projection (audio-thread sample positions, XCMD
lane projection). A second SMF parser is a parallel corpus, not a deleted one.
The license is also MIT-style with a non-binding modification-request tail
(GitHub classifies it `Other`/`NOASSERTION`), so vendoring would add a license
acknowledgment for zero savings.

**Corroboration without dependency:** allegro's pairing is the strongest
external evidence for this spec's semantics — unmatched ons retained at
duration 0, and one note-off closes every open same-key note in a single pass,
the same stack-close `buildSongViewModel` uses (songviewmodel.cpp:97-101). We
adopt the rule, not the library.

### Adapter over DocNote (rejected)

Wrapping `DocNote` (or projecting from `notesForTrack`) couples the
presentation model to document internals (`onIndex`/`endIndex` identity), forks
the single-pass timeline walk that also produces lanes, voices, strip, and the
XCMD projection, and saves no tests — the view-projection checks must pin
timeline pairing regardless. Keep the two pass shapes; they now share one
encoding semantics.

## Non-goals

- Pixel fields on `ViewNote`
- Moving unpaired ons into Other events
- Restoring dashed unterminated borders
- Changing `DocNote`, SMF/document pairing, or the pitch-bend popup flag
- Making zero-duration notes visible
- Vendoring PortSMF or reshaping any layer around Alg types
