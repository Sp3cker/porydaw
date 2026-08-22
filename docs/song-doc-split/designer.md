# SongDocument Split — Domain Model and Deep-Module Design

**Stance:** codebase-design (deep modules, seams, leverage) + domain-modeling (ubiquitous language).
**Scope:** `src/core/songdocument.{h,cpp}` and the existing satellites. No production edits in this pass.
**Verdict:** Keep **one** external module — `SongDocument` — and split only its *implementation*. Do not publish `NoteStore`, `LaneOps`, `TimeOps`, or `UndoSystem` as caller-facing modules. The current problem is a **wide shallow facade sitting on a deep, unpublished engine**, not a missing constellation of public classes.

---

## 1. What is actually here

### 1.1 Inventory

| File | Lines | Role today |
|---|---:|---|
| `src/core/songdocument.h` | 522 | Public types + the entire `SongDocument` interface + private `EditOp` / `TimeEditor` / builder decls |
| `src/core/songdocument.cpp` | 2176 | Commands, load/save, track map, note/lane/raw/track mutations, `applyOps` / `revertOps` |
| `src/core/songdocument_tempo.cpp` | 242 | Projected tempo stream, `TempoEditCommand`, `MixedEditCommand` |
| `src/core/songdocument_timeeditor.hpp` | 78 | Nested `SongDocument::TimeEditor` (under the 80-line floor) |
| `src/core/songdocument_timeeditor.cpp` | 471 | Shared time-edit plan + **remove contents** |
| `src/core/songdocument_timeeditor_insert.cpp` | 278 | **insert blank** + **duplicate** |
| `src/core/songdocument_range.cpp` | 142 | `applyRangeEdit`, `moveRange` |
| **Total** | **3909** | Already a partial split that did not shrink the interface |

Hard ceiling is 600 lines/file; target is 200–400. The header is already in the danger zone. The main `.cpp` is 3.6× the ceiling. The time-editor header is a fragment.

The satellite split already proves the right *kind* of cut (tempo, time, range) and the wrong *kind* of publicity: every satellite is still `SongDocument::method` poking `m_smf` / `m_tempoPoints` / `pushEdit`. That is correct. Do not “fix” it by inventing new public classes.

### 1.2 Callers (who the interface must serve)

Three caller families cross the same seam. That seam **is** `SongDocument`.

1. **Piano roll / selection / velocity** (`src/ui/songview/pianoroll_*.cpp`, `viewstate.cpp`, `velocityarea.cpp`)
   - `notesForTrack`, `findNote(NoteId)`, `addNote` / `addNotes`, `deleteNotes`
   - `moveNotes` / `moveNotesToPitches` (mergeable keyboard vs. one-shot mouse)
   - `resizeNotes` / `resizeNotesLeft`, `setNotesVelocity`, `setNotesVelocities` (revision CAS)
2. **Automation / time selection** (`rangeedit.cpp`, `editordrawer/*`, `nodelane/tempoadapter.cpp`, `pitchbendeditor.cpp`)
   - `lanePoints`, `writeLanePoints`, `moveLanePoints`, `addLanePoint`, `deleteLanePoints`
   - `applyTempoEdit`, `applyRangeEdit`, `moveRange`
   - `removeTimeRange` / `insertBlankTime` / `duplicateTimeRange` via `TimeRange` + `TimeScope`
3. **Event list + checks + playback** (`eventlistviewactions.cpp`, `src/checks/*`, `buildTimeline`)
   - raw index edits, `smf()`, `tempoPoints()`, `tracksRemapped` / `documentChanged` / `revision()`
   - `MidiTimeline::build(smf, tempoPoints, sampleRate)` — a *lossy projection*, never the store

The interface is the test surface (`editcheck.cpp` drives time-range, remap, merge, load). Internal seams must stay unpublished so those checks keep working through `SongDocument`.

---

## 2. Ubiquitous language

These terms are already in the code. The split must use them and stop mixing them.

### 2.1 Identity and storage

**SMF Chunk** (`SmfTrack` in `SmfFile::tracks`):
One MTrk. Indexed as `smfTrack`. Chunk 0 is the **Seq Chunk** — the only place mid2agb reads tempo, time signatures, and loop/label markers from. A chunk is not an engine track.
_Avoid:_ SMF track (when you mean engine track), conductor track (except as informal gloss for an empty seq chunk).

**Engine Track**:
A playable slot 0–15, allocated by `rebuildTrackMap` (`songdocument.cpp` 413–426) for each chunk that contains at least one channel-voice event, in chunk order, first channel byte wins. `m_engineToSmf` / `m_engineChannel` are the live map. Mid2agb / `MidiTimeline` use the same rule.
_Avoid:_ MIDI channel (a property of an engine track, not its identity), track index (ambiguous).

**Seq Chunk**:
Always `tracks[0]` after parse (`SmfFile::read` coerces format 0). Tempo write-back, new loop markers, and new time signatures land here. `deleteTrack` of engine track 0 strips channel events but never removes the chunk. `moveTrack` that displaces chunk 0 migrates seq globals to the new first chunk (`songdocument.cpp` 1961–2010).
_Avoid:_ track 0 (that is an engine slot that may or may not be chunk 0).

**NoteId**:
Document-local opaque token on a note-on `SmfEvent`. Token 0 is unassigned. Never serialized. Never copied across documents. Minted in `mintNoteId` / `applyOps` Insert/Modify/InsertTrack (`songdocument.cpp` 498–513, 2039–2108). Selection and `setNotesVelocities` address notes by `NoteId`. Physical indices are *not* identity.
_Avoid:_ event index, note index, “the note at tick/key” (ambiguous under same-tick duplicates).

**SmfEvent index**:
A location in one chunk’s event vector *right now*. Valid only against the current revision. `DocNote::{smfTrack,onIndex,endIndex}` and `DocLanePoint::{smfTrack,index}` are snapshots. Every mutation comment in the header already says “freshly resolved”.
_Avoid:_ treating these as stable handles.

