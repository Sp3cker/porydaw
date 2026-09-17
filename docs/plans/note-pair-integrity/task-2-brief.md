# Core admission and stable identity

## 1. Context

Implement [spec.md](spec.md)'s single collision rule at SongDocument's
planning seam. Inherit [Global Constraints](plan.md#global-constraints).
Fork-main's `resolveNoteOverlaps` is a transactional trim/remove planner
(edited-note-wins) with no participant-vs-participant check, and
`buildMoveNotesToPitchesOps` remints identities via `appendNoteInsertOps`.
This task replaces all of that with one pure admission predicate plus
optional, side-effect-free builders, and makes NoteIds stable through every
semantic move. Tasks 3, 4 and 5 consume the predicate and the unchanged
public rejection contract (void mutations leave revision, bytes, undo state
and IDs untouched; `moveNotesToPitches` returns false).

The baseline is fork-main: nothing described here is being deleted from an
in-flight diff — `resizeNotesDurations`, `allowIdenticalParticipants`,
`ResizeNotesPlan` and resize-preview plumbing do not exist and must not be
introduced.

## 2. Exact write set

- `src/core/songdocument.h`
- `src/core/songdocument.cpp`
- `src/checks/editcheck/tst_songdocument.h`
- `src/checks/editcheck/tst_songdocument_songnotes.cpp`
- `src/checks/editcheck/tst_songdocument_songmoves.cpp`

## 3. Prerequisites

Task 1: `songdocument_test::notePairsConsistent` is available and is asserted
after every accepted mutation in the matrix below.

## 4. Interface contract

Preserve every public mutation signature (`addNote`, `addNotes`,
`moveNotes`, `moveNotesToPitches`, `resizeNotes`, `resizeNotesLeft`) and the
declarations/roles of `PlannedNote`, `EditOp`, `appendRemoveOps`,
`appendNoteInsertOps`, `applyOps`, `revertOps`, `notesForTrack`, and the
three mergeable command classes.

Replace the private trim/remove resolver with a pure predicate:

```cpp
bool noteEditAdmissible(const std::vector<PlannedNote> &written,
                        const std::vector<DocNote> &editNotes) const;
```

- `written` are the final half-open spans of every terminated participant,
  including unchanged participants of per-pitch moves. Within each
  (engineTrack, key) group: an empty span (`endTick <= tick`) refuses; any
  overlap between two written spans refuses (adjacency accepts). Identical
  duplicate spans overlap — they refuse everywhere, including `addNotes`.
- Against stationary notes: for each engine track touched, scan
  `notesForTrack`; exempt `editNotes` members by `NoteId` (not by
  `(smfTrack, onIndex)`); an unterminated stationary note is skipped exactly
  as fork-main's resolver skipped it (documented limit over pre-existing raw
  material). Any intersection between a stationary span and a written span on
  the same (engineTrack, key) refuses.
- The predicate mutates nothing, is `const`, and produces no removals or
  trims. Group or index participant spans by (engineTrack, key, tick) and
  compare only neighboring spans within each group — no quadratic all-pairs
  scan across pitches or tracks, and no whole-song copy. Participant
  exemption uses an efficient NoteId membership lookup (not a linear
  `editNotes` scan per stationary note), stationary notes are compared only
  against written spans in their own (engineTrack, key) group, and the
  stationary scan keeps the one `notesForTrack` pass per touched track.

Change the three builders to `std::optional<std::vector<EditOp>>`, arguments
unchanged: `buildMoveNotesOps`, `buildMoveNotesToPitchesOps`,
`buildResizeNotesOps`. `nullopt` means refusal. Builders stay side-effect
free; public callers and command constructors build once and refuse before
history or publication. No `ResizeNotesPlan`, no realized-duration storage:
`buildResizeNotesOps` keeps the fork-main shape (per-note
`max(1, duration + d)`, `kMaxTick` headroom guard, admission) and refuses
when the grouped result would collide.

Unify the per-pitch builder with the plain move builder: one emission path
rewrites each note's own on/end events (`preservesNoteId = true`,
velocity intact), taking the destination key per note. Consequences the
tests must pin:

