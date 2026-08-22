# SongDocument decomposition — implementation plan

## 1. Objective and success criteria

**Objective.** Split the `SongDocument` implementation (one 2176-line `.cpp` + one 528-line `.h` + four already-extracted helpers totaling ~3,900 lines) into the `src/core/document/` directory described by `docs/agent-reorg-plan.md` §8, with one cohesive ownership seam per file, respecting the 200–400L target / 600L ceiling and the `~/.claude/CLAUDE.md` Simplicity-First / Surgical-Changes rules. This is a **behavior-preserving, file-level refactor only**: no semantic changes to note pairing, overlap resolution, undo semantics, NoteId minting, track mapping, tempo projection, SMF serialization, or signal ordering.

**Success criteria (all must hold, verified in order):**
1. `src/core/document/` contains the target files; no `SongDocument` member body or `SongDocument::`-scoped type remains in `src/core/songdocument.{h,cpp}` or the four `songdocument_*.{hpp,cpp}` helpers (they are deleted, not left as shims).
2. `cmake --build build --target porydaw porydaw_checks` succeeds on the first build after Phase 3 cutover.
3. The acceptance harnesses in §5 all pass, in the order listed.
4. `lsp references` / scoped `grep` show zero references to the old paths (`core/songdocument`, `songdocument_tempo/range/timeeditor*`) outside the new directory.
5. Public API is byte-identical: the set of `SongDocument` public members, signal signatures, and public/type names that the 52 consumer files rely on is unchanged (consumers touch only their `#include` line).

## 2. Current-state findings (evidence)

### 2.1 File inventory and line counts (measured)
| File | Lines | Role |
|---|---:|---|
| `src/core/songdocument.h` | 528 | Class decl: public API, signals, nested types, private state, friend decls, `EditOp`, `TrackMapState` |
| `src/core/songdocument.cpp` | 2176 | All mutators + lookups + `applyOps`/`revertOps` engine |
| `src/core/songdocument_tempo.cpp` | 242 | `TempoEditCommand`, `MixedEditCommand`, tempo normalization/projection, tempo metas |
| `src/core/songdocument_range.cpp` | 142 | `applyRangeEdit`, `moveRange` |
| `src/core/songdocument_timeeditor.cpp` | 471 | Nested `SongDocument::TimeEditor` core (remove/plan/streams) |
| `src/core/songdocument_timeeditor_insert.cpp` | 278 | `TimeEditor::insertBlank`, `TimeEditor::duplicate` |
| `src/core/songdocument_timeeditor.hpp` | 78 | Nested `SongDocument::TimeEditor` declaration |
| `src/core/lanemoveplan.{h,cpp}` | — | **Independent primitive** (no `SongDocument` dependency at all) — already clean |

### 2.2 Type placement today (from `songdocument.h`)
- **Already namespace-scope (public):** `TrackRemap` (L37), `DocNote` (L50), `DocLanePoint` (L67), `TempoEdit` (L77), `DocTimeSig` (L86), plus `DOC_CC_BEND`/`DOC_CC_VOICE` (L21–22) and free fns `metaIsLoopMarker`/`nameIsLoopMarker` (L27, L32).
- **Nested inside `SongDocument` (private except edit-payloads):** `EditOp` incl. `Type` enum (L412–432), `TrackMapState` (L434–437), `TimeEditor` (fwd L433), `NewNote` (L157), `LanePointValue` (L198), `LanePointMove` (L204), `RangeEdit` + `TrackNotes`/`LaneWrite` (L228–250), `TimeRange` (L272–283), `TimeScope` (L284–305), `PlannedNote` (L480–485).

### 2.3 The indivisible coupling core (the hard constraint any split must respect)
The following form a single correctness-critical unit and are the reason `document.{h,cpp}` must keep a private coordination surface rather than being split into independent classes:

