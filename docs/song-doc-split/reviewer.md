# SongDocument split — engineering review

**Reviewer stance:** safety, undo invariants, testability, incremental execution.
**Scope reviewed:** `src/core/songdocument.{h,cpp}` (522 + 2176 lines), `src/core/songdocument_tempo.cpp` (242), `src/core/songdocument_range.cpp` (142), `src/core/songdocument_timeeditor.{hpp,cpp}` (78 + 471), `src/core/songdocument_timeeditor_insert.cpp` (278); consumers in `src/ui/` (26 files include `songdocument.h`), `src/checks/` (23 files), `src/audio/` (comment-only reference), and the CMake wiring (`porydaw_app`, `porydaw_checks`, `porydaw_render_cli`).
**Date:** 2026-08-21. Line numbers refer to current `main` state.

---

## 1. Executive summary

`SongDocument` is a single `QObject` façade over a byte-faithful SMF model with a private transactional op engine (`EditOp` + `applyOps`/`revertOps`), five `QUndoCommand` subclasses (two mergeable), a derived read model (`DocNote`/`DocLanePoint`/`DocTimeSig`/tempo points), and a nested `TimeEditor` planner. The design is already internally layered: satellites (`_tempo`, `_range`, `_timeeditor*`) are pure member-function translation units hanging off one header. That makes a file split under `src/core/document/` **low-risk and high-value**: the dominant hazard is not architecture but *discipline* — the undo engine's index rules, the publication protocol, and the merge semantics are subtle, cross-file, and currently held together by physical proximity.

Verdict: **proceed**, with the phased plan in §7. The split must be strictly mechanical (function bodies byte-identical, public API frozen, zero check-harness edits) with the full check manifest run per phase. The one substantive pre-split decision is the `MoveNotesToPitchesCommand` revision asymmetry (§3, INV-8a) — pin it or fix it *before* moving code, never during.

---

## 2. Current-state inventory

| File | Lines | Contents |
|---|---|---|
| `songdocument.h` | 522 | Public value types (`TrackRemap`, `DocNote`, `DocLanePoint`, `TempoEdit`, `DocTimeSig`, `TimeRange`, `TimeScope`, `RangeEdit`, `NewNote`, `LanePointValue`, `LanePointMove`); the `SongDocument` façade; friends; private `EditOp`, `TrackMapState`, op builders; member state |
| `songdocument.cpp` | 2176 | 4 command classes, load/save, track-map math + remap algebra, publication, note pairing/read model, note writes/moves, overlap resolution, lane ops, raw-event ops, loop/timesig ops, track lifecycle ops, `applyOps`/`revertOps`, `pushEdit` (2-arg) |
| `songdocument_tempo.cpp` | 242 | `TempoEditCommand`, `MixedEditCommand`, `pushEdit` (3-arg), tempo normalization/extraction, `replaceTempoPoints` (sole tempo writer), raw+tempo mixed edits, `song_document_tempo` meta (de)serialization |
| `songdocument_range.cpp` | 142 | `applyRangeEdit`, `moveRange` |
| `songdocument_timeeditor.hpp` | 78 | Nested `SongDocument::TimeEditor` (private planner; note: nested classes have access to enclosing-class privates) |
| `songdocument_timeeditor.cpp` | 471 | `time_edit_detail` tempo transforms, plan builders, `TimeEditor::remove()` |
| `songdocument_timeeditor_insert.cpp` | 278 | `TimeEditor::insertBlank()`, `TimeEditor::duplicate()` |

Header dependency closure of `songdocument.h`: `QObject`, `QString`, `QUndoStack`, `core/noteid.h`, `core/smf.h`, `core/tempo.h`, `core/timedefaults.h`, `project/decompproject.h` (for `SongInfo`/`SongCfg`). It is included by **26 UI files** (`src/ui/songview.*`, `src/ui/editordrawer/*`, event table/list stack, `src/songsession.h`, …) and **23 check files** — any edit to this header recompiles essentially the whole project except `porydaw_render_cli`.

