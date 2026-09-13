## 1. Context

Task 24 needs a narrow semantic entry for the existing velocity form; it must not reach private note-menu snapshots. The existing form suite supplies direct consumer proof before that action projection lands.

## 2. Exact write set

- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/checks/rollcheck/velocity_prompt.cpp`

## 3. Prerequisites

- [Task 11](task-11-brief.md).

## 4. Interface contract

Add PianoRoll::openSelectedVelocityPrompt(), resolving current selected notes and invoking the existing openVelocityPrompt machinery. Exercise this real semantic entry in the existing form suite; Task 24 is its production action consumer.

## 5. Implementation steps

1. Extract only the selected-note resolution/form-open entry. Keep PendingVelocityPrompt, initial value, bounds, target re-resolution and one-undo acceptance.
2. Exercise the new selected-note entry in the existing rendered form suite, preserving cancel and invalid/stale form acceptance behavior. The old menu path keeps its guarded form open until the combined note-menu cutover.

## 6. Acceptance predicate

Opening and accepting note velocity through the existing rendered menu still edits the intended notes once, with bounded values and preserved draft guards. Named checks: `deno task verify --filter rollcheck --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not expose raw selected-note vectors to the action set or retain a menu target solely for the form.
