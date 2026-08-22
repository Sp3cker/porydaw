# SongDocument Refactor — Authoritative Implementation Plan

**Status:** implementation-ready synthesis  
**Scope:** `src/core/songdocument.{h,cpp}` and the five existing SongDocument satellite files, totaling 3,915 lines.  
**Destination:** `src/core/document/`.  
**Supersedes for implementation:** the individual reports in this directory. They remain evidence and design history; where they disagree, this document governs.

## 1. Objective and approval bar

Refactor `SongDocument` into one deep external module with cohesive internal translation units. Preserve all observable behavior during the decomposition, then perform only two narrowly specified structural simplifications after the mechanical cutover.

The work is complete only when:

1. `SongDocument` remains the single concrete `QObject` and the single document seam used by UI, checks, session, and persistence code.
2. Its implementation lives under `src/core/document/`; no implementation file exceeds 600 lines, and new files normally stay in the 200–400 line band.
3. The public source cutover is complete: no forwarding header, deprecated include, compatibility alias, parallel state holder, or old include path remains.
4. The `EditOp` transaction model, undo/redo behavior, revision behavior, signal order, SMF output, tempo projection, track remapping, and note identity behavior remain unchanged through the mechanical phases.
5. Existing behavioral checks remain unchanged except for mechanical include-path and type-spelling updates.
6. The final full verification and ASan sweep pass.
7. The final review finds no generic helper junk drawer, shallow public role object, gratuitous micro-header, or duplicate implementation of a load-bearing rule.

This is not permission to redesign SongDocument while moving it. The mechanical decomposition and the two approved simplifications are separate reviewable waves.

---

## 2. Locked architectural decisions

### 2.1 External seam

`SongDocument` remains one concrete module:

```text
src/core/document/
  songdocument.h     public class interface
  types.h            public value types belonging to the same module
  *.cpp / private headers
```

Callers may include `core/document/songdocument.h`. A caller that only constructs or stores document value types may include `core/document/types.h`. No caller may include the internal operation, command, TimeEditor, or implementation files.

Do not introduce:

- `NoteDocument`, `LaneDocument`, `TimeDocument`, or `doc.notes()` role objects;
- a virtual document interface;
- pimpl or `DocumentImpl` state;
- `MutationSink`, `SongEditContext`, or another adapter around the one real document;
- separate mutable copies of `SmfFile`, tempo, track-map, revision, or undo state.

There is one state owner and one external seam.

### 2.2 Public types

Move these existing public value types into `src/core/document/types.h` at global scope — the same scope `TrackRemap` and `DocNote` occupy today — without changing their fields, defaults, aggregate behavior, or semantics. Introduce no `document` namespace or any other new namespace: the existing global-scope forward declarations of `class SongDocument;`, `struct DocNote;`, and `struct TrackRemap;` in `songview.h`, `eventlistview.h`, `eventtablemodel.h`, `editorselectionmodel.h`, `automationpage.h`, `cclanes.h`, and `smfcheckfixtures.h` must keep compiling unchanged.

- `TrackRemap`
- `DocNote`
- `DocLanePoint`
- `DocTimeSig`
- `TempoEdit`
- `NewNote`
- `LanePointValue`
- `LanePointMove`
- `RangeEdit`, including its existing nested payloads
- `TimeRange`
- `TimeScope`
- `DOC_CC_BEND` and `DOC_CC_VOICE`

Migrate every `SongDocument::NewNote`, `SongDocument::RangeEdit`, `SongDocument::TimeRange`, `SongDocument::TimeScope`, `SongDocument::LanePointValue`, and `SongDocument::LanePointMove` caller to the global-scope spelling in the same phase. Do not leave `using` aliases in `SongDocument`; they would turn a clean cutover into an indefinite compatibility surface.

The public free functions `metaIsLoopMarker` and `nameIsLoopMarker` keep their declarations in `songdocument.h`; their definitions move to `markers.cpp` in Phase 7B.

Keep implementation-only types private to the module:

- `EditOp`
- `TrackMapState`
- `PlannedNote`
- `TimeEditor`
- every `QUndoCommand` subclass

Do not split the public values among `docnote.hpp`, `doclane.hpp`, `doctime.hpp`, or a public `fwd.hpp`. One cohesive `types.h` is enough.

### 2.3 Internal organization

Use ordinary `SongDocument::` member definitions in focused `.cpp` files. This gives maintainers locality without publishing new modules or granting internal helpers ownership of document state.

Keep `lanemoveplan.{h,cpp}` in `src/core/`. It is already an independent module and is not part of the SongDocument monolith.

Keep `smf.{h,cpp}`, `noteid.h`, `tempo.h`, `timedefaults.h`, and `miditimeline.{h,cpp}` in `src/core/`.

