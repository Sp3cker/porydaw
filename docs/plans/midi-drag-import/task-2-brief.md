# Task 2 — Atomic Document Append

## Context

Appending selected MIDI tracks must use the current document's history, remap, identity, revision, and publication machinery. Task 5 consumes this interface; it must not reproduce mutation policy in the workspace. Read [plan.md](plan.md) Global Constraints and [spec.md](spec.md) Atomic Append.

## Exact write set

- `src/core/songdocument.h`
- `src/core/songdocument.cpp`
- `src/checks/editcheck/tst_songdocument_songtracks.cpp`

## Prerequisites

Task 1's `selectedMidiForAppend` interface.

## Interface contract

- Add `int SongDocument::availableImportTrackSlots() const`.
- Add `int SongDocument::appendImportedTracks(const SmfFile &source, const std::vector<int> &selectedTracks, QString *error)`.
- Available slots equal `track_limits::kHardwareCapacity - engineTrackCount()` and never use player budget.
- Success appends all selected tracks as one history command and returns the first imported engine-track index.
- Failure returns `-1`, supplies an actionable `error` when non-null, and produces no mutation, history entry, revision, remap, or publication.

## Implementation steps

1. Compute hardware slots from the existing engine-track count and canonical limit.
2. Validate selection/capacity, project through `selectedMidiForAppend`, run `removeRedundantSetterEvents`, checked-rescale a copy to the destination division, and validate all tracks before mutation.
3. Build one `SongEditCommand` from existing `EditOp::InsertTrack` operations; apply it through the canonical command path so note IDs, `TrackRemap`, revision, publication, Undo, and Redo remain centralized.
4. Return the mapped first imported engine track only after the command succeeds; preserve exact no-op behavior on every validation/conversion failure.
5. Extend `EditCheckTest::trackCreateDelete` with multi-track append, one-step Undo/Redo, order/remap, stable note-identity, hardware-capacity rejection, rescale failure, and no-publication/no-history failure assertions.

## Acceptance predicate

`deno task verify --filter editcheck --verbose` passes. `trackCreateDelete` proves atomic multi-track append, one-command Undo/Redo, correct remapping/order, stable note identities, capacity enforcement, checked timing conversion, and no observable change on failure.

## Task-specific constraints

- Do not add a new mutation path or manually publish/revise around the command machinery.
- Do not mutate `source`; preprocessing operates on projected copies.
- Do not reject documents merely because they exceed the current player budget.
