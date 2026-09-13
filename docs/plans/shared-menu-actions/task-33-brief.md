## 1. Context

Task 32 supplies the final observed behavior. These existing user-facing documents must not continue promising remapping or playhead-anchored insertion.

## 2. Exact write set

- `docsrc/manual/shortcuts.md`
- `docsrc/manual/piano-roll.md`
- `CHANGELOG.md`

## 3. Prerequisites

- [Task 32](task-32-brief.md).

## 4. Interface contract

Document the final fixed platform bindings/scopes and removal of Keyboard settings; explain ruler inside/outside/chip selection/cursor behavior, no note-grid seek, no-selection Insert Time at edit cursor while playing, and context-menu dismissal. Update the current unreleased changelog without duplicating entries.

## 5. Implementation steps

1. Replace remapping TODO/guidance with the real fixed command inventory and relevant Window/Editor local-input policy; no replacement browser or deferred modifier-hint promise.
2. Correct piano-roll Insert Time/playhead wording and explain the ruler-versus-note-grid distinction, selection-first insertion and menu dismissal. Update current changelog entries to agree with the implemented behavior.

## 6. Acceptance predicate

The three existing documents describe the verified behavior without remapping, stale-menu or playhead-anchor claims, and the complete suite remains green. Named checks: `deno task verify --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not modify AGENTS.md, the user’s reference files or unrelated manual sections; do not introduce a new documentation subsystem.