1. **`EditOp` low-level engine.** `applyOps` (`songdocument.cpp:2031–2127`) and `revertOps` (`2129–2169`) are the only writers of `m_smf` and `m_nextNoteId`. Every mutation — notes, lanes, tempo, range edits, raw edits, topology — is expressed as an ordered `std::vector<EditOp>`. Their index rules are load-bearing: removals/modifications carry apply-time indices; builders emit removals first (descending per track) then inserts that resolve position on apply (`songdocument.cpp:97–100` comment).
2. **Six `QUndoCommand` friend classes** (`friend` list, `songdocument.h:405–410`): `SongEditCommand` (`songdocument.cpp:101–130`), `MoveNotesCommand` (`169–265`), `MoveNotesToPitchesCommand` (`267–352`), `SongCfgCommand` (`132–160`), `TempoEditCommand` (`songdocument_tempo.cpp:100–126`), `MixedEditCommand` (`songdocument_tempo.cpp:128–166`). They reach `trackMapState()/applyOps()/revertOps()/rebuildTrackMap()/trackRemap()/publishMutation()/currentTrackRemap()`, `m_cfg`, `m_tempoPoints`, `replaceTempoPoints()`, `buildMoveNotesOps()`, `buildMoveNotesToPitchesOps()`.
3. **Nested scratch class `SongDocument::TimeEditor`** (`songdocument_timeeditor.hpp`) reaches `m_document.m_smf`, `m_document.m_tempoPoints`, `pushEdit()`, `SongDocument::EditOp`, `SongDocument::TimeRange/TimeScope/TimeEditor::*`.
4. **Undo/redo flow** (`SongEditCommand::redo/undo`, `songdocument.cpp:110–124`): snapshot `trackMapState()` → `applyOps` → `rebuildTrackMap()` → `trackRemap(before, ops)` → `publishMutation(remap)`; undo does `revertOps` + inverse remap. `publishMutation` (`490–496`) increments `m_revision`, emits `tracksRemapped(remap)` **iff** `!remap.isIdentity()`, then `documentChanged()` — the strict ordering invariant.
5. **`publishMutation` double-emission discipline.** `MoveNotesCommand` suppresses its initial redo emission (`191–194`) and `moveNotes` publishes afterward (`songdocument.cpp:1010`) so a merge can replace the provisional state; `MoveNotesToPitchesCommand` does **not** use `trackMapState`/`trackRemap` (it emits `documentChanged()` directly, `285–292`) because a same-track pitch move cannot change the map.

### 2.4 Consumers and build surface
- **Production callers:** `SongSession` (`src/songsession.h:11,38` embeds `SongDocument doc` by value), `SongView` + its extracted surfaces under `src/ui/songview/` (`pianoroll.h`, `rangeedit.cpp`, `timeruler_interaction.cpp`, `drawercoordination.cpp`, `editorselectionmodel.cpp`), `mainwindow.cpp`, `eventlistview.cpp`, `eventtablemodel{edit}.cpp`, `eventlistviewactions.cpp`, `transportbar.cpp`, `pitchbendeditor.hpp`, `pitchbendgraph.hpp`, and the editor drawer (`automationpage.h`, `automationcanvas*.cpp`, `cclanes.*`, `voicechangelane.cpp`, `tempolane.h`, `velocityarea.h`, `nodelane/batchcommit.h`).
- **Forward declarations of `class SongDocument;`** (do **not** `#include`; unaffected by the move but must remain valid): `src/checks/smfcheckfixtures.h:9`, `src/ui/eventlistview.h:12`, `src/ui/eventtablemodel.h:16`, `src/ui/songview.h:44`, `src/ui/editordrawer/automationpage.h:26`, `src/ui/editordrawer/cclanes.h:12`. `struct DocNote;`, `struct SmfEvent;`, `struct TrackRemap;` are also forward-declared — confirming these must **stay namespace-scope** after the move.
- **52 `#include "core/songdocument.h"` sites** (scoped grep, `src`): 19 production (`songsession.h`, `songview.{h,cpp}`, `eventlistview.cpp`, `eventtablemodel*.cpp`, `eventlistviewactions.cpp`, `transportbar.cpp`, `pitchbendeditor.hpp`, `pitchbendgraph.hpp`, `songview/{pianoroll.h,rangeedit.cpp,timeruler_interaction.cpp,drawercoordination.cpp,editorselectionmodel.cpp}`, `editordrawer/{automationpage.cpp,automationcanvas{,_gesture,_input,_menu}.cpp,cclanes.cpp,tempolane.h,velocityarea.h,voicechangelane.cpp,nodelane/batchcommit.h}`) and 33 checks/harnesses (`editcheck.cpp`, `eventviewcheck.cpp`, `exportcheck.cpp`, `hostcheck.cpp`, `pitchbendcheck.hpp`, `renderingplayheadcheck.cpp`, `rollcheck.cpp`, `rollcheckautomation{,_paint,_popup,_tempo_paint}.cpp`, `rollcheckwindowing.cpp`, `savecheck.cpp`, `selectioncheck.cpp`, `smfcheck.cpp`, `smfcheckfixtures.cpp/h`, `onboardcheck/{import,registration}.cpp`, `automationgesturecheck/*`).
- **Build wiring (`CMakeLists.txt`):** the five `songdocument*` files are listed in `porydaw_app` (`CMakeLists.txt:179–184`); `lanemoveplan.cpp/h` at `185–186`. `porydaw_checks` links `porydaw_app` (`475`). `porydaw_render_cli` (`594–605`) does **not** compile `songdocument` — no change there.
- **Checks entry points** (from `src/checks/checkcatalog.cpp`): the catalog drives every `--*check` flag; exact argv spellings in §5.

