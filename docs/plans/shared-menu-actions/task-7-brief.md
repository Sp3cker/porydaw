## 1. Context

All remapping UI, mutable check scaffolding and override consumers are now gone. The catalogue becomes the fixed source for key matching and QAction setup.

## 2. Exact write set

- `src/ui/keymap.h`
- `src/ui/keymap.cpp`
- `src/checks/keyboard/keymapregistry.cpp`

## 3. Prerequisites

- [Task 1](task-1-brief.md).
- [Task 2](task-2-brief.md).
- [Task 3](task-3-brief.md).
- [Task 6](task-6-brief.md).

## 4. Interface contract

Retain stable command IDs and the useful Registry read/match/attach APIs; remove OverrideSnapshot, override/reset/setter/conflict APIs, settings-key serialization, reapplication storage and bindingsChanged. Preserve isModifierKey for note feedback. Cache StandardKey alternatives, literal sequences and held modifiers once; matching must not construct QSettings, parse strings or allocate binding lists per probe. Add Scope::Window and Scope::EditorRouted according to the spec inventory; Context/category remain descriptive. Add the four View IDs and all new unbound edit IDs, with no new default keys.

## 5. Implementation steps

1. Replace settings-backed effective bindings with immutable cached shipped key sequences and fixed modifier chords; preserve exact-modifier matching, keypad normalization and Qt platform alternatives.
2. Remove dead mutation/conflict/persistence/reapply members and declarations after reference closure, retaining translation/read APIs still consumed by application code.
3. Encode the explicit scope/context inventory and new View IDs without changing existing defaults or adding default shortcuts for newly exposed operations.
4. Seed isolated legacy keymap entries before the surviving matching cases run, so their real key/modifier expectations prove legacy overrides are ignored; do not add field-copy or source-text assertions.

## 6. Acceptance predicate

Legacy keymap settings cannot rebind or unbind shipped commands/modifier gestures, matching preserves exact and keypad-normalized semantics, and the surviving production consumers compile against the read-only API. Verify with `deno task verify --filter keymapcheck --filter settings-dialog --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Leave unrelated QSettings intact. Do not add a settings migration, remapping import/export, a manual-table generator, runtime invalidation cache, or generic predicate registry. Exact action-routing APIs are governed by the final shared contracts, not left to this implementer to invent.
