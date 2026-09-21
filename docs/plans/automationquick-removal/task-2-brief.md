# Task 2 — Remove AutomationCanvas family + dead check twins

## Context

Second half of the excision. Deletes the `AutomationCanvas` class family and
`CcDeleteConfirm.qml`, removes every remaining reference in the surviving
dead files, and deletes the uncompiled check sources that reference the
removed surface. Behavior change: none (all touched code is uncompiled).

## Exact write set

Delete — C++ family (9 C++ files + 1 QML):
- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/editordrawer/automationcanvas_deleteprompt.cpp`
- `src/ui/editordrawer/automationcanvas_gesture.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/automationcanvas_menu.cpp`
- `src/ui/editordrawer/automationcanvas_pointmenu.cpp`
- `src/ui/editordrawer/automationcanvas_tabs.cpp`
- `src/ui/editordrawer/automationcanvas_taptempo.cpp`
- `src/ui/songview/quick/CcDeleteConfirm.qml`

Delete — dead check twins (uncompiled; verified absent from
`src/checks/CMakeLists.txt`). Delete each file below, and additionally any
`src/checks/` file that still matches the boundary grep after edits:
- `src/checks/automation/`: `automationactions.cpp`,
  `automationcanvasediting.cpp`, `automationcanvaslayout.cpp`,
  `automationclipboard.cpp`, `automationfixture.cpp`,
  `automationmenus.cpp`, `automationnodedrag.cpp`,
  `automationownership.cpp`, `automationpainting.cpp`,
  `automationparity.cpp`, `automationpencil.cpp`,
  `automationpointmenus.cpp`, `automationpreviews.cpp`,
  `automationquickmenu.h`, `automationrouting.cpp`,
  `automationselection.cpp`, `automationstroke.cpp`,
  `automationtaptempo.cpp`, `automationvalueprompt.h`,
  `automationvoice.cpp`, `ccdeleteconfirmation.cpp`,
  `tst_automationediting.cpp`, `tst_automationediting.h`
- `src/checks/automation/domain/tst_automationdomain.cpp`
- `src/checks/automation/hover/`: `hoverfixture.cpp`, `hoverfixture.h`,
  `tst_automationhover.cpp`
- `src/checks/automation/presentation/`: `painting.cpp`,
  `tst_automationpresentation.cpp`
- `src/checks/automation/raster/`: `interaction.cpp`, `painting.cpp`,
  `rasterfixture.cpp`, `rasterfixture.h`, `tst_automationraster.h`
- `src/checks/drawerpresentation/`: `drawer.cpp`, `valueprompt.cpp`
  (NOT `velocity.cpp` — it is velocity coverage over the live
  VelocityArea surface with zero boundary tokens; deleting it would be
  scope creep against the sibling plan's seam)
- `src/checks/host/`: `tst_hostadapter.cpp`, `tst_hostintegration.cpp`,
  `tst_hostseams.cpp`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp`
- `src/checks/scrollbar/tst_scrollbar.cpp`
- `src/checks/selectionkey/`: `automationprobe.cpp`, `automationprobe.h`,
  `coreediting.cpp`, `gesturecommands.cpp`, `localinputtier_text.cpp`,
  `windowtier_gestures.cpp`, `windowtier_keyboard.cpp`,
  `windowtier_lifetime.cpp`
- `src/checks/timelinepan/`: `tst_timelinepan.cpp` (uncompiled; references
  `TimelineQuickLayer::AutomationSelection`/`AutomationGutterChrome` and
  `requestAutomationUpdate` removed by task 1 — surfaced by task-1
  implementer; verify uncompiled before deleting)

KEEP (live twins / shared dead files — verify before any delete):
- All `.swift` files under `src/checks/` and all `proof.*.txt`.
- `src/checks/automation/domain/` `.swift` files and
  `proof.tst_automationdomain.txt`.
- `src/checks/drawerpresentation/{velocity,voice,voicemenus,drawer}.swift`.
- `src/checks/selectionkey/` `.swift` files if any exist — only the
  `.cpp`/`.h` files listed above die.
- Any file whose only sin is referencing a deleted header but which a live
  target compiles — there are none; if you find one, STOP and report.