## 3. Recommended design (and the argument)

### 3.1 Architecture: one facade class + implementation TUs + hoisted type headers

**`SongDocument` remains one concrete `QObject`.** Do **not** split it into public `NoteDocument`/`LaneDocument`/`TimeDocument` classes and do **not** introduce a pimpl or a parallel state object. Reasons:
- The 6 friend `QUndoCommand`s + `TimeEditor` + `applyOps/revertOps` share one canonical state (`m_smf`, `m_tempoPoints`, `m_engineToSmf`) and one publish funnel (`publishMutation`). Splitting state across objects would create exactly the "two sources of truth" the repo forbids, and would force a message-passing layer between `applyOps` and the per-domain logic for zero benefit.
- The existing codebase already establishes the pattern this refactor extends: `songdocument_tempo.cpp`, `songdocument_range.cpp`, `songdocument_timeeditor*.cpp` are **member functions of `SongDocument` defined in dedicated translation units**. The split below is the same mechanism, generalized and re-homed into `src/core/document/`. It is a mechanical move of bodies, not a redesign.

**The `notes.h`/`lanes.h`/`time.h`/`topology.h`/`raw.h` headers are *value-type and internal-decoration headers*, not public classes.** They declare the payload structs and (where warranted) the cross-TU helper/command declarations. The sole public include path remains `core/document/document.h`, which `#include`s the type headers so consumers see the same names. This keeps all 52 include sites a one-line change and keeps the API surface unchanged.

### 3.2 Target layout and line-count estimates

```
src/core/document/
  document.h                ~400   facade: class SongDocument (public API + signals + state + private decls),
                                  #includes notes.h/lanes.h/time.h/topology.h/editop.h for types
  document.cpp              ~280   ctor, load, save, buildTimeline, ticksPerClock, smfTrackFor/channelFor,
                                  engineTrackForChunk, freeChannel, publishMutation, rebuildTrackMap,
                                  trackMapState, currentTrackRemap, trackRemap, pushEdit(x2), mintNoteId,
                                  mintUnassignedNoteIds, metaIsLoopMarker, nameIsLoopMarker, TrackRemap::isIdentity/inverse
  editop.h                   ~55   EditOp (+Type enum), TrackMapState    (hoisted from nested scope)
  editop.cpp                ~160   applyOps, revertOps  (THE low-level SMF edit engine)
  detail.h                   ~40   free helpers: metaIsTimeSig, moveChunk, cfgSemanticEqual,
                                  trackNameText/trackNameLoc/trackNameLocs, makeChannelEvent,
                                  appendNoteInsertOps, appendRemoveOps, appendEventEditOps
  detail.cpp                ~140   those helper bodies
  topology.h                 ~55   TrackRemap (public), + topology command decls
  topology.cpp              ~270   addTrack, duplicateTrack, deleteTrack, moveTrack, renameTrack, trackName,
                                  canAddTrack, trackRemap (or co-locate remap calc here)
  notes.h                    ~55   DocNote, NewNote, PlannedNote
  notes.cpp                 ~230   lookups: noteAt, notesForTrack, noteEndTick, containsNoteSpan, findNote(x2)
  notes_edit.cpp            ~430   addNote/addNotes/deleteNotes/moveNotes/moveNotesToPitches/resizeNotes/
                                  resizeNotesLeft/setNotesVelocity/setNotesVelocities/nudgeNotesVelocity,
                                  buildMoveNotesOps, buildMoveNotesToPitchesOps, resolveNoteOverlaps
  lanes.h                    ~50   DocLanePoint, LanePointValue, LanePointMove
  lanes.cpp                 ~240   laneEventMatches, laneValue, lanePoints, findLanePoint, makeLaneEvent,
                                  addLanePoint, writeLanePoints, moveLanePoints, deleteLanePoints
  time.h                     ~85   TempoEdit, DocTimeSig, TimeRange, TimeScope, RangeEdit(+TrackNotes/LaneWrite)
  time.cpp                  ~380   tempoPointsFromSmf, normalizeTempoPoints, replaceTempoPoints, applyTempoEdit,
                                  removeRawEventsAndEditTempo, replaceTempoPointWithRawEvent,
                                  removeTempoMetas/writeTempoMetas/makeTempoMeta (song_document_tempo ns),
                                  loopTick/findLoopMarkerEvent/setLoopTick, timeSigs/setTimeSig/moveTimeSig/
                                  deleteTimeSig, applyRangeEdit, moveRange
  timeeditor.h               ~80   SongDocument::TimeEditor declaration (ex songdocument_timeeditor.hpp)
  timeeditor.cpp            ~470   TimeEditor core (unchanged bodies, re-included)
  timeeditor_insert.cpp     ~280   TimeEditor::insertBlank / duplicate (unchanged bodies)
  raw.h                      ~30   (thin; raw-event decls/constants if any beyond SmfEvent)
  raw.cpp                   ~190   insertRawEvent, modifyRawEvent, deleteRawEvents, moveRawEvent,
                                  rawEventMoveBounds, setTrackEndTick
  commands/
    commands.h               ~70   the 6 QUndoCommand subclass declarations (namespace-scope)
    editcommand.cpp         ~130   SongEditCommand + SongCfgCommand + TempoEditCommand + MixedEditCommand
    movecommand.cpp         ~200   MoveNotesCommand + MoveNotesToPitchesCommand
```