**DocNote**:
The paired projection of a note-on plus its ending event, using the mid2agb rule: first later same-channel same-key note-end (`isNoteEnd`: 0x8 or velocity-0 0x9). `endIndex == SIZE_MAX` means **unterminated**. Pairing is linear via a backward 16×256 slot table (`notesForTrack`, 571–615) so out-of-range key bytes do not alias.
_Avoid:_ Note, MidiNote, clip note (UI clipboard).

**DocLanePoint**:
One CC / pitch-bend / program-change event as a `(tick, value)` on an engine track. Last same-tick point is the audible one (`findLanePoint` 699–716). No `NoteId` equivalent — lanes are addressed by `(engineTrack, cc, tick)` plus a stale index.
_Avoid:_ automation node (UI), controller event (too MIDI-literal for voice/bend).

### 2.2 Streams

**Value Stream**:
A last-wins, state-carrying series: CC, bend, voice, **projected tempo**, time signatures. Time edits preserve the state the shifted content was authored under: the last in-range point moves to the seam instead of vanishing, unless a point already sits on the destination seam (`TimeEditor::remove` 406–428; `time_edit_detail::removeTempoPoints` 11–37).
_Avoid:_ automation (CONTEXT.md: family name, not a kind), lane (a UI row over a stream).

**Discrete Event**:
Notes (paired), raw metas that are not time-sig/tempo, loop markers under whole-song, orphan note-ends. Time remove deletes in-range discrete events; it does not “hold state” across the cut.

**Projected Tempo** (`std::vector<TempoPoint> m_tempoPoints`):
The live tempo model. Value is microseconds-per-quarter-note, not BPM. On load, FF 51 metas are read then **stripped** from `m_smf` (`load` 368–369). On save they are written back into the seq chunk (`writeTempoMetas`). `applyOps` asserts `!isTempoMeta` on insert/modify (2036, 2078). Raw FF 51 insert is rejected (1484–1485). Tempo is *not* an SMF event in the live document.
_Avoid:_ tempo track, tempo events, DOC_CC for tempo.

**Lane identity** `(engineTrack, cc)`:
`cc` is a real controller, or `DOC_CC_BEND` (0xFF) / `DOC_CC_VOICE` (0xFD). Voice is a value stream in the document and a *non-node* lane in the UI. That split is correct; do not invent a third representation.

### 2.3 Time and batches

**TimeRange**:
Half-open `[startTick, endTick)`. Empty iff `endTick <= startTick`. This is the musical interval, not a selection object.

**TimeScope**:
Which streams a time operation covers: engine tracks, explicit lanes, tempo, or `wholeSong`. `wholeSong` ignores `tracks`/`lanes` and also covers seq globals + every chunk `endTick` (header 261–266; `eventCovered` 132–148). UI builds this in `SongView::resolveTimeSelectionScope` (`rangeedit.cpp` 58–86) from **Track Scope** / **Lane Scope** (CONTEXT.md). `TimeScope` is the document’s compiled form of those selection terms.

**RangeEdit**:
An explicit multi-stream batch: remove these notes/points/tempo ticks, insert these notes/points/tempo points, one undo item, one `documentChanged`. Indices are read at push time. This is *not* a time operation — it does not close gaps or split notes.

**Time operation** (`removeTimeRange` / `insertBlankTime` / `duplicateTimeRange`):
Structural. Shifts later content, splits notes that cross a seam on insert/duplicate, preserves value-stream state, optionally shortens/lengthens chunk `endTick`. Implemented by nested `TimeEditor`.

### 2.4 Mutation machinery (internal language)

**EditOp**:
The reversible bytecode of the document. Eight kinds: `InsertEvent`, `RemoveEvent`, `ModifyEvent`, `MoveEvent`, `InsertTrack`, `RemoveTrack`, `SetTrackEnd`, `MoveTrack` (header 407–427). Removals carry apply-time indices and must be sorted descending per chunk (`appendRemoveOps` 809–821). Inserts resolve their index on apply via `upper_bound` plus intra-tick pinning (2035–2065).

**Command pipeline**:
`QUndoStack` of `SongEditCommand` | `TempoEditCommand` | `MixedEditCommand` | `SongCfgCommand` | `MoveNotesCommand` | `MoveNotesToPitchesCommand`. Every user-visible mutation is one stack item.

**TrackRemap**:
Old SMF-chunk index → new index, old engine slot → new slot, `-1` = deleted / no longer an engine track. Emitted on `tracksRemapped` *before* `documentChanged` when non-identity (`publishMutation` 490–496). Undo emits `inverse()`.

**Revision**:
Monotonic `m_revision`, incremented only in `publishMutation`. `setNotesVelocities` is compare-and-swap on it (1221–1263). Not every `documentChanged` goes through `publishMutation` — see §5.3.

---

## 3. Depth diagnosis

### 3.1 What is already deep

Several existing entry points pass the deletion test. If they vanished, the complexity would explode across UI and checks.

| Entry point | Hidden behaviour |
|---|---|
| `moveNotes` / `MoveNotesCommand` | Overlap trim, ID preservation, merge-by-rewind, clean-index refusal, publish-after-merge |
| `applyRangeEdit` | Multi-track remove+insert, overlap trim, tempo mix via `MixedEditCommand` |
| `removeTimeRange` / `insertBlankTime` / `duplicateTimeRange` | Stream classification, seam preservation, note split, whole-song `endTick`, tempo projection |
| `applyTempoEdit` | Normalize (sort, clamp µs/qn, last-wins per tick), no-op if unchanged |
| `buildTimeline` | Lossy sample-accurate projection; document stays the store |
| `rebuildTrackMap` + `trackRemap` | Engine-slot allocation and ownership mapping |
| `applyOps` InsertEvent | Tick sort + setup-before-notes + note-end-before-note-on |

