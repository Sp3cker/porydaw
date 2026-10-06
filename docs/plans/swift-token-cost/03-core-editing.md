# Plan 03 — Core editing extensions (planner: ThoughtfulSilkworm — COMPLETE, PARTIALLY VERIFIED)

## Verdict

PARTIALLY VERIFIED. (1) The *plan* kernel already exists and is shared
(TimeActions/TimePlan/materialize — no consolidation left there). (2) The *collision* kernel does NOT
exist: the same span-vs-note resolution is hand-rolled 3× with 3 different emitters — consolidating the
pure decision logic is a real but modest token win with no behavior change IF emitters stay per-call-site.
(3) REJECTED: merging the emitters (e.g. porting NoteEditing.relocate onto TimeActions/materialize)
risks behavior drift.

## Duplication inventory (~175 duplicated/dead lines, 5 files)

- Covered/trim interval math ×3: collectEditedWins (NoteEditing.swift:411-451),
  planCollisionActions (TimeEditing+Collisions.swift:33-60), resolveCollisions (:81-103). Same algorithm:
  per stationary note, scan same-pitch spans, compute covered/trimStart/trimEnd.
- Pairwise overlap check ×3: participantsAreCompatible (NoteEditing.swift:484-503, param
  allowExactDuplicates) + inline copies at TimeEditing+Collisions.swift:10-21 and :70-79.
  Identical sort key (track,pitch,tick) + adjacent same-(track,pitch) overlap test.
- Sort key ×4: ($0.track,$0.pitch,$0.tick) at NoteEditing.swift:167-169,395-397,488-490,
  TimeEditing+Collisions.swift:10-12,70.
- Duplicate concepts: shiftedTick (NoteEditing.swift:505-509) ≡
  TimeDefaults.shiftTickClamped (MusicTypes.swift:113-119); inline velocity clamp
  (TimeEditing.swift:238) ≡ clampVelocity (MidiSemantics.swift:341-343);
  PlannedNote (NoteEditing.swift:476-482) ≅ TimeNoteSpan (TimeEditingSupport.swift:11-16, subset + unused chunk).
- Dead code: TrackRemap.isIdentity (EventEditing.swift:527-533, zero refs); PlannedNote.chunk
  (NoteEditing.swift:61/290, written never read).
- Quantified: kernel (~80 ln) + 3 adapters (~15–25 ln each) ⇒ net −80..−100 LOC; replaces 3 near-copies
  agents must read together (~640 ln across NoteEditing + TimeEditing+Collisions).

## Ownership map

- SongDocument (SongDocument.swift:292-565): canonical mutable model. Sole write path DocumentMutation
  (:163-290) → commit (:460-473) → history.record → publish → projection.repair (:523-527).
  History replay rebuilds projection wholesale (:512-521).
- NoteProjection (NoteProjection.swift:25-187): derived read model; repaired incrementally in publish;
  prior-state memo for gesture base replay (SongDocument.swift:363-369).
- PlaybackTimeline (674 ln): immutable playback projection; built by DocumentSession, NOT SongDocument.
  Read-only w.r.t. edits; out of kernel scope.
- DocumentSession (DocumentSession.swift:89-459, 459 ln): composer — owns document, installs onChange
  (:193-195), rebuilds timeline via PlaybackTimeline.build (:192). Session-only selection/mute-solo never
  enter history. Not a mutation path.

## Steps

1. New `src/swift/core/NoteCollision.swift` (~80 ln, register in core CMakeLists.txt 22-file list):
   two pure @MainActor-free functions — spansAreCompatible(spans:allowExactDuplicates:) and
   resolveStationaryCollisions(spans:stationary:editedIDs:) → decision enum
   {covered, trimmed(start:end:), untouched}. Purity keeps history/grouping/base-state disciplines in extensions.
2. Migrate NoteEditing first (strongest check suite): collectEditedWins (:389-454) builds TimeNoteSpan list,
   calls kernel, emits per decision. relocate (:302)/addNotes (:65) call spansAreCompatible. Delete
   participantsAreCompatible (:484-503), PlannedNote (:476-482), shiftedTick (:505-509 → shiftTickClamped).
   KEEP retainSharedEnds (:456-466) + emission shell untouched.
3. Migrate TimeEditing+Collisions.swift: planCollisionActions (:5-64) + resolveCollisions (:66-106) delegate
   check + covered/trim loops to kernel. Preserve per-caller deltas: planCollisionActions feeds
   reference-projection notes into TimeActions remove/move; resolveCollisions feeds mutation.state-resolved
   notes (findNote at :85 — applyRangeEdit may already have moved them) into removeNote/insertNoteCopy.
4. Pure deletions: TimeEditing.swift:238 inline clamp → clampVelocity; delete TrackRemap.isIdentity
   (EventEditing.swift:527-533). Zero behavior surface.
5. Gate: editcheck suite (src/checks/editcheck/, 26 files: NoteChecks, NoteCorpusChecks, NoteMove*,
   NoteHistoryChecks, TimeCorpusChecks, TimeRange* ×6, DocumentEditChecks, DocumentHistoryChecks,
   ClipboardEditingChecks; runner tst_songdocument_runner.swift). Critical: exact-duplicate addNotes accepted,
   relocate rejects duplicates, paste-collision trims, remove-time seams, undo/redo round-trips.

## Preservation constraints

- Public edit contract unchanged (signatures, NoteEditError incl. conflictingEditedNotes, Bool rejection
  semantics, HistoryOperation merge cases, gesture base-state replay via origin(for:)).
- Projection repair: all paths funnel commit → publish → repair; no direct state.file mutation.
- DocumentChangeSet replay-equivalence: adapters keep today's emission order (kernel returns decisions keyed
  by input; adapters loop in current order).
- Kernel types internal (like TimeNoteSpan); no new PorydawCore public symbols (core has no direct QML exposure).
- retainSharedEnds survives verbatim (no Time-path analog; guards shared note-offs).
- resolveCollisions keeps mutation.state lookup, NOT reference projection.

## Rejected alternatives (with evidence)

- Full relocate→TimeActions/materialize port: materialize re-mints noteIDs when preserveIdentity=false
  (TimeEditing+Streams.swift:139) + Xcmd reconciliation per chunk (:99-108,:173-189); relocate preserves
  noteID (:321) with no Xcmd coupling. No shared-end analog either. High drift risk, zero extra token win.
- Unifying planInsert/planDuplicate split-clone blocks (TimeEditing+Plan.swift:199-215,251-283): different
  boundary arithmetic per mode; ~20 lines saved at real drift risk. Non-goal.
- ThemeColorTables rewrite: excluded (verified by src/checks/themecolor).
- resizeNotesDurations (:151-182) into kernel: computes caps, not decisions; shares only sort key. Keep separate.

## Risks

- Emission-order drift → undo/redo divergence (mitigation: adapter order discipline + corpus checks).
- Exact-duplicate semantics must stay parameterized (addNotes:true vs relocate:false vs Time:absent).
- Reference-vs-mutation source swap in resolveCollisions would silently mis-trim (adapter discipline in-step).
- Dropping retainSharedEnds deletes live note-offs (kept in adapter, covered by NoteCorpusChecks).
- New file must be registered in CMakeLists.txt.