**Line-count honesty.** `document.h` lands at ~400L, above the 300L "target" but well under the 600L ceiling. That residual is inherent: `SongDocument` genuinely declares ~200 public/promoted members and ~15 state fields. The `keep-files-small` rule itself says line count is a warning, not a design rule, and "do not split solely to get below the threshold." I deliberately reject fragment-inclusion (a `document.h` that `#include`s headers *inside* the class body) as it harms navigability — the exact failure the reorganization is meant to cure. I flag this residual explicitly so reviewers can challenge it rather than discover it at code time.

**Notes split rationale.** `notes.cpp` (lookups) vs `notes_edit.cpp` (mutations) is the only place a folder-internal split is needed. They are distinct ownership seams with distinct change reasons (read/pairing vs write/overlap), not a line-count carve: `resolveNoteOverlaps` lives with the mutators that feed it `PlannedNote` spans; the shared event builders (`makeChannelEvent`, `append*Ops`, `appendEventEditOps`) are hoisted to `detail.*` because notes, lanes, range, raw, and topology all call them.

**Comments on `commands/`.** The move-command `mergeWith` machinery (`movesMyOutputs`) is the only nontrivial command logic; the other four are thin `apply→publish` wrappers. To avoid 80L fragments I use two command TUs, not six: `editcommand.cpp` (the four plain apply/publish commands, sharing the snapshot→apply→rebuild→remap→publish idiom) and `movecommand.cpp` (the two mergeable gestures). Their declarations go in `commands.h` because `document.cpp` (`pushEdit`), `time.cpp` (`applyTempoEdit`), `notes_edit.cpp` (`moveNotes`) and `topology.cpp`/`document.cpp` (`setCfg`) all `new` them.

## 4. Sequenced implementation plan

> `git mv` each file first (pure rename, no content change) before any body split, per the reorg plan's "git mv renames are 100%" discipline. Each phase ends in a **green compile** checkpoint before the next phase starts. No build/lint/test run mid-flight by parallel subagents — every phase is a serial integration point owned by one implementer (see Ownership note).

### Phase 0 — Prerequisites: hoist internal types + isolate helpers (compile-checkpoint 0)
1. **Create `src/core/document/` and `git mv`** `songdocument.h` → `document/document.h`, `songdocument.cpp` → `document/document.cpp`, `songdocument_tempo.cpp` → `document/time_tempo.cpp` (provisional name), `songdocument_range.cpp` → `document/time_range.cpp`, `songdocument_timeeditor.hpp` → `document/timeeditor.h`, `songdocument_timeeditor.cpp` → `document/timeeditor.cpp`, `songdocument_timeeditor_insert.cpp` → `document/timeeditor_insert.cpp`, and `lanemoveplan.{h,cpp}` → `document/lanemoveplan.{h,cpp}`. Update the four files' `#include "songdocument.h"` → `#include "document/document.h"` and the two `songdocument_timeeditor.hpp` → `document/timeeditor.h`.
2. **CMake cutover of paths only** (`CMakeLists.txt:179–186`): retarget the `porydaw_app` entries to the new paths. Nothing else changes. Build must stay green — this proves the rename is 100%.
3. **Hoist `EditOp` + `TrackMapState`** out of the class (`document.h:412–437`) into `document/editop.h`, namespace-scope (`editop.h` at top level, matching `TrackRemap`/`DocNote` style). Change every `SongDocument::EditOp` / `SongDocument::TrackMapState` spelling in `document.h`, the command TUs, `timeeditor.*`, and the member bodies to the bare names. `TrackMapState` moves with `EditOp` because both are consumed only by the remap/undo engine and `trackRemap()`.
4. **Hoist the anonymous-namespace free helpers** (`document.cpp:67–95`: `metaIsTimeSig`, `moveChunk`, `cfgSemanticEqual`) plus the track-name helpers (`document.cpp:1857–1891`: `trackNameText`, `trackNameLoc`, `trackNameLocs`) into `document/detail.{h,cpp}` as declared free functions; give them the minimal explicit parameter lists (e.g. `trackNameText(const SmfEvent&)`, `moveChunk(std::vector<SmfTrack>&, int, int)`) so they no longer need class-member access.
5. **Build checkpoint 0** and run `--smfcheck` + `--editcheck` to prove the rename + hoist were behavior-neutral.

