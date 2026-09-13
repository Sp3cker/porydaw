## 1. Context

Tasks 22/23 supply the existing guarded form entries. This task produces the concrete action/semantic commands consumed by final Edit projection in Task 25 and ruler/note rows in Tasks 27/28.

## 2. Exact write set

- `src/ui/songview.h`
- `src/ui/songview/editkeyrouting.cpp`
- `src/ui/songview/editactions.cpp`

## 3. Prerequisites

- [Task 22](task-22-brief.md).
- [Task 23](task-23-brief.md).
- [Task 15](task-15-brief.md).

## 4. Interface contract

Extend EditCommand and EditActions with SetVelocity, SetLoopStart, SetLoopEnd, LoopFromSelection, RemoveLoop, EditTimeSignature and RemoveTimeSignature, using the fixed edit.* IDs in spec.md. All are real unbound actions with shared semantic availability and no menu-owned target.

## 5. Implementation steps

1. Route SetVelocity to openSelectedVelocityPrompt and EditTimeSignature to editTimeSignatureAtCursor through SongView’s owned roll/ruler. Use static canonical labels.
2. Implement loop actions using current edit cursor/authoritative active interval and existing setLoopTick calls. LoopFromSelection needs a nonempty interval, not note/lane edit-scope resolution; preserve its existing lane/tempo-independent loop semantics. Keep two separate undo commands for loop-from-selection and removal; do not macro-merge them.
3. Remove a signature only when an explicit event exists at the current edit cursor. Refresh marker/signature availability from document/cursor changes and keep common readiness/gesture protection. Do not impose Insert Time's scope-resolution requirements on document-global loop markers.

## 6. Acceptance predicate

The new real actions use live cursor/selection state, preserve exact signature identity and existing form transactions, and retain incremental two-command loop undo. Named checks: `deno task verify --filter rollcheck --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. No positional parameter stored in QAction::data, no captured clicked tick, and no new default bindings.
