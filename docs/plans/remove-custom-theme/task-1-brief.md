# Task 1 — De-customize ThemeDialog, delete OklchPicker

## Context

The dialog is the custom theme's only UI surface: hex edits, swatches, the OKLCh picker, an `eventFilter` for hex-edit focus, and a preview debounce timer exist solely to support partial custom drafts. Deleting them leaves three preset radios, the grid-line-contrast slider, and Apply/Close — the shared preset surface per [spec.md](spec.md). Consumer: task 2 consumes this task's dialog shape (the `draftSelection()` signature and the `vanillaModeButton` objectName) when it collapses the optional and reworks the settings check.

## Exact write set

- `src/ui/theme/themedialog.h`, `src/ui/theme/themedialog.cpp`
- `src/ui/theme/oklchpicker.h`, `src/ui/theme/oklchpicker.cpp` — delete both files
- root `CMakeLists.txt` — the `qt_add_library(porydaw_app ...)` block declares oklchpicker
- `src/checks/themelayout/tst_themelayout_chrome.cpp` — `themeDialogGeometry` only
- `src/checks/themelayout/tst_themelayout_scale.cpp`, `src/checks/themelayout/tst_themelayout.h`

## Prerequisites

- None — first task. Produces the dialog interface task 2 consumes.

## Interface contract

- Dialog keeps exactly: `m_modeButtons`, three `addModeButton` calls (Vanilla, DarkNeutralHigh, Immaterial), `m_gridLineContrastSlider`, `m_gridLineContrastValueLabel`, `m_applyButton`, `m_closeButton`.
- Radio objectNames: existing `darkNeutralHighModeButton` / `immaterialModeButton`, plus new `vanillaModeButton` so tests address all three.
- `draftSelection()` keeps its `std::optional<ThemeSelection>` return type unchanged (task 2 collapses it), but after this task its value is never empty — no failure branch remains.
- No preview timer (`m_previewTimer` deleted; preview applies immediately), no `eventFilter` override, no picker/hex/swatch members anywhere in the header.
- `themeDialogGeometry` asserts exactly 3 mode buttons.

## Implementation steps

1. Delete from the dialog: `m_customEditorGroup`, `m_primaryHexEdit`, `m_accentHexEdit`, `m_primarySwatch`, `m_accentSwatch`, `m_picker`, `m_pickerTargetLabel`, `m_pickerTargetsPrimary`, `m_draft.primary`, `m_draft.accent`, `m_ignoreFieldSignals` (its only users are deleted custom-field paths; the slider reset uses QSignalBlocker, `themedialog.cpp:425`); slots `primaryHexEdited`, `accentHexEdited`, `primarySwatchClicked`, `accentSwatchClicked`, `pickerColorSelected`; methods `setField`, `readDraftFromFields`, `parseField`, `canonicalHex`, `updatePicker`, `clearPartialCustomDraft`; and the `eventFilter` override (its only watches are the hex edits, `themedialog.cpp:464-476`).
2. `draftSelection()` builds `ThemeSelection{m_draft.mode, m_draft.gridLineContrast}` with no `customColors` and no failure branch (`themedialog.cpp:247-253`).
3. `schedulePreview()` is the debounce owner (`themedialog.cpp:256-272` — timer restart, invalid-draft fallback, Custom-only `m_previewTimer->start()`). With the custom editor gone `draftSelection()` cannot fail and no mode is Custom, so it collapses to an unconditional `m_controller.preview(*selection)`; `m_previewTimer` and its constructor wiring are deleted. (`previewDraft()` at `:390-398` already previews immediately and stays.)
4. `updateUi()` drops the `custom` enable/disable logic (`themedialog.cpp:289-293`); Apply is enabled whenever the dialog is open with a preset draft (always true — simplify accordingly, keep the committed-restoration reset in `resetDraftToCommitted`).
5. `modeChanged`/`resetDraftToCommitted` drop all `ThemeMode::Custom` and `committedSelection().customColors` branches (`themedialog.cpp:369-379`, `427-436`).
6. Give the Vanilla radio objectName `vanillaModeButton` (`themedialog.cpp:61` — the other two radios already have one).
7. Include/forward-declaration sweep after deletion: `themedialog.cpp` drops `themeresolver.h` (only `isValidColorPair` at `:248`), `<QPainter>`, `<QPixmap>` (picker mask only, `:142-151`); `themedialog.h` drops `<QColor>` if unused and the `QEvent`/`QGroupBox`/`QLineEdit`/`QTimer` forward declarations. Keep `QWidget`/`QVBoxLayout`/`QSlider`/`QLabel`/`QPushButton`/`QButtonGroup`.
8. `tst_themelayout_chrome.cpp` `themeDialogGeometry` (`:224-256`): `QCOMPARE(modeButtons.size(), 4)` → `3` (`:237`), delete the `customModeButton` lookup, `QVERIFY(custom)` and `custom->click()` (`:246`, `:248`, `:250`); keep the `darkNeutralHigh->click()` (`:249`) and the geometry-stability loop (`:251-255`).
9. Delete `oklchpicker.{h,cpp}` and their `CMakeLists.txt` declaration. Update any dialog comment referencing the picker or custom drafts.
10. `tst_themelayout_scale.cpp` + `tst_themelayout.h`: remove the `#include "ui/theme/oklchpicker.h"`, the `pickerPaintingMatchesHitTesting` test function (`tst_themelayout_scale.cpp:127-150` — no `_data` function exists), the now-unused `#include "ui/theme/color_math.h"` (`:5`) and `#include <QImage>` (`:9`), and the slot declaration `tst_themelayout.h:86`. Keep `<cmath>` (`std::abs`, `:149`), `<utility>` (`std::pair`, `:88`).

## Acceptance predicate

- `grep -i "oklchpicker|picker|HexEdit|Swatch|customEditor|ignoreFieldSignals" path="src/ui/theme; src/checks/themelayout"` returns nothing.
- The dialog header lists no picker/hex/swatch members, no `eventFilter` override, no dead includes or forward declarations.
- `tst_themelayout_scale` compiles with no picker references.
- `themeDialogGeometry` asserts exactly 3 mode buttons and passes without the custom radio.

## Task-specific constraints

- Non-goals: `ThemeController`, `ThemeSelection` shape, resolver, `tst_themelayout_settings.cpp`, `tst_themelayout_color.cpp` — tasks 2–3 own those.
- Every scale/polyphony test and the dark-base suite stay untouched; only the picker test goes.