Build wiring (`CMakeLists.txt`):
- `CMAKE_AUTOMOC ON` globally (line 38).
- `porydaw_app` static library lists the core sources explicitly — songdocument family at lines 179–184.
- `porydaw_checks` (line 386) links `porydaw_app` (line 475) — a source move needs exactly **one** list edit per phase; no other target wiring exists.
- `porydaw_render_cli` (lines 594–600) compiles only `mid2agbtables/miditimeline/smf/timelineplayer` — **unaffected** by this refactor.
- `mid2agb` is an external converter binary; unaffected.

---

## 3. Critical behavioral invariants (the contract the split must not break)

Each invariant below is stated with its evidence location and its migration hazard. These are the acceptance criteria for every phase.

### INV-1 — EditOp index discipline
Ops carry indices valid **against the document state at apply time** (songdocument.cpp:105–115 comment, `applyOps` at ~2047). Builders must therefore order **all removals first** (descending per SMF track, deduped — `appendRemoveOps`, ~706), let insertions resolve position at apply time, and record side data (`oldEvent`, `oldEndTick`, `trackData`, resolved `index`) on first apply. `revertOps` (~2142) replays exactly the reverse.
*Hazard:* any new file that builds ops in a different order (e.g. interleaving removals and inserts per track) silently corrupts recorded indices. Keep every op-builder family next to `appendRemoveOps`/`appendEventEditOps` or in a file that documents INV-1 at the top.

### INV-2 — applyOps/revertOps exact mirror
`applyOps` mutates ops in place (records undo data, mints note IDs once via `preservesNoteId` flip). `revertOps` is its perfect inverse, including `moveChunk` being shared with swapped endpoints (songdocument.cpp:84–92).
*Hazard:* the two functions must live in the same TU (or at least the same header) so nobody edits one without seeing the other. Never split `applyOps` from `revertOps` across files.

### INV-3 — Canonical intra-tick placement
`InsertEvent` places setup events (type nibble ≥ 0xB) ahead of same-tick notes and note-ends ahead of same-tick note-ons (`applyOps`, ~2052–2080); `rawEventMoveBounds`'s `pinnedBefore` (~1437) is the same relation expressed as reorder bounds. Two encodings of one rule in two places.
*Hazard:* if these drift apart, raw reordering can produce vectors `insertRawEvent` would never build. Keep a cross-reference comment; ideally co-locate in the same file (`editop.cpp` + a comment, or `rawops.cpp` beside the bounds fn referencing `editop.cpp`).

### INV-4 — Note pairing (mid2agb rule)
A note-on pairs with the **first same-channel same-key end after it**; several note-ons may share one end; the pairing uses the **raw key byte in a 16×256 slot table** (out-of-range keys must not alias, `notesForTrack` ~555–598). `DocNote` indices are **stale after any mutation** — the documented contract ("freshly resolved") that every edit entry point relies on.
*Hazard:* none if moved verbatim; the read model (`notesForTrack`, `noteAt`, `findNote`, `noteEndTick`, `containsNoteSpan`) is self-contained. But it must remain the *only* pairing implementation — do not let a split file re-derive pairing for convenience.

### INV-5 — NoteId minting and preservation
IDs are monotonic (`m_nextNoteId`, wrap-at-0 skipped, `mintNoteId` ~493), minted exactly once per inserted note-on (the `preservesNoteId` flip inside `applyOps`/`ModifyEvent`), preserved across moves/modify/trim re-inserts, and minted for legacy files at `load` (`mintUnassignedNoteIds`).
*Hazard:* the mint-once flag lives inside op mutation. If `EditOp` moves to its own header, `mintNoteId`/`m_nextNoteId` access must stay available to `editop.cpp` (friend or member definition file — see §5, friends).

