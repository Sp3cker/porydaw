# Test oracle support

## 1. Context

Implement [spec.md](spec.md) at the shared editcheck support seam. Inherit
[Global Constraints](plan.md#global-constraints). The spec's invariant — every
semantic edit leaves each (engine track, pitch) with pairwise-disjoint
half-open note spans — needs one test-only oracle that every later task's
acceptance matrix asserts through. Task 2 consumes this helper; this task
changes no production code and declares no test slots.

## 2. Exact write set

- `src/checks/editcheck/tst_songdocument_support.h`
- `src/checks/editcheck/tst_songdocument_support.cpp`

## 3. Prerequisites

None beyond the frozen spec and current repository.

## 4. Interface contract

Add exactly one export to the existing `songdocument_test` namespace:

```cpp
// True when the track's note stream satisfies the spec invariant: every
// positive-velocity note-on resolves to a positive half-open span, each
// release is claimed by exactly one projected note, no release is left
// unclaimed, and same-pitch spans are pairwise disjoint (adjacency legal).
bool notePairsConsistent(const SongDocument &document, int engineTrack);
```

Behavior, mirroring `SongDocument::notesForTrack` pairing exactly (first
same-channel/same-key release after each note-on, velocity-zero note-on
counted as a release):

- Inspect the track's raw channel events as well as the `notesForTrack`
  projection, so an extra release cannot hide behind correct-looking notes:
  every note-on with velocity > 0 must be claimed by a projected note, and
  every release must be claimed by exactly one projected note.
- Unterminated note-ons (no following release) and pre-existing shared-end
  raw material make the helper return false; it is an oracle for authored
  clean fixtures, never a production or import validator.
- No other symbol is added, removed, or reshaped. Existing helpers in the
  header are untouched.

## 5. Implementation steps

1. Declare `notePairsConsistent` in `tst_songdocument_support.h` beside the
   existing predicates (`sameNotes`, `noteEndsBeforeOnsAt`), matching their
   documentation style.
2. Implement it in `tst_songdocument_support.cpp` from `notesForTrack` plus a
   direct scan of the track's SMF chunk events (use the existing
   `document.smfTrackFor` / `document.channelFor` mapping). No fixture or
   document construction changes.

## 6. Acceptance predicate

The helper compiles and links into the editcheck harness with every existing
slot still green (pure addition; no behavior change anywhere). Its detection
power is proven by Task 2's pre-fix reproduction evidence, where it must fail
on the corrupted fork-main geometries before Task 2's admission lands.

NAMED CHECKS (controller under SHARED_TREE; implementer on its settled tree):

```sh
deno task verify --filter editcheck --verbose
```

## 7. Task-specific constraints

- The oracle asserts the projection and raw events of one engine track only;
  it never mutates the document and never asserts on imported corpus songs.
- Do not add slot declarations, fixtures, or production test access — Task 2
  owns `tst_songdocument.h` and the slot matrix.
