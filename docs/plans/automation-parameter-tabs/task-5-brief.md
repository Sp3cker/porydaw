# Task 5: Install accessible compact parameter labels in the gutter

> Route: SDD-track. Execute through rule://sdd-execution-loop with a brief-first sdd-implementer. Read-only task review follows. This brief authorizes only this task, not adjacent work.

## Context

Replace vertically stacked automation rows with a compact grid of nine clickable labels in the existing left gutter and one active plot. Ordered identities: CC1 Modulation, CC7 Volume, CC10 Pan, CC20 Bend range, CC21 LFO speed, registered XCMD 0xFB Echo volume and 0xFC Echo length, dedicated 0xFF Pitch bend, then song-global Tempo. All are available even without written events. Default Volume. Active parameter is SongTab-local, retained across primary-track changes and open-tab round trips, not application-global or persisted.

## Global Constraints

- Preserve ALL automation-node semantics, especially the origin phantom: held value, source event/tick, paint/hit/hover, vertical drag, cancellation, menus and undo. A phantom edits its original event; never insert a duplicate at the viewport edge.
- Keep all logical adapters and shared selected-node batching. Only drawing, ordinary hover/hit targeting and new band selection use the active parameter. Existing explicit multi-lane selections and command targets survive switching, including unpainted lanes and global Tempo.
- Switching labels creates no event, undo entry, cursor move, selection clearing/retargeting or track change. Cancel provisional gestures and owned stale menus/value prompts before changing identity; preserve foreign popup ownership. Resolve LaneHandle from stable row identity after rebuilds.
- Preserve defaults/implicit lead-in, point-menu/value-prompt behavior, normal drag/modifiers, stationary/delete/double-click guards, pencil/sweep/ramp, snapping, same-tick order, XCMD grouping, signed bend, transaction and lifetime rules. Reuse NodeLane, adapters, projection, gesture and NodeLaneQuickPaint; do not rewrite them.
- Tempo belongs in the shared plot, not a pinned/collapsible header. All nine full labels fit without scrolling/overflow. Qt Text.HorizontalFit, FontMetrics and GridLayout own fitting/sizing; only the at-most-three-column policy is local. Use caption-or-smaller type, fontPx(2/3) floor and layout:: geometry. Bind the grid implicitHeight to the existing minimumContentHeight API; do not change shared DrawerMetrics::minBody or Velocity/Voice Changes sizes/cap/handoff.
- Active tab, shared-selection inclusion and focus have distinct indicators. QML labels own mouse input. Enter/Space activate; normal Tab traversal and unhandled SongView keys remain. No focus memory or second key dispatcher.
- Remove Add/Show/Hide, live empty-row/row-height/vertical-automation-scroll UI and unused UI facades. Leave EditorViewState storage, QSettings codec, track remapping and their tests unchanged; do not delete legacy fields/keys or add a migration. Tabs ignore old visibility/height entries. Retain laneRanges, outer section state and every song event; no unsupported tabs/MIDI reclassification. Other scrolling remains.
- Stay within the write set. Read adjacent declarations/fixtures and refresh LSP references before public API changes. Use LSP rename for cross-file renames. Unexpected semantic consumers outside scope: report NEEDS_CONTEXT for a controller brief; never silently drop them.
- Skip formatters, linters, builds and tests in the implementer. The controller runs coverage after writers settle and API/test migration completes. Never suppress failures or claim obsolete assertions passed. Do not commit, push, create a worktree or spawn agents.
- No unrelated engine/document/shared-key refactor, QWidget fallback, compatibility alias or no-op API. Preserve concurrent user changes. This brief is the implementer's single task source; agreed spec: docs/plans/automation-parameter-tabs/spec.md.
- Line-count note: the controller tracks aggregate new/materially rewritten production lines across the plan and reports the count; there is no numeric limit and no budget-based condition. Implement this brief completely and cleanly without optimizing to any size target, never weakening behavior or tests for size, and include your approximate production-line contribution in the required report (with source/destination evidence for any claimed unchanged-move or formatting-only exclusions).

## Exact write set

- `src/ui/songview/quick/AutomationTabs.qml` — create
- `src/ui/songview/quick/TimelineCanvas.qml`
- `CMakeLists.txt`

## Prerequisites

Completed/reviewed tasks: 4.

## Interface contract

Consumes automationCanvas and task 2's properties/invokables. Use QtQuick.Controls.Basic.TabButton, Qt Quick Layouts GridLayout, Text.HorizontalFit and Qt text metrics in the existing Quick window. AutomationTabs.qml has required var canvas and required Item sceneRoot. Add Qt6::QuickControls2; QtQuick.Layouts is a QML import, not a new handwritten layout module. No TabBar, separate controller/model, new popup system or global style change.

## Implementation steps

### Step 1

Create automationParameterTabs as a top-aligned Item with GridLayout/Repeater TabButton delegates named automationParameterTab + index. GridLayout gets the gutter width, zero row/column spacing, and uniformCellWidths/uniformCellHeights. Use Layout.fillWidth and the control's implicitHeight with Layout.minimumHeight from appearance.minimumCellHeight. Do not set delegate x/y/width/height or anchor delegates inside the layout. The grid keeps its implicitHeight, not the allocated drawer height; the root exposes that height.