### INV-6 — Overlap resolution
`resolveNoteOverlaps` (~745–816): a written note wins; a stationary same-track same-key victim keeps its head (end trimmed to span start), keeps its tail (start moved to span end), or is removed when fully covered — **never split**; unterminated notes are never trimmed; trimmed events re-inserted with **exact bytes** and their note IDs; victim indices append to `removals` so INV-1 ordering holds. Used by `addNote`, `addNotes`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`, `resizeNotes`, `resizeNotesLeft`, `applyRangeEdit`, `moveRange` — **eight call sites across what would be 4+ files**.
*Hazard:* the single highest duplication risk in the split. `resolveNoteOverlaps` must be defined exactly once (suggest its own small file or head of `noteops_write.cpp`) and every caller includes the same definition.

### INV-7 — Command merging (gesture semantics)
- `MoveNotesCommand` (songdocument.cpp:174–288): `id()` returns `'Mv'` (0x4d76) **only when `mergeable`** — keyboard transpose/nudge presses collapse; mouse drags pass `mergeable=false` and never merge. `mergeWith` **reverts both commands** (restoring any neighbor the intermediate position trimmed via INV-6), re-lands the accumulated delta from the **gesture's original notes**, and `setObsolete(true)` when the gesture returns to start. `movesMyOutputs` demands the next press edits exactly the notes where this command left them (same IDs, positions, durations) — anything else is a new gesture.
- `QUndoStack` refuses to merge across its clean index — a save between presses keeps its own command (comment at ~168). Dirty-state interplay is load-bearing.
- `MoveNotesToPitchesCommand` (~290–401): `'MP'` (0x4d50), same rewind-and-reland strategy, but multisets of positions instead of per-note matching, and `m_destPitches = other->m_destPitches` (the newer press's pitches win).
*Hazard:* both commands privately reach into document internals (`revertOps`, `buildMoveNotesOps`, `publishMutation` suppression). They must keep friend access and must move **together with their builders**. Merging correctness is covered by `editcheck`'s merged-move fixture (editcheck.cpp:702–718) — that fixture is the gate.

### INV-8 — Publication protocol
`publishMutation` (~485): `m_revision++`, then `tracksRemapped` (only if non-identity) **before** `documentChanged`, after `rebuildTrackMap`. Signal order is a public contract — `rollcheck` and `editcheck` assert the `remap → changed` ordering literally (editcheck.cpp:107–116, rollcheck.cpp:522–528).
Special cases the split must preserve verbatim:
- `MoveNotesCommand::redo` **suppresses** publication on its initial redo (`m_initialRedo`) because a merge may replace the provisional state; the public `moveNotes` wrapper publishes after the stack settles (~1000–1006).
- `load` publishes an all-`(−1)` remap mapping the *previous* state away (~371–377).
- `SongCfgCommand` publishes identity remaps (cfg edits re-run `rebuildTrackMap` because `extendedClocks` changes `ticksPerClock`).

**INV-8a — observed asymmetry (pin or fix before splitting):** `MoveNotesToPitchesCommand::redo`/`undo` emit `documentChanged` **directly** (~339–347) — no `publishMutation`, hence **no `m_revision` bump** — and the public `moveNotesToPitches` (~1008–1029) does not publish either. Every other mutating command bumps revision. Consequence: `setNotesVelocities(expectedRevision, …)`'s optimistic-concurrency guard (~1225) cannot observe a pitch-move gesture. This is pre-existing behavior, not introduced by the split — but a refactor that "tidies" it into `publishMutation` would change observable revision sequencing that `editcheck` records (`loadRevisions`). Decide first: (a) pin current behavior with a note, or (b) fix in a separate, singly-reviewed behavior commit before Phase 1. Do **not** change it as a side effect of moving code.

### INV-9 — TrackRemap inverse symmetry
`TrackRemap::inverse` (~43–63) and `trackRemap` chunk-origin algebra (~440–483): undo must publish the exact inverse so engine-track-anchored UI state survives. Commands cache `m_remap` at redo and publish `m_remap.inverse()` at undo.
*Hazard:* pure math, safe to move; keep `TrackRemap` implementation next to `trackRemap` so the algebra stays reviewable as one unit.

### INV-10 — Tempo single-writer and normalization
`m_tempoPoints` is written **only** by `replaceTempoPoints`, whose input must already be normalized (asserted, `songdocument_tempo.cpp`); normalization = stable sort by tick, clamp µs/qn, **last-at-tick wins**. Raw FF 51 metas are rejected by the raw editor (`insertRawEvent`/`modifyRawEvent` guards), stripped from `m_smf` at `load`, and re-serialized only in `save` via `writeTempoMetas`. Mixed time/range commands carry a typed `TempoPoint` payload through the 3-arg `pushEdit` (`MixedEditCommand`) — the header comment is explicit: they **must not** call `applyTempoEdit`, which would push a second undo item.
*Hazard:* the two `pushEdit` overloads will live in different TUs (2-arg in `editop`/commands file, 3-arg in `tempo.cpp`). Both must remain `SongDocument` members; an accidentally-introduced free/static function would compile and silently break the mixed path. Also: every tempo-touching op builder (range, time editor, raw+tempo) computes `nextTempo` via `editedTempoPointCandidates` or `time_edit_detail` transforms — those helpers must stay single-definition.

### INV-11 — Atomic multi-track range edits
`applyRangeEdit` (songdocument_range.cpp) and `moveRange` land cross-track note/lane/tempo changes as **one** `QUndoCommand` with one `documentChanged`. `moveRange` re-inserts events with exact bytes so unterminated notes stay unterminated; its removals are sorted **ascending + deduped** (a deliberate exception to INV-1's descending rule because the re-insert loop mirrors the removal list by index — the comment says so).
*Hazard:* don't "normalize" that ascending sort to `appendRemoveOps`'s descending order; the two passes are index-coupled.

### INV-12 — Dirty state and save semantics
`isDirty() == !m_undoStack.isClean()`; `save` writes the .mid (with tempo re-injected), conditionally writes the midi.cfg line (`cfgSemanticEqual` excludes `rawFlags`; `m_hadCfgLine`), then `setClean` — and `setClean` is also what fences command merging (INV-7).
*Hazard:* none structurally; `savecheck` covers it. Keep `save`/`load` in the core file.

### INV-13 — Load semantics
Format-0→1 coercion at parse; tempo extraction **then** stripping from the model; undo stack cleared; IDs minted; full-remap publication. The disk copy flips to format 1 on first edit+save — deterministic round-trip relied on by `savecheck`/`roundtrip`.
*Hazard:* none if moved verbatim; keep `load`/`save` together.

### INV-14 — TimeEditor seam and overflow rules
`insertBlank`/`duplicate` (songdocument_timeeditor_insert.cpp) guard `tick + span` overflow and **return false** (no command) when the shift would overflow; value streams seed state at the destination seam (last in-range point moves to `startTick`, or is dropped when a point already sits at the seam — `removeTempoPoints` and the channel-stream loop in `remove()`); unterminated notes split with a synthesized 0x8 end; `wholeSong` moves non-note metas to the seam rather than deleting them; per-chunk `SetTrackEnd` ops close/extend the song. `deleteTrack`/`moveTrack` rescue time signatures and the winning loop marker into chunk 0 (the seq chunk mid2agb reads).
*Hazard:* the TimeEditor is already a separate header/impl — it moves as-is. The chunk-0 rescue logic in `trackops` is the part that must stay co-located with `findLoopMarkerEvent`/`metaIsTimeSig` classification or include them explicitly.

---

## 4. Risk register (split-specific)

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | `resolveNoteOverlaps` duplicated or subtly re-timed across note-op files | **High** | Single definition, one shared internal header; all 8 callers verified by `editcheck` collision fixtures |
| R2 | `applyOps`/`revertOps` drift (INV-2/3) | **High** | Same TU; INV-3's two encodings cross-referenced |
| R3 | `pushEdit` overload split breaks `MixedEditCommand` path | Medium | Both stay `SongDocument` members; grep both signatures after the move |
| R4 | Friend-list churn / private-access backdoors (`EditOp`, `m_smf`, `publishMutation`) | Medium | Friends unchanged, declared once in `songdocument.h`; command classes moved but not re-typed |
| R5 | `tr()` context change if commands gain their own `QObject` parent | Medium | Commands stay non-`QObject` `QUndoCommand` subclasses calling `SongDocument::tr(...)` verbatim |
| R6 | moc fallout from new `Q_OBJECT` types | Low | `SongDocument` remains the **only** `Q_OBJECT` in `document/`; helpers are plain member-function TUs |
| R7 | Include-path churn across 49 files | Low (breadth) | One mechanical commit, scripted; clean cutover, no forwarding shim |
| R8 | Behavior "improvements" smuggled into mechanical moves | **High (process)** | Per-phase rule: bodies byte-identical; `git diff -w` review; INV-8a decided before Phase 1 |
| R9 | TimeEditor loses nested-class privilege if un-nested | Low | Keep it nested (`SongDocument::TimeEditor`) — zero header-semantics change |
| R10 | Translation/undo-label strings drift | Low | Labels are constructor literals; copy verbatim |

---

## 5. Compilation & dependency impact

- **The header is the project.** 26 UI + 23 check includes. The split should *reduce* long-term compile coupling only if internal headers (`editop.h`, `timeeditor.hpp`) stay out of UI reach — they are and must remain private to `document/` (no UI/check file may include them; enforce by grep in review).
- **Facade stays one header.** Keep `core/document/songdocument.h` (path updated everywhere) as the single public include. Do not ship `songdocument_types.h` et al. unless a later phase demonstrably needs it — every extra public header is 49-file churn for marginal gain. The current header at ~520 lines is acceptable; it is declaration-dense, not logic-heavy.
- **AUTOMOC:** new headers are scanned only if listed in a target's sources. Since all new files are plain `.cpp` member definitions plus two internal headers, add each `.cpp` to `porydaw_app` (CMakeLists.txt ~179–184) and keep the internal headers next to them. No `AUTOMOC` action needed beyond listing.
- **One list edit per phase.** `porydaw_checks` and `porydaw` link `porydaw_app`; nothing else consumes these paths.
- **PCH:** `porydaw_pch.hpp` fronts the checks target; unchanged — the moved TUs include the same Qt/std headers as before.
- **LTO/IPO boundary** unchanged (same static library).
- **Include hygiene win (optional, Phase 5):** `songdocument.h` pulls `decompproject.h` only for `SongInfo`/`SongCfg`. If desired later, forward-declare and pass by const-ref — but that changes the public surface; keep it out of the mechanical phases.

---

## 6. Test matrix — which harness gates what

All harnesses run through the `porydaw_checks` manifest (`checkcatalog.cpp`). Verification per phase = build + run the full manifest (plus the ASAN sweep at phase boundaries, per repo practice).

| Harness | SongDocument surface exercised | Gates phases |
|---|---|---|
| `--editcheck` (editcheck.cpp) | **The master gate.** M2 undo-integrity: per-edit undo/redo SMF byte identity, signal ordering (`remap` vs `changed`), revision sequence, tempo round-trip, move-collision fixture, duplicate-global fixture, merged-move fixture (MoveNotesCommand merge + obsolete path), time-range no-op guards | Every phase |
| `--rollcheck` (rollcheck.cpp) | Track remap ordering, note-ID projection (`addNotes` duplicate → distinct IDs, ~277–300), `documentChanged → buildTimeline` refresh cycle, raw metadata-to-engine remap, release ordering | 1, 2, 3 |
| `--eventviewcheck` | Raw event table: insert/modify/delete/move, `rawEventMoveBounds`, notification ordering, conversion state | 3 (rawops) |
| `--savecheck` | `save`/`setClean`/midi.cfg write-back/`isDirty` | 2, final |
| `--smfcheck` (+ fixtures) | Parse-layer invariants feeding `load` | 1 |
| `--selectioncheck`, `--sessioncheck`, `--transportcheck`, `--loopcheck`, `--noteidcheck`, `--polycheck`, `--selftest` | Selection anchoring through remaps, session lifecycle, loop markers, ID stability | 1, 3, 4 |
| `--check-automation-gestures` (automationgesturecheck/*) | `writeLanePoints`, `applyTempoEdit`, gesture transactions, snapshot isolation (`smf().write()` + revision + undo index) | 3 (laneops, tempo) |
| `--check-automation*`, `rollcheckautomation*` | Tempo/CC lanes, popup menus, paint, tempo occlusion | 3, 4 |
| `pitchbendcheck` (via rollcheck) | Bend-lane gestures, undo snapshot advance | 3 |
| `--check-host-integration`, `--exportcheck`, `--check-rendering-playhead` | `load` + `buildTimeline` projection | 1, 4 |
| `--onboardcheck` | Song creation → `load` | 1 |

**Success criterion for the whole refactor: zero check-file edits.** The harnesses verify behavior at the byte/SMF level, which is exactly the right level for a file split. Any need to touch a check during a mechanical phase is a red flag that the phase changed behavior.

**Coverage gaps to be aware of (not blockers):** no white-box unit tests exist for `resolveNoteOverlaps` or `TimeEditor` in isolation — they are covered through `editcheck`/time-range fixtures. Do not add white-box tests before the split; they would pin internals the split exists to relocate. If coverage investment is wanted, do it after, against the public API.

---

## 7. Phased execution plan

Standing rules for every phase:
1. **Mechanical only** — moved function bodies byte-identical; `git diff` review; no renames of public symbols, signals, or value types.
2. **One family per commit**, each leaving the tree building and the manifest green (bisectable).
3. **Full `porydaw_checks` manifest** after each commit; ASAN build sweep at each phase boundary.
4. **CMake list updated in the same commit** as the file move.

### Phase 0 — Baseline & decisions (no code moved)
- Build `porydaw_checks`; run the full manifest; record the baseline (failures = zero, or a known list).
- Decide INV-8a (`MoveNotesToPitchesCommand` revision bypass): pin with an explicit expectation added to `editcheck`'s revision recording, **or** fix in a separate behavior commit reviewed on its own. Either way the split then has a guard.
- Agree the target layout (§8) and the internal-header policy (UI/checks never include `document/editop.h` or `document/timeeditor.hpp`).
- *Exit:* manifest green; INV-8a decision recorded.

### Phase 1 — Move existing satellites unchanged
`songdocument_tempo.cpp` → `document/tempo.cpp`; `songdocument_range.cpp` → `document/range.cpp`; `songdocument_timeeditor.hpp` → `document/timeeditor.hpp`; `songdocument_timeeditor.cpp` → `document/timeeditor_remove.cpp` (471 lines; see §8 note); `songdocument_timeeditor_insert.cpp` → `document/timeeditor_insert.cpp`. Update their `#include "songdocument.h"` → the new header path and the CMake list. No content changes; `TimeEditor` stays a nested class.
- *Gates:* full manifest (editcheck, rollcheck, automation suites especially).

