# Task 4 — Physical timeline host transport

## Context

This task owns TimelineInputHost and its production implementation together. Task 7 migrates the two test-host consumers. Follow [spec.md](spec.md) and [Global constraints](plan.md#global-constraints).

## Exact write set

- `src/ui/songview/quick/timelineinput.h`
- `src/ui/songview/quick/timelineinputitem.h`
- `src/ui/songview/quick/timelineinputitem.cpp`

## Prerequisites

Task 1 enum and task 2 claim/native-predicate contracts. Task 7's test recorders consume this task's declared virtual signatures. Accept the concrete-host migration only as one atomic integration.

## Interface contract

Both TimelineInputHost virtuals and TimelineInputItem overrides take ui::hint_profiles::Id by value. setMouseHint remains a guarded claim; refreshMouseHint remains current-owner-only; resyncMouseHint remains existing recovery-event reacquisition. The dispatch fallback claims Empty. Preserve physical source identity and all scope/lifetime guards.

## Implementation steps

1. Change the virtual and override parameter types together; call the renamed MouseHints::claim with the ID in normal/current-owner refresh paths. Rename resync's allowsSource call to allowsNativeInput, preserving its independent Quick mute/membership checks.
2. Replace QString() fallback payloads with Empty without changing m_hintDispatchClaimed or causing intermediate blank publications.
3. Preserve muting, source-checked clear, hover/grab membership, focus handling, effective visibility/window detach, stationary recovery, and input forwarding unchanged. Remove only formatting-related includes/comments made obsolete by the type swap.

## Acceptance predicate

All three concrete hosts compile under one typed interface, and actual plot/gutter transitions and stationary refresh preserve source ownership without new retained state. **Named checks, controller after atomic integration:** `deno task verify --filter automation --verbose`, `deno task verify --filter mainwindow-routing --verbose`.

## Task-specific constraints

Do not add a retained-profile member to this host, combine refresh with reacquisition, move target classification here, or change mouse/key acceptance. Test-adapter files belong to task 7.