These are the modules. They are just trapped inside one class and one 2k-line file.

### 3.2 What is shallow

The *interface* is shallow: ~66 public methods, plus six nested public structs, plus leaked physical indices. Callers must know almost as much as the implementation.

Concrete shallowness:

1. **`DocNote` / `DocLanePoint` leak storage.** UI clipboard and checks re-scan `notesForTrack` and stuff indices back into the next call. `NoteId` already exists for notes; lanes have no durable id. Every “freshly resolved” comment is an interface failure.
2. **Parallel verbs that share one engine.** `addNote` is `addNotes` of one. `setNotesVelocity` / `nudgeNotesVelocity` / `setNotesVelocities` are three doors into `ModifyEvent` on a note-on. `deleteLanePoints` ignores its `engineTrack` argument (`Q_UNUSED`, 1465).
3. **Tempo has two mutation doors.** `applyTempoEdit` (tempo-only command) vs. `pushEdit(text, ops, nextTempo)` (mixed). The header has to warn callers not to call `applyTempoEdit` from a mixed redo (74–76). That warning is interface, not implementation.
4. **Raw vs. semantic live on one type.** Piano-roll callers compile against `insertRawEvent`, `rawEventMoveBounds`, `EditOp`’s private presence, and `<algorithm>` because `TimeScope` inlines `std::find`.
5. **Inconsistent publication.** `MoveNotesToPitchesCommand::redo` emits `documentChanged()` directly and does **not** increment `m_revision` or emit remaps (`songdocument.cpp` 283–293). `MoveNotesCommand` suppresses the initial redo publish and lets `moveNotes` call `publishMutation` (1005–1010). Same user-facing idea, two contracts. Preserve this until a test pins the intended one — a split that “cleans it up” is a behaviour change.

### 3.3 Header as interface

`songdocument.h` is 522 lines. Nested `RangeEdit` / `TimeRange` / `TimeScope` / `NewNote` / `LanePointValue` / `LanePointMove` account for a large fraction. Meanwhile `DocNote`, `DocLanePoint`, `TempoEdit`, `TrackRemap` are already free-standing. That inconsistency is accidental, not a seam.

`#include <algorithm>` and `#include "project/decompproject.h"` are header pollution. `SongInfo` / `SongCfg` are real parameters of `load` / `setCfg`; the algorithm include is not.

### 3.4 Dependency category

Everything behind this seam is **in-process** (codebase-design / Deepening, category 1). No port, no adapter, no `ISongStore`. One live document, one in-memory `SmfFile`, one stack. “Two adapters means a real seam” — there is only one adapter. Do not introduce a virtual document.

`MidiTimeline` is not an adapter of `SongDocument`. It is a *downstream projection*. `buildTimeline` is the only legitimate door from document → playback.

---

## 4. Ownership and data flow

```
                    ┌──────────────────────────────────────────┐
                    │              SongDocument                │
                    │                                          │
  SongInfo ──────►  │  load()                                  │
                    │    SmfFile::readFile                     │
                    │    tempoPointsFromSmf → normalize        │
                    │    removeTempoMetas(m_smf)               │
                    │    mintUnassignedNoteIds                 │
                    │    rebuildTrackMap                       │
                    │    publishMutation(load remap)           │
                    │                                          │
                    │  owns:                                   │
                    │    m_smf            (canonical, no FF51) │
                    │    m_tempoPoints    (projected stream)   │
                    │    m_undoStack      (QUndoStack)         │
                    │    m_revision       (CAS token)          │
                    │    m_nextNoteId                          │
                    │    m_engineToSmf / m_engineChannel       │
                    │    m_cfg / m_savedCfg / paths            │
                    │    m_trackBudget    (UI/playback hint)   │
                    └─────────────┬─────────────┬──────────────┘
                                  │             │
                                  │             │ buildTimeline()
                                  ▼             ▼
                           .mid + midi.cfg   MidiTimeline
                           save()            (audio thread, immutable)
```

**Who owns what — non-negotiable:**

| Resource | Owner | Not owner |
|---|---|---|
| `SmfFile` | `SongDocument` | UI, TimeEditor, commands, MidiTimeline |
| `m_tempoPoints` | `SongDocument`; sole writer `replaceTempoPoints` | Anyone inserting FF 51 |
| `QUndoStack` | `SongDocument` (`m_undoStack`) | Callers may *observe* via `undoStack()` |
| `m_revision` | `publishMutation` only | Commands that emit `documentChanged` by hand (today: pitch-move) |
| Signals | `SongDocument` | Nested helpers emit only through `publishMutation` / the two move commands |
| `NoteId` mint | `applyOps` + `mintUnassignedNoteIds` | Callers, clipboard |
| Track map | `rebuildTrackMap` after every op apply/revert | UI caches, invalidated by `tracksRemapped` |

**Mutation data flow (the one pipeline):**

```
UI / check
  │  named method (addNotes, applyRangeEdit, removeTimeRange, …)
  ▼
builder (SongDocument method or TimeEditor)
  │  reads current m_smf / m_tempoPoints
  │  resolveNoteOverlaps / planLaneMoves / time plan
  │  produces vector<EditOp> [+ optional nextTempo]
  ▼
pushEdit / specialized QUndoCommand
  │  stack.push → redo()
  ▼
applyOps (records oldEvent / index / oldEndTick / trackData)
  rebuildTrackMap
  replaceTempoPoints?   (mixed / tempo-only)
  publishMutation(remap)
      revision++
      tracksRemapped?    (if !identity)
      documentChanged
```

Undo is the same tape played backwards: `revertOps` in reverse, tempo restored, `publishMutation(inverse)`.

`TimeEditor` is not a second pipeline. It only *builds* ops and calls `pushEdit`.

---

## 5. Where the facade must end

