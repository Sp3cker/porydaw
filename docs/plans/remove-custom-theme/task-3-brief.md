# Task 3 — Delete derive(), picker-only color math, custom check coverage

## Context

With tasks 1–2 landed, `derive()`, its helper set, `isValidColorPair`, and `shiftOklabLightness` have no callers outside the resolver, the color-math file, and `tst_themelayout_color.cpp`. Deleting them settles `themeresolver.h` to the preset-only public surface in [spec.md](spec.md). Consumer: task 4 (Direct) verifies the full-tree sweep is clean.

## Exact write set

- `src/ui/theme/themeresolver.h`, `src/ui/theme/themeresolver.cpp`
- `src/ui/theme/color_math.h`, `src/ui/theme/color_math.cpp`
- `src/checks/themelayout/tst_themelayout_color.cpp`, `src/checks/themelayout/tst_themelayout.h`
- Verify-only (no edits expected): `src/checks/themelayout/tst_themelayout_chrome.cpp`, `src/checks/themelayout/tst_themelayout_settings.cpp`

## Prerequisites

- Task 1 (interface): dialog and scale test carry no `derive`/picker references.
- Task 2 (interface): controller calls neither `isValidColorPair` nor `derive`.

## Interface contract

- `themeresolver.h` declares no `isValidColorPair` and no `derive`; its public surface is `vanilla()`, `darkNeutralHigh()`, `immaterial()`, `withGridLineContrast(Theme, int)`.
- `color_math.h` no longer declares `shiftOklabLightness`; `colorFromOklch`, `oklchFromColor`, and the `sampleSrgb` Oklch overload still compile and still serve `trackactivityrender.cpp`.
- `tst_themelayout.h` declares `trackIdentityContrast()` (renamed from `colorPairValidity()`); the test keeps only the track-identity contrast coverage.

## Implementation steps

1. `themeresolver.h`: delete the `isValidColorPair` and `derive` declarations; rewrite the boundary comment — the file now maps fixed preset tables to the runtime role table only.
2. `themeresolver.cpp`: delete `derive()` (navigation: `:337-600`) and every helper only it uses. Confirm each with `lsp references` before deletion; expected derive-only set: `lightenToContrast`, `selectedTextColor`, `touchableBackground`, `colorAtLightness`, `activeColor`, `stateTextColor`, `blackOrWhiteByWorstContrast`, `domainInk`, `severityText`, `keepChromeReadable`, `keepSurfaceReadable`, `touchableRamp`, `adjustContrast`, `deriveDisabledText`, the touchable-lightness policy constants, and `oklabLightness` (its only consumers are `colorAtLightness`, `touchableRamp`, and `derive`). Keep: `resolvePreset`, `resolveDarkPreset`, `colorFromHex`, `mixColors` (used by `withGridLineContrast`), `withGridLineContrast`, `vanilla()`, `darkNeutralHigh()`, `immaterial()`.
3. `color_math` — verified with `lsp references` 2026-09-11: delete ONLY `shiftOklabLightness` (every consumer is inside `derive()`). KEEP `colorFromOklch` (`trackactivityrender.cpp:13` consumes it), the `sampleSrgb` Oklch overload (internal to `colorFromOklch`), and the `Oklch` struct (`oklchFromColor` → `trackactivityrender`). Do not touch any other color-math function.
4. `tst_themelayout_color.cpp`:
   - `colorPairValidity` (`:100-119`) → rename to `trackIdentityContrast`; keep ONLY the track-identity tail (`:109-118`); delete the `isValidColorPair` assertions (`:102-108`). Keep `#include "ui/theme/trackidentitycolors.h"` (`:7`); update the slot declaration in `tst_themelayout.h:23`.
   - Derived rows exist in THREE data functions — remove `derived-dark`/`derived-light` from `themeCompleteness_data` (`:150-152`), `gridContrast_data` (`:190-192`), AND `laneAndWaveformLegibility_data` (`:243-245`); delete both `startsWith("derived")` branches (`:165-169`, `:221-222`).
   - `themeForName` (`:22-33`): delete the `derived-dark` arm (`:30-31`); its tail (`:32`) is an unconditional `themes::derive(...)` call — replace it with `return themes::vanilla();` so the function has a defined fallback.
   - Keep `colorMath` as-is (tests surviving functions) and its local `oklabReference`/`srgbToLinearReference` reference helpers.
5. `tst_themelayout_chrome.cpp`: VERIFICATION ONLY — task 1 already fixed the custom radio and `themeDialogGeometry` (there is no `customTheme()` helper in chrome; its anonymous namespace is `StyleChangeCounter`/`ThemeRefreshProbe`/`PoisonSwatch`/`matchesDarkBaselinePoison`/`poisonPixelCount`/`containsColor`, `:41-126`). Confirm the chrome grep below is empty.
6. `tst_themelayout_settings.cpp`: VERIFICATION ONLY — task 2 already removed the `themes::derive(...)` call (`:174-179`). Confirm zero `derive` references remain.
7. `tst_themelayout.h`: rename the `colorPairValidity()` slot (`:23`) to `trackIdentityContrast()` per step 4.

## Acceptance predicate

- `grep pattern="isValidColorPair|derive\(|shiftOklabLightness|oklabLightness" path="src/ui/theme; src/checks/themelayout"` → no hits.
- `colorFromOklch` and `sampleSrgb` still resolve in `trackactivityrender.cpp`.
- `grep pattern="customModeButton|derive\(" path="src/checks/themelayout/tst_themelayout_chrome.cpp"` and `grep pattern="derived-|customTheme|customModeButton" path="src/checks/themelayout"` → empty.
- Preset completeness, grid-contrast, chrome, font, dark-base suites compile with unchanged preset rows.

## Task-specific constraints

- Every deletion of a resolver helper is gated on a fresh `lsp references` confirming zero remaining callers (plan.md Constraint 4) — the spec inventory is the expected result, not a substitute for the check.
- `colorMath`, `polyphony`, and dark-base coverage stay byte-for-byte in behavior.