### Phase 2 — Extract the read model & track-map math
Move, verbatim, into `document/queries.cpp`: `metaIsLoopMarker`, `nameIsLoopMarker`, `noteAt`, `notesForTrack`, `noteEndTick`, `containsNoteSpan`, `findNote` ×2, `laneEventMatches`, `laneValue`, `lanePoints`, `findLanePoint`, `findLoopMarkerEvent`, `loopTick`, `timeSigs`, `trackName`, `trackNameText`/`trackNameLoc`/`trackNameLocs` helpers. Into `document/trackmap.cpp`: `TrackRemap::{isIdentity,inverse}`, `rebuildTrackMap`, `trackMapState`, `currentTrackRemap`, `trackRemap`, `smfTrackFor`, `channelFor`, `engineTrackForChunk`, `freeChannel`.
- *Gates:* editcheck, rollcheck (remap ordering), loopcheck, noteidcheck, selectioncheck.

### Phase 3 — Extract the op engine & commands
- `document/editop.h`: `SongDocument::EditOp` struct + declarations of `applyOps`/`revertOps` (members; definition file includes this header). `document/editop.cpp`: `applyOps`, `revertOps`, `moveChunk`, the 2-arg `pushEdit`, `SongEditCommand`, `SongCfgCommand`, `makeChannelEvent`, `appendNoteInsertOps`, `appendRemoveOps`, `appendEventEditOps`.
- `document/commands_move.cpp`: `MoveNotesCommand`, `MoveNotesToPitchesCommand`, `moveNotes`, `moveNotesToPitches`, `buildMoveNotesOps`, `buildMoveNotesToPitchesOps` (they own each other's invariants; keep together).
- *Gates:* editcheck (merged-move + collision fixtures are the critical ones), eventviewcheck, pitchbendcheck path.

### Phase 4 — Extract the remaining edit families (one commit each)
- `document/noteops.cpp`: `addNote`, `addNotes`, `deleteNotes`, `resizeNotes`, `resizeNotesLeft`, `setNotesVelocity`, `setNotesVelocities`, `nudgeNotesVelocity`, `resolveNoteOverlaps` + `PlannedNote`.
- `document/laneops.cpp`: `makeLaneEvent`, `addLanePoint`, `writeLanePoints`, `moveLanePoints`, `deleteLanePoints`.
- `document/rawops.cpp`: `insertRawEvent`, `modifyRawEvent`, `deleteRawEvents`, `rawEventMoveBounds`, `moveRawEvent`, `setTrackEndTick`.
- `document/markers.cpp`: `setLoopTick`, `setTimeSig`, `moveTimeSig`, `deleteTimeSig`.
- `document/trackops.cpp`: `canAddTrack`, `addTrack`, `duplicateTrack`, `deleteTrack`, `moveTrack`, `renameTrack`.
- `songdocument.cpp` shrinks to the façade core: ctor, `load`, `save`, `ticksPerClock`, `setCfg`, `buildTimeline`, `publishMutation`, `mintNoteId`, `mintUnassignedNoteIds`, `replaceTempoPoints` call-sites, `trackBudget`. Rename to `document/songdocument_core.cpp` if desired (optional).
- *Gates per commit:* the family's harness rows in §6; full manifest at phase end.

### Phase 5 — Polish (optional, separately reviewed)
- Header diet only if a concrete need appears; otherwise stop.
- Delete any leftover empty files; single final grep for stale `core/songdocument` include paths; confirm no UI/check file includes an internal `document/` header.

---

## 8. Target file layout (reviewer's proposal)

All under `src/core/document/`; the public header path becomes `core/document/songdocument.h` (every consumer include updated mechanically — clean cutover, no shim). Sizes are estimates from current code spans; all within the 200–400 target / 600 ceiling.

```
src/core/document/
  songdocument.h            ~520  public façade — ONLY public header; unchanged API
  songdocument_core.cpp     ~330  ctor, load, save, ticksPerClock, setCfg, buildTimeline,
                                 publishMutation, mintNoteId(s), trackBudget plumbing
  editop.h                  ~ 60  EditOp struct + applyOps/revertOps/pushEdit decls (internal)
  editop.cpp                ~330  applyOps, revertOps, moveChunk, pushEdit(2-arg),
                                 SongEditCommand, SongCfgCommand, shared append*Op builders
  commands_move.cpp         ~380  MoveNotesCommand, MoveNotesToPitchesCommand,
                                 moveNotes, moveNotesToPitches, build*MoveOps
  noteops.cpp               ~400  addNote/addNotes/deleteNotes/resize*/velocity family +
                                 resolveNoteOverlaps (single definition; 8 callers)
  laneops.cpp               ~290  lane point write/move/delete + makeLaneEvent
  rawops.cpp                ~290  raw event insert/modify/delete/move/bounds + setTrackEndTick
  markers.cpp               ~230  loop markers + time signatures
  trackops.cpp              ~340  track add/duplicate/delete/move/rename + chunk-0 rescue
  queries.cpp               ~380  note/lane/timesig/loop/name read model (pairing lives here)
  trackmap.cpp              ~200  TrackRemap algebra + engine-track map rebuild
  tempo.cpp                 ~242  (moved verbatim)
  range.cpp                 ~142  (moved verbatim)
  timeeditor.hpp             ~78  (moved verbatim; stays SongDocument::TimeEditor)
  timeeditor_remove.cpp     ~380  plan builders + TimeEditor::remove (was _timeeditor.cpp;
                                 time_edit_detail transforms may stay or split off)
  timeeditor_insert.cpp     ~278  (moved verbatim)
```

Interfaces:
- **Public** (`songdocument.h`): everything today's UI/checks use — value types, lookups, edit entry points, signals `documentChanged`/`tracksRemapped`, `undoStack()`, `revision()`, `isDirty()`. Frozen during the refactor.
- **Internal** (`editop.h`, `timeeditor.hpp`): consumed only by `document/*.cpp` and the friend command classes. `EditOp` remains a private nested struct of `SongDocument` (declared in `songdocument.h`, defined-in-place as today); `editop.h` only re-declares the member functions — or, simplest legal shape: keep `EditOp` exactly where it is in `songdocument.h` and make `editop.h` unnecessary. **Recommendation: skip `editop.h` in the first pass; add it only if the friend set grows.**
- **Friends:** unchanged list (`SongEditCommand`, `TempoEditCommand`, `SongCfgCommand`, `MoveNotesCommand`, `MixedEditCommand`, `MoveNotesToPitchesCommand`) — command classes keep their names and private access from their new TUs.

---

## 9. Reviewer checklist (apply to every phase's PR)

- [ ] Moved bodies byte-identical (`git diff` shows only path/brace-context changes)
- [ ] No public symbol, signal, or value-type renamed; no check file edited
- [ ] `resolveNoteOverlaps` still defined exactly once
- [ ] `applyOps` and `revertOps` in the same file
- [ ] Both `pushEdit` overloads still `SongDocument` members
- [ ] `SongDocument` still the only `Q_OBJECT` under `document/`; commands still call `SongDocument::tr`
- [ ] Friend list unchanged; no new private-access helper introduced
- [ ] No UI/check file includes an internal `document/` header
- [ ] CMake `porydaw_app` source list updated; `porydaw_render_cli` untouched
- [ ] Full checks manifest green; ASAN sweep clean at phase boundary
- [ ] Undo-label strings unchanged; `editcheck` revision/signal-order recordings unchanged

---

## 10. Bottom line

The codebase is unusually well-positioned for this split: the op engine, merge semantics, and read model are already conceptually separated inside one class, and the check harness verifies behavior at SMF-byte granularity — meaning a purely mechanical file split can be gated end-to-end without writing a single new test. The two things that will actually hurt if mishandled are (1) the temptation to improve while moving (especially the `MoveNotesToPitches` revision asymmetry and `moveRange`'s ascending-sort exception), and (2) duplicating or re-ordering op construction around `resolveNoteOverlaps`/`appendRemoveOps`. Freeze behavior, move code, run the manifest every commit — and this lands boring, which is the goal.