```
                    PUBLIC SEAM  (learn this, test this)
┌─────────────────────────────────────────────────────────────┐
│  SongDocument                                               │
│    load/save · queries · named edits · signals · timeline   │
├─────────────────────────────────────────────────────────────┤
│  INTERNAL SEAMS  (TUs / nested types, not new includes)     │
│                                                             │
│   EditPipeline     applyOps/revertOps/pushEdit/commands     │
│   NoteOps          pair, overlap, note builders             │
│   LaneOps          CC/bend/voice + planLaneMoves            │
│   TempoModel       normalize, strip/write FF 51, TempoEdit  │
│   TimeEditor       remove / insertBlank / duplicate         │
│   RangeOps         RangeEdit + moveRange                    │
│   TrackLayout      map, remap, add/dup/delete/move/rename   │
│   RawOps           event-list edits, loop, time-sig, EOT    │
└─────────────────────────────────────────────────────────────┘
         │
         ▼
   SmfFile · TempoPoint · NoteId · lanemoveplan (already separate)
```

**Facade ends** at the named methods and the free-standing value types.
**Internal subsystems begin** at `EditOp` and everything that consumes it.

Do **not** put `EditOp`, `PlannedNote`, `TimeEditor`, or any command class in a header the UI can see as a feature. They can stay in `songdocument.h`’s `private:` section (today) or move to a document-private header included only by `src/core/document/*.cpp`.

`lanemoveplan.{h,cpp}` is already the right shape: a pure function over value types, used by `moveLanePoints`. Leave it in `src/core/`. It is not SongDocument.

---

## 6. Design it twice

Three real alternatives. Only one survives the deletion test without multiplying shallow modules.

### Design A — “Seven verbs” (minimize the interface)

```cpp
void editNotes(NoteBatch);
void editLanes(LaneBatch);
void applyTempoEdit(TempoEdit);
void applyRangeEdit(RangeEdit);
bool applyTimeOp(TimeOpKind, TimeRange, TimeScope);
void editTracks(TrackOp);
void editRaw(RawOp);
```

**Depth:** highest per entry point. `RangeEdit` already proves the pattern.
**Cost:** every piano-roll click constructs a batch object. Mergeable moves become flags inside `NoteBatch`, which is how you hide a `MoveNotesCommand` and then rediscover it. Checks become unreadable. The common caller (one note draw) gets worse.
**Reject** as the *only* public surface. Keep `RangeEdit` / `TempoEdit` / `TimeRange+TimeScope` as the batch/structural doors they already are.

### Design B — Public role objects

```cpp
doc.notes().move(...);
doc.lanes().write(...);
doc.tempo().apply(...);
doc.time().remove(...);
doc.tracks().remap();
doc.raw().insert(...);
doc.undo()...
```

**Looks** like modularity. **Is** six new shallow modules that all mutate the same `SmfFile` and must share `EditOp`, the stack, and remap publication. Callers now learn six interfaces *and* the cross-cutting “one undo item / one revision” rule. Two adapters? No — still one document. Hypothetical seam.
**Reject.** This is the design that would feel productive in week one and hostile in month six.

### Design C — One deep facade, split implementation (recommended)

Keep today’s *named* methods. Hoist the already-public value types. Move code under `src/core/document/` so each TU is one internal module. Optionally deepen a few methods later (NoteId-first deletes, drop unused arguments) without changing the module shape.

**Depth:** unchanged for callers on day one; *locality* appears immediately.
**Leverage:** every existing check and UI path keeps compiling against `SongDocument`.
**Seam:** still one, still the right one.

Hybrid worth taking from A: do **not** add more one-off verbs. New cross-stream work goes through `RangeEdit` or `TimeScope`, not `deleteNotesAndLanePointsAndTempo(...)`.

---

## 7. Recommended target layout

`src/core/document/` holds the implementation of the one module. Public include becomes `core/document/songdocument.h`. Update every `#include "core/songdocument.h"` (mechanical; no forwarding shim).

```
src/core/document/
  types.h                 public value types (already part of the interface)
  songdocument.h          the class (methods + private engine decls)
  songdocument.cpp        identity: load/save/cfg/timeline/publish/mint
  pipeline.cpp            EditOp apply/revert, pushEdit, generic commands
  note_commands.cpp       MoveNotesCommand + MoveNotesToPitchesCommand
  notes_query.cpp         pairing and lookups
  notes_edit.cpp          add/delete/resize/velocity + overlap + builders
  lanes.cpp               lane query + write/move/delete
  tempo.cpp               projected tempo + Tempo/Mixed commands
  range.cpp               RangeEdit + moveRange
  timeeditor.hpp          TimeEditor + time_edit_detail decls (private)
  timeeditor.cpp          plan + remove
  timeeditor_insert.cpp   insertBlank + duplicate
  tracks.cpp              engine map, remap, add/dup/delete/move/rename
  raw.cpp                 raw event list, loop, time signature, track end
```

Leave in `src/core/`: `smf.{h,cpp}`, `noteid.h`, `tempo.h`, `timedefaults.h`, `miditimeline.{h,cpp}`, `lanemoveplan.{h,cpp}`. Those are already separate modules.

### 7.1 Line budgets

Estimates from the current bodies. Target 200–400; hard 600; no file under 80.

