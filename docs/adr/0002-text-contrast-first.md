---
status: accepted
---

# Text contrast first

Text legibility is the most important visual requirement of Porydaw. It
outranks legacy color fidelity, visual preference, and pixel-match baselines:
when an inherited color and a legible color conflict, the legible color wins.

## Requirement

Every piece of rendered text meets WCAG 2.x AA against the surface actually
drawn behind it, in every shipped theme (`vanilla`, `dark-neutral-high`,
`immaterial`): 4.5:1 for normal text, 3:1 for large text (≥24px, or bold
≥18.67px). Only text inside a disabled component is exempt (WCAG 1.4.3).
Opacity and alpha count: the composited ink must still pass.

## Cross-platform rule

The app owns its style and palette. `resources/qtquickcontrols2.conf` pins
the Quick Controls style to Fusion on every platform; `src/ui/shell/
ThemedWindow.qml` assigns every Qt palette role in every color group from the
theme, so no control, popup, or menu inherits the platform palette. Never rely
on the platform style, platform palette, dark-mode appearance, or OS idioms.
Every top-level window must derive from `ThemedWindow`.

## Legal ink/surface pairs

Inks and surfaces are `GridPalette` roles (`src/swift/app/timeline/
GridPalette.swift`), applied by `ShellAppearance.apply` (`src/swift/app/
shell/ShellAppearance.swift`).

| Ink | May label |
|---|---|
| `windowText` / `primaryText` / `buttonText` | Every neutral surface: window, chrome, button, buttonHover, tab, tabHover, menu, menuHover, input, alternate, roll, accidentalLane. Never selection or pressed surfaces. |
| `secondaryText`, `warningText`, `errorText` | Only window, chrome, button, tab, menu, input. Never hover, alternate, roll, or accidentalLane surfaces (they fail in dark themes); use `windowText` there. |
| `selectionText` | Only selection surfaces (`tabSelectedBackground`, `selectionRing`, `keyboardActiveKey`). A selected row/tab uses it for all its text, including secondary, warning, and count text. |
| `buttonPressedText` | Only pressed surfaces (`buttonPressedBackground`, `tabPressedBackground`). Same all-text rule as selection. |
| `disabledText` | Only text inside a component whose `enabled` is false. |
| `polyphonyCellText` (white) | Active (`#228445`) and shadow (`#2859A4`) polyphony fills. |
| `polyphonyReleasingText` (dark) | Releasing (`#B98527`) polyphony fill (white-on-amber is 3.26:1). |

Labels of inactive controls declare `enabled: <same condition>` on the label
(or its container) and pick the color from `enabled`, so the inactive state is
explicit. Informational text (hints, captions, empty states, headings, idle
indicators) uses `secondaryText`/`windowText`, never `disabledText`. Never dim
text with `opacity`; use `secondaryText`.

## Prohibitions

- Literal text colors in QML (`#666666`, `white`, …).
- Fallback palettes with literal colors; bind the always-present session
  palette instead.
- QML properties named `palette`: they shadow Qt's own `palette`. Rename to
  `colors`.
- Dimming text via `opacity`; dimming via alpha on the ink.
- `disabledText` for informational text.

## Enforcement

- `swiftcore` `ThemeColorChecks` (`src/checks/themecolor/
  ThemeColorChecks.swift`): static pair-table floors on the applied palette.
- Rendered audit `shell-text-contrast`: `src/checks/editorqml/
  tst_TextContrast.qml` plus `TextContrastAudit.js` grabs real frames and
  measures each visible text item against the dominant surface pixels behind
  it. Run `deno task verify:shell --filter shell-text-contrast --verbose`.
  New surfaces and popups must be reachable by that audit.

## Consequences

Vanilla secondary ink darkened to `#4D4742` (the legacy `#57514C` reached only
3.87:1 on chrome); implicit signatures and ruler beat labels use it.
Severity inks darkened (`#644100`/`#8D1B1F` in vanilla). Amber polyphony
cells use dark text. Placeholder uses secondary ink, never disabled ink.
