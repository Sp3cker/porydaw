# Task 3 — Drop the automation body floor to the shared minimum

Runs in parallel with Task 1 (disjoint files). Task 2 (Flickable, same QML
file as Task 1) lands separately; this task assumes the gutter will scroll
internally and the drawer no longer owes the tabs their cumulative height.

## Target

- `src/ui/editordrawer/drawersections.cpp`
  (`minimumBodyHeight` ~84-90; nothing else in the file)
- `src/ui/editordrawer/drawersections.h`
  (the `minimumBodyHeight` comment ~44-46; nothing else in the file)

Do NOT touch the `minimumContentHeight` property, its setter, its member,
or the `minimumContentHeightChanged` connect — Task 4 owns their removal.
Everything must keep compiling at every step.

## Change

1. `minimumBodyHeight` returns `m_chrome.minBody` for every page: delete the
   `EditorDrawerPage::Automations` special-case (`std::max(m_chrome.minBody,
   minimumContentHeight())`). Keep `ensureChrome()`.
2. Rewrite the `drawersections.h` comment to state the floor is uniform and
   the selector grid scrolls inside the gutter (Task 2), so body height and
   tab height are independent.

## Acceptance

`grep pattern="minimumContentHeight" path="src/ui/editordrawer"` shows only
the property machinery (canvas + connect), no floor logic; `deno task format`
on both files, then `deno task build:app` passes. Verification is
non-waivable: report command plus output. Drawer harness runs stay
controller-side.