**Why Phase 0 first:** everything downstream (`editop.cpp`, the domain TUs, `commands/`) references `EditOp`, `TrackMapState`, and the detail helpers. Establishing those two shared headers first removes the "who owns EditOp" ambiguity before any bodies move.

### Phase 1 — Core command and low-level edit engine extraction (compile-checkpoint 1)
6. Move `applyOps` + `revertOps` bodies (`document.cpp:2031–2169`) into `document/editop.cpp`. They keep full private access as `SongDocument::` members; `editop.cpp` only moves their definition site. `moveChunk` now comes from `detail.h`.
7. Move the two `pushEdit` overloads (`document.cpp:2171–2176` and `songdocument_tempo.cpp:168–175`) plus `publishMutation`, `rebuildTrackMap`, `trackMapState`, `currentTrackRemap`, `trackRemap` into `document/document.cpp` (the facade coordination block).
8. **Create `document/commands/commands.h`** with namespace-scope declarations of `SongEditCommand`, `SongCfgCommand`, `TempoEditCommand`, `MixedEditCommand`, `MoveNotesCommand`, `MoveNotesToPitchesCommand` (these names must match the existing `friend class` declarations unchanged). Move their definitions: `SongEditCommand`+`SongCfgCommand` (from `document.cpp:101–160`), `TempoEditCommand`+`MixedEditCommand` (from `songdocument_tempo.cpp:100–166`) into `commands/editcommand.cpp`; `MoveNotesCommand`+`MoveNotesToPitchesCommand` (from `document.cpp:169–352`) into `commands/movecommand.cpp`.
9. **Build checkpoint 1** — everything still compiles with the engine + commands relocated. Run `--editcheck` (undo integrity) and `--check-note-identity`.

**Why the engine + commands together:** they are the same correctness unit (§2.3). Moving them as one step, with the `commands.h` contract fixed first, lets the domain splitting in Phase 2 be pure body relocation with no further coupling decisions.

### Phase 2 — Domain operation extraction (compile-checkpoint 2)
10. **`notes.*` + `notes_edit.cpp`:** move `noteAt`, `notesForTrack`, `noteEndTick`, `containsNoteSpan`, `findNote`×2 into `notes.cpp`; move `addNote`, `addNotes`, `deleteNotes`, `moveNotes`, `moveNotesToPitches`, `resizeNotes`, `resizeNotesLeft`, `setNotesVelocity`, `setNotesVelocities`, `nudgeNotesVelocity`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`, `resolveNoteOverlaps` into `notes_edit.cpp`. Hoist `DocNote`/`NewNote`/`PlannedNote` decls into `notes.h`. `notes_edit.cpp` still `#include`s `commands/commands.h` for the two move-command constructors.
11. **`lanes.*`:** move `laneEventMatches`, `laneValue`, `lanePoints`, `findLanePoint`, `makeLaneEvent`, `addLanePoint`, `writeLanePoints`, `moveLanePoints`, `deleteLanePoints` into `lanes.cpp`; hoist `DocLanePoint`/`LanePointValue`/`LanePointMove` into `lanes.h`. Keep the `lanemoveplan.h` dependency (already independent).
12. **`time.*`:** move `tempoPointsFromSmf`, `normalizeTempoPoints`, `replaceTempoPoints`, `applyTempoEdit`, `removeRawEventsAndEditTempo`, `replaceTempoPointWithRawEvent` plus the `song_document_tempo` namespace (`removeTempoMetas`, `writeTempoMetas`, `makeTempoMeta`) into `time.cpp`; also `loopTick`, `findLoopMarkerEvent`, `setLoopTick`, `timeSigs`, `setTimeSig`, `moveTimeSig`, `deleteTimeSig`, `applyRangeEdit`, `moveRange`. Hoist `TempoEdit`, `DocTimeSig`, `TimeRange`, `TimeScope`, `RangeEdit`(+nested) into `time.h`. The two `TimeEditor` TUs become `timeeditor.cpp`/`timeeditor_insert.cpp` with `timeeditor.h`; only their include guards/`#include` lines change.
13. **`topology.*`:** move `rebuildTrackMap` (or keep in `document.cpp` as the facade coordination — keep `rebuildTrackMap`/`trackMapState` in `document.cpp` since the friend commands call them as the coordination seam), `addTrack`, `duplicateTrack`, `deleteTrack`, `moveTrack`, `trackName`, `renameTrack`, `canAddTrack`, `freeChannel`, `trackRemap` into `topology.cpp`; hoist `TrackRemap` into `topology.h` (keeping `TrackMapState` in `editop.h`).
14. **`raw.*`:** move `insertRawEvent`, `modifyRawEvent`, `deleteRawEvents`, `moveRawEvent`, `rawEventMoveBounds`, `setTrackEndTick` into `raw.cpp`; `raw.h` carries only the helper decls the event-list views might later need (none required today → keep it minimal or fold the decls into `document.h` and drop `raw.h` if empty; do **not** create a token 30L header).
15. **Build checkpoint 2** — full app + checks compile. Run the §5 acceptance set.

