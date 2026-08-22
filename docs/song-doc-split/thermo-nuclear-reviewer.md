# Thermo-Nuclear Code Quality Review — `SongDocument`

**Reviewer:** Thermo-Nuclear Code Quality Reviewer
**Scope:** `src/core/songdocument.{h,cpp}` (2,698 lines), `src/core/songdocument_timeeditor.{cpp,hpp}` (549), `src/core/songdocument_timeeditor_insert.cpp` (278), `src/core/songdocument_tempo.cpp` (242), `src/core/songdocument_range.cpp` (142) — 3,909 lines total.
**Consumers:** 45+ files across `src/ui/`, `src/checks/`, `src/songsession.h` include `songdocument.h` directly.
**Verdict:** **The approval bar is not met for further growth.** The code is individually well-documented and behaviorally careful — comments here are unusually good — but the *structure* is a god object with six friend command classes, a mutable op-record type, and at least four copy-pasted transaction skeletons. A mechanical file split would be cosmetic. The split under `src/core/document/` must come with the seven code-judo deletions (§4), or it will just ribbon the god object across a directory.

---

## 1. Vital statistics and responsibility inventory

`SongDocument` (songdocument.h:96–522) currently owns, simultaneously:

| # | Responsibility | Evidence |
|---|---|---|
| 1 | SMF container + load/save/midi.cfg persistence | h:109–114, cpp:356–405, `m_hadCfgLine` |
| 2 | QUndoStack transaction coordination, 6 command classes | cpp:101–352, tempo.cpp:100–166, friends at h:443–449 |
| 3 | Engine-track ↔ chunk mapping + `TrackRemap` algebra | cpp:413–488, h:470–473 |
| 4 | Note-graph projection (mid2agb pairing) | `noteAt` cpp:538, `notesForTrack` cpp:577–615, `findNote` 636/647 |
| 5 | Lane (CC/bend/voice) projection + encoding | cpp:664–697, 1287–1348 |
| 6 | Loop-marker / time-sig / track-name semantics | cpp:718–778, 1590–1715, 1848–1949 |
| 7 | Note-overlap resolution policy | `resolveNoteOverlaps` cpp:853–929, 25-line protocol comment at h:490–515 |
| 8 | NoteId minting | cpp:498–513, h:476–477 |
| 9 | Tempo cache (normalized store, SMF read/write) | tempo.cpp:37–98, 177–198 |
| 10 | Raw SMF event editing + intra-tick canonical order | cpp:1481–1587, applyOps 2031–2127 |
| 11 | Time-range editing engine (remove/blank/duplicate) | timeeditor.{hpp,cpp}, 627 lines |
| 12 | Range edit / range move orchestration | range.cpp, 142 lines |

The public surface is ~60 methods plus 8 nested structs (`NewNote`, `LanePointValue`, `LanePointMove`, `RangeEdit::TrackNotes`, `RangeEdit::LaneWrite`, `TimeRange`, `TimeScope`) that UI code constructs by qualified name (e.g. `src/ui/songview/pianoroll_commands.cpp:315` builds `SongDocument::NewNote`). The header is 522 lines and the implementation 2,176 — both past the point where a reader can hold the invariants in mind.

---

## 2. Findings

Findings are ordered: structural regressions and god-object symptoms first, then missed simplifications, branching complexity, boundary problems, file-size, modularity, legibility. Line numbers are to current HEAD.

### F1 — Six friend QUndoCommand classes are three, maybe four, commands (P0 structural)

`SongEditCommand` (songdocument.cpp:101–130), `TempoEditCommand` (tempo.cpp:100–126), and `MixedEditCommand` (tempo.cpp:128–166) are the *same command* with different empty payloads:

- `SongEditCommand::redo` = apply ops → rebuildTrackMap → trackRemap → publish.
- `MixedEditCommand::redo` = apply ops → replaceTempoPoints → rebuildTrackMap → remap-or-identity → publish. With `m_nextTempo == m_tempoPoints`, `replaceTempoPoints` is a value-identical assignment (tempo.cpp:177–181), and the `m_ops.empty()` branch at tempo.cpp:151 selecting `currentTrackRemap()` is exactly what `TempoEditCommand::redo` does.
- `TempoEditCommand` = `MixedEditCommand` with `m_ops` empty and non-trivial tempo.

