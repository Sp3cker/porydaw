## 1. Context

Task 24 needs a semantic entry that opens the existing signature form from current edit-cursor state. The old menu still has clicked-target handling until Task 28.

## 2. Exact write set

- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/checks/rollcheck/time_signature_prompt.cpp`

## 3. Prerequisites

- [Task 18](task-18-brief.md).

## 4. Interface contract

Add TimeRuler::editTimeSignatureAtCursor(), seeding the existing openTimeSigPrompt with the current edit cursor and signature in effect there. Keep exact explicit event ticks and PendingTimeSigPrompt acceptance guards; retain chip double-click behavior.

## 5. Implementation steps

1. Implement the cursor-based entry by reusing sigAtTick/openTimeSigPrompt, not creating another form or prompt target type.
2. Exercise the entry in the existing form suite at an exact event and a cursor without an explicit signature; accepting edits/inserts at that cursor, not an adjacent snap point.

## 6. Acceptance predicate

The cursor-based signature entry opens the existing guarded form and accepts at the intended exact cursor/event tick with existing undo/cancel behavior. Named checks: `deno task verify --filter rollcheck --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not change pointer classification here or remove the form’s revision/target guard.