**Why this order:** notes→lanes→time→topology→raw is dependency order (topology/raw reuse the detail builders; time depends on the tempo helpers hoisted in Phase 0). No step reorders another step's edits, so a single implementer can run the phases serially without merge conflicts.

### Phase 3 — Facade assembly + final CMake cutover (compile-checkpoint 3)
16. **Delete the old files.** After the last body moves out, `src/core/songdocument.{h,cpp}` and the four `songdocument_*` helpers must hold nothing but `#include` stubs destined for deletion; remove them fully (no forwarding shims — clean cutover).
17. **Finalize `document.h`.** It now holds: the `#include`s of `notes.h`/`lanes.h`/`time.h`/`topology.h`/`editop.h`/`detail.h` (and `commands/commands.h` privately), the class shell (public API + signals + state members + private method decls + `friend` decls), and the remaining nested edit-payload types if any are left (prefer both: keep nested edit-payload types, and keep `TimeEditor` fwd decl).
18. **Rewrite the 52 include sites + 6 forward-decl header sites.** Run `lsp references` on `SongDocument` and scoped `grep` (`path` = `src/core`, `src/ui`, `src/checks`, `src/project`) for `songdocument` before touching anything; change `#include "core/songdocument.h"` → `#include "core/document/document.h"`. Forward decls (`class SongDocument;`, `struct DocNote;`, `struct TrackRemap;`, `struct SmfEvent;`, `struct SmfTrack;`) are left as-is because the moved types stay at the same namespace scope and the class name is unchanged.
19. **Final CMake pass:** confirm `porydaw_app` lists exactly the new file paths and no `songdocument*` path remains; confirm `commands/*.cpp`, `editop.cpp`, `detail.cpp`, `notes_edit.cpp`, `notes.cpp`, `lanes.cpp`, `topology.cpp`, `time.cpp`, `raw.cpp`, `timeeditor*.cpp` are present; `lanemoveplan.*` stays.
20. **Full build checkpoint 3** — `cmake --build build --target porydaw porydaw_checks`.

### Phase 4 — Caller verification, check validation, include hygiene
21. Run the §5 acceptance matrix **in order**; a failure stops the phase at its gate.
22. **Obsolete-reference sweep:** `grep` (scoped) + `lsp references` for `songdocument`/`SongDocument::EditOp` respelled symbols returning zero outside `src/core/document/`.
23. `deno task format:check` (clang-format gate) and `deno task checks` (broad ASan sweep) as the final regression net.
24. **Optional docs follow-up (separate small commit, not part of this wave):** add `src/core/document/AGENTS.md` (~20L) implementing the §9 routing row "SongDocument / time / undo → read src/core/document/AGENTS.md".

**Ownership note.** `songdocument.{h,cpp}` and the friend/command/TU seam are a single serialization boundary. One implementation owner controls `document/document.h`, the `friend` list, `applyOps/revertOps`, and the command constructors until `commands.h` is fixed at the end of Phase 1; parallel work starts only after that, and only on independent domain TUs (`notes`, `lanes`, `raw`) whose headers are already frozen. This mirrors the §5/§6 ownership guidance in `docs/agent-reorg-plan.md`.

## 5. Testing and verification

### 5.1 Targeted automated harnesses (exact argv from `checkcatalog.cpp`)
Run via `./build/porydaw_checks` against a scratch copy of the decomp project (the catalog synthesizes `{scratch}`/`{mid2agb}`). `QT_QPA_PLATFORM=offscreen` is required for the UI-driving checks. Order matters; the first three are the primary correctness oracles:

1. **Undo/redo atomicity + SMF canonical ordering** — `QT_QPA_PLATFORM=offscreen ./build/porydaw_checks --editcheck <scratchRoot>` (editcheck.cpp: "undo restores SMF byte-for-byte ... event ticks stay sorted").
2. **NoteId stability** — `--check-note-identity <scratch>` (noteidcheck.cpp).
3. **mid2agb serialization / round-trip parity** — `--roundtrip <scratch> <mid2agb>` and `--savecheck <scratch> mus_route101 <mid2agb>` and `--smfcheck`.
4. **Raw event list** — `--eventviewcheck <scratch>` (raw insert/modify/delete/move + bounds).
5. **Loop markers** — `--loopcheck` (self-contained).
6. **Production UI callers** — `--rollcheck <scratch> mus_route101`, `--rollwindowingcheck <scratch> mus_route101`, `--check-automation <scratch> mus_route101`, `--check-automation-gestures <scratch> mus_route101`, `--check-automation-popup-menus <scratch> mus_route101`, `--check-velocity-page <scratch> mus_route101`, `--check-rendering-playhead <scratch> mus_route101`.
7. **Host/session integration** — `--check-host-seams`, `--check-host-adapter <scratch> mus_route101`, `--check-host-integration <scratch> mus_route101 mus_petalburg`, `--sessioncheck <scratch> mus_route101`, `--tabcheck <scratch> mus_route101 mus_petalburg`.
8. **Onboarding / export / topology-adjacent** — `--onboardcheck <scratch> <mid2agb>`, `--mkcheck <scratch> mus_aqua_magma_hideout`, `--exportcheck <scratch> mus_route101`.
9. **Selection seam (exercises `TrackRemap` consumers)** — `--selectioncheck`.

### 5.2 Verification gates (stop-the-wave ordering)
- **Gate 0 (Phase 0):** build + `--smfcheck` + `--editcheck`.
- **Gate 1 (Phase 1):** build + `--editcheck` + `--check-note-identity`.
- **Gate 2 (Phase 2):** build + the full §5.1 set.
- **Gate 3 (Phase 3):** clean build, plus `deno task format:check`.
- **Gate 4 (Phase 4):** full `deno task checks` (ASan sweep via `tools/run_checks.ts`) + obsolete-reference sweep returns zero findings.

### 5.3 Failure cases each gate must exercise
- **Note overlap resolution:** add/move/resize a note over a stationary same-key note (trim head/tail/full-cover) — covered by editcheck's per-op scripted pass + rollcheck's pencil gestures; no re-pairing of a neighbor's note-end.
- **Mergeable move gestures:** replay of the editcheck transpose/nudge merge case proves `MoveNotesCommand::mergeWith` still rewinds/rel-lands correctly after the command moves to `commands/`.
- **Unterminated notes:** raw-event edits + `resizeNotesLeft`/`moveNotes` on unterminated note-ons keep `endIndex == SIZE_MAX` and note bytes identical.
- **Track-map change:** add/delete/move/rename a track, then verify `tracksRemapped` fires before `documentChanged` with the correct `TrackRemap` — covered by editcheck's track-op stage and host-integration.
- **Tempo/raw mix:** `removeRawEventsAndEditTempo` / `replaceTempoPointWithRawEvent` still push exactly one undo item each (the `MixedEditCommand`, not a double `applyTempoEdit`).

## 6. Risks, compatibility, migration needs

| Risk | Impact | Mitigation |
|---|---|---|
| **Friend/TU coupling regressions** — the 6 commands + `TimeEditor` reach private state; a body move that drops include order breaks build or worse, silently reorders publish | High | Freeze `commands.h` + `editop.h` in Phase 0/1; keep all six as `SongDocument` members with unchanged private access; never add a second state holder |
| **`documentChanged`/`tracksRemapped` ordering or double-emission** (MoveNotesCommand suppress-then-publish and MoveNotesToPitchesCommand direct-emit paths) | High | `publishMutation` stays a single funnel in `document.cpp`; no command emits directly except the two existing documented exceptions; gates 1–2 assert undo/redo byte-identity |
| **NoteId minting drift** — `mintNoteId`/`m_nextNoteId` must remain the sole ID source, exercised through `applyOps` only | High | `mintNoteId`/`mintUnassignedNoteIds` stay in `document.cpp`; `--check-note-identity` as a gate |
| **mid2agb / SMF canonical ordering** — same-tick intra-group ordering (setup < note-on < note-end) and tempo meta placement are load-bearing | High | `applyOps`/`writeTempoMetas` bodies move verbatim; `--roundtrip`/`--smfcheck`/`--editcheck` gate; no "while we're at it" rewrites |
| **`document.h` stays ~400L (over 300L target)** | Low | Accepted residual; cohesion-first per `keep-files-small`; flagged in §3.2 for explicit review |
| **80L fragment temptation** (6 tiny command files, a token `raw.h`) | Low | Group into `commands/editcommand.cpp` + `commands/movecommand.cpp`; drop a header that has no real owner |
| **Missing a forward-decl vs full-include site** (6 fwd sites + 52 include sites) | Medium | Scoped `grep` + `lsp references` sweep in Phase 3–4; fwd decls unaffected |
| **Parallel subagent same-file collisions** | Medium | Serial phases until `commands.h`/`editop.h` freeze; then fan out only on disjoint TUs |

