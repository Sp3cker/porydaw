# Automation parameter tabs — agreed specification

## Status and authority

This records the user's approved behavior. Implementation is partially landed; the implementation audit identified bounded code repairs and corrections to the companion plan. The user has authorized those code repairs and requires the `plan` agent to double-check plan corrections before document edits. Plan status and repair evidence belong in the companion plan; changing this document does not authorize unrelated implementation.

The user's binding requirements are:

> The automation headers and lanes must no longer be listed one-by-one down the automation drawer. Clickable labels where the labels currently are swap which nodes are drawn. Show all available automations without scrolling.

> It is very important that the automation nodes work the exact same; the phantom node stays. Tempo must be one of the selectable automations. Label text can be made pretty small if needed to fit them all.

The user approved the clarification: a compact grid in the existing left gutter; a label-derived drawer minimum; Tempo in the shared plot; tab switching preserves shared selection. Velocity and Voice Changes remain separate. Horizontal timeline scrolling remains. The grid was later revised by the user to a single full-width vertical list of labels; the label-derived minimum and every other point of this clarification still stand.

## Global Constraints

- Preserve all existing automation-node editing semantics; this is a presentation and input-targeting change, not a new editor.
- Preserve the origin phantom node, including its source event/tick, held value, paint, hover, hit target, vertical drag, cancellation, context actions and undo behavior.
- Show exactly one parameter plot at a time, with all nine standard parameter labels available without vertical automation scrolling.
- Include global Tempo in the same selector and shared plot; remove pinned/collapsible Tempo presentation.
- A parameter switch changes view state only: no document mutation, undo entry, edit-cursor move, selection clearing, selection retargeting or primary-track change.
- Preserve shared selection semantics, including selected-node group edits spanning logical lanes that are not currently painted.
- Preserve normal selected-track transitions; retain the chosen parameter type while applying existing track-selection/selection-clearing policy.
- Leave Velocity, Voice Changes, horizontal timeline scrolling, piano-roll vertical scrolling, playback, the audio engine and file serialization behavior unchanged.
- Use Qt Quick controls in the existing Quick window; no QWidget fallback, extra window, focus-memory mechanism or duplicated shared-key dispatcher.
- Prefer built-in Qt types when they own the required behavior. The user permits additional Qt libraries to reduce custom implementation and check code. Use Qt Quick Controls TabButton with Basic visual customization, Qt Quick Layouts GridLayout/Repeater and Text.HorizontalFit for layout/text fitting, and the existing Qt Test harnesses; do not hand-build ordinary button interaction.
- A production helper needs a named product consumer, including a concrete planned QML consumer. Navigation needed only by fixtures belongs in existing check support. Reuse the existing visual-tree lookup rather than adding another traversal, inverse catalog policy or production interface for tests; do not add helper-plumbing tests to justify unnecessary code.
- Use existing typography, theme roles and `layout::` font-relative geometry; smaller label text is allowed, but never replace labels with an overflow menu or scrolling selector.
- Keep all supported logical lane adapters available independently of which parameter is painted; do not implement tabs by keeping only one lane adapter.
- Preserve parameter value ranges, all song events and the existing persisted EditorViewState schema; old visibility/height entries stop controlling the UI but are not deleted from storage.
- The controller tracks new or materially rewritten production lines, including C++, headers, QML, build declarations and all glue, as nonblank, non-comment physical lines in normal project formatting against one preimplementation baseline. Verified unchanged moves, formatting-only changes, deletions and test churn are reported separately; deletions never offset additions. The tracked count is informational bookkeeping: there is no numeric limit and no approval step; preserving required behavior and verification remains mandatory.
- Use `deno task` for builds, format and checks; never invoke CMake directly. The controller runs validation after writers settle.
- A software/offscreen image is not proof that native QSG nodes or phantom nodes render correctly; final rendering proof must use the actual native/default backend.
- The current authorization covers the requested audit corrections and code repairs, not commits, pushes, merges, worktree creation or unrelated implementation.

## User-visible behavior

### Parameter catalog and identity

The standard catalog is the current Add-automation catalog, not all possible MIDI CCs:

| Label | Identity | Scope |
| --- | --- | --- |
| Modulation | CC 1 | Selected primary engine track |
| Volume | CC 7 | Selected primary engine track |
| Pan | CC 10 | Selected primary engine track |
| Bend range | CC 20 | Selected primary engine track |
| LFO speed | CC 21 | Selected primary engine track |
| Echo volume | registered XCMD lane 0xFB | Selected primary engine track |
| Echo length | registered XCMD lane 0xFC | Selected primary engine track |
| Pitch bend | dedicated lane 0xFF | Selected primary engine track |
| Tempo | tempo row identity | Song-global |

Keep this order: existing sorted CC identity order, followed by Tempo. Default to Volume for a newly created automation page. Each SongTab owns its active parameter for its open lifetime; do not add application-global or on-disk active-parameter persistence. Changing the primary track retains the parameter type. Returning to another open SongTab restores that tab's own parameter.

All labels exist even without explicit events. Selecting one must not write a synthetic event. Existing adapter projections, defaults and implicit lead-in behavior remain unchanged. Tempo's label/accessibility description identifies its song-global scope.

