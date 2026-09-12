# Task 4 — Remove the minimumContentHeight property machinery

Runs after Task 2 (the QML Binding that writes the property must be gone
first) and Task 3 (floor logic no longer reads it). Four files: the property
is referenced from the canvas triple plus one connect line — kept as one
task because it is pure deletion with a single compile proving it.

## Target

- `src/ui/editordrawer/automationcanvas.h` — remove the `minimumContentHeight`
  Q_PROPERTY, `setMinimumContentHeight` declaration,
  `minimumContentHeightChanged` signal, `m_minimumContentHeight` member.
- `src/ui/editordrawer/automationcanvas.cpp` — remove the getter.
- `src/ui/editordrawer/automationcanvas_tabs.cpp` — remove the setter
  definition; additionally prune the now-unconsumed `currentFill` and
  `background` keys from `parameterAppearance()` (Task 1 left them dangling;
  `selectionOutline` stays — the underline consumes it). Keep all `tab_*`
  keys and everything else.
- `src/ui/editordrawer/drawersections.cpp` — remove the
  `minimumContentHeightChanged` → `geometryChanged` connect (~line 50-51).

## Change

Pure deletion per the target list. If any other reference to
`minimumContentHeight` survives in `src/` outside `src/checks/` (the checks
rewrite owns those), resolve by symbol name and report it — do not expand
into the checks.

## Acceptance

`grep pattern="minimumContentHeight" path="src"` finds nothing outside
`src/checks/`; `grep pattern="currentFill" path="src/ui"` finds nothing;
`deno task format` on the four files, then `deno task build:app` passes.
Paste raw command outputs (required). Harness runs stay controller-side.