### 2.4 Change discipline

Mechanical phases must move existing declarations and function bodies without semantic cleanup. Specifically, do not during those phases:

- change a public method signature except for the locked global-scope type cutover;
- rename signals, undo labels, commands, or check filters;
- add `std::span`, concepts, generic predicates, casts, fallbacks, validation, or speculative bounds checks;
- change publication behavior;
- change note pairing, overlap handling, event ordering, tempo normalization, or time-range semantics;
- consolidate commands or introduce `NoteEditPlan` while extracting their current bodies;
- modify check expectations to make a phase pass.

If a supposedly mechanical phase needs a behavioral assertion change, stop: the phase changed behavior.

### 2.5 Shared file-local helpers

Two anonymous-namespace helpers in `songdocument.cpp` are consumed by function families that land in different destination TUs:

- `cfgSemanticEqual` — used by `save` (stays in `songdocument.cpp`) and `setCfg` (Phase 3, `pipeline.cpp`);
- `metaIsTimeSig` — used by `timeSigs` (Phase 7B, `markers.cpp`) and by `deleteTrack` / `moveTrack` (Phase 7A, `tracks.cpp`).

When a phase first separates such a helper from one of its consumers, promote the helper to a private static member function declared in `songdocument.h` and defined in the destination TU of its primary family: one definition, no duplicate static copies, no `detail.*` or helper junk-drawer header. This is the one authorized declaration addition during the mechanical wave; it is a move, not a semantic change. Helpers whose consumers all land in one TU (for example the track-name helpers, which all land in `tracks.cpp`) simply move with that family as file-local statics. Phase 9 later relocates `metaIsTimeSig` classification to `smf.{h,cpp}`.

---

## 3. Ubiquitous language

Use these terms in filenames, comments, reviews, and commit descriptions:

- **SMF Chunk:** one `SmfTrack` / MTrk, addressed by `smfTrack`.
- **Seq Chunk:** chunk 0, where mid2agb reads sequence-global metadata. It is not synonymous with engine track 0.
- **Engine Track:** the current channel-mapped editing track, addressed by `engineTrack`.
- **NoteId:** stable note identity. `onIndex`, `endIndex`, and `smfTrack` in `DocNote` are snapshot positions and become stale after mutation.
- **Value Stream:** last-wins state carried over time, including CC, pitch bend, voice, projected tempo, and time signatures where the operation treats them as state.
- **Projected Tempo:** `m_tempoPoints`; the live `m_smf` contains no FF 51 events.
- **TimeRange:** half-open `[startTick, endTick)` musical interval.
- **RangeEdit:** one atomic multi-stream edit payload; it is not a time operation.
- **EditOp:** internal reversible mutation instruction and apply-time undo journal.
- **Command:** a `QUndoCommand`, not an `EditOp`.
- **Facade:** the external `SongDocument` seam. Internal `.cpp` files are its implementation, not new caller-facing modules.

---

## 4. Non-negotiable behavioral invariants

Every phase review must explicitly check the invariants affected by that phase.

### INV-1 — One low-level mutation engine

All undoable post-load SMF edits continue to flow through `applyOps`; undo continues through `revertOps`. Load-time reconstruction remains the documented exception. Builders describe changes as ordered `std::vector<EditOp>`. No extracted feature file creates a second live-edit transaction path.

### INV-2 — `EditOp` is a mutable undo journal

`applyOps` records resolved indices, old events, old track ends, removed track data, and note-ID lifecycle state back into each op. `revertOps` consumes that recorded state in exact reverse order. Keep `applyOps` and `revertOps` in the same translation unit.

Do not convert `EditOp` to `std::variant` or split planning from journaling in this refactor.

### INV-3 — Removal and insertion ordering

Normal event removals are deduplicated and emitted in descending index order per SMF chunk. Inserts resolve their canonical position when applied.

`moveRange` builds one ascending, deduplicated index list shared by its removal and exact-bytes reinsertion passes so reinsertions mirror the removals. The removal ops themselves still flow through `appendRemoveOps`, which emits them in descending order. Preserve the shared-list coupling; do not compute removal and reinsertion indices independently.

### INV-4 — Canonical same-tick placement

Preserve the existing relationship used by insertion and raw-move bounds: setup events precede same-tick notes, and note ends precede same-tick note-ons. `applyOps` and `rawEventMoveBounds` must not encode divergent rules.

### INV-5 — mid2agb note pairing

`notesForTrack` remains the single pairing implementation. It scans backward using 16 × 256 channel/key slots and pairs a note-on with the first later same-channel, same-raw-key note end. The 256-key width prevents malformed raw key bytes from aliasing legal keys. Multiple note-ons may share one end where the existing algorithm allows it.

### INV-6 — NoteId lifecycle