Legacy settings can name ordinary CCs outside this catalog. Their presentation entries no longer control the UI; their MIDI data is not deleted or reclassified. Such events retain their existing Other Events/Event List representation. Do not add unsupported controller tabs to preserve a cosmetic setting, and do not alter the underlying CC classification.

### Labels and geometry

Labels remain physically in the current automation gutter. The shared plot begins at the canonical timeline split and spans the full automation body; it shares the current horizontal camera/grid with the piano roll. There is no separate Tempo header strip or plot and no internal vertical automation scrollbar.

Use QtQuick.Controls.Basic TabButton delegates in GridLayout. Qt owns ordinary input, checking/exclusivity, focus and accessibility actions; Porydaw owns styling, active parameter identity and shared-selection semantics. Keep native checkable/autoExclusive defaults with checked bound to the canvas; no mirrored currentIndex or manual uncheck loop. No TabBar: its scrolling strip is not the approved list. Use ContextMenu.onRequested to open the existing owned parameter menu. A local Keys.AfterItem Enter/Return extension supplies only the advertised activation key where native button behavior does not. Add Qt6::QuickControls2 and import QtQuick.Layouts; Qt 6.9 matches existing CI and supplies ContextMenu.

Use one full-width GridLayout column — the labels stack vertically, each owning the gutter's whole width — plus Text.HorizontalFit/minimumPixelSize for shrinking each label. The caption is the upper font size; the initial floor is layout::fontPx(2.0/3.0). A shared fitted font for every label was an implementation choice, not a user requirement. Per-label Qt fitting is allowed; full readable labels remain mandatory. Do not hand-roll font search, row placement, grid-height arithmetic, a text cache or a second typography fitting API.

Use layout::space(One) for text inset and layout::singlePixel() for outlines. Keep control implicit sizing with layout::fontPxF(4.0/3.0) as the minimum cell height. Bind Math.ceil(grid.implicitHeight) to the existing AutomationCanvas::minimumContentHeight property, with one equality-guarded scalar setter. DrawerSections applies max(existing shared minimum, selector minimum) only to automation. No additional minimumParameterHeight API and no change to DrawerMetrics::minBody or the Voice Changes cap.

The dependency is one-way: font/labels/gutter width -> Qt intrinsic layout height -> automation allocation. Do not bind the grid's height to the allocated body height. Qt may publish the intrinsic requirement after initial layout; reapply it through the existing geometry notification, without timers, polling or a new scheduler. Verify first exposure and resize at the actual minimum supported host geometry. If fit/allocation fails, fix that contract; do not hide labels or alter other bands' height rules.

Selected/current parameter styling, ghost styling, and shared-selection inclusion styling are three distinct states. A parameter can be included in the shared selection while not being the current tab, and a tab can be ghost-enabled while not being either. The ghost-enabled tab takes the yellow bottom rule; shared-selection inclusion takes the right-edge bar; the active tab takes the selected fill. Expose those distinctions to accessibility, not just color. Label focus is ordinary Qt Quick focus; Enter/Return activates the focused label; bare Space stays with window transport, and unhandled shared editing keys continue through the existing SongView policy exactly once. Tab/Shift+Tab traverse labels and leave the group normally. Do not steal arrow keys from existing timeline editing commands.

Left-click activates a parameter without clearing shared selection. Command-click (Qt ControlModifier) on a non-active tab toggles that tab's nodes as ineditable display-only ghosts in the shared plot, without activating it; command-click on the active tab collapses back to a single shown lane; plain-clicking a ghosted tab activates it and keeps the ghost waiting. Ghost toggling is view-local per SongTab, never persisted, and touches neither shared selection, the document, nor undo. Right-click activates that parameter and opens its existing parameter menu, preserving the menu's data/value-range operations. The label must own this event before the old gutter-outside-click selection clearing can run. Pointer/keyboard activation of the already active parameter does not cancel or rebuild anything unnecessarily.

### Node behavior and shared selection

Retain the existing `NodeLane`, `CCLaneAdapter`, Tempo adapter, `NodeLaneQuickPaint`, projection, gesture and batch-commit machinery. Logical lane availability and rendered lane availability are different concepts.

Only the active parameter supplies the plot's hit target, ordinary hover, transient content, origin phantom, and edit routing. User ghost-enabled secondary parameters additionally supply display-only static curve/node content beneath the active lane; they are never hit-testable. All logical lanes still participate in existing explicitly selected multi-lane operations. `collectSelectedNodeDrags`, shared range Copy/Cut/Delete/Nudge/Duplicate and existing clipboard targeting must not be filtered to the active tab merely because only that tab is painted.

Tab switching cancels unfinished pointer gestures and owned stale menu/prompt sessions before changing the active parameter. It clears obsolete hover/preview caches and then rebuilds the active scene. Cancellation writes nothing and must release any pointer grab/follow-scroll pause. Preserve foreign popup ownership. Store active selection by parameter/row identity, never by a transient `LaneHandle` index; resolve the current handle from the current logical-lane table.

