.import "EditorDrawerLayoutSupport.js" as LayoutSupport
.import "EditorDrawerPageSupport.js" as PageSupport

    // ---- the production Automation page -------------------------------------

    function automationPageItem(testCase) { return testCase.pageItem(testCase.automationKind) }

    function automationModel(testCase) { return testCase.surface.applicationSession.automationPage() }

    function automationGutter(testCase) { return testCase.findChild(automationPageItem(testCase), "automationGutter") }

    function automationPlot(testCase) { return testCase.findChild(automationPageItem(testCase), "automationPlot") }

    function automationPlotInput(testCase) {
        return testCase.findChild(automationPageItem(testCase), "automationPlotInput")
    }

    /// The drawn selector tabs of the hosted page, in tree order.
    function automationTabItems(testCase) {
        return PageSupport.collectByNames(testCase, automationPageItem(testCase),
                                       automationTabNames(testCase), [])
    }

    function automationTabNames(testCase) {
        var names = []
        var count = automationModel(testCase).tabCount
        for (var i = 0; i < count; ++i)
            names.push("automationParameterTab" + i)
        return names
    }

    /// The drawn node markers of the hosted page, in tree order.
    function automationNodeItems(testCase) {
        return PageSupport.collectByNames(testCase, automationPageItem(testCase),
                                       ["automationNode", "automationNodePhantom"], [])
    }

    function mountProductionAutomation(testCase, location, values) {
        testCase.verify(testCase.bootstrap.attachProductionSection(testCase.automationKind),
               "the production Automation page attaches to its slot")
        // The camera is shared with every page, so a mounted case starts from the
        // lane's own park instead of inheriting wherever another case left it.
        testCase.surface.gridModel.resetCameraScroll()
        testCase.resetChrome(location, values)
        testCase.tryVerify(function() {
            var toggle = testCase.toggle(testCase.automationKind)
            return toggle !== null && toggle.width > 0
        }, 2000, "the published automation toggle is drawn for the attached page")
        if (!testCase.section(testCase.automationKind).visible)
            LayoutSupport.clickToggle(testCase, testCase.automationKind)
        testCase.tryVerify(function() { return testCase.section(testCase.automationKind).visible }, 2000,
                  "the automation section is visible")
        testCase.tryVerify(function() { return automationPageItem(testCase) !== null }, 2000,
                  "the drawer hosts the production Automation page item")
        testCase.tryVerify(function() {
            var page = automationPageItem(testCase)
            return page !== null && page.width > 0 && page.height > 0
        }, 2000, "the hosted production page took its drawn body size")
        testCase.tryVerify(function() {
            return automationTabItems(testCase).length
                   === automationModel(testCase).tabCount
        }, 2000, "the page drew one selector tab per published catalog parameter"
                  + automationBridgeDiagnostics(testCase))
        return automationPageItem(testCase)
    }

    /// What the hosted page's own QML really sees of the published owner, so a
    /// bridge gap names itself instead of only failing a count.
    function automationBridgeDiagnostics(testCase) {
        var page = automationPageItem(testCase)
        var lines = ["drawnTabs=" + automationTabItems(testCase).length,
                     "publishedTabs=" + automationModel(testCase).tabCount]
        if (page) {
            lines.push("pageModel=" + (typeof page.pageModel))
            lines.push("qmlTabs=" + (page.pageModel ? typeof page.pageModel.tabs : "n/a"))
            lines.push("qmlTabCount=" + (page.pageModel ? page.pageModel.tabCount : -1))
            lines.push("qmlNodeCount=" + (page.pageModel ? page.pageModel.nodeCount : -1))
            lines.push("drawnTabs=" + page.selectorTabCount)
        }
        return " (" + lines.join("; ") + ")"
    }

    /// One drawn tab by its published index, or null.
    function automationTab(testCase, index) {
        var tabs = automationTabItems(testCase)
        for (var i = 0; i < tabs.length; ++i) {
            if (tabs[i].objectName === "automationParameterTab" + index)
                return tabs[i]
        }
        return null
    }

    /// The labels of the drawn tabs, in tree order, so a case compares the
    /// selector it can see against the catalog the page published.
    function drawnAutomationTabLabels(testCase) {
        var labels = []
        var texts = PageSupport.collectByNames(testCase, automationPageItem(testCase),
                                           ["automationParameterTabText"], [])
        for (var i = 0; i < texts.length; ++i)
            labels.push(texts[i].text)
        return labels.join(",")
    }

    function verifyAutomationLabelsFitGutter(testCase) {
        var gutter = automationGutter(testCase)
        var scroller = testCase.findChild(gutter, "automationTabsScroller")
        testCase.verify(gutter && scroller, "the selector exposes its gutter and clipped scroller")
        testCase.fuzzyCompare(gutter.width, testCase.surface.timelineSplitX, 0.01,
                     "the label gutter includes the track headers and keyboard")
        testCase.fuzzyCompare(gutter.width, testCase.surface.headersModel.trackHeaderWidth
                                   + testCase.surface.gridModel.keyboardWidth, 0.01)
        var labels = testCase.bootstrap.automationTabLabels().split(",")
        var tabs = automationTabItems(testCase)
        testCase.compare(tabs.length, labels.length, "every catalog label has a tab")
        var previousScroll = scroller.contentY
        try {
            scroller.contentY = 0
            var bounds = []
            for (var i = 0; i < labels.length; ++i) {
                var tab = automationTab(testCase, i)
                testCase.verify(tab && tab.width > 0 && tab.height > 0, "the parameter tab has bounds")
                var origin = tab.mapToItem(gutter, 0, 0)
                testCase.verify(origin.x >= -0.5 && origin.x + tab.width <= gutter.width + 0.5,
                       "parameter " + labels[i] + " stays inside the widened gutter")
                var text = testCase.findChild(tab, "automationParameterTabText")
                testCase.verify(text, "the parameter tab has its production Text item")
                testCase.compare(text.text, labels[i])
                testCase.verify(text.contentWidth > 0 && text.contentHeight > 0,
                       "the parameter label has rendered ink")
                testCase.verify(text.contentWidth <= text.width + 0.5
                       && text.contentHeight <= text.height + 0.5,
                       labels[i] + " fits without clipping its rendered text")
                var textOrigin = text.mapToItem(tab, 0, 0)
                testCase.verify(textOrigin.x >= -0.5 && textOrigin.x + text.width <= tab.width + 0.5,
                       labels[i] + " text remains inside its own tab")
                var center = { x: origin.x + tab.width / 2, y: origin.y + tab.height / 2 }
                for (var j = 0; j < bounds.length; ++j)
                    testCase.verify(Math.abs(center.x - bounds[j].x) > 0.5
                           || Math.abs(center.y - bounds[j].y) > 0.5,
                           "parameter tabs do not overlap at one center")
                bounds.push(center)
            }
            for (var pair = 0; pair + 1 < labels.length - 1; pair += 2)
                testCase.fuzzyCompare(bounds[pair].y, bounds[pair + 1].y, 0.5,
                             "related controller pairs share a row")
            var tempo = automationTab(testCase, labels.length - 1)
            var left = automationTab(testCase, 0)
            var right = automationTab(testCase, 1)
            testCase.fuzzyCompare(tempo.x, left.x, 0.01, "Tempo shares the first column's left edge")
            testCase.fuzzyCompare(tempo.x + tempo.width, right.x + right.width, 0.01,
                         "Tempo spans both columns")
            testCase.verify(bounds[bounds.length - 1].y > bounds[bounds.length - 2].y,
                   "Tempo closes the selector below the controllers")
            testCase.compare(scroller.clip, true, "the selector clips its scrolling content")
        } finally {
            scroller.contentY = previousScroll
        }
    }

    /// The drawn tab that reports itself checked, or null.
    function drawnAutomationActiveTab(testCase) {
        var tabs = automationTabItems(testCase)
        for (var i = 0; i < tabs.length; ++i) {
            if (testCase.automationTabSelected(tabs[i]))
                return tabs[i]
        }
        return null
    }

    function automationTabWithEvents(testCase) { return testCase.bootstrap.automationTabWithEvents() }

    /// The tab index of the first per-track parameter whose lane is empty.
    function automationEmptyTab(testCase) { return testCase.bootstrap.automationEmptyTab() }

    function revealAutomationTab(testCase, index) {
        var tab = automationTab(testCase, index)
        testCase.verify(tab, "the selector drew tab " + index)
        if (tab.activeFocus)
            LayoutSupport.focusControl(testCase, automationPlot(testCase))
        LayoutSupport.focusControl(testCase, tab)
        var scroller = testCase.findChild(automationGutter(testCase), "automationTabsScroller")
        testCase.tryVerify(function() {
            var origin = tab.mapToItem(scroller, 0, 0)
            return origin.y >= 0 && origin.y + tab.height <= scroller.height
        }, 1000, "keyboard focus minimally reveals the whole parameter control")
        return tab
    }

    function clickAutomationTab(testCase, index, modifiers) {
        var tab = revealAutomationTab(testCase, index)
        testCase.verify(tab, "the selector drew tab " + index)
        testCase.mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton,
                   modifiers === undefined ? Qt.NoModifier : modifiers)
    }

    /// Control-press on a drawn tab: the production ghost toggle entry.
    function pressAutomationTabWithControl(testCase, index) {
        var tab = revealAutomationTab(testCase, index)
        testCase.verify(tab, "the selector drew tab " + index)
        testCase.mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.LeftButton, Qt.ControlModifier)
    }

    /// One real right press on a drawn tab: the production context request.
    function rightClickAutomationTab(testCase, index) {
        var tab = revealAutomationTab(testCase, index)
        testCase.verify(tab, "the selector drew tab " + index)
        testCase.mouseClick(tab, tab.width * 0.2, tab.height / 2, Qt.RightButton)
    }