| File | Est. | Why this cut |
|---|---:|---|
| `types.h` | 210–240 | Hoist every public struct that is not `SongDocument` itself |
| `songdocument.h` | 300–360 | Class only; private `EditOp` / builder decls stay here or in `document_p.h` |
| `songdocument.cpp` | 240–300 | `load`/`save`/`publishMutation`/`mint*`/`setCfg`/`buildTimeline`/`ticksPerClock` |
| `pipeline.cpp` | 380–450 | `applyOps`+`revertOps` (~145) + `SongEdit`/`SongCfg`/`pushEdit` + shared append/make helpers |
| `note_commands.cpp` | 250–290 | Both mergeable commands + the two public wrappers that push them |
| `notes_query.cpp` | 220–260 | `noteAt`, `notesForTrack`, both `findNote`, `noteEndTick`, `containsNoteSpan` |
| `notes_edit.cpp` | 360–420 | `resolveNoteOverlaps`, add/delete, `buildMove*Ops`, resize, velocity trio |
| `lanes.cpp` | 250–300 | match/value/make + four mutators; uses `planLaneMoves` |
| `tempo.cpp` | 240–260 | today’s `songdocument_tempo.cpp` almost unchanged |
| `range.cpp` | 140–160 | today’s file; above the floor, one contract |
| `timeeditor.hpp` | 95–120 | today’s 78 + `time_edit_detail` declarations (kills the fragment and the redecls in insert.cpp) |
| `timeeditor.cpp` | 430–470 | plan + `remove` + shared helpers |
| `timeeditor_insert.cpp` | 270–290 | `insertBlank` + `duplicate` |
| `tracks.cpp` | 360–420 | map/remap + track CRUD + name metas |
| `raw.cpp` | 280–340 | raw CRUD, `rawEventMoveBounds`, loop, time-sig, `setTrackEndTick` |

`range.cpp` at ~142 is allowed. Do not merge it into `lanes.cpp` just to fatten a file — `RangeEdit` is a different contract (multi-stream batch, optional tempo, overlap on *inserted* notes).

If `pipeline.cpp` threatens 500+, peel `makeChannelEvent` / `appendRemoveOps` / `appendNoteInsertOps` / `appendEventEditOps` into `notes_edit.cpp` (they are note-shaped) and keep `applyOps` with the commands.

Optional private header, **only if** `songdocument.h` cannot get under 400:

```
src/core/document/document_p.h    EditOp, PlannedNote, TimeEditor fwd, helper decls
```

Included solely by `document/*.cpp` and `timeeditor.hpp`. Not a public module. Not an adapter.

### 7.2 What each file is allowed to know

| File | May touch | Must not |
|---|---|---|
| `songdocument.cpp` | all members; load/save policy | note pairing, time plans |
| `pipeline.cpp` | `m_smf`, mint, endTick | semantic “what is a note” |
| `note_commands.cpp` | `buildMove*Ops`, apply/revert, merge rules | lane/tempo/raw |
| `notes_*.cpp` | notes, overlap, `EditOp` note shapes | track create, tempo metas |
| `lanes.cpp` | lane events, `planLaneMoves` | note pairing |
| `tempo.cpp` | `m_tempoPoints`, seq-chunk FF 51 on save/load helpers | inserting FF 51 via `EditOp` |
| `range.cpp` | notes + lanes + tempo payloads | time-gap close, track remap ops |
| `timeeditor*` | everything needed to plan a scoped time rewrite | pushing two undo items |
| `tracks.cpp` | chunk vector, seq-global rescue, names | note overlap |
| `raw.cpp` | indices, intra-tick bounds, loop/time-sig metas | projected tempo writes |

Crossing those lines is how the current 2176-line file happened.

---

## 8. Public interface (the external seam)

### 8.1 Types — hoist, do not reinvent

Move to `src/core/document/types.h`, namespace-less, matching `DocNote` today:

```cpp
constexpr uint8_t DOC_CC_BEND  = CoreTimeDefaults::kLaneCcBend;
constexpr uint8_t DOC_CC_VOICE = CoreTimeDefaults::kLaneCcVoice;

bool metaIsLoopMarker(const SmfEvent &ev, char marker);
bool nameIsLoopMarker(const QString &name);

struct TrackRemap { /* unchanged */ };
struct DocNote { /* unchanged, including leaked indices — Phase B */ };
struct DocLanePoint { /* unchanged */ };
struct DocTimeSig { /* unchanged */ };
struct TempoEdit { /* unchanged */ };

struct NewNote { uint64_t tick; uint8_t key; uint32_t duration; uint8_t velocity; };
struct LanePointValue { uint64_t tick; int value; };
struct LanePointMove {
    int engineTrack = -1;
    uint8_t cc = 0;
    DocLanePoint point;
    uint64_t newTick = 0;
    int newValue = 0;
};

struct RangeEdit { /* today’s nested body, including TrackNotes / LaneWrite */ };

struct TimeRange { /* today’s nested body */ };
struct TimeScope { /* today’s nested body */ };
```

On `SongDocument`, keep compatibility aliases so existing `SongDocument::TimeRange` spellings compile during the move:

```cpp
using TimeRange = ::TimeRange;
using TimeScope = ::TimeScope;
using RangeEdit = ::RangeEdit;
using NewNote = ::NewNote;
using LanePointValue = ::LanePointValue;
using LanePointMove = ::LanePointMove;
```

That is a typedef, not a shim module. Delete the aliases once callers use the free names.

### 8.2 `SongDocument` — keep these methods

Group as comments in the header, not as public nested objects.

**Identity and persistence**

```cpp
bool load(const SongInfo &song, QString *error);
bool save(QString *error);
const QString &midPath() const;
const QString &label() const;
const SmfFile &smf() const;                 // read-only store view
const std::vector<TempoPoint> &tempoPoints() const;
const SongCfg &cfg() const;
void setCfg(const SongCfg &cfg);
QUndoStack *undoStack();
bool isDirty() const;
uint64_t revision() const;
uint32_t ticksPerClock() const;
int trackBudget() const;
void setTrackBudget(int budget);
```

**Engine layout (queries only)**

```cpp
int engineTrackCount() const;
int smfTrackFor(int engineTrack) const;
uint8_t channelFor(int engineTrack) const;
QString trackName(int engineTrack) const;
```

**Queries**

```cpp
std::vector<DocNote> notesForTrack(int engineTrack) const;
bool findNote(int engineTrack, uint64_t tick, uint8_t key, DocNote *out) const;
bool findNote(NoteId id, DocNote *out) const;
uint64_t noteEndTick(const DocNote &note) const;
bool containsNoteSpan(int engineTrack, const DocNote &snapshot, uint64_t expectedEndTick) const;
std::vector<DocLanePoint> lanePoints(int engineTrack, uint8_t cc) const;
bool findLanePoint(int engineTrack, uint8_t cc, uint64_t tick, DocLanePoint *out) const;
uint64_t loopTick(bool endMarker) const;          // UINT64_MAX if absent
std::vector<DocTimeSig> timeSigs() const;
```

