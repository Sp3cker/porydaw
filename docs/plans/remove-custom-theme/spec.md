# Remove custom theme — spec

Agreed behavior, shared vocabulary, and forward-facing interfaces. Evidence
tables are verified against the tree as of 2026-09-11 (`lsp references` +
scoped grep); zero callers exist outside the lists below.

## Behavior contract

- Exactly three themes: Vanilla, Dark Neutral High, Immaterial. No custom
  mode, no color picker, no hex/swatch editing, no derive().
- Dialog UX unchanged for presets: mode radio click previews immediately;
  Apply commits; Close/reject rolls back to the committed theme.
- Grid-line-contrast slider and its live preview are shared preset UI and
  survive untouched (plan.md Global Constraint 2).
- Settings: `theme/mode` values `vanilla`, `dark-neutral-high`,
  `immaterial` parse as today. Any other stored value (legacy `custom`
  included) restores Vanilla with the stored `theme/grid-line-contrast`.
  Orphaned `theme/primary` / `theme/accent` keys are removed once on
  restore and never written again.

## Post-removal interfaces

- `themes::ThemeMode` = { Vanilla, DarkNeutralHigh, Immaterial }.
- `themes::ThemeSelection` = { ThemeMode mode, int gridLineContrast } with
  `defaultGridLineContrast = 50`. No `ColorPair`, no `customColors`.
- `themeresolver.h` public surface: `vanilla()`, `darkNeutralHigh()`,
  `immaterial()`, `withGridLineContrast(Theme, int)`. Internal helpers
  `resolvePreset`, `resolveDarkPreset`, `colorFromHex`, `mixColors` (used by
  `withGridLineContrast`), and `withGridLineContrast` itself stay.
- `color_math.h` loses only `shiftOklabLightness`. Kept with runtime
  consumers: `oklchFromColor`, `colorFromOklab`, `colorFromOklch`,
  `oklabFromColor`, `relativeLuminance`, `contrastRatio`, `sampleSrgb`
  (both overloads), and the `Oklch`/`Oklab`/`SrgbSample` structs.
- `ThemeDialog` surface: three mode radios (objectNames `vanillaModeButton`,
  `darkNeutralHighModeButton`, `immaterialModeButton`),
  `m_gridLineContrastSlider` + value label, Apply, Close. No picker, hex
  edits, swatches, `eventFilter`, or preview timer.

## Removal inventory (verified 2026-09-11 via `lsp references` + scoped grep; zero callers outside this list)

| Symbol | Complete caller list outside its own definition | Verdict |
| --- | --- | --- |
| `OklchPicker` class | `themedialog.cpp:137,199,276`; `tst_themelayout_scale.cpp:129,145` (+ moc, generated) | Delete file + build entry |
| `ThemeMode::Custom` | `themecontroller.cpp:26,61,90,124`; `themedialog.cpp:66,251,268,290,356,370,429`; `tst_themelayout_settings.cpp:51,118-120,130,159`; `tst_themelayout_chrome.cpp:237,246,248,250` (`themeDialogGeometry`) | Remove enum member + all arms |
| `ColorPair` | `themecontroller.h:25`; `themecontroller.cpp:104,106`; `themedialog.cpp:249`; `tst_themelayout_settings.cpp:52` | Delete struct |
| `isValidColorPair` | `themecontroller.cpp:23,108`; `themedialog.cpp:248`; `oklchpicker.cpp:214`; `tst_themelayout_color.cpp:102-108` | Delete |
| `derive()` | `themecontroller.cpp:92`; `tst_themelayout_color.cpp:31-32` (`themeForName`); `tst_themelayout_settings.cpp:176` (`dialogCommitAndRevert` tail). NO chrome reference — `tst_themelayout_chrome.cpp:31` is `#include <cmath>` | Delete + helper set |
| `shiftOklabLightness` | only inside `derive()` (`themeresolver.cpp:348,403,417,420,476,483,560,566`) | Delete |
| `oklabLightness` | only derive helpers (`colorAtLightness`, `touchableRamp`) + `derive` (`themeresolver.cpp:115,120,152,346,420,475`) | Delete |
| `colorFromOklch` | **KEPT**: `trackactivityrender.cpp:13`; `oklchpicker.cpp:141,211` + `tst_themelayout_scale.cpp:130` die in task 1 | Stay |
| `sampleSrgb` (both overloads) | `colorFromOklch` internals (`color_math.cpp:134,157`); Oklch overload also `oklchpicker.cpp:167` (dies task 1) | Both stay |
| `oklchFromColor` | `oklchpicker.cpp:37` (dies task 1); `trackactivityrender.cpp:49` stays | Stay |
| Controller `theme/primary`, `theme/accent` settings keys | written in `writeStoredSelection` only when custom; read in `readStoredSelection` `:105-110` | Stop writing; clean up on restore |
| Dialog custom UI: hex edits, swatches, picker, `eventFilter`, preview timer | only inside `themedialog.{h,cpp}` | Delete; slider preview survives |
| `presetcolors.h` comment references to Custom policy (`:337-347`), `themeruntime.cpp:599-600` comment | prose only | Reword; no color changes |
| Dialog custom assertions in checks | `tst_themelayout_chrome.cpp:224-256` (`themeDialogGeometry`: 4-button count + `customModeButton` click); `tst_themelayout_settings.cpp:20-56` (`DialogControls`/`customSelection`), `:95-136`, `:138-180`; `tst_themelayout_scale.cpp:127-150` | Task 1/2 rework per briefs |

Nothing outside `src/ui/theme` and `src/checks/themelayout` references any
removed symbol: `mainwindow.cpp` only constructs `ThemeController`/
`ThemeDialog`; `applicationstartup.cpp` calls `vanilla()`; `tools/`,
`docsrc/`, `docs/` have zero custom-theme hits (sample-import/"custom
geometry" prose is unrelated).

## Out of scope

`trackidentitycolors`, `trackactivityrender`, `songview/detail.cpp`,
`trackvoiceops.cpp` (all keep color-math consumers), runtime theme
application, `presetcolors.h` tables themselves.
