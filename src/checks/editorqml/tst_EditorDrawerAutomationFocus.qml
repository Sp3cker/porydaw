import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_automationModalsRetireWithPage() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-modal-lifetime")
        var loader = findChild(testCase.surface, "drawerBody_automation")
        var host = findChild(testCase.surface, "drawerModalLayer")
        verify(loader && host, "the production loader and external modal host are present")
        verify(findChild(host, "automationMenu"), "the page creates its hosted menu")
        verify(findChild(host, "automationPrompt"), "the page creates its hosted prompt")
        bootstrap.cancelInput()
        try {
            loader.setSource("")
            tryVerify(function() {
                return !findChild(host, "automationMenu") && !findChild(host, "automationPrompt")
            }, 1000, "unloading the page retires both modals while their host survives")
        } finally {
            loader.syncSource()
            tryVerify(function() { return !!AutomationTabsSupport.automationPageItem(testCase) }, 1000,
                      "the existing document owner remounts through the same production loader")
        }
    }

    function test_productionAutomationSetValuePromptFocusRoute() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-value-focus"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active")
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case created a written Volume lane with a real sweep")
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 0, "the Volume lane projects a written node")
        var written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(written >= 0, "the lane projects a written node")

        LayoutSupport.focusControl(testCase, plot)
        tryCompare(model, "plotFocused", true, 1000,
                   "the automation band's focused item is the plot before the point menu opens")
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, written))
        compare(bootstrap.automationMenuActions(), "1,2",
                "the written node's right-press opens the point menu with its typed rows")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1),
               "the point menu's rendered Set Value row accepts a real click")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(model.menuOpen, false,
                "the Set Value pick consumes the point menu as the prompt opens")

        var field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the value prompt rendered its draft input")
        tryCompare(field, "activeFocus", true, 1000,
                   "the value prompt's draft field holds focus on open")
        tryCompare(model, "plotFocused", false, 1000,
                   "the page stops publishing the plot as focused while the value prompt owns focus")
        compare(field.selectedText.length > 0, true,
                "the value prompt's stored draft opens selected")
        tryCompare(plot, "activeFocus", false, 1000,
                   "the plot yields focus while the value prompt holds the band")

        // a) Escape cancels the open prompt: nothing is written, the modal
        // closes, and the band's focus comes back to the plot.
        var revisionBefore = bootstrap.automationDocumentRevision()
        var valuesBefore = bootstrap.automationLaneValues()
        keyClick(Qt.Key_Escape)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        compare(bootstrap.automationLaneValues(), valuesBefore,
                "the cancelled value prompt leaves the lane byte-identical")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the cancelled value prompt writes no document revision")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the value prompt's Escape close returns focus to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus after Escape")

        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1),
               "the reopened point menu's rendered Set Value row accepts a real click")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the reopened value prompt rendered its draft input")
        tryCompare(field, "activeFocus", true, 1000,
                   "the reopened value prompt's draft field holds focus on open")
        tryCompare(model, "plotFocused", false, 1000,
                   "the page stops publishing the plot as focused while the reopened value prompt owns focus")
        var storedBefore = bootstrap.automationLaneValues()
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        tryCompare(model, "promptOpen", false, 1000,
                   "the value route's acceptance closes the value prompt")
        compare(bootstrap.automationLaneValues() !== storedBefore, true,
                "the accepted value draft wrote the lane")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the value prompt's acceptance close returns focus to the automation band's plot")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed")
        compare(bootstrap.automationLaneValues(), storedBefore,
                "undo restores the lane values the accepted draft replaced")
        tryCompare(plot, "activeFocus", true, 1000,
                   "focus stays on the automation band's plot after the value edit's undo")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page still publishes the plot as the automation band's focus after undo")

        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1),
               "the reopened point menu's rendered Set Value row accepts a real click")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the reopened value prompt rendered its draft input")
        tryCompare(field, "activeFocus", true, 1000,
                   "the reopened value prompt's draft field holds focus on open")
        tryCompare(model, "plotFocused", false, 1000,
                   "the page stops publishing the plot as focused while the pre-switch value prompt owns focus")
        var tempoTab = model.tabCount - 1
        verify(tempoTab > volumeTab, "the published tab list ends on Tempo")
        revisionBefore = bootstrap.automationDocumentRevision()
        verify(model.activateParameter(tempoTab),
               "the production parameter switch lands on the Tempo lane")
        tryCompare(model, "promptOpen", false, 2000,
                   "the parameter switch closes the focused value prompt without a write")
        compare(bootstrap.automationPromptOpen(), false,
                "no value prompt survives the parameter switch")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "the parameter switch writes no document revision")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the closed value prompt's focus returns to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus after the switch")
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempoTab }, 2000,
                  "the Tempo lane is active after the switch")
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1))
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        tryCompare(field, "activeFocus", true, 1000,
                   "the reopened prompt owns focus before blur")
        revisionBefore = bootstrap.automationDocumentRevision()
        valuesBefore = bootstrap.automationLaneValues()
        testCase.rollInput().forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(testCase.rollInput(), "activeFocus", true, 1000,
                   "the roll receives focus outside the prompt")
        tryCompare(field, "activeFocus", false, 1000,
                   "the draft field really lost focus to the roll")
        tryCompare(model, "promptOpen", false, 1000,
                   "moving focus off the open prompt cancels it without a write")
        compare(bootstrap.automationDocumentRevision(), revisionBefore)
        compare(bootstrap.automationLaneValues(), valuesBefore)

        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1))
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        keyClick(Qt.Key_Escape)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        compare(!model.acceptPromptDraft() && bootstrap.automationDocumentRevision() === revisionBefore
                && bootstrap.automationLaneValues() === valuesBefore, true,
                "a late acceptance after the close writes nothing")

        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)))
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1))
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        testCase.presenter().toggleSection(testCase.automationKind, true)
        tryCompare(model, "promptOpen", false, 1000,
                   "switching the drawer's visible page cancels the open prompt")
        compare(bootstrap.automationDocumentRevision(), revisionBefore)
        compare(bootstrap.automationLaneValues(), valuesBefore)
        compare(testCase.section(testCase.automationKind).visible, false,
                "the production toggleSection entry hid the automation page")
    }

    function test_productionAutomationTempoPromptFocusRoute() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-tempo-focus"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var tempoTab = model.tabCount - 1
        verify(tempoTab >= 0, "the published tab list ends on Tempo")
        AutomationTabsSupport.clickAutomationTab(testCase, tempoTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempoTab }, 2000,
                  "the Tempo lane is active")

        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        var tempoIndex = -1
        for (var i = 0; i < nodes.length; ++i) {
            if (!nodes[i].model.projected) {
                tempoIndex = i
                break
            }
        }
        verify(tempoIndex >= 0, "the staged tempo lane projects a written node")

        LayoutSupport.focusControl(testCase, plot)
        tryCompare(model, "plotFocused", true, 1000,
                   "the automation band's focused item is the plot before the tempo node menu opens")
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, tempoIndex))
        compare(bootstrap.automationMenuActions(), "1,2",
                "the tempo node's right-press opens the point menu with its typed rows")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1),
               "the tempo point menu's rendered Set Value row accepts a real click")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(model.menuOpen, false,
                "the tempo Set Value pick consumes the point menu as the prompt opens")

        var field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the tempo value prompt rendered its draft input")
        tryCompare(field, "activeFocus", true, 1000,
                   "the tempo value prompt's draft field holds focus on open")
        tryCompare(plot, "activeFocus", false, 1000,
                   "the plot yields focus while the tempo prompt holds the band")
        tryCompare(model, "plotFocused", false, 1000,
                   "the page stops publishing the plot as focused while the tempo prompt owns focus")
        var bpmBefore = bootstrap.automationTempoBpm()
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_3)
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        tryCompare(model, "promptOpen", false, 1000,
                   "the tempo route's acceptance closes the value prompt")
        tryVerify(function() { return bootstrap.automationTempoBpm() === 132 }, 2000,
                  "the accepted tempo draft commits the new bpm")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the tempo prompt's acceptance close returns focus to the automation band's plot")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page republishes the plot as the automation band's focus after the tempo commit")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed")
        compare(bootstrap.automationTempoBpm(), bpmBefore,
                "undo restores the tempo the accepted draft replaced")
        tryCompare(plot, "activeFocus", true, 1000,
                   "focus stays on the automation band's plot after the tempo edit's undo")
        tryCompare(model, "plotFocused", true, 1000,
                   "the page still publishes the plot as the automation band's focus after the tempo undo")
    }

    function test_productionAutomationSpacePriority() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-space"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var propagations = testCase.spacePropagations

        // The plot leaves bare Space to the transport.
        AutomationTabsSupport.automationPlot(testCase).forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return testCase.spacePropagations === propagations + 1 }, 2000,
                  "the automation plot leaves bare Space to the window transport")

        // Focusing the original selector and pressing Space never edits the lane.
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case created a written Volume lane with a real sweep")
        var tab = AutomationTabsSupport.automationTab(testCase, volumeTab)
        verify(tab, "the selector drew the Volume tab")
        LayoutSupport.focusControl(testCase, tab)
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Space)
        compare(bootstrap.automationDocumentRevision(), revision,
                "Space on the focused selector does not edit automation")
        propagations = testCase.spacePropagations
        keyClick(Qt.Key_Return)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "Return activates the focused tab")

        // The Tempo row's Tap control claims only Return/Enter.
        var tempoTab = AutomationTabsSupport.revealAutomationTab(testCase, model.tabCount - 1)
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        LayoutSupport.focusControl(testCase, tapControl)
        keyClick(Qt.Key_Space)
        compare(bootstrap.automationDocumentRevision(), revision,
                "Space on the inline Tap control does not edit automation")
        propagations = testCase.spacePropagations
        compare(bootstrap.automationTapCount(), 0, "the Space key registered no tap")
        AutomationMenuSupport.resetAutomationTap(testCase)

        // The original popup host contains Space without activating a command.
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 0, "the Volume lane projects a written node")
        verify(AutomationMenuSupport.rightClickAutomationNode(testCase, 0), "the first drawn node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the node menu opened")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", true)
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, propagations,
                "the automation menu contains Space instead of leaking into transport")
        compare(bootstrap.automationMenuOpen(), true, "Space leaves the menu open")
        compare(bootstrap.automationDocumentRevision(), revision,
                "menu keyboard input does not edit the song")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationMenuOpen() }, 2000,
                  "Escape closed the menu")

        compare(bootstrap.automationMenuOpen(), false, "the case left no menu open")
        verify(bootstrap.cancelInput(), "the composition's own cancellation settles the page")
        compare(bootstrap.automationInteractionActive(), false,
                "the cancelled page reports no interaction")
    }
    function test_productionAutomationPanGuardsSharedCommands() {
        if (testCase.containerPhase) skip("production composition only")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-pan-commands",
            { "automationVisible": true, "velocityVisible": true, "activePage": "automation" })
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var grid = testCase.surface.gridModel
        verify(input, "the mounted automation page exposes its plot input")
        // Stage a lanes-scope time selection through the production range band:
        // a right drag past the drag distance publishes it on release.
        var y = input.height / 2
        var x1 = input.width * 0.3
        mousePress(input, x1, y, Qt.RightButton)
        mouseMove(input, x1 + 80, y, -1, Qt.RightButton)
        mouseRelease(input, x1 + 80, y, Qt.RightButton)
        var range = bootstrap.automationSelectionRange()
        verify(range.length > 0, "the right-drag band staged a time selection")
        // Opaque pre-stimulus snapshots: the live pan swallows Delete and the
        // first Escape cancels only the pan.
        var revision = bootstrap.automationDocumentRevision()
        var values = bootstrap.automationLaneValues()
        var cursor = grid.editCursorTick
        var x = input.width / 2
        mousePress(input, x, y, Qt.MiddleButton)
        tryVerify(function() { return bootstrap.automationInteractionActive() },
                  1000, "the middle press starts a live pan")
        keyClick(Qt.Key_Delete)
        keyClick(Qt.Key_Escape)
        mouseRelease(input, x, y, Qt.MiddleButton)
        verify(!bootstrap.automationInteractionActive()
                && bootstrap.automationDocumentRevision() === revision
                && bootstrap.automationLaneValues() === values
                && grid.editCursorTick === cursor
                && bootstrap.automationSelectionRange() === range,
                "automation gesture did not block Delete and preserve its time selection on Escape")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return bootstrap.automationSelectionRange() === "" },
                  1000, "second Escape after automation cancellation did not clear time selection")
    }
}