**Compatibility: none needed.** This is an internal refactor of `SongDocument`'s file organization. No public signature, no signal, no SMF output, and no undo index change. No CSV/format migration, no on-disk format change.

## 7. Alternatives considered and rejected

1. **Public `NoteDocument`/`LaneDocument`/`TimeDocument` classes.** Rejected: forces a split of canonical state (`m_smf`, `m_tempoPoints`) and of `applyOps` across objects, violating the no-parallel-state rule; requires re-plumbing the 6 friend commands and `TimeEditor`; ~52 consumers would need mechanical API churn (e.g. `doc.notes()->add(...)`). Higher risk, zero behavior gain.
2. **pimpl / `DocumentImpl` opaque state.** Rejected: the friend commands and `TimeEditor` already need the concrete state; a pimpl adds an indirection layer and a second "interface" for no navigability benefit. The current "one class, bodies-in-TUs" pattern already achieves the file-size goal.
3. **Fragment-inclusion (`document.h` `#include`s method-declaration fragments inside the class body).** Rejected: unusual, harms grep/navigation (the stated pain), and the 528L header is dominated by genuine interface, ~220L of which are type/*EditOp* declarations that move out via the hoisting steps. A ~400L cohesive header is preferable to a clever-but-unreadable one.
4. **One giant `document_impl.cpp` (collapsing the helpers back together).** Rejected: recreates a god file; contradicts the reorganization's whole point.
5. **Splitting each command into its own file (the literal `editcommand.h/cpp`, `movenotescommand.h/cpp`...).** Rejected per `keep-files-small`: six 27–100L files are the "40 tiny files" antipattern; two cohesive command TUs are more discoverable.
6. **Moving `lanemoveplan.{h,cpp}` out of core.** Kept in `document/` (it is a document primitive with no external users beyond `moveLanePoints` and `rangeedit`); verified no `SongDocument` dependency, so it moves verbatim.

## 8. Assumptions and unresolved questions

**Assumptions (proceeding without blocking):**
- The public type/name set is frozen; consumers continue to reference `SongDocument::NewNote`, `SongDocument::RangeEdit`, `SongDocument::TimeRange/TimeScope`, `SongDocument::LanePointMove/Value` exactly as today (kept nested), while `TrackRemap`/`DocNote`/`DocLanePoint`/`TempoEdit`/`DocTimeSig` continue as namespace-scope (they already are).
- `rebuildTrackMap`, `trackMapState`, `currentTrackRemap`, `trackRemap` stay in `document.cpp` as the coordination seam (friend commands call them); `topology.cpp` holds only the track-structure mutators + `trackName`/`renameTrack`. If the implementer prefers `trackRemap` in `topology.cpp`, that is acceptable as long as it remains a `SongDocument::` member — this is a placement detail, not an interface change.

**Genuinely unresolved (would benefit from an owner decision, but neither blocks starting):**
1. Whether `document.h`'s ~400L residual is accepted as-is or the team prefers hoisting the nested edit-payloads (`NewNote`/`RangeEdit`/`TimeRange`/`TimeScope`/`LanePointMove`/`LanePointValue`) to namespace scope too — which would shrink `document.h` to ~330L but forces `SongDocument::X` → `X` churn across ~10 production callers + ~8 checks. My recommendation: **keep them nested** (smaller diff, lower risk), accept the ~400L header.
2. The final naming for the provisional `time_tempo.cpp`/`time_range.cpp` (I recommend merging both into `time.cpp` per the target's `time.*`; the interim names exist only to keep Phase 0 a pure rename).
3. Whether `raw.h`/`notes.h` decl headers that would otherwise be ~30–55L should be dropped in favor of keeping those small decls inline in `document.h` (my recommendation: keep `notes.h`/`lanes.h`/`time.h`/`topology.h` since each declares genuine shared types; drop `raw.h` if it ends up declaring nothing beyond what `document.h` already exposes).