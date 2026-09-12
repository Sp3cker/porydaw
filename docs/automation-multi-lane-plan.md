# Automation multi-lane visibility implementation plan

> **For agentic workers:** Use the OMP `subagent-driven-development` skill when implementing this plan task-by-task. Steps use checkboxes for tracking. This is a concise scope and file map, as requested, rather than a line-by-line implementation recipe.

**Goal:** Show multiple vertically stacked automation lanes by Shift-clicking their parameter tabs.

**Architecture:** AutomationCanvas owns one set of visible parameter catalog indices. The existing QML canvas reference supplies both button state and lane visibility. Reuse the former per-lane layout and page-owned scrolling approach, adapted to the current Quick scene.

**Tech stack:** C++20, Qt Quick/QML, QtTest, repository Deno tasks.

**Spec:** The agreed behavior below is the specification for this change.

## Global constraints and behavior

- Plain click shows only the clicked parameter, including when it is already visible.
- Shift-click toggles that parameter without changing the others. Toggling off the final visible parameter leaves an empty plot; labels remain available.
- Visible lanes stack vertically in existing catalog order, not click order.
- Tempo uses the same layout and interaction rules as other lanes. Do not restore its old special header.
- Preserve the current default Volume parameter and per-song lifetime. Visibility is view state, not a document edit or a new persisted preference.
- Keep visibility separate from existing node/lane editing selection and its label indicators.
- Proposed sizing: retain useful per-lane heights and scroll when their sum exceeds the viewport, using the former implementation as the reference. Do not squeeze every visible lane into the existing height.
- Preserve document, undo, clipboard, track identity, and playback semantics. Hiding a lane safely cancels affected gestures and owned popups without committing a provisional edit.
- Execute dependent tasks sequentially. Review each task and the final change through the harness workflow; follow repository commit/push instructions.

## Current code and historical reference

`automationcanvas_tabs.cpp` currently selects one parameter through `m_activeController`, `activeParameter()`, and `activeLane()`. Every logical lane already has an adapter, but `automationcanvas.cpp` gives each the same full-viewport body. `automationquick.cpp` renders only the active lane. `AutomationTabs.qml` uses exclusive TabButtons.

The parent of commit `459ac88` contains the earlier stacked-lane implementation. It assigned row rectangles cumulatively, hit-tested by vertical position, and kept content height and scroll position in AutomationPage. Commit `3a222e4` subsequently removed the old page scrolling and per-row sizing. Use history as a behavior/mechanics reference, not a wholesale file replacement.

## Code map

| Files | Responsibility/change |
| --- | --- |
| `src/ui/editordrawer/automationcanvas.h`, `automationcanvas_tabs.cpp` | Replace single-visible-parameter authority with a small visible-index set, such as `QSet<int>`. Expose observable visibility to QML and plain/Shift activation. Keep existing node-selection properties distinct. Resolve context-menu targets by parameter identity rather than assuming one active lane. |
| `src/ui/songview/quick/AutomationTabs.qml` | Bind checked appearance to visibility, disable exclusivity, and pass Shift activation to the canvas. Preserve keyboard activation, accessibility, selection outlines, and context menus. |
| `src/ui/editordrawer/automationcanvas.cpp`, `automationcanvas_input.cpp` | Assign visible lanes separate bodies; use those bodies for pointer/hover targeting and input coordinate conversion. Retain logical adapters needed by cross-lane commands. Hidden lanes must not receive pointer hits. |
| `src/ui/editordrawer/automationpage.h`, `automationpage.cpp` | Own restored content height, vertical scroll, and clamping. Update geometry when visibility, lane size, or viewport changes. |
| `src/ui/songview/quick/automationquick.cpp`, `automationnodelanequick.cpp` | Render the visible stack with matching per-lane clipping and scroll translation; preserve existing scene update domains. Change the node renderer only where its geometry assumptions require it. |
| `src/ui/songview/quick/DrawerChromeLayer.qml`, `TimelineCanvas.qml` and their existing C++ geometry bridge | Restore a Quick scrollbar bound to AutomationPage and reserve its geometry through the current layout owner. Reuse the existing Quick scrollbar component. |

## Tasks

### Task 1: Visible lanes and stacked editing

- [ ] Add real label-input tests for plain click, Shift-add, Shift-remove, collapsing an existing multi-selection, and an empty visible set.
- [ ] Implement the visibility set and QML presentation, then stacked lane geometry, rendering, and pointer targeting as one coherent change.
- [ ] Preserve ordinary keyboard activation as exclusive selection. Preserve right-click's existing target-activation behavior and resolve the requested lane explicitly.
- [ ] Update shared test activation helpers to assert visibility rather than a single active index. Keep ordinary one-lane editing scenarios intact.
- [ ] Verify multiple lanes draw and edit independently, including Tempo; hiding a lane cancels provisional interaction without an undo/document change.

### Task 2: Lane sizing and scrolling

- [ ] Adapt historical per-lane height and vertical-scroll mechanics to the current page and Quick layout ownership. Do not restore the historical Tempo header or QWidget plumbing.
- [ ] Bind the Quick scrollbar to page-owned state. Apply the same coordinate conversion to drawing, hover, dragging, pencil input, menus, and clipping.
- [ ] Clamp scroll after removing lanes or resizing the drawer; keep labels usable when the plot is empty or scrolled.
- [ ] Test overflow, scrolling to lower lanes, editing after scroll, and scroll clamping after visibility changes.

## Checks to update

- `src/checks/automation/presentation/painting.cpp` and `tst_automationpresentation.{h,cpp}`: replace single-full-height assumptions; add modifier-click behavior, checked-state, catalog ordering, distinct lane rectangles, and visibility-versus-selection coverage.
- `src/checks/automation/automationfixture.cpp`, `tst_automationediting.{h,cpp}`, `raster/rasterfixture.{h,cpp}`, and `hover/hoverfixture.{h,cpp}`: adapt activation/state queries and lane-coordinate helpers only where needed. Plain-click setup must still select one lane.
- `src/checks/automation/automationcanvaslayout.cpp`, `automationnodedrag.cpp`, `automationstroke.cpp`, and `automationownership.cpp`: cover stacked geometry, correct lane edits, and cancellation on hide. Retain existing edit/undo expectations.
- `src/checks/automation/automationmenus.cpp`, `automationpointmenus.cpp`, `hover/`, and `raster/`: update direct active-parameter assumptions and add representative scrolled-lane popup, hover, and curve coverage.
- `src/checks/scrollbar/tst_scrollbar.cpp`: restore automation scroll coverage through the production Quick control and update its parameter activation helper.

Run focused checks while implementing, then the affected group:

```sh
deno task verify --filter automation --filter scrollbar --verbose
git diff --check
```

Acceptance: all affected checks pass; single-lane editing retains its existing behavior; multiple visible lanes have consistent rendering/input geometry and working scrolling. Report unrelated baseline failures separately rather than weakening assertions.
