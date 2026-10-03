.import "EditorDrawerPageSupport.js" as PageSupport
.import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
.import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport

    function automationMenuRowItems(testCase) {
        var root = testCase.findChild(testCase.surface, "automationMenu")
        if (!root || root.visible !== true)
            return []
        return PageSupport.collectByPrefix(testCase, root, "automationMenuRow_", []).filter(function(row) {
            return !row.model.separator
        })
    }

    // Like the original quick_popup driver: resolve the current typed row in
    // its owning panel, not through the editor's pre-modal visual subtree.
    function menuRowByAction(testCase, panel, actionId) {
        if (!panel) return null
        for (var i = 0; i < panel.rowCount; ++i) {
            var row = panel.rowItem(i)
            if (row && row.model.actionId === actionId) return row
        }
        return null
    }

    function automationMenuSeparatorItems(testCase) {
        var root = testCase.findChild(testCase.surface, "automationMenu")
        if (!root || root.visible !== true)
            return []
        return PageSupport.collectByPrefix(testCase, root, "automationMenuRow_", []).filter(function(row) {
            return row.model.separator
        })
    }

    function clearAutomationLane(testCase, tabIndex) {
        openAutomationTabMenu(testCase, tabIndex)
        if (!testCase.bootstrap.automationMenuOpen())
            return false
        var underlay = testCase.findChild(testCase.surface, "automationMenuUnderlay")
        testCase.verify(underlay, "the lane menu has an outside pointer target")
        testCase.mouseMove(underlay, underlay.width - 1, underlay.height - 1)
        testCase.wait(0)
        testCase.keyClick(Qt.Key_Left)
        testCase.keyClick(Qt.Key_Home)
        if (!triggerAutomationMenuRow(testCase, 6))
            return false
        testCase.tryVerify(function() { return testCase.bootstrap.automationPromptOpen() }, 2000,
                  "the destructive row opened the captured confirmation")
        awaitAutomationModal(testCase, "automationPrompt", true)
        var cancel = testCase.findChild(testCase.surface, "automationPromptCancel")
        testCase.tryVerify(function() { return cancel && cancel.activeFocus }, 1000,
                  "the original confirmation is drawn with Cancel focused")
        var accept = testCase.findChild(testCase.surface, "automationPromptAccept")
        testCase.verify(accept, "the confirmation draws its explicit Delete action")
        testCase.verify(testCase.polishWindow(accept), "the confirmation completed layout before input")
        testCase.mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        testCase.tryVerify(function() { return !testCase.bootstrap.automationPromptOpen() }, 2000,
                  "the confirmation's acceptance closed the form")
        testCase.tryVerify(function() { return testCase.bootstrap.automationLaneEventCount() === 0 }, 2000,
                  "the accepted confirmation emptied the lane")
        return testCase.bootstrap.automationLaneEventCount() === 0
    }

    /// The visible automation modal produced by the page's own publications, and
    /// a wait for the drawn state a case is about to hit.
    function awaitAutomationModal(testCase, name, expected) {
        testCase.tryVerify(function() {
            var item = testCase.findChild(testCase.surface, name)
            return expected ? (item !== null && item.visible === true)
                            : (item === null || item.visible === false)
        }, 2000, name + " visibility is " + expected)
        if (expected && name === "automationMenu") {
            testCase.tryVerify(function() {
                var actions = testCase.bootstrap.automationMenuActions().split(",")
                return automationMenuRowItems(testCase).length
                    + automationMenuSeparatorItems(testCase).length === actions.length
            }, 2000, "the open menu has realized every published action and separator")
            var menu = testCase.findChild(testCase.surface, name)
            testCase.tryVerify(function() { return menu.activeFocus }, 1000,
                      "the open menu acquired keyboard focus before input")
            testCase.verify(testCase.polishWindow(menu), "the menu completed layout before input")
        }
    }

    /// The lane menu of one parameter tab: the production selector's context
    /// request, opened with a real right click on the drawn tab.
    function openAutomationTabMenu(testCase, index) {
        testCase.wait(0)
        var tab = AutomationTabsSupport.revealAutomationTab(testCase, index)
        testCase.verify(tab, "the selector drew tab " + index)
        testCase.mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton)
        testCase.tryVerify(function() { return testCase.bootstrap.automationActiveParameterIndex() === index }, 1000,
                  "a left press reaches the selector's own activation")
        testCase.mousePress(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
        var opened = testCase.bootstrap.automationMenuOpen()
        testCase.mouseRelease(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
        testCase.verify(opened || testCase.bootstrap.automationMenuOpen(),
               "the tab's context request opened the lane menu")
        awaitAutomationModal(testCase, "automationMenu", true)
    }

    function rightClickAutomationNode(testCase, index) {
        testCase.wait(0)
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        if (index >= nodes.length)
            return null
        var point = AutomationGestureSupport.automationNodePoint(testCase, nodes[index])
        if (!point)
            return null
        testCase.mouseClick(AutomationTabsSupport.automationPlotInput(testCase), point.x, point.y, Qt.RightButton)
        return point
    }

    /// The open menu's current row action id, read from the drawn panel itself.
    function currentAutomationMenuAction(testCase) {
        var root = testCase.findChild(testCase.surface, "automationMenu")
        return root && root.visible === true ? root.currentActionId() : -1
    }

    function triggerAutomationMenuRow(testCase, actionId) {
        for (var attempt = 0; attempt < 8; ++attempt) {
            if (currentAutomationMenuAction(testCase) === actionId) {
                testCase.keyClick(Qt.Key_Return)
                return true
            }
            testCase.keyClick(Qt.Key_Down)
        }
        return false
    }

    function activateAutomationNodeMenuRow(testCase, nodeIndex, actionId) {
        return openAutomationNodeMenu(testCase, nodeIndex)
            && triggerAutomationMenuRow(testCase, actionId)
    }

    /// Opens the drawn node menu and waits for its actual keyboard target,
    /// including the shared ListView's deferred delegate realization.
    function openAutomationNodeMenu(testCase, nodeIndex) {
        var point = rightClickAutomationNode(testCase, nodeIndex)
        if (!point)
            return false
        awaitAutomationModal(testCase, "automationMenu", true)
        testCase.keyClick(Qt.Key_Down)
        testCase.tryVerify(function() { return currentAutomationMenuAction(testCase) >= 0 }, 1000,
                  "Down selects a realized point-menu action")
        return testCase.bootstrap.automationMenuOpen()
    }

    function clickAutomationMenuRow(testCase, actionId) {
        var published = testCase.bootstrap.automationMenuActions().split(",")
        var rows = automationMenuRowItems(testCase)
        for (var i = 0; i < rows.length; ++i) {
            if (rows[i].model.actionId === actionId && published.indexOf(String(actionId)) >= 0) {
                testCase.mouseClick(rows[i], rows[i].width / 2, rows[i].height / 2, Qt.LeftButton)
                return true
            }
        }
        return false
    }

    /// The lane's own cancel of the live tap session: no commit, no draft.
    function resetAutomationTap(testCase) {
        AutomationTabsSupport.automationModel(testCase).resetTapTempo()
        testCase.wait(0)
    }
