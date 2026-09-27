import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVelocityPromptTransaction() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity-prompt"
        VelocitySupport.mountProductionVelocity(testCase, location)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the page drew at least one node")
        VelocitySupport.clickNode(testCase, nodes[0])
        var model = VelocitySupport.velocityModel(testCase)
        tryVerify(function() { return model.selectedCount === 1 }, 1000,
                  "the prompt case starts from one selected note")
        var noteId = VelocitySupport.selectedNoteId(testCase)
        verify(noteId >= 0, "the prompt case acts on the grid's selected note")
        var before = VelocitySupport.noteVelocity(testCase, noteId)

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000,
                  "the Set Velocity command opened the page's prompt")
        var field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        verify(field, "the prompt composed its text field")
        tryVerify(function() { return field.activeFocus }, 1000,
                  "the prompt took active focus in its field")
        var velocityCard = VelocitySupport.velocityPromptChild(testCase, "velocityPromptCard")
        verify(velocityCard, "the prompt composed its card")
        var base = model.baseFontPx
        compare(velocityCard.appearance.font.pixelSize, session.typographyFonts.body.pixelSize,
                "velocity prompt follows the session body role")
        compare(velocityCard.appearance.dialogPadding, session.layoutSpaces.one)
        compare(velocityCard.appearance.verticalPadding, session.layoutSpaces.half)
        compare(velocityCard.appearance.radius, session.layoutSpaces.half)
        compare(velocityCard.appearance.dragThreshold, base)
        compare(velocityCard.appearance.background, testCase.surface.gridModel.palette.windowBackground,
                "the prompt binds the grid's body surface role")
        compare(String(findChild(velocityCard, "velocityPromptTitle").text).length > 0, true,
                "the prompt draws its title")
        var velocityCardLabels = PageSupport.collectVisibleTexts(testCase, velocityCard, []).map(function(t) { return t.text })
        verify(velocityCardLabels.indexOf("OK") >= 0, "the prompt draws its OK label")
        verify(velocityCardLabels.indexOf("Cancel") >= 0, "the prompt draws its Cancel label")
        PageSupport.auditVisibleTextInk(testCase, velocityCard, "velocity prompt")
        compare(field.text, String(before), "the prompt opened with the captured value")
        keyClick(Qt.Key_9)
        wait(0)
        compare(field.text, "9", "typing replaced the selected numeric text")
        compare(VelocitySupport.noteVelocity(testCase, noteId), before, "typing committed nothing")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 1000, "Enter accepted the prompt")
        tryVerify(function() { return VelocitySupport.noteVelocity(testCase, noteId) === 9 }, 1000,
                  "the accepted value reached the captured note")

        // Escape cancels with no write.
        var accepted = VelocitySupport.noteVelocity(testCase, noteId)
        session.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000, "the prompt reopened")
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true, 1000,
                   "Escape targets the mounted prompt field")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.promptOpen }, 1000, "Escape closed the prompt")
        compare(VelocitySupport.noteVelocity(testCase, noteId), accepted, "Escape wrote nothing")

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryVerify(function() { return model.promptOpen }, 1000, "the prompt reopened")
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true, 1000,
                   "the outside press targets the mounted prompt")
        var underlay = VelocitySupport.velocityPromptChild(testCase, "velocityPromptUnderlay")
        verify(underlay, "the prompt composed its dismissing underlay")
        var empty = underlay.mapFromItem(VelocitySupport.velocityPlot(testCase),
                                         VelocitySupport.velocityPlot(testCase).width - 4,
                                         VelocitySupport.velocityPlot(testCase).height - 4)
        var selectionBeforeOutside = bootstrap.velocitySelectedNoteIds()
        var revisionBeforeOutside = bootstrap.automationDocumentRevision()
        mousePress(underlay, empty.x, empty.y, Qt.LeftButton)
        tryVerify(function() { return !model.promptOpen }, 1000,
                  "the outside press dismissed the prompt before release")
        mouseRelease(underlay, empty.x, empty.y, Qt.LeftButton)
        compare(VelocitySupport.noteVelocity(testCase, noteId), accepted, "the outside dismissal wrote nothing")
        compare(bootstrap.velocitySelectedNoteIds(), selectionBeforeOutside,
                "the paired outside release does not retarget the selection")
        compare(bootstrap.automationDocumentRevision(), revisionBeforeOutside,
                "the paired outside release commits no document edit")
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "outside cancellation returns focus to the roll")
    }

    function test_productionVelocityPromptButtonsAndFocus() {
        if (testCase.containerPhase) skip("production composition only")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-prompt-buttons")
        VelocitySupport.clickNode(testCase, VelocitySupport.velocityNodes(testCase)[0])
        var noteId = VelocitySupport.selectedNoteId(testCase)
        var before = VelocitySupport.noteVelocity(testCase, noteId)
        var initialRevision = bootstrap.automationDocumentRevision()
        var model = VelocitySupport.velocityModel(testCase)
        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        var field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        var accept = VelocitySupport.velocityPromptChild(testCase, "noteVelocityAccept")
        var cancel = VelocitySupport.velocityPromptChild(testCase, "noteVelocityCancel")
        verify(field && accept && cancel, "the mounted prompt draws the field and both buttons")
        tryCompare(field, "activeFocus", true)
        compare(field.text, String(before))
        compare(field.selectedText, String(before), "the initial value is selected for replacement")
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_5)
        compare(field.text, "95")
        compare(VelocitySupport.noteVelocity(testCase, noteId), before, "editing the displayed draft writes nothing")
        keyClick(Qt.Key_Tab)
        compare(accept.activeFocus, true)
        keyClick(Qt.Key_Tab)
        compare(cancel.activeFocus, true)
        keyClick(Qt.Key_Tab)
        compare(field.activeFocus, true, "Tab wraps back to the numeric field")
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        compare(cancel.activeFocus, true)
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        compare(accept.activeFocus, true)
        keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
        compare(field.activeFocus, true, "reverse traversal wraps to the field")
        compare(field.text, "95", "traversing focus preserves the typed draft")
        compare(model.promptOpen, true)
        compare(bootstrap.automationDocumentRevision(), initialRevision,
                "focus traversal has not committed the numeric draft")
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        tryCompare(model, "promptOpen", false)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "the roll regains focus after the OK button")
        tryVerify(function() { return VelocitySupport.noteVelocity(testCase, noteId) === 95 }, 1000,
                  "the button commits the captured note")
        var acceptedRevision = bootstrap.automationDocumentRevision()
        tryVerify(function() {
            return findChild(testCase.surface, "velocityPromptCard") === null
        }, 3000, "the accepted prompt unmounts before the next command")

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        tryVerify(function() {
            var current = findChild(testCase.surface, "noteVelocityInput")
            return current !== null && current.activeFocus
        }, 3000)
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        cancel = VelocitySupport.velocityPromptChild(testCase, "noteVelocityCancel")
        compare(field.text, "95", "reopening selects the committed value")
        compare(field.selectedText, "95")
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_0)
        compare(field.text, "20")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton)
        tryCompare(model, "promptOpen", false)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "the roll regains focus after Cancel")
        compare(VelocitySupport.noteVelocity(testCase, noteId), 95, "Cancel discards the draft")
        compare(bootstrap.automationDocumentRevision(), acceptedRevision,
                "Cancel does not add a document edit")
    }

    function test_productionVelocityPromptValidationAndDismissal() {
        if (testCase.containerPhase) skip("production composition only")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-prompt-validation")
        VelocitySupport.clickNode(testCase, VelocitySupport.velocityNodes(testCase)[0])
        var noteId = VelocitySupport.selectedNoteId(testCase)
        var before = VelocitySupport.noteVelocity(testCase, noteId)
        var revision = bootstrap.automationDocumentRevision()
        var model = VelocitySupport.velocityModel(testCase)
        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        var field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        var accept = VelocitySupport.velocityPromptChild(testCase, "noteVelocityAccept")
        tryCompare(field, "activeFocus", true)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        compare(field.text, "999", "intermediate out-of-range digits remain editable")
        keyClick(Qt.Key_Return)
        compare(model.promptOpen, true, "invalid Return does not accept")
        compare(field.text, String(before), "invalid Return corrects to the captured value")
        compare(VelocitySupport.noteVelocity(testCase, noteId), before)
        compare(bootstrap.automationDocumentRevision(), revision, "invalid Return writes nothing")
        field.selectAll()
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_9)
        mouseClick(accept, accept.width / 2, accept.height / 2, Qt.LeftButton)
        compare(model.promptOpen, true, "invalid OK does not close the form")
        compare(field.text, String(before), "invalid OK corrects the displayed value")
        compare(bootstrap.automationDocumentRevision(), revision, "invalid OK adds no edit")
        field.forceActiveFocus(Qt.OtherFocusReason)
        field.selectAll()
        keyClick(Qt.Key_2)
        keyClick(Qt.Key_0)
        compare(field.text, "20", "Escape discards a valid uncommitted draft")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "Escape returns focus to the roll")
        compare(bootstrap.automationDocumentRevision(), revision)

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true,
                   1000, "the reopened prompt has mounted before an outside press")
        var selectionBefore = bootstrap.velocitySelectedNoteIds()
        var underlay = VelocitySupport.velocityPromptChild(testCase, "velocityPromptUnderlay")
        verify(underlay)
        var plot = VelocitySupport.velocityPlot(testCase)
        var outside = underlay.mapFromItem(plot, plot.width - 4, plot.height - 4)
        var card = VelocitySupport.velocityPromptChild(testCase, "velocityPromptCard")
        verify(card && outside.x >= 0 && outside.x < underlay.width
               && outside.y >= 0 && outside.y < underlay.height,
               "the outside point lands inside the mounted underlay")
        verify(outside.x < card.x || outside.x >= card.x + card.width
               || outside.y < card.y || outside.y >= card.y + card.height,
               "the outside point misses the visible prompt card")
        mousePress(underlay, outside.x, outside.y, Qt.RightButton)
        tryCompare(model, "promptOpen", false)
        compare(bootstrap.velocitySelectedNoteIds(), selectionBefore,
                "the outside right press does not retarget the selection")
        mouseRelease(underlay, outside.x, outside.y, Qt.RightButton)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "outside right click dismisses and restores focus")
        compare(VelocitySupport.noteVelocity(testCase, noteId), before)
        compare(bootstrap.velocitySelectedNoteIds(), selectionBefore,
                "the outside right release does not retarget the selection")
        compare(bootstrap.automationDocumentRevision(), revision,
                "outside right click writes nothing")
        tryVerify(function() {
            return findChild(testCase.surface, "velocityPrompt") === null
        }, 1000, "the underlay retires after swallowing the paired right release")
    }

    function test_productionVelocityPromptBoundedKeys() {
        if (testCase.containerPhase) skip("production composition only")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-prompt-bounds")
        VelocitySupport.clickNode(testCase, VelocitySupport.velocityNodes(testCase)[0])
        var noteId = VelocitySupport.selectedNoteId(testCase)
        var model = VelocitySupport.velocityModel(testCase)
        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        var field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        for (var down = 0; down < 13; ++down)
            keyClick(Qt.Key_PageDown)
        compare(field.text, "1", "PageDown clamps the displayed value at one")
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        tryVerify(function() { return VelocitySupport.noteVelocity(testCase, noteId) === 1 }, 1000)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "lower-bound acceptance restores roll focus before reopening")

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        for (var up = 0; up < 13; ++up)
            keyClick(Qt.Key_PageUp)
        compare(field.text, "127", "PageUp clamps the displayed value at 127")
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        tryVerify(function() { return VelocitySupport.noteVelocity(testCase, noteId) === 127 }, 1000)
        tryCompare(testCase.rollInput(), "activeFocus", true,
                   1000, "upper-bound acceptance restores roll focus before reopening")

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(model, "promptOpen", true)
        field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Up, Qt.ControlModifier)
        compare(field.text, "127", "both step sizes clamp at the upper bound")
        compare(model.promptOpen, true)
        compare(bootstrap.automationDocumentRevision(), revision, "clamped keys write nothing")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false)
    }
}