**Named edits (one undo item each)** — signatures stay byte-identical in Phase A.

**Projection**

```cpp
std::unique_ptr<MidiTimeline> buildTimeline(double sampleRate) const;
```

**Signals** — order is part of the interface:

```
tracksRemapped(TrackRemap)     // only if !remap.isIdentity()
documentChanged()              // always, after remap
```

`load` publishes a full-delete remap of the previous map (376–383). Listeners rely on that.

### 8.3 Phase B deepenings (same module, smaller interface)

Do these *after* the file move, each with its own check, never mixed into the mechanical split.

1. **Note mutations accept `NoteId` (or `DocNote` without requiring live indices).** Document resolves. UI stops threading `onIndex`.
2. **Drop `addNote`** — it is `addNotes({one})`.
3. **Drop `engineTrack` from `deleteLanePoints`** — it is already unused.
4. **One velocity door.** Keep `setNotesVelocities` (CAS, paint) and `nudgeNotesVelocity` (relative). Implement `setNotesVelocity` as a wrapper or delete it once UI calls the CAS path.
5. **Do not add `doc.notes()`.**
6. **Consider a durable lane-point identity** only if selection needs it. Until then `(track, cc, tick)` last-wins is the model.

### 8.4 What stays off the public interface

- `EditOp`, `PlannedNote`, `TrackMapState`, `TimeEditor`
- All `QUndoCommand` subclasses
- `replaceTempoPoints`, `normalizeTempoPoints`, `tempoPointsFromSmf`
- `applyOps` / `revertOps` / `pushEdit`
- `resolveNoteOverlaps`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`
- `mintNoteId`, `rebuildTrackMap`, `trackRemap`, `publishMutation`
- `time_edit_detail::*`

If a check wants to assert op order, it is testing past the seam. Refuse.

---

## 9. Internal interfaces

These are **not** types UI includes. They are the contracts the TUs owe each other.

### 9.1 EditPipeline

```cpp
// document-private
void SongDocument::applyOps(std::vector<EditOp> &ops);
void SongDocument::revertOps(std::vector<EditOp> &ops);
void SongDocument::pushEdit(const QString &text, std::vector<EditOp> ops);
void SongDocument::pushEdit(const QString &text, std::vector<EditOp> ops,
                            std::vector<TempoPoint> nextTempo);
void SongDocument::publishMutation(TrackRemap remap);
```

**Invariants**

- Removals in a batch are descending per chunk; inserts after all removals (except `TimeEditor` / range, which already assemble that way).
- `InsertEvent` / `ModifyEvent` never carry `isTempoMeta`.
- First apply of an insert that is a note-on mints an id and sets `preservesNoteId` so redo does not mint a second id (2039–2042, 2103–2108).
- `ModifyEvent` copies `oldEvent.noteId` when both sides are note-ons (2081–2083).
- Intra-tick placement: setup (`typeNibble >= 0xB`) before same-tick notes; note-end before same-tick note-on (2047–2063). `rawEventMoveBounds` pins the same relation (1536–1540).
- `pushEdit(text, ops, nextTempo)` normalizes tempo and no-ops if `ops.empty() && normalized == m_tempoPoints` (168–174).
- `pushEdit(text, ops)` no-ops on empty ops (2171–2175).

### 9.2 NoteOps

```cpp
std::vector<DocNote> SongDocument::notesForTrack(int engineTrack) const;
void resolveNoteOverlaps(const std::vector<PlannedNote> &written,
                         const std::vector<DocNote> &editNotes,
                         std::vector<std::vector<size_t>> &removals,
                         std::vector<EditOp> &trims) const;