A new band drag in the shared plot selects the active lane only. Existing broader selections remain broader until the user performs an explicit replacing selection operation. Simultaneous visual comparison returns as command-click ghost pinning (view-only); vertical band-drag selection across stacked rows disappears by design; the semantic operations on already selected multiple lanes do not.

The following must retain their current observable behavior:

- Origin phantom paint/hit/hover/drag and the source event's original tick; a phantom is not a duplicate insertion at the viewport edge.
- Explicit versus implicit tick-zero defaults, including Tempo lead-in and Volume/Pan projections.
- Normal node drag; modifier axis locks; stationary-delete/double-click guard; value prompts and point menus.
- Pencil, sweep and ramp behavior; fine/grid snapping; half-open interval boundaries; out-of-range value-axis growth.
- Multi-node/multi-lane selected edits; same-tick ordering; XCMD grouping; pitch-bend range/value conversion.
- One logical undo transaction per committed gesture and no mutation before commitment.
- Escape, ungrab, focus loss, deactivation, drawer hide, track/document/song replacement and SongTab lifetime cancellation.
- Hover, selection rings, transient previews, endpoint overflow clips, playhead/grid alignment and content/transient/hover invalidation separation.

### Presentation state and menus

Remove Add/Show/Hide lane presentation actions. All supported labels remain present after clearing or deleting their events. Retain existing parameter-local Copy, Paste, Clear, value-range controls, node menus and guarded destructive event deletion; do not conflate an old Delete CC lane command with Clear unless their source event semantics are proven identical.

Retire live stacked-lane sizing, empty-row registration, hiding and vertical automation scrolling from the UI. Preserve the existing EditorViewState fields, QSettings codec, remap implementation and their complete round-trip tests unchanged. The new selector does not consult old row visibility/height fields. No schema version, key deletion, migration, cleanup write or new persistence adapter is needed for this feature. Preserve laneRanges, outer section state and all music. This is retention of the existing storage contract, not a new compatibility facade for removed UI methods.

## Required proof

Existing semantic tests are the baseline, not expendable scaffolding. Change fixture activation/geometry, not expected musical outcomes, to adapt them to tabs. Delete tests whose sole contract is now-removed pinning, collapse, row-resize, Add/Hide or automation-scrollbar behavior; replace useful surface coverage with real label activation and one-plot assertions.
Fixture identity/coordinate queries remain pure: a probe for Pan does not activate Pan. Input scenarios explicitly activate their intended parameter before using its coordinates. Shared fixture capability must execute and pass an existing behavioral case before dependent migrations rely on it; a successful build or fixture initialization alone is not behavioral proof.

New permanent coverage is justified for five plausible new failure modes: switching preserves explicit multi-lane selection; a phantom still edits its source event after a parameter switch; a pending gesture/value prompt cannot commit to the new parameter; ghost toggling must not touch shared selection, the document, or undo; ghost secondary lanes must paint without gaining hit targets. Use existing QtTest classes and fixtures.

Do not add unit checks for Qt's button press/release lifecycle, generic focus traversal, accessibility action plumbing or GridLayout positioning. Keep a small existing-window integration check that native control activation reaches the correct Porydaw parameter and preserves shared selection/key routing. The phantom, node edits, transaction/cancellation and minimum-fit assertions remain application responsibilities and must not be removed.

Final proof must include all nine labels at the minimum drawer size and an enlarged UI font, every label's real activation, selected-track changes, an open-SongTab round trip, Tempo editing, and a horizontally scrolled phantom drag with undo on the native/default Quick backend. An unchanged-document snapshot must survive cycling through all labels. Do not claim native visual verification from an offscreen software capture.

## Evidence anchors

- `src/ui/editordrawer/cclanes.cpp`: current row/catalog composition and adapter semantics.
- `src/core/m4asemantics.cpp`, `src/core/xcmd.h`: supported controller classification and registered echo lanes.
- `src/ui/editordrawer/automationcanvas.cpp`: logical handles, geometry, rebuild cancellation and value-prompt lifetime.
- `src/ui/editordrawer/automationcanvas_input.cpp`: old gutter selection clearing, row resize and pointer routing.
- `src/ui/editordrawer/automationcanvas_gesture.cpp`: origin phantom and intentional multi-lane selected-node edits.
- `src/ui/songview/quick/automationquick.cpp`: static/transient/hover composition through NodeLaneQuickPaint.
- `src/ui/songview/editorselectionmodel.cpp`, `editkeyrouting.cpp`, `rangeedit.cpp`: authoritative shared selection and command semantics.
- `src/ui/editordrawer/drawersections.cpp`, `drawerchrome.*`, `editordrawer.cpp`, `src/ui/songview/quick/DrawerChromeLayer.qml`: actual automation scrollbar and drawer allocation ownership.
- `src/ui/editorviewstate.cpp`: legacy application-global presentation codec, not the outdated song-sidecar description in SPEC.md.
- `src/checks/checkcatalog.cpp`: exact harness filter names.

Source may change between planning and execution. Re-read affected symbols and refresh LSP references before each public-interface cutover; do not blindly apply recorded line numbers.
