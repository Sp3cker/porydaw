# Task 1 — `sgc_` intent pipe + executor + `swiftcommands` harness

## Context

The write direction of the document seam: intents up, undoable execution
C++-side. Producer of the pipe Tasks 4–5 submit through. Vocabulary and
routing are FIXED in [spec.md §1–2](spec.md) — implement, do not redesign.

## Exact write set

- `src/ui/songview/quick/swiftgrid/command_feed.{h,cpp}` (new) — C ABI:
  `SgcIntent` enum, `SgcResult` enum, payload structs, single
  `sgc_submit(const SgcIntentCommand *, SgcOutcome *)` entry + Swift-side
  registration of the submission sink (the `sgw_` function-pointer
  pattern; Swift calls C++, never the reverse).
- `src/ui/songview/quick/swiftgrid/intent_executor.{h,cpp}` (new) —
  QObject-free executor: document intents → `SongDocument` command path
  (one undo entry each, batch = one entry); session intents →
  `SongView` setters; validation before any mutation.
- `src/ui/songview/quick/swift-grid-prototype/SgcCommands.swift` (new) —
  Swift mirror enums/structs, `Sendable`, submission API.
- Harness `src/checks/swiftcommands/` (new) + three registration points.

## Prerequisites

Wave 3 final gate green.

## Interface contract

- ABI layout mirrors `document_feed.h` conventions (fixed-width ints,
  arrays by pointer+count, no Qt types). String payloads: UTF-8
  pointer+length, copied immediately, not retained.
- Validation (C++-side, single place): token liveness against the
  document, field ranges, track bounds. Malformed ⇒ `rejectedInvalid`,
  zero side effects.
- `SGC_NOTE_ADD` outcome carries the assigned `NoteId` token back so
  Swift can select/track the new note.
- Session intents must not touch `QUndoStack` — the harness proves it by
  stack depth invariance.

## Implementation steps

1. Write `command_feed.h` per spec §1–2 exactly.
2. Executor: route enum → existing production APIs. Track ops go through
   the same production paths `TrackHeaderModel` uses today; note ops
   through the `SongDocument` command path the C++ roll uses.
3. Swift mirror + submission call; no C++→Swift linkage.
4. Harness `swiftcommands`: build a fixture `SongDocument`; exercise the
   full validation matrix per intent (valid, stale token, out-of-range,
   bad track); undo granularity (move gesture = 1 entry; delete batch =
   1 entry); session routing (mute/solo leave stack depth unchanged);
   round-trip (add → `sgd_` revision push observed by a registered
   capture).

## Acceptance predicate

- `deno task verify --filter swiftcommands --verbose` green.
- `deno task build:app` + canaries (`selectionkey-core`, `rollcheck-static`) green.

## Task-specific constraints

- No edits to `SongDocument`, `SongView`, or `trackvoiceops.cpp` — the
  executor calls existing public APIs. Missing accessor ⇒ escalate.
- Intent vocabulary additions are forbidden (spec amendment required).
