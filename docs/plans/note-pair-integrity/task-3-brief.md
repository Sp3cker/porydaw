# Range producer

## 1. Context

Implement [spec.md](spec.md)'s single collision rule for the two multi-track
range producers. Inherit [Global Constraints](plan.md#global-constraints).
Consume Task 2's contracts: the private `SongDocument::noteEditAdmissible`
predicate and the public unchanged-revision rejection behavior (both
producers are void; a refused edit pushes nothing). Fork-main gaps this task
closes: `applyRangeEdit` validates only tick domains before mutation —
combined-destination note collisions (including same-destination
`TrackNotes` groups, identical paste twins, and batches onto freshly
expanded tracks) are never checked, and the note check sits inside
`if (!m_smf.tracks.empty())`, bypassing empty-document expansion entirely;
`moveRange` plans `written` spans as shifted-start plus original duration
while the emission re-inserts each event at its independently clamped tick,
so the planned span can differ from the emitted one.

## 2. Exact write set

- `src/core/songdocument_range.cpp`
- `src/checks/editcheck/tst_songdocument_songranges.cpp`

## 3. Prerequisites

Task 2: `noteEditAdmissible` exists with the exempt-by-NoteId semantics, and
identical spans refuse. Task 1's oracle is used in this task's assertions.

## 4. Interface contract

`applyRangeEdit` and `moveRange` signatures and all non-note semantics
(track expansion, lane XCMD rewriting, tempo payloads, removal ordering,
`pushEdit` shapes) are unchanged. What changes:

- `applyRangeEdit` collects the complete eligible written-note set before
  any mutation: every `RangeEdit::TrackNotes` note whose `engineTrack` lands
  inside the post-expansion map (mirroring the emission loop's eligibility
  exactly, so skipped invalid destinations stay out of admission), all
  groups combined — and calls `noteEditAdmissible(written,
  edit.removeNotes)`. Refusal returns before track creation, removal
  planning, lane writes, tempo merging and history: no `InsertTrack`, no
  `pushEdit`, revision and bytes unchanged. The call sits outside the
  `if (!m_smf.tracks.empty())` guard so an empty original SMF with a
  track-expanding batch is validated too (there the stationary set is empty
  but batch-vs-batch disjointness still applies).
- `moveRange` plans exactly the endpoints it will emit: for each terminated
  note the written span is `[shiftTickClamped(tick, dTick),
  shiftTickClamped(endEventTick, dTick))` using the note's own end-event
  tick, not shifted-start plus original duration. A span collapsed to zero
  length (original duration positive) refuses the whole mixed move.
  Admission runs against the stationary set with the moved notes as
  `editNotes` before any `appendXcmdPatchOps`/removal/insert assembly;
  refusal returns with notes, lane points and tempo untouched. Unterminated
  moved note-ons keep their raw re-insertion behavior and contribute no
  span, as at fork-main.

## 5. Implementation steps

1. Add the failing rows first (see matrix), capturing bytes, revision, undo
   index, `engineTrackCount` and the gathered note/lane/tempo state before
   each refusal.
2. In `applyRangeEdit`, hoist the combined-destination validation above the
   track-expansion block per the contract; keep the existing tick-domain
   admission loop where it is.
3. In `moveRange`, replace the `written` construction with exact clamped
   endpoints, add the zero-length refusal and the admission gate before
   op assembly.
4. Complete the matrix and run the named checks.

## 6. Acceptance predicate

Through the unchanged void producers: two same-destination overlapping
`TrackNotes` groups (and identical-twin paste notes) refuse atomically — no
new tracks, removals, lane writes, tempo change, history entry or revision
change — while disjoint multi-track pastes with track expansion still
accept and round-trip through undo; a `moveRange` whose clamped left-shift
collapses a span or collides with a stationary same-pitch note refuses with
its mixed payload untouched, and an accepted clamped move leaves
`songdocument_test::notePairsConsistent` true with note geometry matching
the actually emitted endpoints.

Matrix (existing corpus slots, extended bodies — no new or renamed slots):

| Slot | Added required cases |
| --- | --- |
| `rangeEdit` / songranges | Overlapping same-destination groups refuse (bytes, revision, `engineTrackCount`, undo count unchanged); identical-twin paste notes refuse; accepted paste onto a freshly expanded track still lands and undoes byte-exactly. |
| `rangeMove` / songranges | Tick-zero clamped move that collapses or collides refuses with notes+lane+tempo untouched; accepted clamped move's spans equal the emitted clamped endpoints (assert via `findNote` geometry and the oracle). |

NAMED CHECKS (controller under SHARED_TREE; implementer on its settled
tree):

```sh
deno task verify --filter editcheck --qt rangeEdit rangeMove
deno task verify --filter editcheck --verbose
```

The empty-original-SMF hoist is structural (no corpus fixture stages an
empty SMF): it is verified by review of the gate's placement plus the
batch-vs-batch rows above, which exercise the same predicate on the
expansion path.

## 7. Task-specific constraints

- Do not edit `tst_songdocument.h` (Task 2 owns it): coverage goes into the
  two existing corpus slots' bodies only.
- No stationary trimming of any kind remains in either producer; refusal is
  the only collision outcome. `insertBlankTime`/`duplicateTimeRange` (other
  file) are non-goals and stay untouched.
- Keep raw payloads, XCMD epoch handling and tempo semantics byte-exact;
  admission is purely additive geometry checking.