One `DocumentEditCommand{ops, nextTempo}` subsumes all three, deleting ~80 lines and — far more importantly — deleting the *possibility* that the three transaction skeletons drift. They already live in two different TUs (`songdocument.cpp` vs `songdocument_tempo.cpp`), and the two `pushEdit` overloads that construct them are split across those same files (cpp:2171 and tempo.cpp:168–174). This is a boundary drawn by file convenience, not by concept.

### F2 — The note-edit transaction skeleton is copy-pasted eight times (P0, ~150 deletable lines)

Every note-writing edit repeats this exact shape:

```cpp
std::vector<std::vector<size_t>> removals(m_smf.tracks.size());
std::vector<PlannedNote> written;
/* fill removals with per-track indices; fill written spans */
std::vector<EditOp> trims;
resolveNoteOverlaps(written, editNotes, removals, trims);
std::vector<EditOp> ops;
for (size_t t = 0; t < m_smf.tracks.size(); t++)
    appendRemoveOps(ops, int(t), std::move(removals[t]));
/* append insert ops */
ops.insert(ops.end(), trims.begin(), trims.end());
pushEdit(...);
```

Sites: `addNote` (cpp:931–948), `addNotes` (949–971), `buildMoveNotesOps` (~1030–1076), `buildMoveNotesToPitchesOps` (1077–1116), `resizeNotes` (1117–1154), `resizeNotesLeft` (1155–1201), `applyRangeEdit` (range.cpp:6–73), `moveRange` (range.cpp:74–142). The load-bearing invariant — *all removals first, per-track descending, trims last, so apply-time indices stay valid* — is documented in prose at each site (e.g. range.cpp:40–41) instead of being enforced by a type. One `NoteEditPlan` builder (§4, J2) makes the ordering structural and deletes the copies.

### F3 — `EditOp` is a mutable union-of-everything that doubles as a transaction log (P1 boundary)

`EditOp` (h:451–469) has 8 types and 10 fields; most are unused per variant (`indexTo` only for `MoveEvent`, `trackData` only for track ops, `oldEvent`/`oldEndTick` only for revert). Worse, it is *not a value*: `applyOps` writes back into the op — `op.index` recorded at cpp:2050, `op.oldEvent` at 2059/2073, `op.oldEndTick` at 2051/2075, `op.preservesNoteId` flipped at 2038–2041 and 2085–2090. Ops are input on the way in and undo-journal on the way out. That is a legitimate design (it avoids pre-computing undo state) but it means:

- ops can never be treated as immutable plans, compared, or cached;
- `MoveNotesCommand::mergeWith` (cpp:205–233) must *rebuild* `m_ops` from `m_notes` because the recorded ops are spent ammunition;
- the field-validity rules exist only in the header comment.

Minimum fix: isolate `EditOp` + `applyOps`/`revertOps` + the id-minter into one module where "recorded on apply" is documented once and the struct is invisible to everything else. End-state fix (phase 2): `std::variant<Insert, Remove, Modify, Move, ...>` with the recorded journal as a parallel vector — then the plan really is a value and merge-rebuild becomes plan arithmetic.

### F4 — `DocNote`'s dual addressing makes every consumer a temporal-logic machine (P1, the deepest issue)

`DocNote` (h:69–87) carries both a stable identity (`noteId`) and physical snapshot positions (`onIndex`/`endIndex`, `smfTrack`) valid only at read time. Consequence, all patchwork rather than cure:

- `containsNoteSpan` (cpp:625–635) — exists purely so callers can ask "did my snapshot survive?"
- `setNotesVelocities(expectedRevision, …)` (cpp:1222–1264) — an optimistic-concurrency protocol bolted onto a single-threaded document because UI gestures hold stale snapshots across mutations.
- `MoveNotesCommand::movesMyOutputs` (cpp:235–260) — re-derives note identity by comparing *seven fields* to recognize "the next press is still my gesture."

The identity system (noteid.h) was built for exactly this and then not fully adopted as the addressing currency. The UI already selects by `NoteId` everywhere (`editorselectionmodel`, velocity areas resolve `findNote(id, …)` immediately before every mutation — e.g. `src/ui/songview/pianoroll_commands.cpp:216`, `src/ui/editordrawer/velocityarea.cpp:389`). Phase-2 public APIs should take `std::vector<NoteId>` and resolve to physical indices *inside* the push-time builder, where the document is guaranteed current. That deletes the staleness-comment genre, `containsNoteSpan` from the hot path, and collapses `movesMyOutputs` to an id+position compare.

