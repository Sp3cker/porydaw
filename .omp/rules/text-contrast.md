---
name: text-contrast
description: "Text contrast is the top UI priority: every QML text must meet WCAG AA against its real surface via GridPalette pairs"
scope: "tool:edit(*.qml), tool:write(*.qml), tool:edit(**/GridPalette.swift), tool:edit(**/ShellAppearance.swift)"
---

Text contrast is the top priority of any UI change. See
`docs/adr/0002-text-contrast-first.md`.

- WCAG 2.x AA for all rendered text in every theme (4.5:1 normal, 3:1 large
  ≥24px or bold ≥18.67px). Opacity/alpha counts. Only text in disabled
  components is exempt.
- `windowText`: all neutral surfaces. `secondaryText`/`warningText`/
  `errorText`: only window, chrome, button, tab, menu, input — never hover,
  alternate, roll, or accidentalLane (use `windowText` there).
- `selectionText`: only selection surfaces; `buttonPressedText`: only
  pressed surfaces. Selected/pressed rows use them for all text.
- `disabledText`: only inside `enabled: false` components. Info text uses
  `secondaryText`. Bind `enabled` on labels of inactive controls.
- Never: literal text colors, fallback palettes with literals, QML
  properties named `palette` (use `colors`), dimming text via opacity.
- Cross-platform: Fusion style plus `ThemedWindow` owns every palette role;
  never the platform style/palette; every top-level window derives from it.
- If a theme role is missing, do not invent a literal: stop and request it.
- Verify: `deno task verify:shell --filter shell-text-contrast --verbose`.
  New surfaces/popups must be reachable by that audit.