`m_nextNoteId` remains the sole ID source. IDs are minted once for newly inserted note-ons, preserved across move/modify/trim reinsertions, and assigned to legacy notes during load. The `preservesNoteId` lifecycle inside `applyOps` must remain unchanged during decomposition.

### INV-7 — Overlap resolution

`resolveNoteOverlaps` remains one definition used by every note-writing path. A written note wins. A stationary same-track/same-key victim keeps its head, keeps its tail, or is removed when fully covered; it is never split. Unterminated notes are not overlap-trimmed. Trimmed and moved notes preserve exact event bytes and NoteIds.

### INV-8 — Mergeable gesture commands

`MoveNotesCommand` and `MoveNotesToPitchesCommand` each retain their own current merge semantics; they are not required to match each other. Both keep their command IDs (`0x4d76` / `0x4d50`), matching rules, rewind-and-reland merge behavior, clean-index fencing, undo text, and identity comparisons.

Net-zero obsolescence is a `MoveNotesCommand`-only behavior: only it calls `setObsolete(true)` when an accumulated gesture returns to its start. `MoveNotesToPitchesCommand` deliberately has no equivalent check — a pitch gesture that lands back on its origin pitches leaves a spent command on the stack and still emits `documentChanged`. This asymmetry is pre-existing observable behavior (undo-stack depth); do not "fix" it during the split.

A save between gestures fences command merging through `QUndoStack::setClean`; do not duplicate or bypass that behavior.

### INV-9 — Publication protocol, including the existing asymmetry

The canonical publication path remains:

```text
mutate state
rebuild track map when required
increment revision
emit tracksRemapped(nonIdentityRemap), if needed
emit documentChanged()
```

Preserve the special paths exactly during the split:

- `MoveNotesCommand` suppresses publication during initial redo; `moveNotes` publishes after the stack has settled in case the push merged.
- `MoveNotesToPitchesCommand` directly emits `documentChanged` without the normal revision/remap publication path. This is a known behavioral asymmetry, not permission to fix it while moving code.
- Load publishes the existing full-remap behavior.

Any publication-semantic repair is outside this plan.

### INV-10 — TrackRemap symmetry

`TrackRemap::inverse`, pre/post track-map snapshots, chunk-origin algebra, map rebuild, and signal payloads remain one reviewable model. Undo publishes the exact inverse remap.

### INV-11 — Tempo has one projected writer

`replaceTempoPoints` remains the sole writer of `m_tempoPoints`. Normalization remains stable-sort, clamp, and last-at-tick-wins. Raw FF 51 insertion remains rejected. Load extracts and removes tempo metas from live SMF; save writes them back into a copy.

Mixed SMF/tempo operations remain one undo item and one publication.

### INV-12 — Atomic range and time operations

`applyRangeEdit`, `moveRange`, and each TimeEditor operation continue to create one undo item, one revision transition according to current behavior, and one publication. Never split a mixed operation into independent note, lane, and tempo commands.

### INV-13 — TimeEditor seam rules

Preserve all current empty-range and overflow no-op behavior, half-open interval behavior, gap closure, note splitting, whole-song metadata movement, track-end updates, and value-stream seam seeding. Tempo transformations and SMF transformations still land through one mixed edit.

### INV-14 — Persistence and dirty state

`isDirty()` remains `!m_undoStack.isClean()`. Save writes SMF plus projected tempo and conditionally updates midi.cfg before marking the stack clean. Load clears the value-owned undo stack, rebuilds state, mints legacy NoteIds, and publishes the existing remap/change sequence. Keep load and save together in the facade core.

### INV-15 — Canonical channel and marker semantics

`SmfEvent::channel()` remains the canonical masked MIDI channel source. Do not add a speculative `freeChannel` behavior change based on impossible out-of-range canonical channels.

Existing `smf.{h,cpp}` remains the canonical home for `smfTextIsMarker`, `smfMetaIsMarker`, and `SmfChannelPrefix`. Later helper deduplication must reuse or deepen this module rather than create a `detail` or broad `smfsemantics` grab-bag.

---

## 5. Final target layout and ownership

```text
src/core/document/
  types.h                    public value types only
  songdocument.h             SongDocument class, signals, state, private declarations
  songdocument.cpp           ctor, load/save cfg persistence, dirty/revision, timeline, publication, ID minting
  pipeline.cpp               EditOp apply/revert, generic edit commands, setCfg, pushEdit plumbing
  note_commands.cpp          the two mergeable note-move commands and public push wrappers
  notes_query.cpp            note pairing, projection, lookup, span queries
  notes_edit.cpp             note CRUD, overlap resolution, move builders, resize, velocity
  lanes.cpp                  lane query/encode/write/move/delete
  tempo.cpp                  projected tempo normalization, persistence helpers, tempo edits
  range.cpp                  RangeEdit and moveRange
  timeeditor.hpp             private TimeEditor contract
  timeeditor.cpp             time-edit planning and removal
  timeeditor_insert.cpp      insertBlank and duplicate
  trackmap.cpp               TrackRemap algebra, map rebuild, channel/chunk lookup
  tracks.cpp                 track add/duplicate/delete/move/rename and seq-chunk rescue
  markers.cpp                loop marker and time-signature query/edit operations
  raw.cpp                    raw event CRUD, move bounds, track-end editing
```