### F5 — mid2agb parity rules are triplicated across the core (P1, canonical-helper violation)

- `metaIsTimeSig` exists **twice**: anonymous namespace songdocument.cpp:71–74 and `TimeEditor::metaIsTimeSig` timeeditor.cpp:102–105. Identical logic.
- The name/marker classification dance (`SmfChannelPrefix` observe + `nameSeen` + first-unprefixed-0x03 rules) appears **three times** with three different shapes: `findLoopMarkerEvent` (cpp:718–752), the `moveTrack` rescue pass (cpp:1951–1978), and `trackNameLoc`/`trackNameLocs` (cpp:1866–1880). `MidiTimeline::build` holds a fourth copy of the reading rules.
- `smf.h` already exports `smfMetaIsMarker`, `smfTextIsMarker`, `isTempoMeta` — a canonical home exists and is simply not being extended.

Any divergence between these copies is a mid2agb parity bug that no compiler will catch. One `smfsemantics` module (§4, J4) is mandatory before any file split, because the split itself will otherwise freeze the duplication into separate directories.

### F6 — `TimeEditor` is a module cosplaying as a nested class (P2 modularity)

The 78-line `songdocument_timeeditor.hpp` declares 15+ private helpers, ten of them prefixed `timeEdit*` (`timeEditAffectedSmfTracks`, `timeEditCloseGapTrackEnds`, `timeEditShiftRightTrackEnds`, `makeTimeEditTaken`, `assembleTimeEditOps`, `buildTimeEditPlan`, `timeEditStreams`, …). The prefix noise is the tell: these want to be file-scope functions in a `timeedit` module, and the only reason they are members is access to `SongDocument` privates (nested-class friendship). The header includes all of `songdocument.h` just to exist.

Additional boundary damage: `songdocument_timeeditor_insert.cpp:5–10` forward-declares `time_edit_detail::insertBlankTempoPoints` / `duplicateTempoPoints` that are *defined in the other TU* (timeeditor.cpp:39–87) — a module split in half across files with no header, so the seam is invisible and the linkage is by convention.

### F7 — `moveLanePoints` is 110 lines of condition sprawl with a local aggregate (P2)

songdocument.cpp:1351–1460: a locally-declared `LaneRequests` struct, `std::map` lane indexing, `std::set` source dedup, a `singularCc` variable captured across three loops, a linear scan to find each point's id inside its lane, and a three-way undo-label selection computed at the end. This function mixes validation, grouping, planning (`planLaneMoves` — correctly delegated to `lanemoveplan`), and op assembly. It needs the same NoteEditPlan-style treatment lanes got in `lanemoveplan.h`: group → plan → assemble, three functions.

### F8 — `MoveNotesCommand` vs `MoveNotesToPitchesCommand`: copy-paste drift already visible (P2, latent bug class)

The two classes (cpp:169–264 and 267–352) duplicate the merge protocol (~90% identical) and have already drifted:

