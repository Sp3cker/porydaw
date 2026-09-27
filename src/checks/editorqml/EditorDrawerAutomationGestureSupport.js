.import "EditorDrawerPageSupport.js" as PageSupport
.import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport

    /// The drawn fill of one node marker: the delegate itself fills the plot and
    /// its children carry the projected position.
    function automationNodeFill(testCase, handle) {
        return handle ? testCase.findChild(handle, "automationNodeFill") : null
    }

    /// One drawn node marker's centre, in the plot input's own coordinates.
    function automationNodePoint(testCase, handle) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var fill = automationNodeFill(testCase, handle)
        if (!fill)
            return null
        return fill.mapToItem(input, fill.width / 2, fill.height / 2)
    }

    /// The drawn node markers of the active lane whose projected tick matches, in
    /// tree order: the projection publishes one marker per display point.
    function automationNodesAtTick(testCase, tick) {
        var nodes = AutomationTabsSupport.automationNodeItems(testCase)
        var matches = []
        for (var i = 0; i < nodes.length; ++i) {
            if (Math.abs(nodes[i].model.tick - tick) < 0.5
                    && !nodes[i].model.phantom)
                matches.push(nodes[i])
        }
        return matches
    }

    /// Whether the active lane's own hover reports a node under one plot point:
    /// the page's own hit test answers, so a case never guesses the node radius.
    function automationNodeUnderPoint(testCase, x, y) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        testCase.mouseMove(input, x, y, -1, Qt.NoButton, Qt.NoModifier)
        testCase.wait(0)
        var nodes = automationLaneNodes(testCase)
        for (var i = 0; i < nodes.length; ++i) {
            if (nodes[i].model.hovered === true)
                return true
        }
        return false
    }

    function automationFreePoint(testCase) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var candidates = [Math.round(input.height / 2), Math.round(input.height * 0.75), 4]
        for (var x = 24; x < input.width - 4; x += 16) {
            for (var c = 0; c < candidates.length; ++c) {
                if (!automationNodeUnderPoint(testCase, x, candidates[c]))
                    return { "x": x, "y": candidates[c] }
            }
        }
        return null
    }

    /// A column at or after `step` that holds no drawn node of the active lane,
    /// checked against the page's own hover at the row the caller will press.
    function automationFreeColumn(testCase, step, row) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var y = row === undefined ? Math.round(input.height / 2) : row
        for (var x = step; x < input.width - 4; x += 16) {
            if (!automationNodeUnderPoint(testCase, x, y))
                return x
        }
        return -1
    }

    function writeVolumeLanePoints(testCase, tabIndex) {
        AutomationTabsSupport.clickAutomationTab(testCase, tabIndex)
        testCase.tryVerify(function() { return testCase.bootstrap.automationActiveParameterIndex() === tabIndex }, 2000,
                  "the Volume lane is active")
        var free = automationFreePoint(testCase)
        if (!free)
            return false
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        dragAutomationPlot(testCase, free.x, free.y,
                                    Math.min(input.width - 4, free.x + 120), free.y)
        testCase.tryVerify(function() { return testCase.bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the sweep left the Volume lane written events")
        testCase.tryVerify(function() { return automationWrittenNodeIndex(testCase) >= 0 }, 2000,
                  "the written Volume lane draws a written node")
        return automationWrittenNodeIndex(testCase) >= 0
    }

    /// The index of the first drawn node that names a *written* occurrence: the
    /// projected engine node's Delete row is published disabled by design.
    function automationWrittenNodeIndex(testCase) {
        var nodes = automationLaneNodes(testCase)
        for (var i = 0; i < nodes.length; ++i) {
            if (!nodes[i].model.projected)
                return i
        }
        return -1
    }

    /// Every drawn node marker of the active lane, without the origin phantom.
    function automationLaneNodes(testCase) {
        var nodes = AutomationTabsSupport.automationNodeItems(testCase)
        var matches = []
        for (var i = 0; i < nodes.length; ++i) {
            if (!nodes[i].model.phantom)
                matches.push(nodes[i])
        }
        return matches
    }

    /// One real press/move/release drag inside the page's own plot, in plot
    /// coordinates, so every case drives the production pointer route.
    function dragAutomationPlot(testCase, fromX, fromY, toX, toY, modifiers) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var mods = modifiers === undefined ? Qt.NoModifier : modifiers
        testCase.mousePress(input, fromX, fromY, Qt.LeftButton, mods)
        // The first move past the slop arms the stroke; the second drafts it,
        // exactly as the production sweep's own activation rule reads them.
        testCase.mouseMove(input, (fromX + toX) / 2, (fromY + toY) / 2, -1, Qt.LeftButton, mods)
        testCase.mouseMove(input, toX, toY, -1, Qt.LeftButton, mods)
        testCase.mouseRelease(input, toX, toY, Qt.LeftButton, mods)
    }

    function automateRangeSelection(testCase, fromX, toX, row) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var y = row === undefined ? input.height / 2 : row
        testCase.mousePress(input, fromX, y, Qt.RightButton)
        testCase.mouseMove(input, toX, y, -1, Qt.LeftButton)
        testCase.mouseRelease(input, toX, y, Qt.RightButton)
    }

    function dragAutomationPlotRow(testCase, x, pressY, armY, settleY, modifiers) {
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var mods = modifiers === undefined ? Qt.NoModifier : modifiers
        testCase.mousePress(input, x, pressY, Qt.LeftButton, mods)
        testCase.mouseMove(input, x, armY, -1, Qt.LeftButton, mods)
        testCase.mouseMove(input, x, armY + (settleY - pressY), -1, Qt.LeftButton, mods)
        testCase.mouseRelease(input, x, armY + (settleY - pressY), Qt.LeftButton, mods)
    }

    function automationRowForValue(testCase, value) {
        var known = []
        var nodes = automationLaneNodes(testCase)
        for (var i = 0; i < nodes.length && known.length < 2; ++i) {
            if (nodes[i].model.value === undefined || nodes[i].model.y === undefined)
                continue
            known.push({ "y": nodes[i].model.y, "value": nodes[i].model.value })
        }
        if (known.length < 2 || known[0].value === known[1].value)
            return -1
        var scale = (known[1].y - known[0].y) / (known[0].value - known[1].value)
        return known[0].y + (known[0].value - value) * scale
    }

    /// The drawn preview markers of a live gesture.
    function automationPreviewItems(testCase) {
        return PageSupport.collectByNames(testCase, AutomationTabsSupport.automationPageItem(testCase),
                                       ["automationPreviewNode"], [])
    }