- NoteIds survive pitch/scale-fold moves; the `appendNoteInsertOps` emission
  and the `shouldSkip` semantics (including the unchanged-participant
  injection) are gone from this path.
- An unchanged destination still contributes its current span to `written`
  (a converging sibling refuses against it) but emits no ops.
- An unterminated participant moves its patched note-on to the destination
  key instead of staying behind; it contributes no span. Its note-on start
  tick still obeys start-tick overflow admission: `note.tick + dTick` is
  validated for every rewritten note including unterminated ones (the
  end-tick/duration check applies only to terminated notes), so a positive
  `dTick` past `kMaxTick` headroom refuses the batch atomically instead of
  silently clamping the note-on to `kMaxTick`.

Command merging becomes plan-first in all three `mergeWith` bodies: after the
existing compatibility match, evaluate the accumulated candidate against the
pure predicate and the overflow guards before reverting anything; a refused
candidate returns false with zero document mutation (the stack keeps the two
separate commands). Admission alone is not sufficient: because clamping does
not compose additively, a merge is committed only when the accumulated
candidate geometry replanned from the gesture originals exactly equals the
already-applied sequential final geometry of the two commands, compared per
participant by `NoteId` (tick, key and duration). Any mismatch returns false
before any revert, leaving both accepted commands separate — e.g. one note
moved −20 then +10 (clamped at tick 0) must not merge into a net −10 that
rebuilds a different landing, and a duration resized −20 then +5 must not
merge into a net −15. `MoveNotesToPitchesCommand::movesMyOutputs` drops its
by-value tuple matcher and uses the `MoveNotesCommand` pattern (match each
original note's output tick/key/duration/velocity by `NoteId`). The incoming
`destPitches` vector stays bound to the incoming notes' `NoteId`s: when the
second call supplies the same notes in a different order, the matched
destinations are reordered into the original `m_notes` order (or the merge
refuses) before overflow checks, admission and assignment — positional reuse
of `other->m_destPitches` against `m_notes` is prohibited.
`MoveNotesCommand`/`ResizeNotesCommand` keep their clamp-composition
compatibility loops and clean-index behavior.

Consumers in this task's files: `addNote`, `addNotes`, `resizeNotesLeft`,
and the three builders' public entry points refuse on `nullopt`/false before
pushing anything. Void refusals change no bytes, tempo, tracks, IDs,
revision, save-state token, undo count or redo availability.

Test slots (declared in `tst_songdocument.h`, all synthetic-document slots
defined in this task's two .cpp files; corpus slots keep their per-song
rows):

- New: `noteBatchCollisionRejects`, `noteResizeCollisionRejects` (bodies in
  `tst_songdocument_songnotes.cpp`), `noteIdentityStable` (body in
  `tst_songdocument_songmoves.cpp`).
- Renamed: `noteMoveOverlap` → `noteMoveOverlapRefuses` (body rewritten to
  the refusal contract).
- Rewritten bodies, names kept: `noteMoveOverlap`'s old trim expectations,
  `noteMoveCollision` (per-pitch trim/remove pins become refusal +
  stationary identity retention), `noteMoveMerge` (rerouted through free
  pitches; merge-count, undo and clean-index assertions kept),
  `noteMoveBatch` (adds NoteId-preservation through per-pitch moves),
  `noteEditingBatch` (adds identical-twin rejection).
- Added cases inside those existing slots only (no new slot declarations):
  `noteMoveMerge` gains clamp non-composition refusals — a move sequence
  whose accumulated delta replans to different geometry than the two
  applied commands (e.g. −20 then +10 clamped at tick 0) must not merge and
  must leave both commands undo/redo-correct, plus the same boundary for
  per-pitch time movement and for resize (duration clamped at 1); and a
  reversed-order second per-pitch call asserting each `NoteId` lands on its
  own destination pitch through merge and undo/redo. `noteMoveBatch` gains
  an unterminated note-on moved by a positive `dTick` past `kMaxTick`
  headroom: the batch refuses (false return, bytes/history/identity
  unchanged) rather than capping the note-on at `kMaxTick`.

## 5. Implementation steps

1. Add the failing matrix first using `songdocument_test::makeDocument`
   synthetic clean songs; capture bytes, revision, undo index/count/clean
   state, IDs and velocities before each refusal. Keep the actual pre-fix
   failures as reproduction evidence.
2. Add `noteEditAdmissible` (header comment replaces the fork-main
   edited-note-wins comment block above `resolveNoteOverlaps`), delete
   `resolveNoteOverlaps` and its `removals`/`trims` plumbing from `addNote`,
   `addNotes`, `resizeNotesLeft` and the builders; wire refusals at each
   public entry. `deleteNotes` and non-note lanes are untouched.
3. Convert the three builders to `std::optional`, unify per-pitch emission
   with `buildMoveNotesOps`' own-event rewrite, and switch the command
   constructors to prebuilt ops.
4. Restructure the three `mergeWith` bodies to plan-first as specified;
   overflow guards precede the predicate; the rewind-rebuild-apply path runs
   only after admission succeeded — and only after the accumulated candidate
   geometry was proven equal to the already-applied sequential geometry per
   `NoteId`, with per-pitch destinations realigned to the original note
   order when the incoming order differs.
5. Complete the slot matrix below, reroute `noteMoveMerge` through free
   pitches, and run the named checks.

## 6. Acceptance predicate

Every spec row holds through unchanged public mutations: grouped right-edge
extension `[0,10)` + `[20,30)` with +20 refuses atomically (no cap); grouped
left extension into a sibling refuses; single-note resize/draw/move onto a
stationary note refuses with the stationary note's ID, span and velocity
untouched; identical `addNotes` twins refuse while disjoint and adjacent
batches accept; per-pitch moves preserve NoteIds (including unterminated
participants) and refuse convergent or clamped-colliding destinations;
unterminated per-pitch participants obey start-tick overflow refusal;
mergeable sequences whose accumulated candidate geometry differs from the
applied sequential result stay as two commands with correct undo/redo;
undo/redo of accepted edits round-trips bytes exactly; refused edits leave
bytes, revision, undo/redo availability and IDs identical; accepted edits
leave `songdocument_test::notePairsConsistent` true.

NAMED CHECKS (controller under SHARED_TREE; implementer on its settled
tree):

```sh
deno task verify --filter editcheck --qt noteBatchCollisionRejects noteResizeCollisionRejects noteIdentityStable noteMoveOverlapRefuses noteMoveCollision noteMoveMerge noteMoveBatch noteEditingBatch
deno task verify --filter editcheck --verbose
```

The first command is the new/rewritten matrix; the second proves raw
editing, tick limits, publication, history, ranges and time edits stay
green. Known gap outside this write set: `documentPublicationNetZero` and
`documentMergedOverlapPublication` (`tst_songdocument_document.cpp`) move a
note onto an equal-start stationary note and will fail under uniform
refusal; they — with the `addNote`-seeded overlap in
`drawerpresentation/velocity.cpp` — are owned by the inline Direct Task 6
of [plan.md](plan.md), `Align downstream fixtures with refusal semantics`
(prerequisite: this task), not this brief. The full-harness green
expectation therefore holds at the plan milestone once Task 6 lands; at
this task's own settle point the two named document slots are the recorded
exception.

## 7. Task-specific constraints

- No command may enter `QUndoStack` to discover admission failure; initial
  planning and merged replanning use the same gate.
- No public planning API leaves `SongDocument` (no `resizeNotesDurations`
  ever); the predicate and builders stay private.
- No stationary note is ever trimmed, shortened, moved or removed by a
  semantic edit; refusal is the only collision outcome.
- No identical-duplicate admission flag or branch anywhere.
- Pre-existing shared-end/unterminated raw material keeps fork-main
  interpretation; no whole-document cleanup pass.
- Selection ownership, playback, new-song creation and SMF pairing code are
  untouched.
