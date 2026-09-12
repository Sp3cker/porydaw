# Task 1 — Tab hover/selected semantics, press-down activation, selection hoist

First QML task of the automation-tabs-qml plan. The C++ appearance bridge
already landed and is committed beneath this task: `parameterAppearance()`
exposes `tabBackground`, `tabHoverBackground`, `tabSelectedBackground`,
`tabText`, `tabHoverText`, `tabSelectedText`, `tabOutline` (use these key
names verbatim; they map to `Role::tab_*`).

## Target

- `src/ui/songview/quick/AutomationTabs.qml` — the only file. Nothing else.

## Change

1. Fill precedence (matches `QTabBar`, `themeruntime.cpp:127-131`; selected
   wins over hover):
   `checked ? appearance.tabSelectedBackground : tab.hovered ? appearance.tabHoverBackground : appearance.tabBackground`.
   No pressed fill — `QTabBar` has none; the activation itself is the feedback.
2. Text tracks fill:
   `checked ? appearance.tabSelectedText : tab.hovered ? appearance.tabHoverText : appearance.tabText`.
3. Border always `appearance.tabOutline` (width stays `appearance.stroke`).
   The transparent-unless-included border goes away.
4. `selectionIncluded` (shared time-selection coverage, NOT tab selection)
   demoted to a secondary indicator — a small dot or underline element, never
   a full-cell outline. `Accessible.selected` binds `checked`, not inclusion;
   inclusion stays text-only in `Accessible.description`.
5. Keep the inner focus ring (`focusOutline`) painted over all states, and
   keep the existing `Keys` behavior exactly (plain Return/Enter claimed,
   bare Space unclaimed so transport wins; see current `onShortcutOverride`).
6. Press-down activation: add `onPressed: root.canvas.activateParameter(tab.index)`;
   keep `onClicked` as the fallback (AT press action, keyboard click). The
   double-fire is free — `activateParameter` early-returns on the active index
   (`automationcanvas_tabs.cpp:109`). Do NOT add a TapHandler/MouseArea
   (no second dispatcher). Right-click keeps the existing menu path, which
   activates-then-opens.
7. Selection perf hoist (no bitmask — decided): one root-level
   `readonly property var selectedParams: root.canvas.selectedParameters`;
   each tab's `selectionIncluded` reads `selectedParams.includes(tab.index)`
   instead of calling the C++ getter per tab (9 QList builds become 1).
8. Keep the `minimumContentHeight` Binding and grid layout untouched — the
   Flickable task owns them.

## Acceptance

`deno task format` on the file, then `deno task build:app` passes.
Verification is non-waivable: report command plus output. QML behavior
harness runs (`--filter=automation`, `--filter=selectionkey`) stay
controller-side; do not run them.