std::vector<EditOp> buildMoveNotesOps(...) const;
std::vector<EditOp> buildMoveNotesToPitchesOps(...) const;
```

**Invariants**

- Pairing = first later same-channel same-key end; several ons may share one end.
- Unterminated notes are not overlap-trimmed (877–878) and keep their on-event bytes when moved (`preservesNoteId`).
- Written span wins: stationary same-key overlap keeps head, or tail, or is deleted; **never split** (header 461–474; impl 853–929).
- `MoveNotesCommand` merge: `id() == 0x4d76` when mergeable; rewind both, rebuild from **original** `m_notes`, land accumulated delta; inverse merge may `setObsolete(true)` and still publish from `moveNotes` (162–229, 1005–1010).
- `MoveNotesToPitchesCommand` merge: `id() == 0x4d50`; requires all notes on one engine track; **preserve today’s publication quirk** (§5.3) until specified otherwise.
- QUndoStack will not merge across the clean index — do not reimplement that.

### 9.3 LaneOps

```cpp
bool laneEventMatches(const SmfEvent &, uint8_t cc) const;
int  laneValue(const SmfEvent &, uint8_t cc) const;
SmfEvent makeLaneEvent(uint8_t cc, uint8_t channel, uint64_t tick, int value) const;
```

**Invariants**

- Same-tick replace, not shadow (`addLanePoint` 1306–1314; `findLanePoint` last-wins).
- `writeLanePoints` overwrites `[tickBegin, tickEnd]` inclusive (1332–1335) — **closed** interval, unlike `TimeRange`. Do not “fix” this during the split.
- `moveLanePoints` is `planLaneMoves` then modify-in-place when tick unchanged, else remove+insert. Voice uses the same path.
- Not for tempo. Not a fake lane.

### 9.4 TempoModel

```cpp
static std::vector<TempoPoint> tempoPointsFromSmf(const SmfFile &);
static std::vector<TempoPoint> normalizeTempoPoints(std::vector<TempoPoint>);
void replaceTempoPoints(std::vector<TempoPoint> normalized);  // sole writer
void applyTempoEdit(const TempoEdit &);
// namespace song_document_tempo:
void removeTempoMetas(SmfFile &);
void writeTempoMetas(SmfFile &, const std::vector<TempoPoint> &);
```

**Invariants**

- Normalized = strictly increasing ticks, last-wins on a tick, µs/qn clamped (`normalizeTempoPoints` 37–52; `Q_ASSERT` on write 179).
- Live `m_smf` contains zero FF 51.
- `writeTempoMetas` merges into seq chunk keeping non-tempo events; tempo metas sit *before* same-tick leftovers (86–91) — save-round-trip shape.
- Mixed time/range commands call `pushEdit(..., nextTempo)`, never `applyTempoEdit`.

### 9.5 TimeEditor

```cpp
class SongDocument::TimeEditor {
    bool remove();
    bool insertBlank();
    bool duplicate();
};
```

Public doors remain:

```cpp
bool removeTimeRange(const TimeRange &, const TimeScope &);
bool insertBlankTime(const TimeRange &, const TimeScope &);
bool duplicateTimeRange(const TimeRange &, const TimeScope &);
```

**Invariants**

- Empty range or empty SMF → false, no command.
- `EventKind::{Note, ChannelState, TimeSig, Other}`; value streams = ChannelState + TimeSig + projected tempo.
- Remove: last in-range value-stream point moves to `startTick` unless seam `endTick` already holds one. Discrete in-range notes die. Notes starting at/after `endTick` shift left. Whole-song also moves `Other` metas to the seam (never deletes them) and closes every `endTick` (`timeEditCloseGapTrackEnds` 228–248).
- Insert blank: events at/after `startTick` shift right; notes crossing the seam split so the hole is silent (insert.cpp 49–72). Overflow → false.
- Duplicate: copy `[start, end)` to `endTick`, shift later content, seed destination seam with effective value-stream state (insert.cpp 186–245), including implicit CC defaults via `CoreTimeDefaults::controllerDefault`.
- Tempo uses `time_edit_detail::{remove,insertBlank,duplicate}TempoPoints`, then one `pushEdit`.
- `eventCovered`: tempo metas never selected from SMF (they are not there); whole-song covers non-channel events plus channel events on mapped engine tracks (132–148).

### 9.6 TrackLayout

```cpp
void rebuildTrackMap();
TrackMapState trackMapState() const;
TrackRemap currentTrackRemap() const;          // identity of *current* counts
TrackRemap trackRemap(const TrackMapState &before, const std::vector<EditOp> &ops) const;
int addTrack(int voice);                       // -1 if none free
int duplicateTrack(int engineTrack);           // channel events only, EOT kept
void deleteTrack(int engineTrack);
bool moveTrack(int engineTrack, int targetEngine);
void renameTrack(int engineTrack, const QString &name);
```

**Invariants**

- Engine count ≤ 16; unique MIDI channels; `freeChannel` / `canAddTrack`.
- New track = new chunk + program-change seed at tick 0 (`addTrack` 1738–1760).
- Duplicate copies owned channel events onto a new channel; no metas (`duplicateTrack` 1763–1796).
- Delete engine-on-chunk-0: strip channel events. Delete other: rescue time-sigs and winning loop markers into chunk 0, then `RemoveTrack` (1798–1846).
- Move that changes who is chunk 0: strip seq globals (time-sig + marker family, but not the chunk name / prefixed non-marker 0x03) and reinsert into the new first chunk (1951–2013).
- Names: first unprefixed 0x03; `nameIsLoopMarker` refused; empty name removes.

### 9.7 RawOps

Event-list contract, unchanged:

- No semantic validation (orphan note-ons are legal).
- Tick-changing modify = remove + reinsert (`appendEventEditOps`).
- `moveRawEvent` cannot leave the tick group or break pinning; no-op if clamped dest == index.
- `setTrackEndTick` never precedes the last event.

---

## 10. Signals, revision, dirty — the publication contract

This is the easiest thing for a split to break. Write it down as interface.

| Path | `m_revision++` | `tracksRemapped` | `documentChanged` |
|---|---|---|---|
| `SongEditCommand` redo/undo | yes (`publishMutation`) | if !identity / inverse | yes |
| `TempoEditCommand` | yes | only if somehow non-identity (uses `currentTrackRemap`, i.e. almost never) | yes |
| `MixedEditCommand` | yes | as remap of ops | yes |
| `SongCfgCommand` | yes | identity remap → no remap signal | yes |
| `MoveNotesCommand` initial redo | **no** (suppressed) | no | no |
| `moveNotes` after `push` | yes (`currentTrackRemap`) | no (identity) | yes |
| `MoveNotesCommand` merge | no publish inside merge | — | next `moveNotes` publishes |
| `MoveNotesCommand` undo | yes | inverse | yes |
| `MoveNotesToPitchesCommand` redo/undo/merge | **no** | **no** | **yes, direct emit** |
| `load` | yes | full `-1` remap of previous | yes |

`isDirty()` is `!m_undoStack.isClean()`. `save` writes SMF+tempo, maybe midi.cfg, then `setClean()`. Load `clear()`s the stack.

`setNotesVelocities(expectedRevision, …)` returns `nullopt` if revision mismatches or a `NoteId` is missing; returns the (possibly unchanged) revision if it pushed or was a no-op. Pitch-move’s failure to bump revision is visible here. **Do not silently route pitch-move through `publishMutation` in the split.**

---

## 11. Domain scenarios the new layout must still get right

These are the edge cases that force the language above. If a proposed extra class cannot state them, it is the wrong class.

1. **Two notes, same tick, same key, different `NoteId`.** Selection and velocity paint must not confuse them. Pairing may share one end. Identity is `NoteId`, not `(tick,key)`.
2. **Keyboard transpose through a neighbour.** Intermediate overlaps trim the neighbour; merge rewinds to the gesture start and re-lands once. Undo of the merged command restores the start, including the untrimmed neighbour.
3. **Save between two transpose keypresses.** Stack clean index blocks merge. Two commands. Do not special-case this in NoteOps.
4. **Time remove on a CC lane, last point in range, nothing at `endTick`.** That point must reappear at `startTick` with the same value. Tempo uses the identical rule in `removeTempoPoints`.
5. **Insert blank through a sounding note.** The note splits; the hole is silent; the right fragment is a new note (new `NoteId`, `preserveNoteId == false` in insert.cpp 59–61).
6. **Duplicate a CC range with no point at `startTick`.** Destination seam is seeded from the last point at-or-before start, or from the controller default if the first point is strictly inside (insert.cpp 196–237).
7. **Delete the engine track whose chunk is 0.** Seq chunk remains; channel events go; tempo stream untouched; loop/time-sig stay.
8. **Move the seq chunk away from index 0.** Time-sigs and markers migrate; the chunk’s name meta travels with the chunk; engine order follows chunk order.
9. **Raw insert of FF 51.** Rejected. Tempo lives in `m_tempoPoints`. Event list edits tempo through `applyTempoEdit` / mixed helpers (`removeRawEventsAndEditTempo`, `replaceTempoPointWithRawEvent`).
10. **Whole-song remove.** Metas are not deleted; they slide to the seam. Every `endTick` closes. The song gets shorter.
11. **`writeLanePoints` vs `TimeRange`.** Lane draw is a **closed** tick interval; time ops are half-open. Clipboard range copy uses half-open (`rangeedit.cpp` 126–128). Mixing these is a bug factory — keep both, document both.

---

## 12. Migration sequence

Mechanical, behaviour-preserving, one check family per step. No “while we’re here”.

1. **Create `src/core/document/` and hoist types** into `types.h`. `songdocument.h` includes it and adds `using` aliases. Header line count should drop before any `.cpp` moves. Compile only.
2. **Move `tempo.cpp` / `range.cpp` / `timeeditor*` as-is** (already separate TUs). Update CMake paths. This is a rename.
3. **Cut `pipeline.cpp` + `note_commands.cpp` out of `songdocument.cpp`.** Highest risk: friend commands, merge, publication order. `editcheck` merge/remap cases are the gate.
4. **Cut `notes_query.cpp` + `notes_edit.cpp`.** Gate: rollcheck note identity, overlap, velocity CAS.
5. **Cut `lanes.cpp`.** Gate: automation gesture checks, `planLaneMoves` collision cases.
6. **Cut `tracks.cpp`.** Gate: `editcheck` remap order (`tracksRemapped` then `documentChanged`), seq-global rescue, name/loop collisions.
7. **Cut `raw.cpp`.** Gate: `eventviewcheck`.
8. **Leave `songdocument.cpp` as load/save/publish/mint/timeline.** Confirm it sits in the 200–400 band.
9. **Expand `timeeditor.hpp`** with `time_edit_detail` declarations so it is not a 78-line fragment.
10. **Only then** Phase B signature deepenings, one verb at a time.

CMake today lists the six sources explicitly (`CMakeLists.txt` ~179–183). Replace those entries; do not glob.

Do not run the world-suite between steps 2–8 if the assignment for implementers is the same as this one; run the **named** check for that slice.

---

## 13. What not to do

- **Do not** create `INoteStore` / virtual documents / “for testability”. Category 1 dependency. Tests already construct a real `SongDocument`.
- **Do not** give UI a `TimeEditor` or an `EditOp` builder. The three bool methods are the interface; 700 lines behind them is the point.
- **Do not** put tempo back into live SMF so “everything is events”. The dual store is the deepest existing seam and the reason `MixedEditCommand` exists.
- **Do not** make time-sig a second projected stream in this split. Conceptually it is a value stream; physically it is SMF. Changing that is a behaviour project.
- **Do not** unify `writeLanePoints`’s closed interval with `TimeRange`’s half-open interval as a drive-by.
- **Do not** “fix” `MoveNotesToPitchesCommand` publication while moving files.
- **Do not** split into many &lt;80-line headers (`NoteInsert.h`, `Overlap.h`, …). That is the fragment failure mode.
- **Do not** leave `src/core/songdocument.h` as a forwarding include “for compatibility”. Update includes; delete the old path.
- **Do not** add a `src/core/document/` public sub-API that UI includes besides `songdocument.h` and `types.h`. `timeeditor.hpp` is private.
- **Do not** move `lanemoveplan` or `MidiTimeline` under `document/`. They are already modules.

---

## 14. How this meets the file-size rule without lying

A 522-line header cannot become a 200-line header without either PIMPL or deleting methods. Phase A should land `songdocument.h` around 300–360 (types hoisted, methods unchanged). That is honest and under the hard ceiling. Phase B is what gets it into the 200–400 *target*.

`songdocument.cpp` at 2176 is the actual emergency. The layout above is sized from current function bodies so no TU is a junk drawer and none is a postage stamp.

The existing satellites (`tempo`, `range`, `timeeditor`) are the proof that **method-preserving TU splits work in this codebase**. Finish that job. Do not start a different one.

---

## 15. Glossary for the implementer (short)

| Say | Do not say |
|---|---|
| SMF Chunk / Seq Chunk | SMF track (unless you really mean engine-mapped chunk index `smfTrack`) |
| Engine Track | current track, MIDI track, lane |
| NoteId | note index, event index |
| Value Stream | automation (kind), CC (when you also mean tempo/timesig/voice) |
| Projected Tempo | tempo events in the live SMF |
| TimeRange / TimeScope | selection, loop region |
| RangeEdit | time operation |
| EditOp (internal) | command (that’s the QUndoCommand) |
| Facade / internal seam | service, component, layer |

`SongDocument` is the document. Everything else in `src/core/document/` is how it is compiled, not what callers learn.