- `MoveNotesCommand` supports the **net-zero collapse**: after accumulating deltas it checks `movesMyOutputs(m_notes)` and calls `setObsolete(true)` (cpp:221–224) so returning to the start *removes* the undo item.
- `MoveNotesToPitchesCommand::mergeWith` (295–321) has **no equivalent check** — a pitch gesture that lands back on its origin pitches leaves a spent command on the stack and emits `documentChanged` unconditionally.
- Their publication paths differ: the delta command suppresses initial publication and computes remaps; the pitches command emits bare `documentChanged` with no remap handling (its `redo` at 289–295 — benign today because note moves can't remap tracks, but the asymmetry means the next person extending one will not know which half to copy).

Unify behind one mergeable-move mechanism parameterized by "how to rebuild the plan" (delta vs dest-pitches), with the collapse check shared.

### F9 — Hidden state machines (P2)

1. `m_initialRedo` (cpp:191–194, 262): a command that must *not* publish on its first redo because `moveNotes` (cpp:993–1011) publishes after the stack settles, in case a merge replaces the provisional state. Correct, but the invariant "who publishes what, when" is split across two files and a comment. This is the single subtlest protocol in the codebase and it lives in a private bool.
2. `preservesNoteId` flips *inside* `applyOps` (cpp:2038–2041, 2085–2090) as a side effect of committing — a flag that means both "builder intends ID preservation" and "the minter already ran," depending on lifecycle phase.
3. `m_hadCfgLine` + `m_savedCfg` + `cfgSemanticEqual` (cpp:88–93, 387–405) — a three-variable write-back state machine for midi.cfg persistence living as document members.

None is individually wrong; all three are invisible at the call sites they govern. Each belongs inside the module that owns its lifecycle (commands module, ops module, persistence module respectively).

### F10 — File sizes and the 1,000-line event horizon (P2)

`songdocument.cpp` is 2,176 lines — more than double the ceiling this project's own discipline (200–400 target, 600 hard) allows. The satellite files are individually in range but were split *by section, not by concept*: `songdocument_tempo.cpp` contains not just tempo logic but the mixed-command machinery and half the `pushEdit` overload pair; `songdocument_range.cpp` mixes the multi-track clipboard paste with the nudge engine; `songdocument_timeeditor*.cpp` split one class's methods across two TUs. The current layout has already paid the cost of splitting (six files, forward-declaration workarounds at timeeditor_insert.cpp:5–10 and songdocument.cpp:16–19) while collecting none of the benefit (one class, one set of friends, one header).

### F11 — Minor legibility/complexity notes (P3)

- `setNotesVelocities` dedups resolved notes with `std::find_if` inside the input loop (cpp:1235–1241) — O(n²) on paint batches; a small map is cheaper and clearer.
- `findNote(engineTrack, tick, key, …)` (cpp:636–646) rebuilds the entire track projection (`notesForTrack`) per call; callers in `src/checks/rollcheck.cpp` call it in loops (e.g. rollcheck.cpp:1509–1529, six sequential probes). Fine at current sizes, but it is the projection API most likely to become hot.
- `load()` (cpp:356–385) performs twelve sequential member mutations plus a synthesized all-dead remap. As a facade delegating to modules it is fine; as the second-largest function in the file it reads as a checklist without structure.

---

## 3. What is already right (keep, don't re-litigate)

- **The op-list transaction model itself.** "Builders emit an ordered op list; applyOps commits; revertOps rewinds; one command per gesture" is a genuinely good spine. The review above asks for isolation and typing, not replacement.
- **`TrackRemap` algebra** (h:51–62, cpp:445–488): pure, replay-based, inverse-computable. Deserves extraction, not redesign.
- **`lanemoveplan.h`** — the plan/execute split for lane moves is exactly the shape `moveLanePoints`' caller-side logic and the note-edit skeleton (F2) should follow.
- **The pairing algorithm** in `notesForTrack` (cpp:577–615, backward single-pass with 16×256 slots) is tight and its mid2agb-parity comment is load-bearing documentation.
- **The checks suites** (`src/checks/editcheck.cpp`, `rollcheck*.cpp`, `hostcheck.cpp`, `pitchbendcheck.cpp`, `automationgesturecheck/`) aggressively assert undo counts, revisions, and byte-identical SMF output — they are the regression harness that makes this refactor safely executable. The transition plan (§6) leans on them.

---

## 4. Code-judo moves (the point of the split)

Each of these deletes a concept rather than redistributing it. They are ordered by leverage; J1–J4 are prerequisites for a clean directory split.

**J1 — One transaction command.** Collapse `SongEditCommand` + `TempoEditCommand` + `MixedEditCommand` into a single `DocumentEditCommand{text, ops, nextTempo}` (F1). The two `pushEdit` overloads become one function with an optional tempo payload. Deletes ~80 lines and the cross-TU skeleton split. Behavior-identical by the equivalence argument in F1; `editcheck.cpp`'s undo-count/revision assertions guard it.

**J2 — `NoteEditPlan` builder.** A type that owns the removals-first/descending/trims-last ordering once:

```cpp
// noteops.h
struct NoteEditPlan {
    // All removals per SMF track; plan.finalize() sorts+dedups descending
    // and emits: removals, caller inserts, trims — in canonical order.
    void removeEvent(int smfTrack, size_t index);
    void writeNotes(std::span<const PlannedNote> written, std::span<const DocNote> edited);
    void addInsert(EditOp op);           // caller's own inserts
    std::vector<EditOp> finalize(const SmfFile &smf) &&;
  private:
    std::vector<std::vector<size_t>> removals;
    std::vector<PlannedNote> written;
    std::vector<DocNote> edited;
    std::vector<EditOp> inserts, trims;
};
```

All eight copy-paste sites in F2 become 3–5 line plan fills. Deletes ~150 lines and every per-site prose comment about ordering; the invariant becomes unreachable-to-violate.

**J3 — NoteId as the addressing currency (phase 2).** Public edit APIs gain `…ByIds(std::vector<NoteId>, …)` overloads that resolve internally at push time; snapshot-based overloads remain as thin wrappers that resolve ids first. Over a series of UI-side follow-ups, `containsNoteSpan`, `expectedRevision`, and the seven-field `movesMyOutputs` compare shrink or disappear (F4). This is the only move that changes consumers; everything else is internal.

**J4 — `smfsemantics` canonical module.** Move `metaIsLoopMarker`, `nameIsLoopMarker`, `metaIsTimeSig`, `trackNameLoc(s)`, `trackNameText`, `findLoopMarkerEvent`, `loopTick`, `timeSigs`, plus the lane event encode/decode trio (`laneEventMatches`, `laneValue`, `makeLaneEvent`) and `makeChannelEvent` into free functions over `const SmfFile&` in one place (F5). `MidiTimeline` should consume the same functions — that is a one-line-per-callsite change that closes the last parity-copy channel.

**J5 — Un-nest TimeEditor into a `timeedit` module.** Strip the `timeEdit*` prefixes, make `buildTimeEditPlan`/`timeEditStreams` into `PlanBuilder`, the three operations into free functions `removeRange/insertBlank/duplicateRange(SongEditContext&, …)`, and reunite the two split TUs under proper headers (F6). The `taken` matrix stays — it is an honest ownership mask — but it becomes a small `EventClaims` type with the bounds-checked `consume` and nothing else.

**J6 — Pure modules for pure logic.** `trackmap` (TrackMapState/rebuild/remap algebra) and `tempo` (normalize/from-smf/write-metas/candidates) become free-function modules with no QObject, no signals, no friends (F10, F6). This is what makes the eventual unit-level checks possible without instantiating a `SongDocument` and a `QUndoStack`.

**J7 — Kill the friendship web.** Six friend classes (h:443–449) become zero: commands live in the `document` namespace with an explicit `MutationSink` interface (apply ops, replace tempo, rebuild map, publish) that is also exactly what `TimeEditor` and the op builders need. The facade `SongDocument` implements it privately. Friendship is replaced by one narrow, documented contract instead of six broad ones.

---

## 5. Target architecture — `src/core/document/`

All files 100–400 lines (600 hard ceiling). The public `SongDocument` API and nested type names are **unchanged** — 45+ consumers keep compiling via type aliases; the facade stays the single Qt/QObject boundary.

```
src/core/document/
├── doc_types.h              ~150   value types: DocNote, DocLanePoint, DocTimeSig,
│                                   TempoEdit, TimeRange, TimeScope, RangeEdit,
│                                   PlannedNote, NewNote, LanePointValue, LanePointMove,
│                                   TrackRemap (+isIdentity/inverse), DOC_CC_* constants.
│                                   No Qt, no includes beyond smf/tempo/noteid.
├── smfsemantics.h/.cpp      ~200   how mid2agb reads the file — the ONE parity home:
│                                   metaIsLoopMarker, nameIsLoopMarker, metaIsTimeSig,
│                                   findLoopMarkerEvent, loopTick, timeSigs,
│                                   trackNameLoc/trackNameText, laneEventMatches,
│                                   laneValue, makeLaneEvent, makeChannelEvent.
├── trackmap.h/.cpp          ~130   TrackMapState, rebuildTrackMap, engineTrackForChunk,
│                                   smfTrackFor/channelFor helpers, freeChannel,
│                                   trackRemap(before, ops), currentTrackRemap.
│                                   Pure functions over (SmfFile, EditOp list).
├── editop.h                 ~120   EditOp struct + field-validity rules documented once,
│                                   NoteIdMinter (next id, mint, mintUnassigned),
│                                   moveChunk. applyOps/revertOps declared here.
├── editop.cpp               ~220   applyOps/revertOps as free functions over
│                                   (SmfFile&, vector<EditOp>&, NoteIdMinter&) —
│                                   the ONLY place "recorded on apply" exists.
├── overlap.h/.cpp           ~200   resolveNoteOverlaps + PlannedNote span logic,
│                                   pure over (const SmfFile&, note projection).
├── noteops.h/.cpp           ~330   NoteEditPlan (J2) + all note-edit builders:
│                                   addNote/addNotes/deleteNotes/move(delta)/
│                                   moveToPitches/resize/resizeLeft/velocity —
│                                   each a pure (state) → vector<EditOp> function
│                                   or NoteEditPlan fill. appendNoteInsertOps,
│                                   appendRemoveOps, appendEventEditOps live here.
├── trackops.cpp             ~260   addTrack/duplicateTrack/deleteTrack/moveTrack/
│                                   renameTrack/setLoopTick/setTimeSig/moveTimeSig/
│                                   deleteTimeSig/setTrackEndTick/raw event edits +
│                                   rawEventMoveBounds. Builders only; reuse
│                                   smfsemantics + noteops primitives.
├── tempo.h/.cpp             ~200   TempoStore: normalize, pointsFromSmf,
│                                   writeTempoMetas/removeTempoMetas,
│                                   editedTempoPointCandidates; the single
│                                   m_tempoPoints writer lives behind it.
├── commands.h/.cpp          ~320   DocumentEditCommand (J1: subsumes Song/Tempo/
│                                   Mixed), SongCfgCommand, the unified mergeable-
│                                   move command (J-basis for F8), MutationSink
│                                   interface (J7). The only QUndoCommand code.
├── timeedit_plan.h/.cpp     ~260   PlanBuilder: EventKind, StreamIdentity,
│                                   TimeEventRef, TimeEditPlan, buildTimeEditPlan,
│                                   streams, EventClaims (the 'taken' mask),
│                                   assemble/track-end helpers.
├── timeedit_remove.cpp      ~170   removeRange(SongEditContext&) — seam-close logic.
├── timeedit_insert.cpp      ~280   insertBlank + duplicateRange — seam-shift logic.
├── timeedit_tempo.h/.cpp    ~140   the three pure tempo-stream transforms currently
│                                   in time_edit_detail (one home, no cross-TU decls).
└── songdocument.h/.cpp      ~300/~420  FACADE — public API unchanged, QUndoStack,
                                        signals, revision, load/save/cfg persistence,
                                        buildTimeline. Delegates everything else.
```

Notes on the shape:

- **`SongEditContext`** is the internal read/write view handed to builders and TimeEditor: `SmfFile &smf`, `const TrackMap &map`, `TempoStore &tempo`, `NoteIdMinter &ids`. It is *not* public, *not* a QObject, and exists to replace six friend declarations with one parameter type. The facade constructs it from its members.
- **`songdocument.h` keeps nested-type names** via aliases (`struct NewNote; using SongDocument::NewNote = document::NewNote;` pattern), so `src/ui`'s qualified uses compile untouched.
- **`smf.cpp`, `noteid.h`, `lanemoveplan.*`, `timedefaults.h`, `tempo.h`, `miditimeline.*` stay where they are.** Only the six `songdocument*` files dissolve. `midiimport` and `SongRegistry` dependencies stay behind the facade.
- Nothing in the layout is under ~120 lines or over ~420; no file approaches the 600 ceiling; every module has exactly one reason to change.

### Public/internal interface sketch

```cpp
// doc_types.h — the only header UI needs for value types
namespace document {
struct DocNote { NoteId noteId; int engineTrack, smfTrack; size_t onIndex, endIndex;
                 uint64_t tick; uint32_t duration; uint8_t key, velocity, channel;
                 bool unterminated() const; };
struct TimeRange { uint64_t startTick=0, endTick=0; bool empty() const; uint64_t span() const;
                   bool contains(uint64_t) const; bool overlaps(uint64_t,uint64_t) const; };
struct TimeScope { std::vector<int> tracks; std::vector<std::pair<int,uint8_t>> lanes;
                   bool tempo=false, wholeSong=false; bool coversTrack(int) const;
                   bool coversTempo() const; bool coversLane(int,uint8_t) const; };
struct RangeEdit { /* as today, members moved to namespace scope */ bool empty() const; };
struct TrackRemap { std::vector<int> smfTrackMap, engineTrackMap;
                    int newSmfTrackCount=0, newEngineTrackCount=0;
                    bool isIdentity() const; TrackRemap inverse() const; };
}

// commands.h — the entire undo surface
namespace document {
class MutationSink {  // implemented privately by SongDocument
  public:
    virtual ~MutationSink() = default;
    virtual void applyOps(std::vector<EditOp>&) = 0;
    virtual void revertOps(std::vector<EditOp>&) = 0;
    virtual void replaceTempoPoints(std::vector<TempoPoint> normalized) = 0;
    virtual TrackMapState trackMapState() const = 0;
    virtual void rebuildTrackMap() = 0;
    virtual void publishMutation(TrackRemap) = 0;
};
class DocumentEditCommand : public QUndoCommand {  // J1 — one transaction skeleton
    QString-less: takes text; holds vector<EditOp> ops; vector<TempoPoint> nextTempo
    (empty ⇒ leave tempo untouched; equal ⇒ no-op write, both preserved semantics);
};
}
```

---

## 6. Transition strategy (behavior-preserving, checks-gated)

The repo's check binaries (`editcheck`, `rollcheck*`, `hostcheck`, `pitchbendcheck`, `smfcheck`, `automationgesturecheck`, `savecheck`, `eventviewcheck`, `selectioncheck`) assert undo counts, revisions, signal order, and byte-identical SMF output — run the relevant one after every phase. Each phase compiles and passes checks before the next begins.

**Phase 0 — Canonicalize parity helpers (J4).** Add `document::smfsemantics` *in place* (it can start as `src/core/document/smfsemantics.*`), delete the duplicate `metaIsTimeSig`, point all four classification sites at it. No file moves yet; smallest possible diff; immediately kills F5.

**Phase 1 — Command unification (J1) + MutationSink (J7).** Introduce `commands.h/.cpp` with `DocumentEditCommand`; delete `SongEditCommand`/`TempoEditCommand`/`MixedEditCommand` and unify `pushEdit`. Gate: `editcheck` (velocity/undo assertions), `rollcheck` (merge/collapse assertions on keyboard moves — the `movesMyOutputs`/`setObsolete` behavior), `hostcheck` (signal order). Do **not** yet touch the two move commands beyond moving them; the F8 unification is its own change.

**Phase 2 — Ops and builders (J2, J3-lite).** Move `EditOp`/`applyOps`/`revertOps`/minter into `editop.*`; extract `NoteEditPlan` and rewrite the eight copy-paste sites to fill plans. Gate: `editcheck`, `rollcheck` (overlap-trim cases), `pitchbendcheck` (`containsNoteSpan` fixtures), `rollcheckautomation*` (lane sweep and group-move paths).

**Phase 3 — TimeEditor extraction (J5, J6).** Un-nest `TimeEditor` into `timeedit_*` files under `document/`; move tempo transforms into `timeedit_tempo`; give the plan builder `SongEditContext` instead of friendship. Gate: `rollcheckwindowing`/range-edit paths, `eventviewcheck`, `savecheck` (SMF byte identity after each range op).

**Phase 4 — Facade reduction.** Move remaining method bodies to `noteops/trackops/tempo`; `songdocument.cpp` becomes load/save/cfg/signal plumbing delegating to modules. Add nested-type aliases. Delete the old six files. Gate: full check suite + a no-op build of `src/ui` (zero UI edits expected).

**Phase 5 (separate, consumer-touching) — NoteId addressing (J3) and F8 unification.** Add `…ByIds` overloads, migrate UI call sites opportunistically, then unify the mergeable-move commands. Each UI migration is independently landable.

Explicitly **not** in scope for any phase: changing the op-list transaction model, changing signal semantics or emission order (`tracksRemapped` before `documentChanged`), changing `TrackRemap` layout, or `std::variant`-izing `EditOp` (revisit after Phase 2 isolates it — two invariants must never move in one change).

---

## 7. Bottom line

`SongDocument` is a well-commented, behaviorally disciplined god object — which is precisely why it has grown to 2,700 lines and six friends without anyone stopping it: every individual addition is reasonable, and the *checks* keep it honest. The structural debt is now charging rent in copy-paste (F2, F8), duplicated parity rules that can silently diverge from mid2agb (F5), a mutable op type that resists composition (F3), and an addressing model that pushes staleness bookkeeping into 45 consumer files (F4).

The split under `src/core/document/` is justified and overdue, but **only** as the vehicle for the seven judo moves in §4. A split that merely slices `songdocument.cpp` by section into `songdocument_notes.cpp`, `songdocument_tracks.cpp`, … would leave every finding above intact and add directory friction on top. Do J1–J4 as part of the move; they delete more code than the file structure adds.
