# Peel 01 — Document contracts (NoteId, revision, batch APIs) + hidden document-layer fixes

Read `docs/peels/GROUND-RULES.md` first. Source: branch commit `b22b1e4`
("refactor(document): add stable note and mutation contracts"), files
`src/core/songdocument.{h,cpp}` (+703 lines), new `src/core/noteid.h`, plumbing in
`src/core/smf.h`, `src/core/miditimeline.h`, `src/ui/songviewmodel.h`; tests in the
branch's `src/editcheck.cpp` (+923) and new `src/noteidcheck.cpp` (139).

This peel is **infrastructure + four real behavior fixes**. It is the prerequisite
for Peel 02 (event list) and Peel 03 (velocity lane); do it first, faithfully, and
resist scope creep into UI.

## Part A — user-facing document-layer fixes (each gets its own test)

These were silently bundled into the "refactor" commit; they are correct and wanted:

1. **No-op edits stop polluting the undo stack.**
   - `moveNotes`: pre-check whether any note's clamped tick/key actually changes;
     return early without pushing a command.
   - `setNotesVelocity`: skip notes already at the target value.
   - `nudgeNotesVelocity`: skip notes whose clamped result equals the current value.
2. **Inverse merged moves remove their command.** `MoveNotesCommand::mergeWith`
   calls `setObsolete(true)` when the accumulated delta returns every note to its
   origin — dragging/nudging a note away and back leaves no undo entry. Note the
   branch's subtlety: the obsolete path must still publish the mutation so views
   refresh (branch defers first-redo publication and re-publishes after push).
3. **`duplicateTrack` foreign-channel bugfix.** When a chunk hosts more than one
   channel, duplicate must copy only events whose `channel()` matches the source
   engine track's channel (`if (ev.channel() != sourceChannel) continue;`). Main
   currently copies every channel event in the chunk — a real data bug.
4. **Move/resize clone the original events.** `moveNotes` / `resizeNotes` /
   `resizeNotesLeft` copy the existing note-on/off `SmfEvent` and adjust tick/fields
   instead of synthesizing fresh events via `makeChannelEvent` — preserving every
   other byte on the event (and, once added, the NoteId).

## Part B — contracts (infrastructure for later peels)

Port these APIs from the branch (`git show <branch>:src/core/songdocument.h` and
`noteid.h`); keep main's existing APIs working alongside:

- `src/core/noteid.h`: opaque `NoteId` token + `NoteVelocity{noteId, velocity}`.
  Minted per note-on at SMF parse/mutation time (`mintNoteId`), never serialized.
  Threaded through `SmfEvent`, `TimelineEvent` (`miditimeline.h:24` on branch),
  `ViewNote` (`songviewmodel.h:17`), `DocNote::noteId`.
- `uint64_t SongDocument::revision()` + a `publishMutation()` chokepoint that bumps
  it before emitting `documentChanged`.
- `TrackRemap{smfTrackMap, engineTrackMap, newSmfTrackCount, newEngineTrackCount}`
  + signal `tracksRemapped(TrackRemap)`, emitted for any non-identity remap
  (add/delete/move). Keep the existing `trackMoved` signal as transitional.
- `setNotesVelocities(expectedRevision, std::vector<NoteVelocity>)` — batch velocity
  write that refuses (no-ops) when the revision doesn't match. One undo entry.
- `moveLanePoints(std::vector<LanePointMove>)` — batch lane-point move, one undo
  entry. Keep single-point `moveLanePoint`.
- `findNote(NoteId, DocNote*)`; `notesForTrack()` results carry `noteId`.
- `mergeableWith` keyed by `noteId` (per-note find) instead of sorted-tuple compare.

## Cautions

- Same-tick event semantics are load-bearing (mid2agb same-tick ordering, the
  same-tick dedup rules) — cloning events (A4) must not reorder same-tick events.
- The undo-merge changes (A1/A2) intersect main's "consecutive keyboard presses
  merge into one command" behavior, which rollcheck asserts with exact undo-index
  arithmetic — expect to update rollcheck counts deliberately, never loosen them.
- Do NOT port the branch's `EditorViewState`/drawer types here; they belong to
  Peels 03/08.

## Tests

- Adapt the branch's `editcheck.cpp` additions and `noteidcheck.cpp` harness (test
  code ports far more directly than UI code; the branch registered `--noteidcheck`
  in `src/main.cpp` and CMake). Cover: identity survives move/resize/velocity/undo;
  revision bumps exactly once per mutation; `setNotesVelocities` stale-revision
  refusal; batch APIs are single undo entries; each Part A fix (e.g. no-op move
  pushes nothing; away-and-back merge leaves no entry; duplicateTrack on a
  multi-channel chunk copies only its channel).
- Negative-test per probe; full ASAN sweep + ctest (savecheck/roundtrip/smfcheck
  guard byte-fidelity — they must stay green untouched).
