# Task 2 — Strip Custom from ThemeController, migrate stored settings

## Context

The controller owns the `Custom` enum member, `ColorPair`, the `customColors` field, and the custom persistence branch. Removing them settles the `ThemeSelection` shape to the contract in [spec.md](spec.md) and makes the stored-settings path preset-only. Consumer: task 3 — its resolver/color-math deletions require zero remaining controller calls into `isValidColorPair`/`derive`.

## Exact write set

- `src/ui/theme/themecontroller.h`, `src/ui/theme/themecontroller.cpp`
- `src/checks/themelayout/tst_themelayout_settings.cpp`

## Prerequisites

- Task 1 (interface): dialog already free of custom members; `vanillaModeButton` objectName exists; `draftSelection()` still returns `std::optional` — this task collapses it.

## Interface contract

- `enum class ThemeMode` = exactly `Vanilla, DarkNeutralHigh, Immaterial`; `ThemeSelection` = `{ ThemeMode mode, int gridLineContrast }`; `ColorPair` and `customColors` no longer exist.
- `isValid()` keeps the grid-line-contrast range guard and gates `preview()`/`commit()`; it no longer mentions colors or Custom.
- `writeStoredSelection()` writes only `theme/mode` and `theme/grid-line-contrast`; no code path can produce `theme/primary` or `theme/accent`.
- `readStoredSelection()` on legacy `"custom"` (or any unknown mode): Vanilla + stored contrast, and the `theme/primary`/`theme/accent` keys removed once (plan.md Constraint 3).
- `draftSelection()` returns plain `ThemeSelection` (optional collapsed).

## Implementation steps

1. `themecontroller.h`: remove `Custom` from `ThemeMode`, delete `struct ColorPair`, remove `customColors` from `ThemeSelection`. Update the class comment ("Dialogs send the active mode and any valid Custom colors here" → mode + grid-line contrast only).
2. `themecontroller.cpp`:
   - `isValid()` (named `isValid`, `themecontroller.cpp:20-27`): delete ONLY the customColors clause (`:22-24`) and the `|| selection.mode != ThemeMode::Custom` tail (`:26`). KEEP the contrast range check (`:25`) — `withGridLineContrast` Q_ASSERTs `0 <= contrast <= 100` (`themeresolver.cpp:604`) and `isValid` gates `preview()` (`:52`) and `commit()` (`:63`).
   - `commit()`: delete the custom-colors retain block (`:58-62`); the `isValid` call simplifies; the `writeStoredSelection`/`apply`/`m_selection` flow stays (`:65-68`).
   - `resolve()`: delete the `case ThemeMode::Custom:` arm (`:90-93`) and the trailing `Q_UNREACHABLE()` (`:95`) — the switch becomes exhaustive over three members.
   - `writeStoredSelection()`: write only `theme/mode` and `theme/grid-line-contrast`; remove the `canonicalColor` helper entirely.
   - `readStoredSelection()` (const member; `m_settings` is `QSettings&` so key removal compiles): delete the `"custom"` branch (`:124-126`); unknown mode strings fall through to the Vanilla default with the stored contrast; when the stored mode was legacy `"custom"`, remove the `theme/primary`/`theme/accent` keys once.
3. `tst_themelayout_settings.cpp` rework:
   - `DialogControls`/`dialogControls`/`controlsPresent`: remove the `custom` radio field and lookup (`:21`, `:33`), the `primary`/`accent` line-edit fields and lookups (`:24-25`, `:36-37`), update `controlsPresent` (`:43-47`); add a `vanilla` lookup for `vanillaModeButton`.
   - `themePersistence_data` (`:95-105`): replace the `custom` row with a `vanilla` row (`static_cast<int>(themes::ThemeMode::Vanilla) << "vanilla"`); keep `dark-neutral-high` and `immaterial`. No invalid-mode row — legacy-value handling is `settingsRepair`'s job.
   - `themePersistence` (`:107-136`): delete `customSelection()` (`:49-54`) and the `themeMode == Custom` branches (`:118-120`, `:130-135`); the loop body becomes the plain preset round-trip.
   - `dialogCommitAndRevert` (`:138-180`): click `controls.darkNeutralHigh` instead of the custom flow (`:151-156` becomes a preset commit); delete the hex-edit setText lines and every `committed.customColors` assertion (`:159-163`); keep the preset preview clicks (`:165-171`) and the close/revert tail, rewriting `:174-179` to assert against the committed preset (e.g. `themes::withGridLineContrast(themes::darkNeutralHigh(), 80)`), NOT `themes::derive(...)`.
   - `settingsRepair` (`:75-93`) is the legacy-migration test and already covers custom→Vanilla + key removal — extend it: seed a VALID non-default `theme/grid-line-contrast` (e.g. 80) and assert the restored selection honors 80 instead of always asserting `defaultGridLineContrast` (`:91-92`).
4. Collapse task 1's `draftSelection()` from `std::optional` to a plain `ThemeSelection` and confirm the dialog still builds.

## Acceptance predicate

- `grep -i "ThemeMode::Custom|ColorPair|customColors" path="src/ui/theme"` returns nothing.
- `tst_themelayout_settings` exercises: vanilla/dark-neutral-high/immaterial round-trip; legacy custom → Vanilla with contrast 80 honored and legacy keys removed.
- `grep pattern="theme/primary|theme/accent" path="src/ui/theme"` matches only the `readStoredSelection` cleanup code — no write path.

## Task-specific constraints

- Non-goals: dialog internals (task 1 done), resolver's `isValidColorPair`/`derive` definitions (task 3 deletes them — this task only removes controller *calls* so the build stays green).