Qt text fitting replaces the C++ font search:
```qml
contentItem: Text {
    text: tab.text
    font: tab.font
    fontSizeMode: Text.HorizontalFit
    minimumPixelSize: root.appearance.minimumFont.pixelSize
    textFormat: Text.PlainText
    wrapMode: Text.NoWrap
    elide: Text.ElideNone
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: root.appearance.text
    Accessible.ignored: true
}
```

The only application layout policy is the maximum of three columns: use FontMetrics at appearance.minimumFont to obtain the widest complete label advance plus two insets, then bind columns to min(3, max(1, floor(gutterWidth / minimumCellWidth))). Bind that width calculation explicitly to labels, minimumFont and inset; Qt owns measurement/invalidation, not an imperative JS cache. GridLayout owns cell distribution and total implicitHeight, and each Text chooses its fitted font. Do not recreate the old nested font-size/candidate loop in JavaScript. A tiny/unlaid-out width is not evidence that text fits; the native minimum-host gate remains mandatory.

Publish only the resulting requirement:
```qml
Binding {
    target: root.canvas
    property: "minimumContentHeight"
    value: Math.ceil(grid.implicitHeight)
}
```

### Step 2

Keep TabButton's native checkable/autoExclusive defaults; bind checked to canvas.activeParameter === index and call canvas.activateParameter(index) from onClicked. Canvas remains the domain authority; native checked state is the control's presentation, not a second persisted model. No ButtonGroup/currentIndex mirror, manual uncheck loop or onCheckedChanged model synchronization. Qt's C++-owned checked updates do not replace a QML binding; never imperatively assign checked in QML. Test only that a real activation and a programmatic SongTab/track transition settle on the correct parameter, not Qt's exclusivity implementation.

Use the existing appearance roles for Basic background/content and selection/focus outlines. Preserve native pressed/canceled/Space/focus/accessibility actions; use StrongFocus, visualFocus, Accessible.selected and only the application-specific global-Tempo/shared-selection description. Do not add an explicit accessible press handler. Leave unhandled editing keys to the existing root policy. Keep a local Keys.AfterItem Enter/Return extension only where the native button did not consume the advertised key, ignoring auto-repeat and modified Return; do not add a Shortcut that activates from elsewhere in the window.

Use Qt's platform context-menu event, not a right-button gesture recognizer:
```qml
Controls.ContextMenu.onRequested: position => {
    const p = tab.mapToItem(root.sceneRoot, position.x, position.y)
    root.canvas.openParameterMenu(tab.index, p.x, p.y)
}
```
Qt accepts this event even without ContextMenu.menu when requested has a handler. Reuse the existing QuickPopupSession menu and its ownership/revision guards; do not migrate the menu/forms to Controls.Menu as collateral work. No TapHandler/MouseArea overlay for context-menu detection or ordinary activation.

### Step 3

In the automation gutter replace the obsolete stacked TimelineTextLayer and two Tempo-header plates with AutomationTabs parented to automationBand.gutterSide, anchors.fill: parent, canvas: automationCanvas, sceneRoot: root and z: 3. The existing gutter input item is z=2. Keep plot input/layers, hover/transient value text and the canonical split. Do not retain a hidden old selector or runtime feature flag.

### Step 4

Register AutomationTabs.qml in the existing QML resource/module declarations. Extend, rather than duplicate, the existing dependencies:
```cmake
find_package(Qt6 6.9 REQUIRED COMPONENTS Qml Quick QuickControls2 Svg Widgets)
target_link_libraries(porydaw_app PRIVATE Qt6::Qml Qt6::Quick Qt6::QuickControls2)
```
ContextMenu requires Qt 6.9; uniform grid cells require 6.6. The existing build and release CI already install Qt 6.9.x, so 6.9 makes the actual requirement explicit rather than raising CI to a new release. Keep Qt Test checks-only. Verify the deployed QML imports include Controls Basic/Templates and QtQuick.Layouts; a successful C++ link alone is insufficient. Do not add another test framework.

Primary references: [TabButton](https://doc.qt.io/qt-6/qml-qtquick-controls-tabbutton.html), [AbstractButton](https://doc.qt.io/qt-6/qml-qtquick-controls-abstractbutton.html), [Text fitting](https://doc.qt.io/qt-6/qml-qtquick-text.html#fontSizeMode-prop), [FontMetrics](https://doc.qt.io/qt-6/qml-qtquick-fontmetrics.html), [GridLayout](https://doc.qt.io/qt-6/qml-qtquick-layouts-gridlayout.html), [ContextMenu](https://doc.qt.io/qt-6/qml-qtquick-controls-contextmenu.html), [Binding](https://doc.qt.io/qt-6/qml-qtqml-binding.html), [Basic customization](https://doc.qt.io/qt-6/qtquickcontrols-customize.html), [Keys.AfterItem](https://doc.qt.io/qt-6/qml-qtquick-keys.html).

## Acceptance predicate

All nine real Quick labels activate the correct single plot without changing shared selection or song data, and remain in the existing gutter with distinct active, selection-scope and focus indicators.

## Controller verification

Controller: `deno task build:app`, then launch the actual app and exercise Volume, Pan and Tempo through the standard controls. Require no missing QML import or unsupported-native-style customization warning; observe the correct single plot, stable camera and unchanged document/selection. Exercise right-click routing and the Enter extension once through existing integration coverage in task 27. Do not add tests for Qt's press/release signal sequences, generic focus traversal, exclusivity or GridLayout placement algorithm. Keep application-level fit, tab-to-parameter, selection, phantom and stale-prompt checks.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
