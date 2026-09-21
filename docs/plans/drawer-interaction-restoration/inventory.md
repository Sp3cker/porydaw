# Historical drawer interaction inventory

Read-only scout evidence; accepted corrections in spec.md override initial findings. Baseline working tree at 8b55b65a9202366a69910da7499e0213c3e7d62c includes existing uncommitted work. Historical source is the parent of each named migration commit, not the migration itself.

# Automation Plot Editing Interaction Matrix (Historical vs. Current Working Tree)

Pre-Swift baseline commit for automation: `d2eb173e`.
Governing rules: `docs/plans/swift-backend-charter.md`.

---

## 1. Interaction Behavior Matrix

| Stable ID | Input / Modifiers / Context | Historical Outcome (Pre-d2eb173e Source) | Current Equivalent (Working Tree Source) | Status | Smallest Restoration Owner / Seam | Existing Check Coverage & Exact Command |
|---|---|---|---|---|---|---|
| `AUTO-PAN-01` | Middle Mouse Drag in plot area | Horizontal scroll: captures press point `m_pan.pos` and initial scroll `startHScroll`; drag updates `scrollX = startHScroll - delta.x()`; cursor is `ClosedHandCursor`. (`automationcanvas_input.cpp:166-179, 211-222, 302-308`) | Handled via Swift `dispatchPointerPress/Move/Release`: sets `panActive`, `cursorKind = closedHand`, calls `mutateCamera { setHScroll(scrollX - delta) }`. (`AutomationInteraction.swift:464-468, 475-487`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-WHL-01` | Shift + Mouse Wheel over plot | Horizontal scroll by wheel delta: `m_page.requestHorizontalScroll(scrollX - delta)`. (`automationcanvas_input.cpp:38-51`) | Delegated via QML `WheelHandler` to `gridModel.handleWheel(angleX, angleY, pixelX, pixelY, modifiers, ...)`. (`AutomationPage.qml:816-831`) | Preserved | QML: `AutomationPage.qml` | `editorqml/EditorQmlTests`<br>`./build/src/checks/editor_qml_tests` |
| `AUTO-WHL-02` | Mouse Wheel (no Shift) over plot | Horizontal time zoom anchored at mouse position X: `m_page.requestTimeZoom(input, input.position.x())`. (`automationcanvas_input.cpp:48-50`) | Delegated via QML `WheelHandler` to `gridModel.handleWheel(..., event.x, event.y)`. (`AutomationPage.qml:816-831`) | Preserved | QML: `AutomationPage.qml` | `editorqml/EditorQmlTests`<br>`./build/src/checks/editor_qml_tests` |
| `AUTO-NODE-01` | Left Click on Node (Stationary, travel < `activationDistance`, no Shift) | Stationary release deletes the clicked node! `PointDragGesture::release()` returns `StationaryDelete`. Commits `commitNodePointDeletes`. (`automationcanvas_input.cpp:338-343`, `nodelane/gesture.cpp:32-38`, `automationcanvas_gesture.cpp:280-286`) | Swift `releasePlot`: `.stationaryDelete` commits `AutomationNodeResolver.deletions`. (`AutomationInteraction.swift:186-191`, `AutomationNodeTransactions.swift:29-34`) | Preserved | Swift: `AutomationInteraction.swift` | `automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-NODE-02` | Shift + Left Click on Node (Stationary) | Axis-lock armed on press (`deleteStationary = false`). Release without drag is a no-op (`PointDragRelease::NoOp`). Node is preserved. (`automationcanvas_gesture.cpp:391`, `nodelane/gesture.cpp:35-37`) | Swift `pressPlot`: `deleteOnStationary = !modifiers.shift`. On release without move, release is `.noOp`, no commit. (`AutomationInteraction.swift:130, 206`) | Preserved | Swift: `AutomationInteraction.swift` | `automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-NODE-03` | Left Drag on Single Node (Unselected) | Drags single node. Clamps tick $\ge 0$ and value to `[minimum, maximum]`. Live preview updates. Commits `edit automation points`. (`automationcanvas_input.cpp:113-118`, `nodelane/gesture.cpp:180-210`, `automationcanvas_gesture.cpp:286-290`) | Swift `AutomationNodeDragTransaction.single`: moves node, clamps to parameter range. Commits `AutomationNodeResolver.moves`. (`AutomationInteraction.swift:132-136, 192-195`) | Preserved | Swift: `AutomationNodeTransactions.swift` | `automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-NODE-04` | Left Drag on Node inside Active Time Selection | Drags ALL nodes covered by selection across ALL active/covered lanes by shared $\Delta t, \Delta v$; clamps $\Delta t$ at tick 0; on release shifts time selection by $\Delta t$. (`automationcanvas_gesture.cpp:360-385, 287-301`) | Swift `AutomationNodeDragTransaction.selection` collects targets across lanes, BUT `releasePlot` packs all moves into single `LaneMoves(facts, transaction.moves)` where `facts.parameter` is active only! Secondary lanes either ignored or misattributed. | Missing / Changed | Swift: `AutomationInteraction.swift:192-195` (partition `LaneMoves` by parameter) | Gaps in multi-lane drag coverage. Deferred: `src/checks/automation/automationselection.cpp` (`multiLaneSelectionDragPreservesTempoAndCcOrder`) |
| `AUTO-NODE-05` | Shift + Left Drag on Node (Axis Lock) | Dynamically locks travel to dominant axis: Time axis if $\lvert\Delta x\rvert \ge \lvert\Delta y\rvert$, Value axis if $\lvert\Delta y\rvert > \lvert\Delta x\rvert$. Cursor switches to `SizeHorCursor` / `SizeVerCursor`. (`nodelane/gesture.cpp:304-320`, `automationcanvas_gesture.cpp:273-276`) | Swift `AutomationPointDrag.update` evaluates axis lock and sets `axisLock`; `AutomationNodeDragTransaction.update` applies axis lock. Cursor kinds published to QML. (`AutomationTransactions.swift:65-72`, `AutomationNodeTransactions.swift:135-144`) | Preserved | Swift: `AutomationTransactions.swift` | `swiftcore/AutomationPage::hitGeometry`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-NODE-06` | Alt + Left Drag on Node (Fine Grid) | Ticks snap to fine grid (clocks). (`automationcanvas_input.cpp:110-112`, `automationcanvas_gesture.cpp:177`) | Swift `modifiers.fine` maps `Qt.AltModifier` and snaps using fine camera lattice. (`AutomationInteraction.swift:23-28, 381-388`) | Preserved | Swift: `AutomationInteraction.swift` | `automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-NODE-07` | Ctrl + Left Drag on Node (Value Snap) | Snaps value to neutral (for Pan: neutral 64 snap within `neutralSnapRadius = 6px`). (`automationcanvas_gesture.cpp:202-212`) | Swift `facts.metadata.snappedValue` snaps value to neutral within `neutralSnapRadius`. (`AutomationProjection.swift:156-166`) | Preserved | Swift: `AutomationProjection.swift` | `automation-domain/AutomationDomainTest::panNeutralSnap`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PHAN-01` | Left Drag on Origin Phantom (Tick 0 Default Node) | Hits tick 0 projected default node; drags value while locking tick to 0; on release promotes projected default into written event at tick 0. (`automationcanvas_gesture.cpp:52-85, 200-215, 303-306`) | Swift `AutomationPhantomDragTransaction`: locks tick to 0; on release commits `AutomationNodeResolver.moves` which promotes projected tick zero. (`AutomationInteraction.swift:138-143, 201-205`, `AutomationEdits.swift:191-235`) | Preserved | Swift: `AutomationNodeTransactions.swift` | `automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SWP-01` | Left Click in Empty Plot Space (Stationary, no drag) | Sets timeline edit cursor to clicked tick (`m_page.commitEditCursor(snapTick(rawTick)))`. Does NOT insert a node. (`automationcanvas_gesture.cpp:308-311`) | Swift `releasePlot`: if `.drag` and `!slopExceeded`, sets `session.editCursor = projection.tick(atX: pressX, fine: false)`. (`AutomationInteraction.swift:211-213`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SWP-02` | Left Drag in Empty Plot Space (Sweep Drag, no Shift) | Drag sweep: fills lattice ticks between motion samples with held staircase values; on finish restores original trailing held value 1 lattice step past release. (`nodelane/gesture.h:130-150`, `automationcanvas_gesture.cpp:312-322`) | Swift `AutomationSweepTransaction`: records intermediate lattice points; finish computes trailing held boundary; commits `writeLane` / `editTempo`. (`AutomationDrawingTransactions.swift:40-100`, `AutomationEdits.swift:405-430`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish`, `::sweepFinishRestoresTrailingHeldValue`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SWP-03` | Shift + Left Drag in Empty Space (Ramp Sweep) | Ramp sweep: linear ramp interpolation between anchor and release point across grid ticks; on finish restores trailing held value. (`nodelane/gesture.h:132, nodelane/gesture.cpp:240-270`) | Swift `AutomationSweepTransaction` with `mode = .ramp`: linearly interpolates values from anchor to release; restores trailing held value. (`AutomationDrawingTransactions.swift:65-95`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish`, `::sweepFinishRestoresTrailingHeldValue`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SWP-04` | Alt + Left Drag in Empty Space (Fine Sweep) | Sweeps points quantized to fine grid (clocks). (`automationcanvas_gesture.cpp:177, 312`) | Swift `modifiers.fine` passes fine grid setting to `finish(fine:projection:)`. (`AutomationInteraction.swift:213-215`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-01` | Left Click on Node in Pencil Mode | Drags hit node if within cell bounds, identical to node drag. (`automationcanvas_input.cpp:78-95`) | Swift `pressPlot`: hits node in `lane.hitTest`, enters `.node` drag transaction. (`AutomationInteraction.swift:127-137`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::hitGeometry`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-02` | Delete / Backspace Key while Hovering Node in Pencil Mode | Deletes hovered node immediately if note selection is empty and time selection is inactive! Commits `commitNodePointDeletes`. (`automationcanvas_input.cpp:428-456`) | NOT IMPLEMENTED in `AutomationPage.qml` or `AutomationPage.swift`. `Keys.onPressed` on `plot` does not handle Delete/Backspace; no hover-delete route in Swift. | Missing | QML: `AutomationPage.qml` `Keys.onDeletePressed`, Swift: `deleteHoveredNode()` | Deferred: `src/checks/automation/automationpencil.cpp` (`pencilClickOnExcursionNodeDeletesExcursion`) |
| `AUTO-PEN-03` | Left Drag in Pencil Mode (Default / Snapped) | Snapped step drawing: horizontal bars across grid cells; vertical slop suppression ($dx > dy \times 4$) avoids vertical jitter; restores endpoint held value. (`automationcanvas_gesture.cpp:250-265`, `nodelane/gesture.cpp:322-350`) | Swift `AutomationPencilTransaction.applySnappedSegment`: suppresses vertical jitter within `verticalSlopDistance`; restores endpoint. (`AutomationDrawingTransactions.swift:150-220`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-04` | Ctrl + Left Drag in Pencil Mode (Freehand) | Freehand drawing: unsnapped clock-quantized points; bypasses vertical slop. (`automationcanvas_gesture.cpp:258-261`) | Swift `freehand = modifiers.snapValue && !modifiers.shift`; calls `applyFreehandSegment`. (`AutomationInteraction.swift:361-375`, `AutomationDrawingTransactions.swift:222-250`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-05` | Shift + Left Drag in Pencil Mode (Value Lock) | Locks value dimension to initial press sample value. (`automationcanvas_gesture.cpp:261`) | Swift `locking = modifiers.shift && !modifiers.snapValue`; locks continuous value. (`AutomationInteraction.swift:362-368`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-06` | Single Click on Excursion Node in Pencil Mode | Deletes excursion node if clicking at default/held value. (`nodelane/pencilgesture.cpp:110-140`) | Swift `AutomationPencilTransaction`: redundant click at held value resolves to deletion or no-op. (`AutomationDrawingTransactions.swift:200-215`) | Preserved | Swift: `AutomationDrawingTransactions.swift` | `automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PEN-07` | Pencil Tool Cursor | Bundled pixmap pencil cursor `pencilCursor()`. (`automationcanvas_input.cpp:17-30`) | QML uses standard cross cursor `Qt.CrossCursor` fallback (noted in `AutomationPage.qml:20-25`). | Changed | QML: `AutomationPage.qml` `cursorFor(1)` | Visual only; verified via `cursorKind` property |
| `AUTO-SEL-01` | Right Mouse Drag $\ge$ `startDragDistance` (Band Selection) | Extends time selection `[startTick, endTick)` horizontally; extends across compatible lanes vertically (`laneStart..laneEnd`). (`automationcanvas_input.cpp:224-245`, `nodelane/gesture.cpp:45-80`) | Swift `AutomationRangeBand` tracks `anchorTick` and `currentTick` horizontally, but does NOT track vertical lane range across multiple rows in plot. | Changed | Swift: `AutomationInteraction.swift:79-88` (`AutomationRangeBand`) | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SEL-02` | Right Mouse Drag Released with Zero Snapped Width | Clears active time selection if one was active. (`automationcanvas_input.cpp:322-330`) | Swift `releaseBand`: if `last > first` selects range; if `last == first` does not explicitly clear selection if outside. | Missing | Swift: `AutomationInteraction.swift:233-248` | Gaps in zero-width release check |
| `AUTO-SEL-03` | Left Click Outside Active Time Selection | Clears active time selection immediately. (`automationcanvas_input.cpp:53-76, 180-184`) | Swift `clearSelectionIfPressIsOutside(x:)` checks `selectionContains(tick:facts:)` and calls `applyTimeSelection(nil)`. (`AutomationInteraction.swift:257-270`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-SEL-04` | Left Click Inside Active Time Selection (Empty Space) | Initiates sweep or node drag without clearing selection. (`automationcanvas_input.cpp:71-76`) | Swift `selectionContains` returns true, keeps selection intact, starts sweep/drag. (`AutomationInteraction.swift:260-270`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-MENU-01` | Stationary Right Click on Node | Opens Node Context Menu (`SetValue = 1`, `DeleteNode = 2`). (`automationcanvas_pointmenu.cpp:45-90`) | Swift `openPointMenu`: publishes `menuOpen = true`, rows `[SetValue, Delete]`. Rendered by `AutomationMenu.qml`. (`AutomationModal.swift:132-143`) | Preserved | Swift: `AutomationModal.swift`, QML: `AutomationMenu.qml` | `swiftcore/AutomationPage::promptTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-MENU-02` | Node Menu "Delete" on Projected Tick 0 Default Node | "Delete" menu item is disabled (`del.enabled = writtenAtTick`), because default node has no written event. (`automationcanvas_pointmenu.cpp:88-102`) | Swift `menuRows`: `let written = !facts.snapshot.occurrences(at: tick).isEmpty; text: "Delete", enabled: written`. (`AutomationModal.swift:135-141`) | Preserved | Swift: `AutomationModal.swift` | `swiftcore/AutomationPage::promptTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-MENU-03` | Outside Right Click while Node Menu is Open | Retargets menu immediately to node under the new click (`m_nodeMenuHost->outsideRightPressed` -> `retargetNodeMenu`). (`automationcanvas_pointmenu.cpp:40-42, 170-205`) | Swift `dispatchPointerPress`: clicks while menu is open cancel menu first, do not retarget on same press. | Changed | Swift: `AutomationInteraction.swift` | Deferred: `src/checks/automation/automationpointmenus.cpp` (`outsideRightClickDismissesPointMenu`) |
| `AUTO-MENU-04` | Stationary Right Click inside Time Selection | Opens Lane / Range Context Menu (Copy, Cut, Paste, Delete, Clear Selection). (`automationcanvas_menu.cpp:115-140`) | Swift `openRangeMenu`: publishes `menuOpen = true`, rows for range selection. (`AutomationModal.swift:165-177`) | Preserved | Swift: `AutomationModal.swift`, QML: `AutomationMenu.qml` | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-MENU-05` | Lane Menu Actions (Whole Lane) | Copy CC lane, Paste CC lane (replace), Clear events, Delete automation events. (`automationcanvas_menu.cpp:45-56, 140-165`) | Swift `menuRows(for: .lane)`: Copy, Paste, Clear, Delete automation events. (`AutomationModal.swift:144-164`) | Preserved | Swift: `AutomationModal.swift` | `swiftcore/AutomationPage::rangeEditAndClipboard`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-MENU-06` | Lane Menu CC ValueRange Submenu | Submenu with Auto, 16, 32, 64, 127 to rescale lane display range (`CanvasMenuAction::ValueRange`). (`automationcanvas_menu.cpp:165-215`) | OMITTED in Swift `AutomationMenuAction` and `AutomationMenu.qml` (no submenu support in rewritten menu). | Missing | Swift: `AutomationModal.swift`, QML: `QuickMenuPanel.qml` / `AutomationMenu.qml` | Deferred: `src/checks/automation/automationmenus.cpp` (`laneMenuValueRangeSubmenuPickRescalesAndCloses`) |
| `AUTO-MENU-07` | Stationary Right Click in Empty Space (Outside Selection) | No-op; consumes event, opens nothing, clears locked hover. (`automationcanvas_input.cpp:333-350`) | Swift `releaseBand`: does not open point menu or range menu, band is cleared. (`AutomationInteraction.swift:239-247`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PRMT-01` | Value Prompt Open ("Set Value") | Opens prompt card; text input prefilled with current value in prompt domain (e.g. BPM or 0-127); selects text; bounds `[minimum, maximum]`. (`automationcanvas.cpp:483-494`, `DrawerChromeLayer.qml:280-330`) | Swift `openCapturedPrompt`: publishes `promptOpen = true`, `promptKind = value`, draft, bounds. Rendered in `AutomationPrompt.qml`. (`AutomationModal.swift:250-290`) | Preserved | Swift: `AutomationModal.swift`, QML: `AutomationPrompt.qml` | `swiftcore/AutomationPage::promptTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PRMT-02` | Value Prompt Accept (Enter / OK) | Revalidates target epoch and document revision; converts displayed value to stored value; commits single atomic move / write. (`automationcanvas.cpp:509-545`) | Swift `acceptCapturedPromptDraft`: checks revision guard; commits `LaneMoves` / `TempoMoves`. (`AutomationModal.swift:310-350`) | Preserved | Swift: `AutomationModal.swift` | `swiftcore/AutomationPage::promptTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PRMT-03` | Value Prompt Cancel (Escape / Outside Click) | Discards draft, clears prompt, restores focus, document untouched. (`automationcanvas.cpp:560-565`, `DrawerChromeLayer.qml:287-292`) | Swift `cancelCapturedPrompt`: clears prompt, publishes state, restores focus. (`AutomationModal.swift:352-360`, `AutomationPage.qml:210`) | Preserved | Swift: `AutomationModal.swift`, QML: `AutomationPrompt.qml` | `swiftcore/AutomationPage::promptTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PRMT-04` | CC Delete Confirmation Open | Triggered by "Delete automation events"; captures written event count; displays message confirming event count and parameter title. (`automationcanvas_deleteprompt.cpp:30-75`, `CcDeleteConfirm.qml:1-60`) | Swift `openLaneDeleteConfirmation`: publishes `promptKind = confirmLaneDelete`, count, title, message. (`AutomationModal.swift:180-200`) | Preserved | Swift: `AutomationModal.swift`, QML: `AutomationPrompt.qml` | `swiftcore/AutomationPage::deleteTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-PRMT-05` | CC Delete Confirmation Initial Focus Safety | CANCEL button holds initial focus (`cancelButton.forceActiveFocus`) so accidental Return cancels. (`CcDeleteConfirm.qml:25-30`) | REGRESSION: `AutomationPrompt.qml:83-84` gives initial focus to `accept` (Delete) button instead of `cancel`! (`takeFocus: if (promptRoot.confirming) accept.forceActiveFocus(...)`) | Changed / Unsafe | QML: `AutomationPrompt.qml` (or restore `CcDeleteConfirm.qml`) | Safety gap in `AutomationPrompt.qml` |
| `AUTO-PRMT-06` | CC Delete Confirmation Accept | Deletes all written events for CC lane; parameter row remains. Commits single undo point. (`automationcanvas_deleteprompt.cpp:125-160`) | Swift `acceptLaneDeleteConfirmation`: commits `AutomationNodeResolver.deletions` for all written events. (`AutomationModal.swift:370-390`) | Preserved | Swift: `AutomationModal.swift` | `swiftcore/AutomationPage::deleteTransactions`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-DBL-01` | Double Click on Node | Consumed, returns true, inserts nothing, no-op. (`automationcanvas_input.cpp:396-402`) | Swift `dispatchPointerDoubleClick`: cancels in-flight gestures, clears preview, returns true. (`AutomationInteraction.swift:561-570`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-DBL-02` | Double Click in Empty Plot Space | Consumed, inserts nothing, cancels in-flight gesture and clears preview. (`automationcanvas_input.cpp:403-417`) | Swift `dispatchPointerDoubleClick`: cancels gesture, clears preview draft. (`AutomationInteraction.swift:561-570`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-KEY-01` | Space Key over Plot Area | Never consumed by plot; passes through to window transport (play/pause). (`automationcanvas_input.cpp:420-425`, `AutomationPage.qml:17-19`) | QML `plotInput` has no shortcut override for Space; `Keys.onEscapePressed` handles Escape only. Space reaches host transport. (`AutomationPage.qml:209-210`) | Preserved | QML: `AutomationPage.qml` | `editorqml/EditorQmlTests`<br>`./build/src/checks/editor_qml_tests` |
| `AUTO-KEY-02` | Escape Key Routing & Priority | Priority order: cancels open prompt $\to$ menu $\to$ live gesture (node/sweep/pencil) $\to$ band selection $\to$ pan $\to$ tap tempo $\to$ clears hover $\to$ passes to window. (`automationcanvas_input.cpp:460-475`, `automationcanvas.cpp:445-455`) | Swift `dispatchEscape()`: strict hierarchical order matching historical precedence exactly. (`AutomationInteraction.swift:580-590`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-CAN-01` | Stale Document Revision / Mismatch on Commit | Compares `document.revision()` against `expectedRevision` before commit; if mismatched, aborts commit without mutation. (`automationcanvas_gesture.cpp:45-50, 130-135, 275-280`) | Swift `AutomationCommit`: `guard document.revision == edit.revision else { return false }`. Stale plans discard cleanly. (`AutomationEdits.swift:408, 434`) | Preserved | Swift: `AutomationEdits.swift` | `swiftcore/AutomationPage::pointIdentityAndStaleness`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-CAN-02` | Section Hidden / Window Deactivation | `inputCancelled(Hidden)`: cancels interaction, clears hover, dismisses menu/prompt without stealing focus. (`automationcanvas_input.cpp:465-475`) | Swift `cancelSectionInteraction()` / `cancelAllInteractions()`: cancels gesture, band, pan, menu, prompt, draft, hover. (`AutomationInteraction.swift:592-610`) | Preserved | Swift: `AutomationInteraction.swift` | `swiftcore/AutomationPage::cancellationAndNoOps`<br>`./build/src/checks/porydaw_checks` |
| `AUTO-UNDO-01` | History & Undo/Redo Integration | Every completed interaction produces exactly one atomic document transaction with specific undo label. Undo rolls back entire stroke/move/delete. (`automationcanvas_gesture.cpp:115-125`) | Swift `AutomationCommit` routes through `session.document.applyRangeEdit` or `writeLane`, creating single undo checkpoint. Undo/redo verified. (`AutomationEdits.swift:405-450`) | Preserved | Swift: `AutomationEdits.swift` | `swiftcore/AutomationPage::historyUndoRedo`<br>`./build/src/checks/porydaw_checks` |

---

## 2. Source QML Recovery Recommendations

1. **CC Delete Confirmation Prompt (`CcDeleteConfirm.qml`)**:
   - **Historical File**: `src/ui/songview/quick/CcDeleteConfirm.qml` (intact in repo!).
   - **Recommendation**: Recover original `CcDeleteConfirm.qml` directly. The current rewritten `AutomationPrompt.qml` combines value prompt and delete confirmation into a single component, but introduces an unsafe focus inversion (`accept` button receives initial focus instead of `cancelButton`).
   - **Required Bridge Properties**: Bind to `bridge.ccDeletePromptTitle`, `bridge.ccDeletePromptMessage`, `bridge.ccDeletePromptAppearance`, `bridge.acceptCcDeletePrompt()`, and `bridge.cancelCcDeletePrompt()`.

2. **Value Prompt Card (`DrawerChromeLayer.qml`'s `drawerValuePrompt`)**:
   - **Historical Location**: `src/ui/songview/quick/DrawerChromeLayer.qml:280-395`.
   - **Recommendation**: Extract into standalone `AutomationValuePrompt.qml` based on `PromptCard.qml`. Provides proper text selection on open (`valuePromptInput.selectAll()`), numeric validation, proper text input styling, and theme metrics.

3. **Context Menus (`QuickMenuPanel.qml`)**:
   - **Historical File**: `src/ui/songview/quick/QuickMenuPanel.qml` (intact in repo!).
   - **Recommendation**: Discard the hardcoded, flat `AutomationMenu.qml` and restore `QuickMenuPanel.qml` via `QuickMenuHost`/`QuickPopupSession` or adapt it to receive Swift-bridged hierarchical menu models so submenus (`ValueRange`) and keyboard navigation operate cleanly.

4. **Plot Surface (`AutomationPage.qml`)**:
   - **Status**: Historically, the plot had NO dedicated QML file (it was rendered via C++ `TimelineQuickScene` / `automationquick.cpp`). Therefore, `AutomationPage.qml` is the correct destination QML view, but requires:
     - Addition of `Keys.onPressed` to route Delete/Backspace to `pageModel.deleteHoveredNode()`.
     - Correction of modal initial focus.

---

## 3. Differences Requiring Swift Backend Changes

1. **Multi-Lane Selection Drag Partitioning (`AUTO-NODE-04`)**:
   - **Bug**: `AutomationInteraction.swift:192-195` constructs `AutomationNodeResolver.moves([AutomationNodeResolver.LaneMoves(facts, transaction.moves)])` with only `facts` (which binds solely to `activeParameter`).
   - **Fix**: Group `transaction.moves` by parameter and create a `LaneMoves` entry for each covered parameter with that lane's own snapshot/facts.
2. **Pencil Hover Delete (`AUTO-PEN-02`)**:
   - **Bug**: No method exists on `AutomationPage` to delete the hovered node via keyboard shortcut.
   - **Fix**: Add `@discardableResult public func deleteHoveredNode() -> Bool` on `AutomationPage` which commits deletion of `hover.point` if `isPencilMode && hover.hasPoint && !hasTimeSelection`.
3. **CC Value Range Submenu (`AUTO-MENU-06`)**:
   - **Bug**: `AutomationMenuAction` lacks enum entries and handlers for `RangeAuto`, `Range16`, `Range32`, `Range64`, `Range127`.
   - **Fix**: Add value range actions to `AutomationMenuAction` and dispatch display range updates to the lane view model.
4. **Band Selection Zero-Width Release (`AUTO-SEL-02`)**:
   - **Bug**: When band selection completes with `anchorTick == currentTick` (clicked or zero travel), it does not clear an existing time selection if clicked outside.
   - **Fix**: In `releaseBand`, if `last == first`, check if click was outside selection; if so, clear selection.
5. **Node Menu Outside Right-Click Retargeting (`AUTO-MENU-03`)**:
   - **Bug**: Swift dismisses the menu on outside click without retargeting the new node in the same event.
   - **Fix**: Re-evaluate node hit on outside right-press and open the menu for the newly targeted node immediately.


Exhaustive historical-to-current inventory of editor drawer interactions, state transitions, keyboard routing, and recovery recommendations.

### 1. Behavior Matrix

| ID | Input / Modifiers / Context | Historical Outcome & Source | Current Equivalent & Source | Status | Smallest Restoration Seam / Owner | Existing Check Coverage |
|---|---|---|---|---|---|---|
| DRW-CONT-01 | Left Click / Enter on Section Toggle | Toggles section visibility; if opened, becomes active page and requests focus; if closed while focused, focus transfers to next visible section or roll (`drawerchrome.cpp:258`, `editordrawer.cpp:315`). | `EditorDrawerPresenter.toggleSection(kind:drawerOwnsFocus:)` (`EditorDrawer.swift:150`, `EditorDrawer.qml:283`). | Preserved | `EditorDrawerLayout.toggleSection` | `tst_EditorDrawer.qml:200-350`, `EditorDrawerChecks.swift:focusID` |
| DRW-CONT-02 | Click on Blank Chrome Bar | Steals focus from timeline/editor without activating any command (`drawerchrome.cpp:342`, `DrawerChromeLayer.qml: drawerBarInput`). | None; `drawerBar` has no input handler (`EditorDrawer.qml:395`). | Missing | Add `MouseArea` to `drawerBar` in `EditorDrawer.qml` requesting focus | `tst_EditorDrawer.qml` |
| DRW-CONT-03 | Velocity Detent Button Click / Return | Toggles PSG velocity detents (`drawerchrome.cpp:273`, `DrawerChromeLayer.qml: drawerDetent`); visible only when PSG voice active. | Relocated to ad-hoc button inside `VelocityPage.qml:224` (`velocityDetent`); missing from drawer bar. | Changed | Add detent state to `EditorDrawerLayout`/`EditorDrawerPresenter` and restore `drawerDetent` in `EditorDrawer.qml` | `tst_EditorDrawer.qml:1892-1906`, `VelocityPageChecks.swift` |
| DRW-CONT-04 | Left Drag on Resize Handle | Dynamically resizes section body; clamps to minBody and host height; spills VoiceChanges into Automation if exceeded (`drawerchrome.cpp:331`, `drawersections.cpp:230`). | `EditorDrawerPresenter.applyResize(kind:delta:)` (`EditorDrawerLayout.swift:513`, `EditorDrawer.qml:262`). | Preserved | `EditorDrawerLayout.applyResize` | `tst_EditorDrawer.qml:600-800`, `EditorDrawerChecks.swift:resizeID` |
| DRW-CONT-05 | Up / Down Arrow on Focused Handle | Adjusts height by +/- step (`layout::Space::Two`); Left/Right consumed no-op (`DrawerChromeLayer.qml:38-51`). | `handle.adjust(1)` / `handle.adjust(-1)` (`EditorDrawer.qml:220-229`). Left/Right consumed. | Preserved | `EditorDrawer.qml` | `tst_EditorDrawer.qml:820-860` |
| DRW-CONT-06 | Host Resize / Window Bounds Change | Recalculates heights under host clamp: VoiceChanges prioritized, Automation preserved, Velocity remainder (`drawersections.cpp:328`). | `EditorDrawerLayout.configureHost` (`EditorDrawerLayout.swift:680-720`). | Preserved | `EditorDrawerLayout` | `EditorDrawerChecks.swift:clampID` |
| AUTO-TAB-01 | Left Click / Return on Parameter Tab | Activates selected parameter; updates active lane; invalidates hover; scrolls tab into view minimally (`automationcanvas_tabs.cpp:180`, `AutomationTabs.qml:103`). | `AutomationPage.activateParameter(index)` (`AutomationPage.swift:590`, `AutomationPage.qml:274`). | Preserved | `AutomationPage.activateParameter` | `automationselection.cpp`, `tst_EditorDrawer.qml` |
| AUTO-TAB-02 | Ctrl + Left Click on Inactive Parameter Tab | Toggles ghost lane pin if lane has written events (`automationcanvas_tabs.cpp:106,198`). | `AutomationPage.toggleGhostParameter(index)` (`AutomationPage.swift:626`, `AutomationPage.qml:283`). | Preserved | `AutomationPage.toggleGhostParameter` | `automationstroke.cpp`, `AutomationPageChecks.swift` |
| AUTO-TAB-03 | Ctrl + Left Click on Active Parameter Tab | Clears all ghost parameters (`automationcanvas_tabs.cpp:125`). | Clears `ghostPins` if `index == activeParameterIndex` (`AutomationPage.swift:631`). | Preserved | `AutomationPage.toggleGhostParameter` | `AutomationPageChecks.swift` |
| AUTO-TAB-04 | Right Click on Parameter Tab | Opens parameter context menu for that lane at click position (`automationcanvas_tabs.cpp:211`, `AutomationTabs.qml:116`). | `AutomationPage.openParameterMenu(index:x:y:)` (`AutomationPage.swift:645`, `AutomationPage.qml:370`). | Preserved | `AutomationPage.openParameterMenu` | `automationpointmenus.cpp` |
| AUTO-TAB-05 | Tab Visual Feedback (Active, Events, Shared Selection, Ghost) | Active background, event pip, selection inclusion vertical stripe, ghost bottom edge line (`AutomationTabs.qml:301-347`). | Mirrored in `AutomationPage.qml:320-370` using `AutomationTabHandle` properties (`active`, `ghosted`, `included`, `eventCount`). | Preserved | `AutomationTabs.qml` / `AutomationTabHandle` | `automation-tabs` visual fixtures |
| AUTO-TAP-01 | Inline Tap Button Press / Return on Tempo Tab | Accumulates tap interval; starts/restarts idle commit timer; updates inline draft readout (`automationcanvas_taptempo.cpp:18`, `AutomationTabs.qml:81`). | Replicated inline in `AutomationPage.qml:454` and `AutomationTapTempo.swift:80`. | Preserved | `AutomationTapTempo.swift` | `automationtaptempo.cpp:429` |
| AUTO-TAP-02 | Tap Tempo Idle Timeout | Commits draft BPM as tick-0 TempoEditCommand if draft is valid and differs from existing tick-0 tempo (`automationcanvas_taptempo.cpp:37`). | `AutomationPage.commitTapTempoAfterIdle()` (`AutomationTapTempo.swift:103`). | Preserved | `AutomationTapTempo.swift` | `automationtaptempo.cpp:90-150` |
| AUTO-TAP-03 | Floating Modal Tap Tempo Dialog | Did NOT exist historically (historical was purely inline on the Tempo tab). | Introduced as `TapTempo.qml` in current tree (`AutomationPage.qml:895`). | Changed (Superfluous) | Remove `TapTempo.qml` floating modal; retain inline tap button on tab. | `tst_EditorDrawer.qml` |
| KB-ROUT-01 | Bare Space Key across all drawer surfaces | Bare Space passes through to window transport (Play/Pause); NOT claimed by toggles, handles, tabs, or tap tempo (`DrawerChromeLayer.qml:132`, `AutomationTabs.qml:89`). | Preserved via `Keys.onShortcutOverride` claiming only Return/Enter in `EditorDrawer.qml:240,295`, `AutomationPage.qml:292,488`. | Preserved | QML ShortcutOverride policy | `tst_EditorDrawer.qml:40-70` |
| KB-ROUT-02 | Left / Right Arrows on Resize Grip | Consumed as no-ops to prevent unowned song-edit / timeline scrub arrows from leaking (`DrawerChromeLayer.qml:47`, `EditorDrawer.qml:237`). | Preserved in `EditorDrawer.qml:237-238`. | Preserved | `EditorDrawer.qml` | `tst_EditorDrawer.qml` |
| KB-ROUT-03 | Escape Key Handling | Closes prompt / menu / tap-tempo session without committing; passes to window when no modal is active (`DrawerChromeLayer.qml:280`, `AutomationPrompt.qml:145`, `AutomationPage.qml:165`). | Handled by `AutomationPage.handleEscape()` (`AutomationPage.swift:650`, `AutomationPrompt.qml:145`). | Preserved | `AutomationPage.handleEscape` | `tst_EditorDrawer.qml` |

### 2. Source QML Recovery Recommendations
- `AutomationTabs.qml`: Can be fully restored and reused in place of the ad-hoc `Repeater` in `AutomationPage.qml`. Rebind `canvas.parameterLabels` -> `page.pageModel.tabs`, `canvas.activeParameter` -> `page.pageModel.activeParameterIndex`, and `canvas.tapTempo` -> `page.pageModel.tapTempoTap()`.
- `DrawerChromeLayer.qml` vs `EditorDrawer.qml`:
  - `EditorDrawer.qml` modular architecture (Loader per section, modalLayer) is cleaner than `DrawerChromeLayer.qml`'s monolithic overlay, BUT it missed two crucial features:
    1. The blank chrome bar click sink (`drawerBarInput`) must be added to `drawerBar` to absorb focus.
    2. The velocity detents button (`drawerDetent`) belongs in the drawer container chrome bar, not floating inside the velocity ruler in `VelocityPage.qml`.
- `TapTempo.qml`:
  - Should be retired. Historical pre-Swift implementation was purely an inline control within the Tempo parameter tab (`automationTempoTapButton` + `automationTempoTapDraft`). The floating panel introduced in Task 6b causes visual redundancy and diverges from original UX.

# Historical-to-Current Editor Drawer Interaction Inventory: Velocity & Voice Changes

## 1. Exhaustive Interaction & Behavior Matrix

| Stable ID | Input / Modifiers / Context | Historical Outcome & Source Revision/Path/Symbol | Current Equivalent & Source Path/Symbol | Status | Smallest Restoration Owner / Seam | Existing Check Coverage & Exact Command |
|---|---|---|---|---|---|---|
| `VEL-CLICK-RULER` | Left click in ruler (`inRuler`), No modifier | Sets velocity of all `selectedNotes()` to clicked ruler tick/level (1–127). Single doc transaction `setVelocities`. <br>`pre-4b0d0738` `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp:200-217` `VelocityArea::pointerPress` | Sets velocity of `selectedTrackNotes()`. <br>`src/swift/app/drawer/velocity/VelocityPage.swift:420-435` `VelocityPage.pointerPress(.ruler)`, `VelocityPage.qml:248-261` `rulerInput` | **Preserved** | `VelocityPage.swift:rulerClickSet` | `checks/drawerpresentation/velocity.cpp:chromeAndContinuousAxis`<br>`checks/swiftcore/VelocityPageChecks.swift:axisID`<br>`tst_EditorDrawer.qml:test_productionVelocityPageMountsAndRenders`<br>Cmd: `ctest -R swiftcore` / `editor_qml_tests` |
| `VEL-CLICK-RULER-UNLOCK` | Left click in ruler + Ctrl (detent unlock) | Sets exact continuous velocity even in intrinsic PSG mode. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:204` `detentsUnlocked` | Sets unquantized velocity via `axis.yToVelocity`. <br>`VelocityPage.swift:422`, `detentsUnlocked(modifiers:allowShift:)` | **Preserved** | `VelocityPage.swift` | `checks/velocity/velocitydetentdragging.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:psgID`<br>Cmd: `ctest -R swiftcore` |
| `VEL-DETENT-TOGGLE` | Click on Detent button | Toggles continuous/quantized PSG detents. In C++ drawer chrome bar; cancels active interaction and rebuilds axis. <br>`pre-4b0d0738` `velocityarea.cpp:setUseDetents`, `drawerchrome.cpp` | Toggle button rendered directly in ruler column QML, calls `pageModel.toggleDetents()`. <br>`VelocityPage.qml:198-245` (`velocityDetent`), `VelocityPage.swift:718-727` | **Changed** (Moved from drawer bar chrome into ruler QML column) | `EditorDrawer.qml` vs `VelocityPage.qml` | `checks/drawerpresentation/velocity.cpp:psgRenderingAndDetentToggle`<br>`checks/swiftcore/VelocityPageChecks.swift:psgID`<br>Cmd: `ctest -R swiftcore` |
| `VEL-NOTE-SELECT-SINGLE` | Left click on note handle, no Ctrl, not selected | Deselects prior notes, selects clicked note. Freezes note snapshot for drag. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:286-288` | Clears selection, selects clicked note, prepares `VelocityGestureState`. <br>`VelocityPage.swift:458-466`, `VelocityPage.qml:441-450` | **Preserved** | `VelocityPage.swift:pointerPress` | `checks/velocity/velocityselection.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:transactionID`<br>`tst_EditorDrawer.qml:test_productionVelocityPointerEdit` |
| `VEL-NOTE-SELECT-ADD` | Left click on unselected note handle + Ctrl | Adds note to existing selection. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:281-285` | Extends selection set in `DocumentSession`. <br>`VelocityPage.swift:454-457` | **Preserved** | `VelocityPage.swift:pointerPress` | `checks/velocity/velocityselection.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:transactionID` |
| `VEL-NOTE-TOGGLE-RELEASE` | Left click on note handle with Ctrl, released without moving `>= activationDistance` | Toggles note selection (deselected if already selected). No document edit. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:396-407` | Toggles note ID in selection. <br>`VelocityPage.swift:547-561` | **Preserved** | `VelocityPage.swift:pointerRelease` | `checks/velocity/velocityclicks.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:transactionID` |
| `VEL-NOTE-DRAG-REL` | Left click on note handle + drag vertical `>= activationDistance` | Relative multi-note velocity edit: one delta applied across all selected notes without collapsing relative offsets. Clamped/canonicalized per voice map. Commits 1 `setVelocities` transaction on release. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:148-181, 396-415` | Computes delta, updates preview, commits 1 transaction on release. <br>`VelocityGesturePolicy.applyRelative`, `VelocityPage.swift:484-494, 568-571` | **Preserved** | `VelocityPage.swift` & `VelocityGesturePolicy` | `checks/velocity/velocitydetentdragging.cpp`<br>`checks/drawerpresentation/velocity.cpp:velocityGestureTransactions`<br>`checks/swiftcore/VelocityPageChecks.swift:gestureID` |
| `VEL-NOTE-DRAG-REL-INTRINSIC` | Left click + drag in Intrinsic (PSG) context | Level-based stepping (`moveLevels`). Only steps when pointer crosses PSG volume boundary. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:173-178` | Stepping via `note.map.moveLevels(note.exactOrigin, levelDelta)`. <br>`VelocityTransactions.swift:VelocityGesturePolicy.applyRelative` | **Preserved** | `VelocityTransactions.swift` | `checks/drawerpresentation/velocity.cpp:psgRenderingAndDetentToggle`<br>`checks/swiftcore/VelocityPageChecks.swift:psgID` |
| `VEL-PAINT-SWEEP` | Left click on empty plot + drag sweep | Sweeps across plot; sets velocity of all selected notes whose ticks lie within sweep x-range. Commits on release. If empty selection, clears selection on release. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:52-106, 269-272, 386-391` | Sweeps via `paintBetween`, previews, commits 1 transaction on release. <br>`VelocityPage.swift:442-446, 495-498, 541-544`, `VelocityTransactions.swift` | **Preserved** | `VelocityPage.swift` & `VelocityTransactions.swift` | `checks/velocity/velocitypainting.cpp`<br>`checks/velocity/velocitydetentpainting.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:gestureID` |
| `VEL-RAMP-SHIFT` | Shift + Left click + drag across plot | Draws linear ramp line between press and pointer. Calculates interpolated velocity along line for selected notes within range. Commits on release. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:108-129, 259-264, 392-395` | `VelocityGestureKind.ramp`, renders `velocityRamp` in QML, commits on release. <br>`VelocityPage.swift:437-441, 499-500, 545-546`, `VelocityPage.qml:399-413` | **Preserved** | `VelocityPage.swift`, `VelocityTransactions.swift`, `VelocityPage.qml` | `checks/drawerpresentation/velocity.cpp:rampAndRollPreview`<br>`checks/swiftcore/VelocityPageChecks.swift:gestureID` |
| `VEL-BAND-SELECT-DRAG` | Right click on plot + drag `>= startDragDistance` | Draws marquee band reticle (`m_bandRect`). Notes intersecting band are selected on release. Supports Ctrl to extend selection. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:237-258, 307-313, 364-383` | `VelocityGestureKind.pendingBand -> .band`. Previews selection, updates selection on release. <br>`VelocityPage.swift:429-436, 501-508, 526-540`, `VelocityPage.qml:388-397` | **Preserved** | `VelocityPage.swift` | `checks/drawerpresentation/velocity.cpp:transientBandAndStackedNodes`<br>`checks/swiftcore/VelocityPageChecks.swift:transactionID` |
| `VEL-RIGHT-CLICK-SINGLE` | Right click on note or background without drag | On note: selects note (or toggles with Ctrl). On background without Ctrl: clears selection. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:371-380` | Evaluated in `pointerRelease` under `.pendingBand`. <br>`VelocityPage.swift:530-539` | **Preserved** | `VelocityPage.swift` | `checks/drawerpresentation/velocity.cpp:transientBandAndStackedNodes`<br>`checks/swiftcore/VelocityPageChecks.swift:transactionID` |
| `VEL-PAN-MIDDLE` | Middle click + drag on plot | Horizontal pan of `EditorCamera`. Pauses follow-scroll during pan. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:230-236, 314-318, 359-363` | Adjusts camera `scrollX`, suspends follow-scroll. <br>`VelocityPage.swift:423-428, 509-515, 522-525` | **Preserved** | `VelocityPage.swift:pointerMove` | `checks/swiftcore/VelocityPageChecks.swift:cancellationID` |
| `VEL-WHEEL-SCROLL` | Shift + Wheel / Horizontal Wheel | Horizontal viewport scroll. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:417-424` | `WheelHandler` delegates to `page.gridModel.handleWheel`. <br>`VelocityPage.qml:452-464` | **Preserved** | `VelocityPage.qml:WheelHandler` | `checks/swiftcore/EditorGridCameraChecks.swift` |
| `VEL-WHEEL-ZOOM` | Vertical Wheel (unmodified) | Time zoom anchored at pointer x. <br>`pre-4b0d0738` `velocityarea_interaction.cpp:425-427` | `WheelHandler` delegates to `page.gridModel.handleWheel`. <br>`VelocityPage.qml:452-464` | **Preserved** | `VelocityPage.qml:WheelHandler` | `checks/swiftcore/EditorGridCameraChecks.swift` |
| `VEL-PROMPT-INVOKE` | `edit.set_velocity` command / shortcut | Opens Set Velocity modal for selected notes. Frozen snapshot of note IDs and initial values. <br>`pre-4b0d0738` `pianoroll_commands.cpp:openVelocityPrompt`, `src/ui/songview/quick/VelocityPrompt.qml` | `VelocityPage.swift:openSelectedVelocityPrompt()`, wired via `DocumentWorkspace.swift:87-89` | **Preserved** | `DocumentWorkspace.swift` -> `VelocityPage.swift` | `checks/rollcheck/velocity_prompt.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:promptID`<br>`tst_EditorDrawer.qml:test_productionVelocityPromptTransaction` |
| `VEL-PROMPT-FORM-VIEW` | Modal dialog component | Hosted in `QuickPopupSession` using `PromptCard.qml`, `DragInput.qml`, `PromptButton.qml`. <br>`pre-4b0d0738` `src/ui/songview/quick/VelocityPrompt.qml` | Rewritten inline in `src/ui/songview/quick/drawer/VelocityPrompt.qml` with raw `Rectangle`, `TextInput`, `MouseArea`. | **Missing / Degraded** (Original view discarded) | `VelocityPrompt.qml` | `checks/rollcheck/velocity_prompt.cpp` (asserts `DragInput` items and behavior) |
| `VEL-PROMPT-DRAG-SCRUB` | Drag mouse on input value | Draggable numeric scrubber (`DragInput.qml`): drag mouse horizontally or vertically to scrub velocity value up/down. <br>`pre-4b0d0738` `src/ui/songview/quick/DragInput.qml` | None. Rewritten `drawer/VelocityPrompt.qml` only has plain `TextInput`. Scrubbing does not exist. | **Missing** | `VelocityPrompt.qml` -> restore `DragInput` | `checks/rollcheck/velocity_prompt.cpp` |
| `VEL-PROMPT-KEY-STEPS` | PageUp / PageDown / ArrowUp / ArrowDown in prompt | PageUp/PageDown steps by 10 (clamped 1–127). Up/Down steps by 1. <br>`pre-4b0d0738` `DragInput.qml:Keys.onPageUpPressed`, `Keys.onPageDownPressed` | None. Rewritten `drawer/VelocityPrompt.qml` does not handle PageUp/PageDown or Up/Down stepping. | **Missing** | `VelocityPrompt.qml` -> restore `DragInput` | `checks/rollcheck/velocity_prompt.cpp:595,614` |
| `VEL-PROMPT-KEY-NAV` | Tab / Backtab cycling in prompt | `textInput -> acceptButton -> cancelButton -> textInput`. Explicit `KeyNavigation.tab` and `backtab`. <br>`pre-4b0d0738` `src/ui/songview/quick/VelocityPrompt.qml:66-67, 78-79, 90-91` | No explicit `KeyNavigation` properties set in `drawer/VelocityPrompt.qml`. Default focus cycling relies on item order. | **Changed / Incomplete** | `VelocityPrompt.qml` | `checks/rollcheck/velocity_prompt.cpp:535-555` |
| `VEL-PROMPT-ACCEPT-CANCEL` | Enter/Return accepts, Esc/Underlay cancels | Enter commits 1 `setVelocities` transaction. Esc or clicking outside underlay cancels without write. Focus returns to plot. <br>`pre-4b0d0738` `src/ui/songview/quick/VelocityPrompt.qml` | Enter commits via `acceptPrompt()`, Esc/underlay cancels via `cancelPrompt()`. Focus returns to plot. <br>`VelocityPage.swift:641, 668`, `VelocityPrompt.qml:247-255` | **Preserved** | `VelocityPage.swift`, `VelocityPrompt.qml` | `checks/rollcheck/velocity_prompt.cpp`<br>`checks/swiftcore/VelocityPageChecks.swift:promptID`<br>`tst_EditorDrawer.qml:test_productionVelocityPromptTransaction` |
| `VEL-CANCEL-ALL` | Escape key, window deactivate, section hide, track switch, document replacement | Synchronous cancellation of pointer gesture, follow suspension, and prompt. Reverts preview, writes 0 history entries. <br>`pre-4b0d0738` `velocityarea.cpp:cancelInteraction, refresh` | Cancels gesture and prompt synchronously via `cancelSectionInteraction()`. <br>`VelocityPage.swift:678-701` | **Preserved** | `VelocityPage.swift:cancelSectionInteraction` | `checks/drawerpresentation/velocity.cpp:velocityGestureTransactions`<br>`checks/swiftcore/VelocityPageChecks.swift:cancellationID`<br>`tst_EditorDrawer.qml:test_productionVelocityCancellation` |
| `VEL-UNDO-REDO` | Document Undo / Redo | Rebuilds handles, updates value axis, leaves page owner and selection intact. <br>`pre-4b0d0738` `velocityarea.cpp:refresh(DrawerScope::Content)` | Document change observer refreshes page, rebuilds handles. <br>`VelocityPage.swift:refreshFromDocument` | **Preserved** | `VelocityPage.swift:refreshFromDocument` | `checks/swiftcore/VelocityPageChecks.swift:historyID` |
| `VEL-KEYSPLIT-BOUNDARY` | Active track uses Keysplit / Drumkit voice | Historically resolved per-note ToneData child group. Swift currently lacks per-key subvoice lookup in `BankSlotView`. Publishes diagnostic and disables exact editing. <br>`pre-4b0d0738` `src/checks/drawerpresentation/velocity.cpp:psgAxisContexts` | Publishes diagnostic string in `velocityContextDiagnostic`, disables exact edits while keeping rendering live. <br>`VelocityContext.swift:keysplitSubvoice`, `VelocityPage.swift:contextUnsupported` | **Preserved as Explicit Blocker** | Requires native `BankSlotView.subvoiceMacro(forKey:)` | `checks/swiftcore/VelocityPageChecks.swift:keysplitID`<br>`tst_EditorDrawer.qml:test_productionVelocityContextIsExact` |

---

## 2. Exhaustive Interaction & Behavior Matrix: Voice Changes

| Stable ID | Input / Modifiers / Context | Historical Outcome & Source Revision/Path/Symbol | Current Equivalent & Source Path/Symbol | Status | Smallest Restoration Owner / Seam | Existing Check Coverage & Exact Command |
|---|---|---|---|---|---|---|
| `VOICE-MARKER-CLICK-NOOP` | Left press + release on marker without moving `>= startDragDistance` | Does not move marker. Does not create history entry or mutate document. <br>`pre-414d2544` `src/ui/editordrawer/voicechangearea/voicechangearea.cpp:437-452, 525-545` | Handled by `phase == .pending`. Commits nothing on release. <br>`VoiceChangesPage.swift:pointerPress, pointerRelease`, `VoiceLanePolicy.swift` | **Preserved** | `VoiceChangesPage.swift:pointerRelease` | `checks/drawerpresentation/voice.cpp:voiceMarkerDragTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:moveID`<br>Cmd: `ctest -R swiftcore` |
| `VOICE-MARKER-DRAG-MOVE` | Left click on marker + horizontal drag `>= startDragDistance` | Enters active drag. Changes cursor to `Qt::SizeHorCursor`. Previews marker tick snapped to grid lattice. Release commits single `moveLanePoints` transaction. <br>`pre-414d2544` `voicechangearea.cpp:478-506, 525-545` | Transitions to `.active`, updates `previewTick`, sets `cursorKind = 3` (`Qt.SizeHorCursor`), commits `moveLanePoints` on release. <br>`VoiceChangesPage.swift:pointerMove, pointerRelease`, `VoiceChangesPage.qml:446-474` | **Preserved** | `VoiceChangesPage.swift` & `VoiceLanePolicy.swift` | `checks/drawerpresentation/voice.cpp:voiceMarkerDragTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:moveID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPointerAndMenuTransactions` |
| `VOICE-MARKER-DRAG-FINE` | Left click on marker + Alt/Option + drag | Snaps drag preview tick to fine clock lattice (`ticksPerClock` / `SongDocument.ticksPerClock`). <br>`pre-414d2544` `voicechangearea.cpp:498` `m_grid.snapTick(rawTick, input.modifiers & Qt::AltModifier)` | Checked via `VoiceModifier.alt`. Snaps to clock lattice. <br>`VoiceChangesPage.swift:pointerMove`, `VoiceLanePolicy.swift` | **Preserved** | `VoiceLanePolicy.swift:snappedTick` | `checks/swiftcore/VoiceChangesPageChecks.swift:fineSnapID`<br>Cmd: `ctest -R swiftcore` |
| `VOICE-MARKER-COLLISION` | Drag marker to same tick as existing marker, or release at original tick | If dragged onto existing marker tick, existing point is overwritten or rejected per document collision rule. If released at same tick, no-op (no document edit, no history). <br>`pre-414d2544` `voicechangearea.cpp:537-543` | Same-tick release exits without write. Collisions handled via `moveLanePoints`. <br>`VoiceLanePolicy.swift:moveCommit`, `VoiceChangesPage.swift:pointerRelease` | **Preserved** | `VoiceLanePolicy.swift` | `checks/swiftcore/VoiceChangesPageChecks.swift:collisionID` |
| `VOICE-DOUBLECLICK-EMPTY` | Left double-click on empty plot area | Captures logical snapped tick and current voice slot. Opens Voice Picker with title "Insert voice change". On pick: commits `addLanePoint`. <br>`pre-414d2544` `voicechangearea.cpp:459-465`, `voicechangemenu.cpp:115-121, 245-247` | Calls `pointerDoubleClick(x:y:)`, captures target, sets `pickerOpen = true`. On accept commits `addLanePoint`. <br>`VoiceChangesPage.swift:425-442`, `VoiceChangesTransactions.swift` | **Preserved in Swift, Changed in QML** | `VoiceChangesPage.swift`, `VoiceChangesPage.qml` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:insertionID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPickerKeyboardAndCancellation` |
| `VOICE-DOUBLECLICK-MARKER` | Left double-click on existing marker | Captures existing marker occurrence (tick & value). Opens Voice Picker with title "Change voice". On pick: commits `moveLanePoints` with new value. <br>`pre-414d2544` `voicechangearea.cpp:459-465`, `voicechangemenu.cpp:115-121, 239-244` | Calls `pointerDoubleClick(x:y:)`, captures occurrence, sets `pickerOpen = true`. On accept commits `moveLanePoints`. <br>`VoiceChangesPage.swift:425-442`, `VoiceChangesTransactions.swift` | **Preserved in Swift, Changed in QML** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:replacementID` |
| `VOICE-RIGHTCLICK-MARKER-MENU` | Right-click on existing marker | Opens context menu with 2 rows: 1. "Change voice", 2. "Delete". Clamped to viewport. <br>`pre-414d2544` `voicechangearea.cpp:434-436`, `voicechangemenu.cpp:138-144` (`QuickMenuPanel.qml`) | Publishes 2 rows in `menuRows`. Sets `menuOpen = true`. Renders `VoiceChangeMenu.qml` on `modalHost`. <br>`VoiceChangesPage.swift:408-418`, `VoiceChangeMenu.qml` | **Preserved in Swift, Changed in QML** (Rewritten custom popup instead of `QuickMenuPanel`) | `VoiceChangesPage.swift`, `VoiceChangeMenu.qml` | `checks/drawerpresentation/voicemenus.cpp:voiceContextMenuTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPointerAndMenuTransactions` |
| `VOICE-RIGHTCLICK-EMPTY-MENU` | Right-click on empty lane area | Opens context menu with 1 row: "Insert voice change". Clamped to viewport. <br>`pre-414d2544` `voicechangearea.cpp:434-436`, `voicechangemenu.cpp:145-147` | Publishes 1 row in `menuRows`. Sets `menuOpen = true`. Renders `VoiceChangeMenu.qml`. <br>`VoiceChangesPage.swift:408-418`, `VoiceChangeMenu.qml` | **Preserved in Swift, Changed in QML** | `VoiceChangesPage.swift`, `VoiceChangeMenu.qml` | `checks/drawerpresentation/voicemenus.cpp:voiceContextMenuTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID` |
| `VOICE-MENU-ACTION-CHANGE` | Select "Change voice" from context menu | Closes menu, opens Voice Picker initialized to marker's slot and tick. <br>`pre-414d2544` `voicechangemenu.cpp:286-292` | `activateMenuRow(index)` -> opens picker for captured target. <br>`VoiceChangesPage.swift:680-705` | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voicemenus.cpp:voiceContextMenuTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID` |
| `VOICE-MENU-ACTION-INSERT` | Select "Insert voice change" from context menu | Closes menu, opens Voice Picker initialized to snapped tick and active slot. <br>`pre-414d2544` `voicechangemenu.cpp:286-292` | `activateMenuRow(index)` -> opens picker for captured target. <br>`VoiceChangesPage.swift:680-705` | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voicemenus.cpp:voiceContextMenuTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID` |
| `VOICE-MENU-ACTION-DELETE` | Select "Delete" from context menu | Deletes marker from lane via `document.deleteLanePoints`. 1 transaction, 1 history entry. <br>`pre-414d2544` `voicechangemenu.cpp:295-307` | Deletes captured occurrence via `document.deleteLanePoints`. <br>`VoiceChangesPage.swift:696-702` | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voicemenus.cpp:voiceContextMenuTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID` |
| `VOICE-MENU-DISMISS-OUTSIDE` | Outside click with menu open | Outside click (Left, Right, or Middle) dismisses menu immediately; click is swallowed so no underlying plot action or selection occurs. <br>`pre-414d2544` `voicechangemenu.cpp:272-280` (`QuickPopupSession`) | Handled by `voiceMenuUnderlay` MouseArea in `VoiceChangeMenu.qml:81-87`. Calls `dismissVoiceMenu()`. | **Preserved** | `VoiceChangeMenu.qml` | `checks/drawerpresentation/voicemenus.cpp:voiceMenuOutsideRightDismissesWithoutRetarget`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:menuID` |
| `VOICE-MENU-STALE-REJECT` | Camera scroll or document edit while menu open | Captured target is frozen. Camera scroll keeps target at logical tick. If document revision changed before row click, action rejected. <br>`pre-414d2544` `voicechangemenu.cpp:175-190, 223-238` | Captured revision verified in `activateMenuRow`. Stale revision commits nothing. <br>`VoiceChangesPage.swift:683` | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voicemenus.cpp:voiceMenuTargetHoldsAcrossCameraScroll`<br>`checks/drawerpresentation/voicemenus.cpp:voiceMenuStaleDocumentRejectsPick` |
| `VOICE-PICKER-VIEW-CARD` | Voice picker modal presentation | Hosted in `QuickPopupSession` using `VoicePickerPrompt.qml` (`PromptCard.qml`, `PromptButton.qml`, `HoverHint.qml`). <br>`pre-414d2544` `src/ui/songview/quick/VoicePickerPrompt.qml` | Rewritten inline in `src/ui/songview/quick/drawer/VoicePicker.qml` with raw `Rectangle`, `TextInput`, `ListView`, custom styling. | **Missing / Degraded** (Original view discarded) | `VoicePicker.qml` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions` |
| `VOICE-PICKER-AUDITION-HOLD` | Press and hold on voice picker row | Auditions middle C (C4) using selected voice program. `AudioEngine::previewVoice(program, 60, 100)`. <br>`pre-414d2544` `VoicePickerPrompt.qml:231` `bridge.pressAndHold(row.program)`, `voicepicker.cpp:pressAndHold` | **COMPLETELY MISSING / DISABLED**. `NativeAudio` only exposes `previewNote(track:key:velocity:)` (selected track's voice), not arbitrary program. `auditionAvailable = false`. | **Missing (Capability Blocker)** | Requires native `pd_audio_service_preview_voice(service, program, key, velocity)` in C service + Swift wrapper `NativeAudio.previewVoice` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions` (audition assertions)<br>`checks/swiftcore/VoiceChangesPageChecks.swift:auditionID` |
| `VOICE-PICKER-AUDITION-REL` | Release held press or move filter out of match | Sends note-off (`AudioEngine::previewVoice(program, 60, 0)`). <br>`pre-414d2544` `VoicePickerPrompt.qml:233-234` `bridge.releaseHeld()`, `voicepicker.cpp:releaseHeld` | **Missing** (along with audition hold). | **Missing** | Native audio service + Swift bridge | `checks/drawerpresentation/voice.cpp:voicePickerTransactions` |
| `VOICE-PICKER-TAB-CYCLE` | Tab / Backtab cycling in picker | `search -> list -> acceptButton -> cancelButton -> search`. Down arrow in search moves focus to list. Explicit `KeyNavigation.tab/backtab`. <br>`pre-414d2544` `src/ui/songview/quick/VoicePickerPrompt.qml:107-108, 142-143, 255-256, 268-269` | `drawer/VoicePicker.qml` lacks all `KeyNavigation` properties! Down arrow in search moves selection index but does NOT move active focus to list! | **Missing / Broken** | `VoicePicker.qml` | `checks/drawerpresentation/voice.cpp`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:keyboardID` |
| `VOICE-PICKER-SEARCH-FILTER` | Type text in search box | Filters program list in real-time. Highlights/selects first match. If no match, disables OK button and shows "No matching voices". <br>`pre-414d2544` `voicepicker.cpp:setFilter`, `VoicePickerPrompt.qml:105, 239-245` | Real-time filter via `VoiceChangesPage.swift:setPickerFilter`. Updates `pickerRows`, disables accept. <br>`VoiceChangesPage.swift:581-602`, `VoicePicker.qml:228-230` | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:keyboardID` |
| `VOICE-PICKER-ACCEPT-CANCEL` | Enter/Return or OK button accepts; Esc or Cancel button cancels | Enter commits selected voice. Escape or outside click cancels without writing. Focus returns to origin plot. <br>`pre-414d2544` `VoicePickerPrompt.qml:23-28`, `voicechangemenu.cpp` | Enter commits via `acceptPicker()`, Esc cancels via `cancelPicker()`. Focus returns via `page.focusOrigin()`. <br>`VoiceChangesPage.swift:630-678`, `VoicePicker.qml:74-85` | **Preserved** | `VoiceChangesPage.swift`, `VoicePicker.qml` | `checks/drawerpresentation/voice.cpp:voicePickerTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:insertionID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPickerKeyboardAndCancellation` |
| `VOICE-HOVER-BACKGROUND` | Hover mouse over empty plot | Displays hover line and label showing slot number, symbol, and voice name at hovered tick. <br>`pre-414d2544` `voicechangearea.cpp:468-477`, `voicechangequick.cpp:rebuildQuickHover` | Displays hover line and label showing slot text. <br>`VoiceChangesPage.swift:updateHover`, `VoiceChangesPage.qml:371-387` (`voiceHoverLabel`) | **Preserved** | `VoiceChangesPage.swift` & `VoiceChangesPage.qml` | `checks/drawerpresentation/voice.cpp:voiceHoverLifecycle` |
| `VOICE-HOVER-MARKER` | Hover mouse over existing marker | Displays marker hover outline and tick readout. <br>`pre-414d2544` `voicechangearea.cpp:updateHover` | Highlights marker selection outline and updates hover text. <br>`VoiceChangesPage.swift:updateHover`, `VoiceChangesPage.qml:283-294` | **Preserved** | `VoiceChangesPage.swift` & `VoiceChangesPage.qml` | `checks/drawerpresentation/voice.cpp:voiceHoverLifecycle` |
| `VOICE-CONTEXT-READOUT` | Display current voice name at right edge | When playing: displays voice at rounded shared-playhead tick. When stopped: displays voice at `DocumentSession.editCursor`. <br>`pre-414d2544` `voicechangearea.cpp:presentPlayhead`, `voicechangequick.cpp` | Published as `readoutText`, `readoutVisible`. Updated via `presentPlayheadTick` or `refreshFromDocument`. <br>`VoiceChangesPage.swift:348-380`, `VoiceChangesPage.qml:389-405` (`voiceReadout`) | **Preserved** | `VoiceChangesPage.swift` | `checks/drawerpresentation/voice.cpp:voiceSurfaceAndPaintLifecycle`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:contextID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPlayheadPerformance` |
| `VOICE-PAN-MIDDLE` | Middle click + drag on plot | Horizontal pan of `EditorCamera`. Pauses follow-scroll. <br>`pre-414d2544` `voicechangearea.cpp:428-433, 507-511, 521-524` | Adjusts camera `scrollX`, suspends follow-scroll. <br>`VoiceChangesPage.swift:pointerMove, pointerRelease` | **Preserved** | `VoiceChangesPage.swift` | `checks/swiftcore/VoiceChangesPageChecks.swift:cancellationID` |
| `VOICE-WHEEL-NAV` | Wheel scroll & zoom | Shift+wheel = horizontal scroll. Plain wheel = time zoom. <br>`pre-414d2544` `voicechangearea.cpp:wheel` | Handled via `WheelHandler` delegating to `gridModel.handleWheel`. <br>`VoiceChangesPage.qml:476-488` | **Preserved** | `VoiceChangesPage.qml:WheelHandler` | `checks/swiftcore/EditorGridCameraChecks.swift` |
| `VOICE-CANCEL-ALL` | Escape key, window deactivate, section hide, track switch, document replacement | Cancels active drag, dismisses open menu, dismisses open picker. Writes 0 history entries. <br>`pre-414d2544` `voicechangearea.cpp:cancelInteraction, setPopupSession` | Synchronous cancellation via `cancelSectionInteraction()`. Cancels drag, menu, picker. <br>`VoiceChangesPage.swift:750-775` | **Preserved** | `VoiceChangesPage.swift:cancelSectionInteraction` | `checks/drawerpresentation/voice.cpp:voiceMarkerDragTransactions`<br>`checks/swiftcore/VoiceChangesPageChecks.swift:cancellationID`<br>`tst_EditorDrawer.qml:test_productionVoiceChangesPickerKeyboardAndCancellation` |
| `VOICE-UNDO-REDO` | Document Undo / Redo | Restores voice lane markers, held spans, active program context. <br>`pre-414d2544` `voicechangearea.cpp:refresh(DrawerScope::Content)` | Document change observer refreshes page, rebuilds markers. <br>`VoiceChangesPage.swift:refreshFromDocument` | **Preserved** | `VoiceChangesPage.swift:refreshFromDocument` | `checks/swiftcore/VoiceChangesPageChecks.swift:historyID` |
| `VOICE-SPACE-TRANSPORT` | Bare Space key press | Does not trigger modal actions or plot edits; propagates to window transport to toggle Play/Pause. (Only typing in picker search claims text keys). <br>`pre-414d2544` `voicechangearea.cpp:keyPress` (returns false), `VoicePickerPrompt.qml:search` | Handled via `Keys.onShortcutOverride` claiming only Return/Enter in menu and prompt. Bare Space propagates to window. <br>`VoiceChangesPage.qml`, `VoiceChangeMenu.qml:119-122`, `VoicePicker.qml:81-84` | **Preserved** | `VoiceChangeMenu.qml`, `VoicePicker.qml` | `tst_EditorDrawer.qml:test_productionVoiceChangesSpacePriority` |

---

## 3. Source QML Recovery Recommendations & Seam Analysis

### A. Velocity Prompt: Original QML Recovery vs Rewritten View
- **Original QML Candidate**: `src/ui/songview/quick/VelocityPrompt.qml` (and its dependencies `PromptCard.qml`, `DragInput.qml`, `PromptButton.qml`).
- **Why Original is Superior**:
  1. `DragInput.qml` supplies mouse-drag scrubbing (horizontal/vertical drag to rapidly scrub velocity numbers up/down), which is completely lost in the rewritten `drawer/VelocityPrompt.qml`.
  2. `DragInput.qml` implements PageUp / PageDown step increments (+/- 10) and Up/Down arrows (+/- 1), which `checks/rollcheck/velocity_prompt.cpp` explicitly asserts.
  3. `VelocityPrompt.qml` has complete, tested `KeyNavigation.tab` / `backtab` focus chaining between input and OK/Cancel buttons.
  4. Native theme styling, font metrics, and accessible attributes match the rest of the Porydaw UI.
- **Swift Backend Seam Needed for Original Recovery**:
  Original `VelocityPrompt.qml` expects a `bridge` object with:
  - `velocityPromptAppearance`: `QVariantMap` containing dialog theme colors, fonts, radius, padding.
  - `velocityPromptTitle`: `String` ("Set Velocity").
  - `velocityPromptLabel`: `String` ("Velocity:").
  - `velocityPromptInitialValue`: `Int` (1–127).
  - `velocityPromptMinimumValue`: `1`, `velocityPromptMaximumValue`: `127`.
  - `acceptVelocityPrompt(Int)`: commits transaction.
  - `cancelVelocityPrompt()`: dismisses transaction.
  *Swift Backend Diff*: In `VelocityPage.swift`, these properties already exist in slightly altered forms (`promptDraft`, `promptOpen`, `promptMinimum`, `promptMaximum`, `acceptPrompt()`, `cancelPrompt()`). Adding a tiny adapter or exposing the exact property names on `VelocityPage` allows direct reuse of the original `src/ui/songview/quick/VelocityPrompt.qml`.

### B. Voice Picker: Original QML Recovery vs Rewritten View
- **Original QML Candidate**: `src/ui/songview/quick/VoicePickerPrompt.qml` (and `PromptCard.qml`, `PromptButton.qml`, `HoverHint.qml`).
- **Why Original is Superior**:
  1. Contains the real press-and-hold audition wiring: `MouseArea { onPressed: bridge.pressAndHold(row.program); onReleased: bridge.releaseHeld(); onDoubleClicked: prompt.acceptDisplayed() }`.
  2. Contains complete Tab / Backtab `KeyNavigation` across Search Input, Voice List, OK, and Cancel.
  3. Search Input Down-Arrow key deterministically transfers active focus to the ListView (`list.forceActiveFocus(Qt.TabFocusReason)`), allowing immediate arrow navigation through matches without touching the mouse.
  4. Centering on match change: `list.positionViewAtIndex(list.currentIndex, ListView.Center)`.
- **Swift Backend Seam Needed for Original Recovery**:
  Original `VoicePickerPrompt.qml` expects a `bridge` object with:
  - `voicePickerTitle`: `String` ("Change voice" or "Insert voice change").
  - `voicePickerAppearance`: `QVariantMap` (theme styling).
  - `voicePickerModel`: `QAbstractListModel` with roles `program`, `label`.
  - `filter`: read/write `String`.
  - `currentRow`: `Int`.
  - `hasMatch`: `Bool`.
  - `selectRow(Int)`, `accept()`, `cancel()`, `pressAndHold(Int)`, `releaseHeld()`.
  *Swift Backend Diff*: Currently `VoiceChangesPage.swift` exposes a flat array of `pickerRows` (`[VoicePickerRowModel]`) instead of a `QAbstractListModel`. Swift can either expose a minimal list model or an adapter matching `voicePickerModel`, and implement `pressAndHold`/`releaseHeld`.

### C. Voice Context Menu: `QuickMenuPanel.qml` vs `VoiceChangeMenu.qml`
- **Original Architecture**: Historically, menus did not have ad-hoc custom QML files per page. They used the shared `songview::QuickMenuHost` / `QuickMenuModel` rendered by `src/ui/songview/quick/QuickMenuPanel.qml`.
- **Current Architecture**: Replaced by custom-built `src/ui/songview/quick/drawer/VoiceChangeMenu.qml` composed into `drawerModalLayer`.
- **Assessment**: While `VoiceChangeMenu.qml` faithfully reproduces the visual rows (Change voice, Delete, Insert voice change) and keyboard navigation (Up/Down/Enter/Esc), recovering `QuickMenuPanel.qml` or standardizing context menus eliminates duplicated menu styling and ensures consistent platform menu behavior.

---

## 4. Discrepancies Requiring Swift Backend Changes

1. **Voice Audition Capability Blocker**:
   - *Problem*: `VoicePickerPrompt.qml` and legacy `checks/drawerpresentation/voice.cpp` require auditioning arbitrary bank slots via middle C on click-and-hold.
   - *Backend Gap*: Current `NativeAudio` exposes only `previewNote(track:key:velocity:)` which previews the track's *current* voice, NOT an arbitrary program slot.
   - *Required Backend Change*: Add native audio C function:
     ```c
     void pd_audio_service_preview_voice(AudioServiceHandle *service, int program, int key, int velocity);
     ```
     and Swift wrapper in `NativeAudio.swift`:
     ```swift
     public func previewVoice(program: Int, key: UInt8, velocity: UInt8)
     ```
   - *Impact*: Unlocks `VOICE-PICKER-AUDITION-HOLD` and `VOICE-PICKER-AUDITION-REL`, enabling full restoration of `VoicePickerPrompt.qml`.

2. **Keysplit / Drumkit Subvoice Velocity Context Blocker**:
   - *Problem*: Velocity editing in tracks with keysplit or drumkit voices is currently blocked and disabled (`contextUnsupported = true`).
   - *Backend Gap*: `BankSlotView` in Swift does not expose per-note keysplit table or drumkit subvoice mapping (`ToneData.subGroup[key]`).
   - *Required Backend Change*: Read-only API on native bank slot:
     ```swift
     func subvoiceMacro(slot: Int, key: UInt8) -> Int32?
     ```
   - *Impact*: Unlocks full exact velocity detent resolution for drumkits and keysplits.

3. **Bridge Properties for Original QML Components**:
   - To restore `src/ui/songview/quick/VelocityPrompt.qml` and `VoicePickerPrompt.qml`:
     - Swift `VelocityPage` must provide `velocityPromptAppearance` dictionary and bridge methods `acceptVelocityPrompt(value)` / `cancelVelocityPrompt()`.
     - Swift `VoiceChangesPage` must provide `voicePickerAppearance` dictionary, `pressAndHold(program)` / `releaseHeld()`, and either a list model or list property conforming to `VoicePickerPrompt.qml` expectations.

---

## 5. Verification Coverage & Commands

| Suite / Target | Files Covered | Exact Verification Command |
|---|---|---|
| **Swift Core Checks** | `VelocityPageChecks.swift`<br>`VoiceChangesPageChecks.swift` | `ctest -R swiftcore --output-on-failure` |
| **Editor QML Suite** | `src/checks/editorqml/tst_EditorDrawer.qml` | `ctest -R editorqml-drawer --output-on-failure` |
| **Drawer Presentation (Legacy)** | `checks/drawerpresentation/velocity.cpp`<br>`checks/drawerpresentation/voice.cpp`<br>`checks/drawerpresentation/voicemenus.cpp` | `ctest -R drawerpresentation --output-on-failure` |
| **Roll Check (Velocity Prompt)** | `checks/rollcheck/velocity_prompt.cpp` | `ctest -R rollcheck --output-on-failure` |
| **Velocity Editing (Legacy)** | `checks/velocity/*` (8 test suites) | `ctest -R velocity --output-on-failure` |

# Controller follow-up: confirmed corrections

# Automation Drawer Interaction & Parity Investigation Architecture

## 1. Multi-Lane Commit & Preview Verification & Data-Contract Corrections

### 1.1 Confirmed Defect: Multi-Lane Move Commit Loss
* **Location**: `src/swift/app/drawer/automation/AutomationInteraction.swift:192-194`
* **Defect**: In `releasePlot(x:y:modifiers:)`, the commit dispatch executes:
  ```swift
  committed = commit(AutomationNodeResolver.moves([
      AutomationNodeResolver.LaneMoves(facts, transaction.moves)
  ]))
  ```
  While `transaction.moves` contains moves across all covered lanes (`[AutomationNodeMove]` with heterogeneous `parameter` values), they are packed into a single `LaneMoves` with `facts` bound exclusively to `self.activeParameter`.
* **Failure Mechanism**: In `AutomationNodeResolver.laneMoves` (`AutomationEdits.swift:240-255`), every move is evaluated against `request.facts.snapshot`:
  ```swift
  let group = facts.occupants(at: move.sourceTick)
  if group.isEmpty {
      guard move.sourceTick == 0, facts.snapshot.projectedTickZero else { return false }
      ...
  }
  ```
  When a move belongs to a secondary lane:
  1. If the active lane has no occupant at `move.sourceTick`, `facts.occupants` returns empty and `laneMoves` returns `false`, causing the entire multi-lane move transaction to fail and commit nothing (`nil`).
  2. If the active lane happens to have an occupant at `move.sourceTick`, the move mutates the *active parameter* rather than the secondary lane's parameter, corrupting document data.
  3. If Tempo is among the selected lanes, it is routed through `laneMoves` instead of `tempoMoves` (or vice versa), failing immediately.
* **Exact Data-Contract Correction (Using Existing Types)**:
  `AutomationNodeResolver.moves(_ requests: [LaneMoves]) -> AutomationDocumentPlan?` already accepts an array of `LaneMoves`. In `AutomationNodeDragTransaction`, retain the covered lane snapshots or facts (already supplied to `selection(...)` as `lanes: [(parameter: AutomationParameter, snapshot: AutomationLaneSnapshot)]`). In `releasePlot`:
  ```swift
  let movesByParameter = Dictionary(grouping: transaction.moves, by: \.parameter)
  let requests = movesByParameter.compactMap { (parameter, moves) -> AutomationNodeResolver.LaneMoves? in
      guard let laneFacts = transaction.laneFacts(for: parameter) ?? facts(parameter: parameter, modifiers: modifiers, session: session) else { return nil }
      return AutomationNodeResolver.LaneMoves(laneFacts, moves)
  }
  committed = commit(AutomationNodeResolver.moves(requests))
  ```

### 1.2 Stationary Selected Deletion: Verification & Disproven Scout Claim
* **Historical Source Contract**: `src/ui/editordrawer/automationcanvas_gesture.cpp:288-292`:
  ```cpp
  const NodeDragFinish finish = gesture->finish();
  if (finish.release == PointDragRelease::StationaryDelete &&
      gesture->grabbedPoint < gesture->points.size()) {
      changed = commitNodePointDeletes(gesture->expectedRevision,
                                       {gesture->points[gesture->grabbedPoint]});
  }
  ```
* **Disproven Scout Claim**: Initial scout claims suggested stationary release on a multi-node selection was supposed to delete all selected nodes across all covered lanes. This is **FALSE**. Historical C++ explicitly deleted ONLY the single grabbed node (`{gesture->points[gesture->grabbedPoint]}`). Deleting all selected nodes was reserved for explicit range deletion commands (`deleteCapturedSelection()`).
* **Actual Defect & Correction**: In `AutomationInteraction.swift:186-190`:
  ```swift
  case (.stationaryDelete, _):
      committed = commit(AutomationNodeResolver.deletions(
          revision: facts.revision,
          [AutomationNodeResolver.LaneDeletes(parameter: facts.parameter,
                                              snapshot: facts.snapshot,
                                              ticks: transaction.deleteTicks)]))
  ```
  If a stationary click occurs on a node in a secondary lane (in multi-lane view), deleting through `facts.parameter` routes to the active parameter rather than the grabbed target's parameter.
* **Data-Contract Correction**:
  ```swift
  guard let grabbed = transaction.grabbed else { break }
  let targetFacts = transaction.laneFacts(for: grabbed.parameter) ?? facts(parameter: grabbed.parameter, modifiers: modifiers, session: session)
  committed = commit(AutomationNodeResolver.deletions(
      revision: targetFacts.revision,
      [AutomationNodeResolver.LaneDeletes(parameter: grabbed.parameter,
                                          snapshot: targetFacts.snapshot,
                                          ticks: [grabbed.source.tick])]))
  ```

### 1.3 Confirmed Defect: Multi-Lane Transient Previews
* **Location**: `src/swift/app/drawer/automation/AutomationScene.swift:122, 592-604`
* **Defect**:
  1. `AutomationPreviewDraft.resolve(gesture:frozen:)` strips parameter identity:
     `case let .node(transaction): points = transaction.targets.map(\.current)`
     It flattens all targets into an untyped `[AutomationLanePoint]`.
  2. `publishPreview()` projects all points using `facts.metadata`:
     `y: (projection.y(point.value, metadata: facts.metadata) - extent).rounded()`
     Where `facts.metadata` is exclusively the active parameter.
* **Impact**: Secondary lane targets with distinct value ranges (e.g. Tempo 20..300, PitchBend -8192..8191, Volume 0..127) are projected with the active lane's scale, causing nodes to clamp offscreen or jump erratically. Furthermore, `previewText` formats secondary lane values using the active lane's formatter.
* **Historical C++ Contract**: `src/ui/songview/quick/automationnodelanequick.cpp:236-242, 293-305`:
  `NodeDragGesture::previewPoints` was partitioned per lane (`std::vector<std::vector<NodePoint>>`). In addition, `previewValueLabel` only displayed on the lane where the grabbed node resided (`label.lane == context.handle`).
* **Data-Contract Correction**:
  Change `AutomationPreviewDraft` to preserve parameter identity or target instances:
  ```swift
  struct AutomationPreviewDraft: Sendable {
      struct TargetPreview: Sendable {
          let parameter: AutomationParameter
          let point: AutomationLanePoint
      }
      let targets: [TargetPreview]
      let text: String
      let grabbedParameter: AutomationParameter?
  }
  ```
  In `publishPreview()`, project each point's Y coordinate using its own `AutomationParameterMetadata(parameter: target.parameter)`, and format `previewLabelText` from the grabbed target's metadata.

---

## 2. Band Selection, Extents, Retargeting, and Hover Delete

### 2.1 Right-Band Drag Threshold vs. Zero Snapped Width
* **Historical Contract**: `src/ui/editordrawer/nodelane/gesture.cpp:62-79`, `automationcanvas_input.cpp:307-330`:
  1. `m_band.move()` checks `(pos - pressPos).manhattanLength() >= QApplication::startDragDistance()`. Only then does `active = true`.
  2. On release:
     - If `!active` (never exceeded drag distance, e.g. click): returns `std::nullopt`. This triggers node context menu or range context menu. It **NEVER** clears selection.
     - If `active && first < last`: publishes new band selection.
     - If `active && first == last` (drag threshold exceeded, but snapped width is zero): **clears** active selection via `model.clearTimeSelection()`.
* **Disproven Scout Claim**: Scout in `AUTO-SEL-02` claimed: "if last == first, check if click was outside selection; if so, clear selection". This is a **FALSE POSITIVE**. Clearing selection on a stationary right-click outside selection violates C++ parity; stationary right-clicks must open menus or miss cleanly without wiping selection.
* **True Defect**: Swift `AutomationRangeBand` lacks an activation threshold (`startDragDistance`). A drag that moves >5px but stays within one snapped grid interval is treated as a click, triggering context menus rather than clearing the selection.

### 2.2 Lane Extent Availability in Single-Active-Lane View
* **Verification**: In single-active-lane view, the plot body contains only the active lane.
* **Disproven Scout Claim**: Scout in `AUTO-SEL-01` reported missing vertical lane extent in Swift `AutomationRangeBand` as a missing interaction gap. In single-active-lane view, tracking vertical lane spans across multiple rows in the plot body is **INAPPLICABLE / FALSE POSITIVE**. It is only meaningful when multiple stacked lanes are rendered simultaneously.

### 2.3 Right-Click Menu Retargeting
* **Historical Contract**:
  - Point Menu (`automationpointmenus.cpp:261-285`): Outside right-click on another node **retargets** the menu to the second node immediately (`QuickMenuHost::outsideRightPressed -> retargetNodeMenu`).
  - Lane Menu (`automationmenus.cpp:341-382`): Outside right-click **dismisses** without retargeting (`outsidePressDismissesLaneMenuWithoutSideEffects`).
  - CC Delete Prompt (`ccdeleteconfirmation.cpp:273-314`): Outside right-click **dismisses** without retargeting (`ccDeletePromptOutsideRightPressClosesWithoutRetarget`).
* **Correction**: QML `AutomationMenu.qml` underlay captures all clicks and unconditionally calls `dismiss()`. For point menus, an outside right-click must check for a node hit at the click location to retarget without requiring a second click.

### 2.4 Hover Delete Routing & Window Priority
* **Historical Contract**: `src/ui/editordrawer/automationcanvas_input.cpp:417-440`:
  ```cpp
  if (keys.matches(input.key, input.modifiers, QLatin1String("roll.delete")) && m_pencilMode &&
      m_hoverState.hover.lane.valid()) {
      auto &model = m_page.m_owner.selectionModel();
      if (model.noteSelection().empty() && !model.timeSelection().active()) {
          if (hover.hasPoint) { ... commitNodePointDeletes(...); }
          return true; // Consumed (including miss over blank space)
      }
  }
  return false; // Defer to shared window/selection policy
  ```
* **Critical Rules & False Positive Rejection**:
  1. **Pencil Mode Only**: Hover delete is strictly a pencil tool action (`m_pencilMode`). In Arrow mode, pressing Delete while hovering a node does NOT delete the node.
  2. **Window Priority / Deferral**: When a note selection or time selection exists, hover delete MUST return `false` (unaccepted) so the Delete key routes to the window-level selection delete action.
  3. **Consumed No-Op**: In pencil mode with no selection, hovering over blank space must accept the event (`return true`) to prevent accidental window transport triggers.

---

## 3. CC Value-Range Mapping & Menu Submenu Behavior

### 3.1 Display State & Architecture
* **State Ownership**: Pure view/presentation state stored in `EditorViewState.laneRanges[rowId] -> uint8_t`.
* **Semantics**: Does not mutate document data; produces 0 revisions and 0 undo entries.
* **Plot Y-Projection**: For zoomable lanes, the maximum Y value projected is the active range (or `autoRange(max)` if set to 0).

### 3.2 Exact Parameter Eligibility
Based on `TimeDefaults.laneDomain(for: controller).zoomable`:
* **Zoomable (Eligible for Value Range Submenu)**:
  - Volume (`0x07`)
  - Modulation (`0x01`)
  - LFO Speed (`0x13`)
  - Bend Range (`0x14`)
  - LFO Delay (`0x1A`)
  - Echo Volume (`0x30`)
  - Echo Feedback (`0x31`)
  - Echo Time (`0x32`)
  - Echo Low-pass (`0x33`)
  - Echo High-pass (`0x34`)
* **Non-Zoomable (Value Range Submenu Excluded)**:
  - Tempo (song-global)
  - Pitch Bend (`0xFF`)
  - Pan (`0x0A`, centered)
  - Modulation Type (`0x16`, discrete 0..2)
  - Fine Tune (`0x18`, centered)

### 3.3 Menu Submenu Hierarchy & Values
* **Parent Item**: "Value range" (`Action::ValueRange = 7`), child of lane context menu.
* **Child Items**:
  1. `Action::RangeAuto = 8`: "Auto (fit to data)" (Value `0`)
     - Auto algorithm: `maximum <= 16 ? 16 : maximum <= 32 ? 32 : maximum <= 64 ? 64 : 127`
  2. `Action::Range16 = 9`: "0–16" (Value `16`)
  3. `Action::Range32 = 10`: "0–32" (Value `32`)
  4. `Action::Range64 = 11`: "0–64" (Value `64`)
  5. `Action::Range127 = 12`: "0–127 (full)" (Value `127`)
* **Defaults**: Modulation defaults to `0` (Auto). All other zoomable controllers default to `127`.
* **Checked State**: Exactly one item has `checked = true` matching the active range.

---

## 4. Uncovered Historical C++ Check Inventory

The following historical check scenarios from `src/checks/automation/` have no corresponding contract coverage in `AutomationPageChecks.swift` or current QML checks:

### 4.1 Menu, Value Range, and Popup Scenarios
1. `AutomationEditingTest::laneMenuValueRangeSubmenuPickRescalesAndCloses`: Hovering Value Range row opens typed submenu; picking `Range64` updates view state without document mutation; reopened menu shows `Range64` checked; Escape dismisses.
2. `AutomationEditingTest::outsideRightClickDismissesPointMenu`: Outside right-click on another node retargets open point menu to second node immediately.
3. `AutomationEditingTest::pointMenuSyntheticDefaultDeleteDisabledAndSetValuePromotes`: Synthetic tick-0 engine node shows Delete row disabled; Set Value promotes synthetic node into written event.
4. `AutomationEditingTest::pointMenuStaleDocumentCannotDeleteTarget`: Stale document revision prevents point menu action execution.
5. `AutomationEditingTest::pointMenuForeignTakeoverInvalidatesPendingTarget`: Opening foreign popup cancels pending point menu target.
6. `AutomationEditingTest::consumedValuePromptCannotFollowTrackSwitch`: Prompt opened on Track A aborts if track changes before accept.
7. `AutomationEditingTest::ccDeletePromptSyntheticOnlyVolumeSkipsConfirmation`: Deleting lane events on Volume with only synthetic tick-0 default performs no deletion and shows no confirmation prompt.
8. `AutomationEditingTest::ccDeletePromptDefaultLaneWrittenCountExcludesSynthetic`: Prompt text reflects only written event count, excluding synthetic default.
9. `AutomationEditingTest::ccDeletePromptInitialReturnCancelsWithoutNavigation`: Initial Enter/Return key press triggers Cancel button safely.

### 4.2 Multi-Lane & Selection Drag Scenarios
10. `AutomationEditingTest::multiLaneSelectionDragPreservesTempoAndCcOrder`: Group-dragging selected nodes across Tempo and CC lanes preserves ordering and clamps collectively at tick 0.
11. `AutomationEditingTest::multiCcLaneSelectionDragExcludesTempoAndVolume`: Multi-CC drag moves only covered CC nodes, preserving unselected Tempo and Volume nodes.
12. `AutomationEditingTest::multiLaneSelectionDragAbortsOnDocumentRebuild`: External document rebuild mid-drag aborts multi-lane gesture cleanly.
13. `AutomationEditingTest::selectedRangeDragAndDelete`: Moving and deleting selected time range across multiple lanes commits atomically.

### 4.3 Pencil & Stroke Motion Scenarios
14. `AutomationEditingTest::pencilClickOnExcursionNodeDeletesExcursion`: Clicking isolated excursion node in pencil mode deletes excursion and restores held line.
15. `AutomationEditingTest::pencilSubCellHorizontalJitterDoesNotAlterStroke`: Sub-cell horizontal jitter during pencil stroke does not create redundant points.
16. `AutomationEditingTest::pencilZigzagStrokePreservesDirectionalExtrema`: Zigzag pencil strokes preserve directional min/max peaks.
17. `AutomationEditingTest::pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit`: Backtracking over a drawn span preserves extrema and overwrites with the latest revisit value.
18. `AutomationEditingTest::pencilCancellationRoutesAbortGestureWithoutCommit_data`: In-flight pencil stroke aborts via Escape, deactivation, or foreign replacement with 0 edits.

### 4.4 Tap-Tempo Staging Scenarios (Completely Missed in Initial Matrix)
19. `AutomationEditingTest::tapTempoDraftAccumulatesFromSecondTapAndFreezesDocument`: Second tap begins draft accumulation without modifying document.
20. `AutomationEditingTest::tapTempoSingleStrayTapAfterIdleGapCommitsNothing`: Stray tap after idle timeout resets cadence without write.
21. `AutomationEditingTest::tapTempoFourTapsCommitOnceAtTickZeroAndUndoRestores`: Four consistent taps commit BPM at tick 0 once; undo restores previous tempo.
22. `AutomationEditingTest::tapTempoTappingCurrentTickZeroTempoIsSilent`: Tapping at existing BPM produces no document revision.
23. `AutomationEditingTest::tapTempoCommitReplacesTickZeroPointPreservingLaterPoints`: Tap commit overwrites tick 0 while preserving subsequent tempo changes.
24. `AutomationEditingTest::tapTempoCommitInsertsFirstTempoPointOnNonzeroDocument`: Tap commit inserts initial tempo point on non-zero song.
25. `AutomationEditingTest::tapTempoConcurrentTempoEditAbortsDraftSynchronously`: Concurrent external tempo edit clears tap staging.
26. `AutomationEditingTest::tapTempoDocumentChangedSeamClearsSession`: Document change signal resets tap session.
27. `AutomationEditingTest::tapTempoDisabledCanvasAndEmptyDocumentAreNoOps`: Disabled canvas ignores tap inputs.
28. `AutomationEditingTest::tapTempoRenderedTapButtonStagesTapWithoutDocumentChanges`: Rendered UI Tap button drives staging identically to keyboard tap.
29. `AutomationEditingTest::tapTempoMeanWindowAndClampBounds`: Tap tempo averages intervals and clamps strictly to 20..300 BPM.

### 4.5 Keyboard, Navigation, and Layout Scenarios
30. `AutomationEditingTest::actionTextInputImmunity`: Keystrokes in value prompt text fields do not trigger transport or lane shortcuts.
31. `AutomationEditingTest::actionRepeatImmunity`: Autorepeat key events do not duplicate single-shot gesture actions.
32. `AutomationEditingTest::primaryTrackSwitchRebuildsRowsDuringPan`: Track switch during middle-mouse pan rebuilds rows without breaking pan continuity.
33. `AutomationEditingTest::scrolledOriginPhantomCommits`: Dragging origin phantom while tick 0 is scrolled offscreen commits value change to origin point.
34. `AutomationEditingTest::detailThresholdHiddenVisibleNodePrecedence`: Hit-testing dense node clusters resolves visible nodes before hidden nodes.
35. `AutomationEditingTest::emptyParameterSwitchPreservesGridResolution`: Switching to an empty parameter retains active grid snap resolution.

# Native Audio & Velocity Subvoice Integration Architecture

## 1. Audition Capability Architecture

### Native Audio Seam
- **Authority**: `AudioEngine::previewVoice(uint8_t voice, uint8_t key, uint8_t velocity)` (`src/audio/audioengine.h:132`, `src/audio/audioengine.cpp:426`). Operates via generation-counted atomic `m_previewVoiceCmd` on track 0 of `m_previewEngine`. Parameter conventions: key=60 (`kVoiceAuditionKey`), audition velocity=112 (`kVoiceAuditionVel`), note-off velocity=0.
- **C ABI Export**: `pd_audio_service_preview_voice(PdAudioService *service, uint8_t voice, uint8_t key, uint8_t velocity)` in `src/audio/swift_audio_service.h` and `src/audio/swift_audio_service.cpp`.
- **Swift Service**: `NativeAudio.previewVoice(program: UInt8, key: UInt8 = 60, velocity: UInt8)` in `src/swift/app/NativeAudio.swift`.

### Ownership & Forwarding Pipeline
1. `ApplicationSession` instantiates and owns `NativeAudio` as `private var audio: NativeAudio?`.
2. `ApplicationSession` injects `audio` into `DocumentWorkspace.init(...)` which holds `private unowned let audio: NativeAudio`.
3. `DocumentWorkspace` coordinates `VoiceChangesPage` using the decoupled callback pattern established by `PianoGrid.onAudition`:
   `voiceChangesPage.onAuditionVoice = { [weak audio] program, key, velocity in ... }`
4. `VoiceChangesPage` tracks `soundingProgram: Int = -1` and exposes `@QtBridgeable` methods `pressAndHoldPickerRow(index: Int)` and `releasePickerAudition()`.
5. Every dismissal, filter change that hides the sounding row, escape, outside click, accept, cancel, and workspace teardown invokes `releasePickerAudition()`, ensuring strict pairing of note-on (vel=112) with note-off (vel=0).

---

## 2. Keysplit / Drumkit Per-Key Subvoice Velocity Architecture

### Native Resolution Authority
- **Authority**: `resolveVoice(const ToneData *tone, std::optional<uint8_t> key, VelocityVoice *failure)` in `src/core/velocitymodel.cpp:45-78`.
  - For `VOICE_KEYSPLIT_ALL` (Drumkit): `resolved = &subgroup[*key]`
  - For `VOICE_KEYSPLIT`: `resolved = &subgroup[tone->keySplitTable[*key]]`
  - Resolves PSG hardware types (`VOICE_SQUARE_1`, `VOICE_SQUARE_2`, `VOICE_PROGRAMMABLE_WAVE`, `VOICE_NOISE`) vs DirectSound.
- **Legacy UI Precedent**: `VelocityArea::contextForNote(const DocNote &note)` (`src/ui/editordrawer/velocityarea/velocityarea.cpp:348`) calls `VelocityMap::resolve(context.voice, note.key)`. When all selected notes share compatible PSG maps, `VelocityArea::resolveContext` selects Intrinsic PSG detents (15 levels / 16 graduations).

### Project Service Seam & Swift BankSlotView
1. `PdBankSlotView` in `src/project/swift_project_service.h` is extended with `const int32_t *subvoiceMacros` (128-element array of `BankVoiceMacro` ordinals, or `NULL` if not keysplit).
2. `fillSlotViews` in `src/project/swift_project_service.cpp` reads `view.bank.get()->voices[slot]` via the borrowed `VoicegroupLease`, iterates keys 0..127 through `resolveVoice()`, maps them to `BankVoiceMacro` ordinals, and populates `subvoiceMacros`.
3. `BankSlotView` in `src/swift/app/ProjectService.swift` adopts `public var subvoiceMacros: [Int32]?` and `public func subvoiceMacro(forKey key: Int) -> Int32?`.
4. `VelocityContextPolicy.resolve(...)` in `src/swift/app/drawer/velocity/VelocityContext.swift` accepts `key: Int? = nil`. When `key` is present and resolves via `subvoiceMacro(forKey:)`, it maps the subvoice to `VoiceKind`, yielding `VelocityVoiceContext(status: .resolved, map: VelocityMap(voiceKind: kind))` with `editable = true`.
5. `VelocityPage.swift` projects handles and selection presentations using `(note.tick, note.key)`, re-enabling PSG detents and prompt editing for keysplit/drumkit voices.