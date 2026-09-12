# Task 6: Nudge feedback and group drag shifts

## Context

Consume Task 1's scalar shift and Task 3's no-mutation rejection contract. A nudge must not reveal a destination the document rejected, and a group drag must not collapse point spacing by independently saturating each tick. See [UI movement behavior](spec.md#ui-movement-behavior).

## Exact write set

- `src/ui/songview/pianoroll_commands.cpp`
- `src/ui/editordrawer/nodelane/gesture.cpp`
- `src/checks/automation/domain/gestures.cpp`

## Prerequisites

1: `CoreTimeDefaults::shiftTickClamped`.
3: invalid upper note moves leave document revision/history unchanged.

## Interface contract

No public signature, gesture-state field, keyboard binding, focus policy, or QObject ownership change. `PianoRoll::nudgeSelectedNotes` reflects only accepted moves. `NodeDragGesture::applyDrag` applies a common bounded tick delta; `finish()` continues to report the actual grabbed-point displacement.

## Implementation steps

1. In `PianoRoll::nudgeSelectedNotes`, compare the existing document revision around `moveNotes` and omit destination reveal/feedback when no mutation occurred. Use the shift helper for accepted reveal-start positions. Keep computed note ends wide until a checked display-domain ceiling conversion, so the reveal range cannot wrap to zero. Preserve mergeability, the swap-hint scope, and the existing normal refresh path.
2. In `NodeDragGesture::applyDrag`, find both earliest and latest original point ticks in the existing traversal. Bound the common requested delta by lower-zero and upper headroom, then shift each original point through the helper. Preserve point value clamps, axis locking, preview ordering, and collision semantics; do not allocate a second point collection.
3. Extend `AutomationDomainTest::nodeDragAndPhantomOutcomes` with a multi-point group whose grabbed point can move farther right than its latest sibling can. Assert preserved inter-point distances, the exact last valid position, and agreement between preview/current points and `finish().dTick`. Include the existing lower-edge behavior as a preservation case. For a CC lane, resolve the resulting `NodePointMove` values through `nodelane::resolveCcMoves`, append them with `nodelane::appendResolvedCcMoves`, and apply the resulting `SongDocument::RangeEdit`; check observed document destinations. Those production functions are read-only dependencies, not additional write files.
4. Exercise ordinary left/right nudges and a rejected near-limit nudge through the actual app or existing UI driver: the rejected nudge leaves note data/history and camera reveal unchanged. Exercise an upper-limited multi-point node drag and release. Capture the resulting state as smoke evidence; do not add an unrelated permanent UI test file or change shortcuts to facilitate the probe.

## Acceptance predicate

Nudge feedback follows the actual document outcome, and node dragging preserves a group's relative timing at both domain edges with matching preview/commit results. Existing input behavior and the focused new group regression pass. Named checks:

```sh
deno task verify --filter rollcheck --filter selectionkey --filter automation-domain --filter automation-editing --verbose
```

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. The selection-endpoint helper substitutions in `automationcanvas_gesture.cpp` belong exclusively to Task 7. Do not replace per-point value clamping with a group value policy, add new state to remember a requested delta, or narrow variable-bound resize-left geometry.
