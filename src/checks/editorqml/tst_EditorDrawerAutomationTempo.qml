import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionAutomationTempoPromptPresentation() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-prompt-presentation")
        var model = AutomationTabsSupport.automationModel(testCase)
        var plot = AutomationTabsSupport.automationPlot(testCase)
        var tempoTab = model.tabCount - 1
        AutomationTabsSupport.clickAutomationTab(testCase, tempoTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === tempoTab },
                  2000, "the Tempo tab is active for its prompt")
        var revision = bootstrap.automationDocumentRevision()
        var history = session.canUndo
        var originalBpm = bootstrap.automationTempoBpm()
        var typedBpm = originalBpm === 90 ? 91 : 90
        var original = bootstrap.automationLaneValues()
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)),
               "the written tempo point opens its menu")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1), "the rendered Set Value row opens the form")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(model.promptOpen && bootstrap.automationDocumentRevision() === revision
                && session.canUndo === history && bootstrap.automationLaneValues() === original, true,
                "the tempo node prompt opens without a write")
        compare(model.promptTitle === "Set tempo" && model.promptLabel === "BPM:"
                && model.promptMinimum === 20 && model.promptMaximum === 255
                && model.promptDraft === String(originalBpm), true,
                "the tempo prompt shows its title, label and bounds")
        var prompt = findChild(testCase.surface, "automationPrompt")
        PageSupport.auditVisibleTextInk(testCase, prompt, "tempo value prompt")
        var field = findChild(prompt, "automationPromptInput")
        tryCompare(field, "activeFocus", true)
        compare(field.selectedText, String(originalBpm), "the tempo draft opens selected")
        keyClick(Qt.Key_9)
        keyClick(typedBpm === 90 ? Qt.Key_0 : Qt.Key_1)
        compare(field.text, String(typedBpm), "the rendered tempo input took the typed BPM")
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        compare(bootstrap.automationTempoBpm() === typedBpm
                && bootstrap.automationDocumentRevision() === revision + 1
                && session.canUndo && !model.promptOpen, true,
                "the typed tempo draft replaces the written tempo")
        tryCompare(plot, "activeFocus", true, 1000,
                   "the tempo prompt acceptance returns focus to the plot")
        verify(bootstrap.requestAutomationUndo(), "the tempo edit undoes")
        compare(bootstrap.automationLaneValues(), original, "undo restores the written tempo")
    }

    function test_productionAutomationCenteredPromptOffset() {
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-centered-prompt")
        var model = AutomationTabsSupport.automationModel(testCase)
        var panTab = bootstrap.automationPanIndex()
        verify(panTab >= 0, "the catalog publishes Pan")
        AutomationTabsSupport.clickAutomationTab(testCase, panTab)
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the Pan plot has a clear sweep start")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        AutomationGestureSupport.dragAutomationPlot(testCase, free.x, free.y,
                                    Math.min(input.width - 4, free.x + 120), free.y)
        tryVerify(function() { return AutomationGestureSupport.automationWrittenNodeIndex(testCase) >= 0 }, 2000,
                  "the Pan sweep drew a written node")
        var written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        var node = AutomationGestureSupport.automationLaneNodes(testCase)[written].model
        var tick = node.tick
        var stored = node.value
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, written), "the Pan node opens its menu")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1), "the rendered Set Value row opens Pan")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        var field = findChild(testCase.surface, "automationPromptInput")
        tryCompare(field, "activeFocus", true)
        compare(model.promptMinimum === -64 && model.promptMaximum === 63
                && model.promptDraft === String(stored - 64), true,
                "the centered parameter's prompt opens in displayed units")
        PageSupport.auditVisibleTextInk(testCase, findChild(testCase.surface, "automationPrompt"),
                                     "centered Pan prompt")
        field.selectAll()
        keyClick(Qt.Key_Minus)
        keyClick(Qt.Key_6)
        keyClick(Qt.Key_4)
        compare(field.text, "-64", "the centered lower-bound text is accepted for entry")
        compare(field.acceptableInput, true, "the centered lower-bound text is in the field's domain")
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        compare(bootstrap.automationLaneValues().split(",").indexOf(tick + ":0") >= 0, true,
                "the centered draft's lower bound stores zero")
        written = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, written), "the lower-bound Pan node opens its menu")
        verify(AutomationMenuSupport.clickAutomationMenuRow(testCase, 1), "the Set Value row reopens Pan")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        field = findChild(testCase.surface, "automationPromptInput")
        tryCompare(field, "activeFocus", true)
        field.selectAll()
        keyClick(Qt.Key_6)
        keyClick(Qt.Key_3)
        keyClick(Qt.Key_Return)
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", false)
        compare(bootstrap.automationLaneValues().split(",").indexOf(tick + ":127") >= 0, true,
                "the centered draft's upper bound stores one twenty-seven")
    }

    function test_productionAutomationTapTempoThroughInput() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-tap"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var tempoTab = AutomationTabsSupport.revealAutomationTab(testCase, model.tabCount - 1)
        verify(tempoTab, "the Tempo row is drawn in the selector")
        var tapControl = findChild(tempoTab, "automationTempoTapButton")
        verify(tapControl, "the Tempo row composed its Tap control")
        const tapText = findChild(tapControl, "automationTempoTapLabel")
        verify(tapText, "the mounted Tap label is present")
        compare(tapText.font.family, session.typographyFonts.caption.family,
                "Tap uses the caption face")
        compare(tapText.font.pixelSize, session.typographyFonts.caption.pixelSize,
                "Tap uses the caption size")
        compare(tapText.font.weight, session.typographyFonts.caption.weight,
                "Tap uses caption weight")
        var tempoBefore = bootstrap.automationTempoBpm()
        verify(tempoBefore > 0, "the staged song names a tick-zero tempo (" + tempoBefore + ")")
        var revisionBefore = bootstrap.automationDocumentRevision()
        var undoBefore = session.canUndo
        compare(String(tapControl.Accessible.name).length > 0, true,
                "the Tap control publishes its accessible name ('" + tapControl.Accessible.name + "')")
        var inlineDraft = PageSupport.collectByName(testCase, tempoTab, "automationTempoTapDraft", [])[0]
        verify(inlineDraft, "the Tempo tab has an inline draft readout")
        compare(inlineDraft.visible, false, "the draft readout starts hidden")

        // A real pointer press on the Tap control registers one tap at the event
        // boundary, and the panel publishes the live session.
        mouseClick(tapControl, tapControl.width / 2, tapControl.height / 2, Qt.LeftButton)
        tryVerify(function() { return bootstrap.automationTapCount() >= 1 }, 2000,
                  "the pointer tap registered a tap")
        compare(bootstrap.automationInteractionActive(), true,
                "a live tap session is the page's interaction fact")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "tapping writes nothing to the document")
        compare(session.canUndo, undoBefore, "tapping records no history entry")

        // The keyboard's own tap: Return on the focused control.
        LayoutSupport.focusControl(testCase, tapControl)
        keyClick(Qt.Key_Return)
        wait(0)
        compare(bootstrap.automationTapCount() >= 1, true,
                "Return on the focused Tap control registered a tap")
        verify(bootstrap.automationTapIdleCommitMs() > 0,
               "the panel published its idle commit window ("
               + bootstrap.automationTapIdleCommitMs() + " ms)")

        // Cancelling the session takes the draft with it and writes nothing.
        AutomationMenuSupport.resetAutomationTap(testCase)
        compare(bootstrap.automationTapCount(), 0, "the cancel cleared the tap session")
        compare(bootstrap.automationTempoBpm(), tempoBefore,
                "a cancelled session wrote no tempo")
        compare(bootstrap.automationDocumentRevision(), revisionBefore,
                "a cancelled session published no revision")
        compare(session.canUndo, undoBefore, "a cancelled session recorded no history entry")

        var gapMs = (tempoBefore === 150) ? 500 : 400
        var taps = 4
        var expectedDraft = (tempoBefore === 150) ? 120 : 150
        verify(bootstrap.automationTapCadence(gapMs, taps),
               "the production tap route took the cadence")
        compare(bootstrap.automationTapDraftBpm(), expectedDraft,
                "the draft is the tapped average (" + bootstrap.automationTapDraftBpm() + ")")
        compare(bootstrap.automationTapCount(), taps, "the session holds every tap")
        verify(bootstrap.automationTapIdleElapsed(), "the idle window committed the ready draft")
        tryVerify(function() { return bootstrap.automationTempoBpm() === expectedDraft }, 2000,
                  "the tick-zero tempo now names the tapped tempo ("
                  + bootstrap.automationTempoBpm() + ")")
        compare(session.canUndo, true, "the tempo edit recorded one history entry")
        compare(bootstrap.automationDocumentRevision() > revisionBefore, true,
                "the tempo edit published its own revision")
        compare(bootstrap.automationTapCount(), 0, "the commit cleared the session")
        compare(bootstrap.automationInteractionActive(), false,
                "the committed session left no interaction live")
        var committedRevision = bootstrap.automationDocumentRevision()
        compare(committedRevision > revisionBefore, true,
                "the tempo edit published one revision")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationTempoBpm(), tempoBefore,
                "Undo restored the previous tick-zero tempo")
        compare(session.canUndo, undoBefore, "the tempo edit was exactly one history entry")
        verify(bootstrap.requestAutomationRedo(), "the production redo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationTempoBpm(), expectedDraft, "Redo restored the tapped tempo")
        compare(bootstrap.automationDocumentRevision() >= committedRevision, true,
                "the undo and redo each published their own revision")

        // The panel's own readout is driven by the published session, and a
        // single tap is not commit-ready.
        verify(bootstrap.automationTapCadence(500, 3), "the production tap route took 500 ms gaps")
        compare(model.tapTempoTapCount, 3, "the panel publishes the live tap count")
        compare(model.tapTempoActive, true, "the panel publishes the live session")
        inlineDraft = PageSupport.collectByName(testCase, tempoTab, "automationTempoTapDraft", [])[0]
        tryVerify(function() { return inlineDraft && inlineDraft.visible }, 1000,
                  "the live cadence is drawn inside the Tempo tab")
        tryCompare(inlineDraft, "text", "120 BPM", 1000,
                   "the original inline readout shows the tapped tempo")
        compare(inlineDraft.font.family, model.minimumFont.family,
                "live BPM draft uses the minimum caption face")
        compare(inlineDraft.font.pixelSize, model.minimumFont.pixelSize,
                "live BPM draft uses the minimum caption size")
        compare(inlineDraft.font.weight, model.minimumFont.weight,
                "live BPM draft uses the minimum caption weight")
        compare(bootstrap.automationTempoBpm(), expectedDraft,
                "a live session writes nothing until its idle window")
        AutomationMenuSupport.resetAutomationTap(testCase)
        verify(bootstrap.automationTapCadence(750, 3),
               "the production tap route took 750 ms gaps")
        tryCompare(inlineDraft, "text", "80 BPM", 1000,
                   "the readout recomputes on every tap")
        compare(bootstrap.automationTempoBpm(), expectedDraft)
        AutomationMenuSupport.resetAutomationTap(testCase)
        verify(bootstrap.automationTapCadence(500, 1), "the production tap route took a lone tap")
        compare(bootstrap.automationTapCount(), 1, "the lone tap stands in the session")
        verify(!bootstrap.automationTapIdleElapsed(),
               "a lone tap's idle window commits nothing")
        compare(bootstrap.automationTempoBpm(), expectedDraft,
                "a lone tap left the tempo stream alone")
    }
}
