# dod-landable — independent DOD wins, no canonical-storage change

Land the bounded wins from the two DOD audits (Muse + Astra, 2026-11-14)
that do NOT require replacing `MidiFile` canonical storage. Every task is
behavior-preserving; observable bytes, ordering, FIFO semantics, and paint
output must not change.

## Tasks

| # | Task | Route |
|---|---|---|
| 1 | Bulk-merge `MidiChunk.apply` insertion phase | SDD (ordering semantics, history offsets) |
| 2 | Occupied-bitset held storage in `LiveInsert` | SDD (callback path, FIFO semantics) |
| 3 | Hoist shared per-track work + single prefix-count pass in `Sequencer.prepareLive` | SDD (callback path, ordinal semantics) |
| 4 | Share `VelocityGestureState.noteIndices` into `VelocityInteractionSnapshot` | SDD (one behavior change, 3 files) |
| 5 | Block-max-end index for roll note culling | SDD (producer/consumer across 3 files) |
| 6 | Visible-range rectangles in EffectOutput | SDD (camera/selection semantics, 1 file) |

All seats `sdd-implementer`. All tasks SHARED_TREE in one worktree with
disjoint write sets; they may fan out. No task consumes another's interface.

## Global Constraints

- Worktree root: `/Users/spencer/dev/cProjects/porydaw/.worktrees/dod-landable`
  (branch `feature/dod-landable`, BASE `e161303d538e624542740e04bd7948703fb32510`).
  Every read/grep/edit uses literal absolute paths under that root. Never
  relative `src/...` paths (they resolve to the main checkout).
- Behavior-preserving only. No public API changes except where a brief names
  one. No check edits, no proof-ledger edits, no CMake edits.
- SHARED_TREE: do not run builds, checks, formatters, or `uv` commands.
  Report `tests: DEFERRED_TO_CONTROLLER`. Read-only file-local inspection
  (diagnostics via LSP where available, re-reads) is yours to do and report.
- Controller verification (after the whole batch settles):
  - `uv run --no-sync dev build:checks`
  - `uv run --no-sync dev checks --filter swiftcore` (T1, T2 via LiveInsertChecks/PlaybackChecks, T3)
  - `uv run --no-sync dev checks:qml` (T4, T6)
  - `uv run --no-sync dev checks:qml-roll` (T5)
  - `uv run --no-sync dev format --check`
  Implementers reuse these; do not rediscover commands. If scope changes make
  a command stale, say so in the result instead of narrowing silently.
- Swift 6 conventions per repo AGENTS.md: comments at most 2 lines, explicit
  closure types, no hardcoded pixel constants (n/a here), per-frame/callback
  code allocation-free in steady state.
- Commit policy: one milestone checkpoint after final whole-branch review;
  no per-task commits. Implementers commit nothing.

## Milestones

1. Batch settles + controller checks pass → per-task review.
2. Final whole-branch review → single checkpoint commit + push.
