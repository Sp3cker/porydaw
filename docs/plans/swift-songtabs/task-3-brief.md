# Context
Verify actual QML tab surface and strict existing visuals without features beyond C++ QTabWidget. Read plan.md global constraints/spec and task-2 objectName contract.

# Exact write set
- src/checks/swiftgridprototype/songtabs_smoke.cpp
- src/checks/swiftgridprototype/songtabs_smoke.h
- src/checks/swiftgridprototype/grid_smoke.cpp
- src/checks/swiftgridprototype/interaction_smoke.cpp (failure attribution only)
- src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt

# Prerequisites
Task 1 controller/App initialization, task 2 C++-parity strip, task 4 move API.

# Interface contract
verifySongTabs(QQuickWindow*) runs after original grid scenarios before PASS. App seeds three sessions, selects first; existing original grid scenarios use that first page. At new tab test start close the other clean bootstrap sessions through their actual close controls for isolated setup. Fixture opening via controller.openTab is allowed ONLY in checks to represent out-of-scope browser/session creation; it is not claimed as UI acceptance. Tab actions use actual pointer input. No app hooks or smoke-env branches.

Selected page resolved through controller.selectedId and songTab_<id>; descendant grid/menu/input lookup scoped there. Strip controls match task-2 brief: selection/close and left/right scrolling only. No plus/dropdown/tab-key-navigation surface.

# Implementation steps
1. Preserve all original strict raster/geometry/gesture assertions and expected values. Existing border-failure diagnostic may remain useful. Coordinates use mapToScene, never hard-coded strip offsets; single-pixel probes sample containing interior pixel.
   Native smoke startup must request activation once and wait for an active window before exercising keyboard contracts, not merely wait for exposure. No per-action focus restoration. Preserve failure-only transport diagnostics identifying inactive-window interference.
2. Open fixtures through controller semantic operation and await a requested native rendered frame before pointer input; page QObject existence alone is insufficient. Actual pointer selection/edit/switch proves per-page camera, selection, undo and sibling musical isolation. Reveal actual note before clicking; snapshot post-edit camera. Real drag reorder proves rowsMoved, persistent index and exact live page/grid/camera retention.
3. Actual close handles background selection preservation, dirty Cancel/Discard, final empty state; reopening is external fixture setup through openTab. Replace former empty instructional-label expectations with blank page/no grid leakage. No existence/source assertions for removed controls unless needed to prevent actual user-visible regression.
4. Narrow window and open enough fixture sessions to overflow. Use actual native left/right scroll buttons to reveal and click a genuinely offscreen tab, then edit/select/Escape on its grid. Remove dropdown scenarios, TabFocusAllControls guard and traversal diagnostics: C++ tab bar is NoFocus, no invented keyboard traversal feature. Native modal buttons remain accessible/keyboard-capable normally.
5. Preserve original explicit smoke source registration; no new executable, source build migration or app-side hooks. Maintain exact tab indicator/separator and grid clipping raster checks.

# Acceptance predicate
Main runs deno task prototype:swift-grid --smoke and sees original strict passes plus named C++-parity tab scenarios, no app warnings. Main runs existing visual suites on native Retina independently; no baseline changes. Authors skip builds/tests/linters/formatters.

# Task-specific constraints
Five-file exception is one native check/registration surface, including existing transport failure diagnostics. Real pointer input for changed tab UI; fixture construction uses controller because browser opening is explicitly outside this prototype. No forceActiveFocus calls or fake UI state.