Edit (remove references to the deleted surface only):
- `src/ui/editordrawer/automationpage.h` — drop `m_canvas`, `canvas()`,
  `class AutomationCanvas;`, `friend class AutomationCanvas;`.
- `src/ui/editordrawer/automationpage.cpp` — drop the include and
  `m_canvas = new AutomationCanvas(*this);` plus any `m_canvas` uses.
- `src/ui/editordrawer/drawerchrome.cpp` — drop the include, the
  `m_automationPage.canvas()` connect (~213), and all `m_page.canvas()`
  value-prompt forwards (~339–374).
- `src/ui/editordrawer/drawerchrome.h` — drop the declarations orphaned by
  those forwards.
- `src/ui/editordrawer/drawersections.cpp` — drop the include only (no
  canvas() references exist).
- `src/ui/songview.cpp` — drop the `automationcanvas.h` include (~line 4).
- `src/ui/songview/editactions.cpp` — drop the include (~line 3), the
  `AutomationCanvas` comment (~192–195), and the `page->canvas()` /
  `pencilMode()` gating branch (~324–326) — dead code; delete the branch.
- `src/ui/songview/editkeyrouting.cpp` — drop the include (~line 16) and
  the `page->canvas()` / `setPencilMode` uses (~207–208, ~359–362) — dead
  code; delete the branches.
- `src/ui/songview/quick/timelinequickview.cpp` — drop the include, the
  `automationCanvas` context property (~159–160), the
  `canvas()->setPopupSession` call (~181), and the plot/gutter input
  bindings to `m_automation->canvas()` (~302–306).
- `src/ui/songview/quick/timelinequickview.h` — drop anything now orphaned
  by those removals (e.g. unused `m_automation` uses — keep the member if
  other lanes still read it).
- `src/ui/songview/quick/timelinequickview_window.cpp` — drop the include
  and `m_automation->canvas()->setPopupSession(nullptr)` (~147).
- `src/ui/editordrawer/cclanes.cpp` — retarget the
  `translate("AutomationCanvas", …)` contexts (~122, ~130–131) to the
  enclosing class name.
- `src/ui/editordrawer/tempolane.cpp` and
  `src/ui/editordrawer/nodelane/tempoadapter.cpp` — same translate-context
  retarget (~13, ~9).
- `src/ui/editordrawer/nodelane/gesture.h` — reword the 'moved from
  AutomationCanvas' comment (~189) to name the concept, not the class.
- `src/ui/songview/quick/promptappearance.h` — reword the
  `CcDeleteConfirm` doc comment (~11) to describe the prompt contract
  without naming the deleted file.

## Prerequisites

Task 1 complete: paint path deleted, `timelinequickscene.{h,cpp}`
automation members gone, `TimelineCanvas.qml` band removed.

## Interface contract

- No new symbols. Deletion + reference removal only.
- C++ `AutomationPage` survives as a shell (still owned by `EditorDrawer`);
  it loses only canvas-related members.
- After this task, the boundary grep in plan.md task 3 is empty.

## Implementation steps

1. Delete the 9 C++ files + `CcDeleteConfirm.qml`.
2. Edit the referencing files listed above; for each, remove only lines
   tied to the deleted surface.
3. Delete the listed dead check files; then run the boundary grep over
   `src/checks/` (excluding `proof.*.txt`) and delete any remaining
   uncompiled file that still references the removed surface (report each
   extra deletion).
4. Run the full boundary grep over `src/`; every hit must be resolved by
   deletion or reference removal — never by guards or `#if 0`.

## Acceptance predicate

Per plan.md Verification policy (all four commands, run by implementer).
Task-specific greps (must be empty over `src/`, excluding `proof.*.txt`
fixtures which are frozen logs):
`grep -rn "AutomationCanvas\|automationcanvas\|CcDeleteConfirm\|automationCanvas" src/ --exclude="proof.*.txt"`
`grep -rln "automationcanvas\.h" src/`

## Task-specific constraints

- The `.swift` twins and `proof.*.txt` files are load-bearing live tests —
  deleting one is a spec violation.
- If a listed file turns out to be compiled (present in any CMakeLists
  source list), STOP and report — the plan's dead-code premise is wrong
  for that file.
- Do not delete `automationpage.{h,cpp}`, `editordrawer*`, `songview*`,
  `timelinequickview*`, or `TimelineCanvas.qml` — out of scope.