Expected sizes are guides, not reasons to create padding or dishonest fragments:

| File | Expected lines | Ownership note |
|---|---:|---|
| `types.h` | 180–240 | Existing public value types; no implementation machinery |
| `songdocument.h` | 300–380 | One cohesive class interface; under 400 preferred, 600 hard ceiling |
| `songdocument.cpp` | 250–350 | Facade lifecycle and publication only |
| `pipeline.cpp` | 350–450 | `applyOps` and `revertOps` stay together |
| `note_commands.cpp` | 250–350 | Merge state machines stay visible together |
| `notes_query.cpp` | 220–280 | One note-pairing implementation |
| `notes_edit.cpp` | 380–500 | May exceed 400; never exceed 600 |
| `lanes.cpp` | 250–320 | Reuses `lanemoveplan` |
| `tempo.cpp` | 220–300 | Existing satellite is already cohesive |
| `range.cpp` | 140–180 | Existing cohesive exception to the normal size floor |
| `timeeditor.hpp` | 75–120 | Existing private contract; do not fragment further |
| `timeeditor.cpp` | 430–500 | Under the hard ceiling |
| `timeeditor_insert.cpp` | 260–310 | Existing cohesive operations |
| `trackmap.cpp` | 150–230 | Map algebra and lookup only |
| `tracks.cpp` | 260–380 | Track lifecycle and seq-chunk rescue |
| `markers.cpp` | 150–240 | Marker/time-signature semantics and mutations |
| `raw.cpp` | 260–340 | Raw list operations; projected tempo excluded |

Do not merge unrelated ownership merely to make a short file longer. Do not create headers for files whose declarations already belong in `songdocument.h`.

---

## 6. Execution and subagent model

One integration owner controls `songdocument.h`, the source `songdocument.cpp`, CMake, and phase boundaries. Those files are shared mutation points and must not be edited concurrently.

The integration owner is the main orchestrating session. It serializes phases, performs each phase's final review, and is the only agent that commits: one commit per phase, and one per Phase 7 subphase, so the history stays bisectable. A phase's task subagent does perform the source cut in `songdocument.cpp` — control means serialized access, not that task agents never touch shared files; exactly one phase is in flight at a time. When a phase's verification goes red, the integration owner reverts that phase's commit and re-dispatches the phase with the failure evidence; no later phase builds on a red one.

For each phase:

1. An **explorer** subagent (the harness's read-only `scout` agent) maps the exact symbols and LSP references affected by that phase when the mapping is not already frozen.
2. One **task** subagent performs the complete phase, including the source cut, destination file, includes, and CMake entry. It skips project-wide validation while editing.
3. A **reviewer** subagent reviews the phase against the listed invariants and verifies that moved bodies did not acquire semantic edits.
4. The integration owner runs the phase's targeted verification and records the deliverables.
5. A **sonic** subagent may perform only mechanical include/type spelling updates on files disjoint from the integration owner's files.

Do not fan out two agents that both cut bodies from `songdocument.cpp`. Parallel work becomes safe only after shared declarations and source ownership are frozen, and only for genuinely disjoint files.

Every phase is independently buildable and reviewable. CMake changes land in the same phase as the file they register. Do not leave compiling stubs, forwarding files, duplicate bodies, or a phase that requires the following phase to build.

---

## 7. Verification policy and evidence

### 7.1 Commands

Use the repository tasks rather than invented direct harness commands:

```bash
deno task build:app
deno task build:checks
deno task verify --filter <manifest-name> [--filter <manifest-name> ...]
deno task verify --all
deno task format:check
deno task checks build-asan/porydaw_checks
```

`deno task checks build-asan/porydaw_checks` is the final broad ASan sweep; the checks task requires the binary path as its first argument. Run targeted filters after each focused phase and `verify --all` at the specified wave boundaries.

Relevant manifest names include:

- `editcheck`
- `noteidcheck`
- `roundtrip`
- `savecheck`
- `eventviewcheck`
- `loopcheck`
- `rollcheck`
- `automation-gestures`
- `automation`
- `host-seams`
- `host-adapter`
- `host-integration`
- `sessioncheck`
- `tabcheck`
- `selectioncheck`
- `smfcheck`

Use the manifest as the authority if names change; do not hard-code a stale report's argv.

### 7.2 Required phase deliverables

Every phase report must include:

- files and symbols moved;
- invariants reviewed;
- exact targeted verification run and its result;
- whether any check source changed, and why;
- old and new line counts for affected implementation files;
- CMake entries added/removed;
- confirmation that no duplicate definitions or transitional stubs remain.

Record phase reports and the Phase 0 baseline in `docs/song-doc-split/phase-reports.md`, one section per phase, so the evidence chain outlives the subagents that produced it.

At a clean-cutover phase, also include LSP-reference and scoped-search evidence that old paths or spellings are gone. Do not rely on a historical claim that there are exactly 52 include sites; discover the current set.

---

## 8. Mechanical decomposition wave

### Phase 0 — Baseline and frozen decisions

**Agent:** explorer for mapping, integration owner for verification, reviewer for baseline assessment.

**Work:**

1. Record current `SongDocument` file line counts and the current CMake source entries.
2. Use LSP references plus scoped search to inventory the current public include and nested public type callsites.
3. Build application and checks.
4. Run the baseline core checks:

   ```bash
   deno task verify --filter editcheck --filter noteidcheck --filter roundtrip \
     --filter savecheck --filter smfcheck
   ```

5. Record known failures, if any. Do not edit production or check code to manufacture a green baseline.
6. Run the complete final gate set once — `deno task verify --all`, `deno task format:check`, and the ASan sweep below — and record every result. A failure discovered at Phase 8 must be provably pre-existing, not four phases old.
7. Record `MoveNotesToPitchesCommand`'s direct-emission behavior as intentionally preserved for this refactor.

**Exit:** the baseline, including the full gate set, is recorded in `phase-reports.md`; target paths, type cutover, and invariants are frozen.

### Phase 1 — Move the existing module into `core/document`

**Agent:** one task integration agent; sonic may update disjoint caller includes after the header move is established; reviewer checks rename purity.

**Work:**

1. Create `src/core/document/`.
2. Move directly to final names:

   ```text
   songdocument.h                       -> document/songdocument.h
   songdocument.cpp                     -> document/songdocument.cpp
   songdocument_tempo.cpp               -> document/tempo.cpp
   songdocument_range.cpp               -> document/range.cpp
   songdocument_timeeditor.hpp          -> document/timeeditor.hpp
   songdocument_timeeditor.cpp          -> document/timeeditor.cpp
   songdocument_timeeditor_insert.cpp   -> document/timeeditor_insert.cpp
   ```

3. Update CMake's explicit `porydaw_app` source list in the same change.
4. Update every include of `core/songdocument.h` to `core/document/songdocument.h`. Use LSP file rename/reference support where available, then scoped search for residual paths.
5. Do not move `lanemoveplan`.
6. Do not alter declarations or bodies beyond include paths required by the move.
7. Delete the old paths; add no forwarding header.

**Verification:**

```bash
deno task build:app
deno task build:checks
deno task verify --filter editcheck --filter savecheck --filter smfcheck
deno task verify --all
```

**Exit:** pure path cutover, no old include or source path, all existing bodies otherwise unchanged.

### Phase 2 — Extract and cleanly cut over public value types

**Agent:** one task agent owns `types.h` and `songdocument.h`; sonic may migrate disjoint callers; reviewer checks field-for-field identity and alias absence.

**Work:**

1. Create `types.h` with exactly the public values listed in §2.2.
2. Preserve field order, defaults, helper methods, aggregate behavior, and namespace conventions.
3. Update `SongDocument` declarations to use the global-scope types.
4. Migrate all qualified caller spellings to the global-scope names, including the `SongDocument::TimeRange` / `SongDocument::TimeScope` spellings inside the private `timeeditor.hpp` header.
5. Add direct `types.h` includes only where a caller no longer needs the full document class.
6. Keep `EditOp`, `TrackMapState`, `PlannedNote`, and `TimeEditor` private.
7. Leave no `SongDocument::X` compatibility aliases.

**Verification:**

```bash
deno task build:app
deno task build:checks
deno task verify --filter editcheck --filter noteidcheck --filter selectioncheck
deno task verify --all
```

**Exit:** public values have one definition in `types.h`; all callers use the final spelling; `songdocument.h` is materially smaller.

### Phase 3 — Extract the mutation pipeline and mergeable command machinery

**Agent:** one task agent; reviewer focuses on INV-1 through INV-3, INV-6, INV-8, and INV-9.

**Work:**

1. Create `pipeline.cpp` and move, without semantic change:
   - `applyOps` and `revertOps` together;
   - `moveChunk` if it is used only by that mirror pair;
   - `SongEditCommand`, `SongCfgCommand`, `setCfg`, and the `cfgSemanticEqual` helper used by that path;
   - the existing two-argument `pushEdit` path, `makeChannelEvent`, and `appendRemoveOps`.
2. Create `note_commands.cpp` and move both mergeable note command classes plus their public stack-push wrappers.
3. Keep `TempoEditCommand`, `MixedEditCommand`, and the tempo-aware `pushEdit` path in `tempo.cpp` for this mechanical phase.
4. Preserve friend access, command IDs, first-redo suppression, direct-emission quirks, undo labels, and clean-index merge behavior.
5. Do not introduce `DocumentEditCommand`, `MutationSink`, `SongEditContext`, or `NoteEditPlan` yet.
6. Promote `cfgSemanticEqual` per §2.5 when moving `setCfg`.

**Verification:**

```bash
deno task build:checks
deno task verify --filter editcheck --filter noteidcheck --filter eventviewcheck \
  --filter rollcheck --filter host-seams --filter host-integration
deno task verify --all
```

**Exit:** the mutation mirror and merge state machines are isolated but behavior-identical.

### Phase 4 — Extract read models and track-map algebra

**Agent:** one task agent; reviewer focuses on INV-5, INV-9, INV-10, and signal consumers.

**Work:**

1. Create `notes_query.cpp` and move the note pairing and query family as one definition set.
2. Create `trackmap.cpp` and move `TrackRemap` behavior, map snapshots, rebuild, chunk/channel lookup, and remap algebra.
3. Keep these as `SongDocument::` member definitions where they need document state; do not introduce a new state object.
4. Do not duplicate note pairing for convenience in edit files.
5. Keep `publishMutation` in `songdocument.cpp`.

**Verification:**

```bash
deno task build:checks
deno task verify --filter noteidcheck --filter selectioncheck --filter rollcheck \
  --filter loopcheck --filter host-integration
```

**Exit:** read projection and track-map math each have one cohesive home.

### Phase 5 — Extract note mutations

**Agent:** one task agent; reviewer focuses on INV-1, INV-3, INV-5 through INV-8.

**Work:**

1. Create `notes_edit.cpp`.
2. Move note add/delete/move-builder/resize/velocity operations, `appendNoteInsertOps`, and `resolveNoteOverlaps` without rewriting their transaction skeletons.
3. Keep `resolveNoteOverlaps` defined exactly once.
4. Preserve removal ordering, exact event bytes, unterminated-note handling, NoteId preservation, revision-CAS behavior, and undo text.
5. Do not add `NoteEditPlan` or NoteId-only public edit methods in this phase.

**Verification:**

```bash
deno task build:checks
deno task verify --filter editcheck --filter noteidcheck --filter rollcheck \
  --filter savecheck
```

**Exit:** all note mutation behavior is localized and checks observe byte-identical undo/redo behavior.

### Phase 6 — Extract lane operations

**Agent:** one task agent; reviewer focuses on lane last-wins behavior, closed write intervals, collision planning, and atomic publication.

**Work:**

1. Create `lanes.cpp`.
2. Move lane query, encoding, add, write, move, and delete functions.
3. Continue to reuse `lanemoveplan` from `src/core/`.
4. Preserve CC, pitch-bend, and voice encoding, clamping, same-tick replacement, inclusive `writeLanePoints` range semantics, undo labels, and one-command gesture behavior.
5. Do not treat projected tempo as a lane.

**Verification:**

```bash
deno task build:checks
deno task verify --filter editcheck --filter automation-gestures --filter automation \
  --filter rollcheck
```

**Exit:** lane behavior has one implementation home and no duplicate gesture planner.

### Phase 7 — Extract track, marker, and raw-event families

**Agent:** one task agent per ordered subphase; do not run them concurrently because each cuts the shared source. One reviewer checks the complete phase.

#### Phase 7A — Tracks

Create `tracks.cpp`; move track add/duplicate/delete/move/rename, free-channel selection, track-name query/classification helpers, and seq-chunk rescue. Preserve unique channels, the 16-track limit, program seed, chunk-0 retention, global-event rescue, names, remap calculation, and publication order. Promote `metaIsTimeSig` per §2.5 when it splits between `tracks.cpp` and `markers.cpp`.

Verification filters: `editcheck`, `selectioncheck`, `tabcheck`, `host-integration`, `savecheck`.

#### Phase 7B — Markers

Create `markers.cpp`; move loop-marker and time-signature queries/mutations. Preserve first-unprefixed-name handling, `SmfChannelPrefix` scope, marker vocabulary, chunk-0 rules, last-wins behavior, and track-name rejection of marker spellings.

Verification filters: `loopcheck`, `eventviewcheck`, `editcheck`, `roundtrip`, `savecheck`.

#### Phase 7C — Raw events

Create `raw.cpp`; move raw insert/modify/delete/move/bounds, `appendEventEditOps`, and track-end editing. Preserve raw permissiveness, tempo-meta rejection, tick-change remove/reinsert behavior, same-tick pinning, no-op bounds, exact bytes, and `endTick` constraints.

Verification filters: `eventviewcheck`, `editcheck`, `smfcheck`, `roundtrip`.

After each subphase:

```bash
deno task build:checks
deno task verify --filter <listed-filter> [--filter <listed-filter> ...]
```

After Phase 7C:

```bash
deno task verify --all
```

**Exit:** the original monolithic implementation contains only facade-core responsibilities.

### Phase 8 — Finalize the facade and mechanical cutover

**Agent:** integration owner; reviewer performs a two-axis review: architectural ownership and behavioral preservation.

**Work:**

1. Leave `songdocument.cpp` with constructor, load/save cfg persistence, dirty/revision access, timeline construction, publication, NoteId minting, and genuinely cross-domain facade plumbing.
2. Confirm each target file respects its ownership in §5 and the 600-line ceiling.
3. Remove obsolete declarations, includes, stale CMake paths, duplicate definitions, empty files, and extraction scaffolding created by these phases.
4. Use LSP references and scoped searches to prove:
   - no `core/songdocument.h` references remain;
   - no old `songdocument_*` source paths remain;
   - no migrated `SongDocument::X` public type spellings or aliases remain;
   - no UI/check file includes an internal document header;
   - `resolveNoteOverlaps`, note pairing, tempo replacement, and the op mirror each have one definition.
5. Do not perform unrelated cleanup.
6. Rebuild the ASan checks binary before the final sweep: no `deno` task builds `build-asan/` (`build:app` / `build:checks` configure only `build/`, and `deno task checks` runs a given binary without compiling it), so the integration owner runs `cmake -S . -B build-asan -DPORYDAW_ASAN=ON` followed by `cmake --build build-asan -j<n>` — the one sanctioned direct-CMake invocation, performed by the integration owner only. Running `deno task checks build-asan/porydaw_checks` against a stale binary is a false green.

**Verification:**

```bash
deno task build:app
deno task build:checks
deno task verify --all
deno task format:check
deno task checks build-asan/porydaw_checks
```

**Exit:** the mechanical refactor is independently releasable and behavior-preserving.

---

## 9. Approved post-split simplification wave

These phases begin only after Phase 8 is green. They are separate semantic-preservation refactors, not cleanup hidden inside extraction commits.

### Phase 9 — Reuse canonical SMF classification helpers

**Agent:** explorer maps all duplicate classification sites; one task agent performs the consolidation; reviewer checks mid2agb parity.

**Work:**

1. Remove the duplicate `metaIsTimeSig` implementation by placing or reusing the narrow canonical predicate in `smf.{h,cpp}`.
2. Route existing loop-marker and channel-prefix classification through `smfTextIsMarker`, `smfMetaIsMarker`, and `SmfChannelPrefix` where their semantics are exactly identical.
3. Do not force track-name, marker-rescue, lane encoding, or generic channel-event construction into one broad helper merely because each interprets SMF.
4. Add no `detail.*` or generic `smfsemantics.*` bucket.
5. Preserve exact event-order and prefix-scope behavior.

**Verification:**

```bash
deno task build:checks
deno task verify --filter smfcheck --filter roundtrip --filter loopcheck \
  --filter eventviewcheck --filter editcheck
deno task verify --all
```

**Exit:** exact duplicate classification is gone and canonical SMF ownership is clearer without a new shallow module.

### Phase 10 — Unify generic document edit commands

**Agent:** one task agent; reviewer focuses on undo payloads, empty-tempo representation, remaps, revision, publication, and no-op behavior.

**Work:**

1. Replace `SongEditCommand`, `TempoEditCommand`, and `MixedEditCommand` with one `DocumentEditCommand` that owns:
   - edit text;
   - `std::vector<EditOp>`;
   - `std::optional<std::vector<TempoPoint>> nextTempo`;
   - the old tempo payload only when tempo participates;
   - the track-map/remap state required for exact undo publication.
2. Use `std::nullopt` to mean “do not edit tempo.” An engaged empty vector means “replace projected tempo with no explicit points.” Never use vector emptiness as a sentinel.
3. Replace the two generic `pushEdit` paths with one internal path whose optional tempo payload preserves:
   - op-only edits;
   - tempo-only edits;
   - mixed edits;
   - empty-tempo edits;
   - no-op detection;
   - one undo item and one publication.
4. Keep `SongCfgCommand`, `MoveNotesCommand`, and `MoveNotesToPitchesCommand` separate.
5. Do not introduce `MutationSink` or another virtual seam. The unified command remains a friend of the one concrete `SongDocument`.
6. Do not change the move-command publication asymmetry in INV-9.
7. `DocumentEditCommand` and the unified `pushEdit` live in `pipeline.cpp`, replacing both current overloads; `tempo.cpp` keeps only its tempo-aware callers.
8. The unified path normalizes the optional tempo payload first and pushes nothing exactly when `ops.empty()` and the tempo payload is either disengaged or equal to `m_tempoPoints`. This preserves both current overloads: the two-argument path no-ops on empty ops; the three-argument path no-ops on empty ops plus unchanged normalized tempo. `applyTempoEdit` keeps its direct no-op early return so stack depth never changes.
9. The unified command adopts `MixedEditCommand`'s redo/undo skeleton verbatim — snapshot `trackMapState()`, apply ops when non-empty, `replaceTempoPoints`, `rebuildTrackMap()`, remap (`currentTrackRemap()` when ops are empty, `trackRemap(before, ops)` otherwise), publish; undo mirrors with the inverse remap. `TempoEditCommand`'s never-rebuild path disappears into this skeleton. The equivalence argument — rebuilding the track map over an unchanged SMF is a no-op yielding an identity remap, so publication is identical — must be confirmed by the reviewer against `editcheck`'s recorded revision and signal sequences.

**Verification:**

```bash
deno task build:checks
deno task verify --filter editcheck --filter automation-gestures --filter automation \
  --filter eventviewcheck --filter roundtrip --filter savecheck \
  --filter host-integration
deno task verify --all
deno task format:check
deno task checks build-asan/porydaw_checks
```

**Exit:** three duplicate generic transaction commands become one without changing observable behavior.

---

## 10. Explicitly deferred work

The following findings may be valid future projects but are not authorized by this plan:

- NoteId-only public edit interfaces and removal of snapshot addressing from `DocNote`;
- `NoteEditPlan` or a generalized transaction builder;
- unifying the two mergeable move commands;
- changing `MoveNotesToPitchesCommand` revision/remap publication;
- replacing `EditOp` with typed variants;
- un-nesting and redesigning TimeEditor;
- introducing `std::span` across public mutation methods;
- performance changes to note lookup or velocity deduplication;
- changing closed lane-write intervals or half-open time ranges;
- putting projected tempo back into live SMF;
- new white-box tests of private operation ordering;
- security hardening unsupported by a reachable invariant violation.

Each requires its own behavioral contract, callsite migration plan, and focused review. Do not leave overload shims or parallel implementations in anticipation of that work.

---

## 11. Final reviewer checklist

### External module

- [ ] `SongDocument` remains the only public document object and only `Q_OBJECT` in the module.
- [ ] Callers include only `songdocument.h` and, where sufficient, `types.h`.
- [ ] No old include path, forwarding header, public role object, compatibility alias, pimpl, context object, or virtual mutation interface exists.

### State and transactions

- [ ] `SongDocument` remains the sole owner of SMF, projected tempo, track map, revision, and undo stack.
- [ ] `applyOps` and `revertOps` remain adjacent and exact mirrors.
- [ ] Ordinary removals remain descending; `moveRange` retains its single ascending, deduplicated index list coupled to reinsertion while removal ops still flow through `appendRemoveOps`.
- [ ] `resolveNoteOverlaps` and note pairing each have one definition.
- [ ] Tempo replacement has one writer and mixed edits remain atomic.

### Undo and publication

- [ ] Command IDs, merge behavior, clean-index behavior, undo labels, obsolete-command behavior, and first-redo suppression are unchanged.
- [ ] Remap signals precede document-changed signals on the canonical path.
- [ ] `MoveNotesToPitchesCommand`'s existing direct-emission behavior remains unchanged.
- [ ] Save/load dirty-state and stack-clean semantics are unchanged.

### Domain and persistence

- [ ] Backward 16 × 256 note pairing remains byte-for-byte equivalent.
- [ ] NoteId mint/preserve behavior is unchanged.
- [ ] Seq-chunk rescue, name/marker classification, and channel-prefix scope are unchanged.
- [ ] Live SMF contains no tempo metas; save/roundtrip output is unchanged.
- [ ] Range and TimeEditor operations remain one command and preserve seam behavior.

### Structure and evidence

- [ ] Every file has one stated reason to change and is under 600 lines.
- [ ] No generic helper junk drawer or gratuitous micro-header was introduced.
- [ ] CMake names every implementation source explicitly.
- [ ] Existing behavioral checks changed only for mechanical include/type spelling.
- [ ] Targeted phase checks, final `verify --all`, `format:check`, and `checks` results are recorded.
- [ ] A dedicated reviewer approves both architectural ownership and behavioral preservation.
