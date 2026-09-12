# Task 6 — Focused/checked tab scrolls into view

The Task 2 Flickable clips overflow, so keyboard focus or the checked tab
can sit invisible with no indication. This task adds minimal ensure-visible
behavior; it does not change fills, activation, or layout.

## Target

- `src/ui/songview/quick/AutomationTabs.qml` — the only file. Nothing else.

## Change

1. When the checked tab changes OR a tab gains active focus, if that tab's
   bounds lie outside the Flickable viewport, adjust `contentY` by the
   minimum offset that brings it fully into view (standard ensure-visible;
   never recenter, never animate).
2. Only react to checked/focus changes — never track continuously, and never
   fight an in-progress user flick/drag. If `moving`/`dragging` guards are
   needed to avoid fighting the user's gesture, add the narrower one and say
   so in the result.
3. Reuse existing ids/structure (grid Repeater `itemAt`, tab geometry);
   no new theme roles, no new files, no layout-primitive violations.

## Acceptance

`deno task build:app` passes (compiles the QML via qmlcachegen). Paste raw
output. Behavior proof (short drawer, focus last tab, viewport follows)
stays controller-side; name the exact manual/automated check in the result.
