import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_velocityHintsResumeAfterOutsideRelease() {
        if (testCase.containerPhase) skip("the production owner runs in its own process")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-hint-release")
        var input = VelocitySupport.velocityPlotInput(testCase)
        var ruler = VelocitySupport.velocityRuler(testCase)
        var status = findChild(testCase.surface, "mouseHintStatus")
        var text = findChild(status, "mouseHintStatusText")
        verify(status && text, "the production status strip is drawn")
        tryCompare(testCase.surface, "hintWindowActive", true)
        mouseMove(status, status.width / 2, status.height / 2)
        tryCompare(text, "text", "")

        var x = input.width / 2
        var y = input.height / 2
        mouseMove(input, x, y)
        tryVerify(function() { return text.text.length > 0 }, 1000,
                  "the plot supplies instructions before the gesture")
        var plotInstructions = text.text
        mouseMove(ruler, ruler.width / 2, ruler.height / 2)
        tryVerify(function() {
            return text.text.length > 0 && text.text !== plotInstructions
        }, 1000, "the gutter advertises its different interaction")
        mouseMove(input, x, y)
        tryCompare(text, "text", plotInstructions)

        // Keep x fixed so the middle-button grab changes no camera position.
        var outside = input.mapFromItem(status, status.width / 2, status.height / 2)
        mousePress(input, x, y, Qt.MiddleButton)
        mouseMove(input, x, outside.y, -1, Qt.MiddleButton)
        mouseRelease(input, x, outside.y, Qt.MiddleButton)
        tryCompare(text, "text", "", 1000,
                   "an outside release retires the originating plot instructions")
        mouseMove(input, x, y)
        tryCompare(text, "text", plotInstructions, 1000,
                   "returning to the plot restores its instructions")
    }

    // Real pointer input on the drawn nodes: a selection click, then a vertical
    // drag that previews and commits exactly one document transaction.
    function test_productionVelocityPointerEdit() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity-pointer"
        VelocitySupport.mountProductionVelocity(testCase, location)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the page drew at least one node")
        var notes = VelocitySupport.primaryGridNotes(testCase)
        verify(notes.length > 0, "the grid published editable primary notes")

        var input = VelocitySupport.velocityPlotInput(testCase)
        var node = nodes[0]
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        mouseClick(input, center.x, center.y, Qt.LeftButton)
        tryVerify(function() { return VelocitySupport.velocityModel(testCase).selectedCount === 1 },
                  1000, "a node click selected exactly its own note")

        var targetId = VelocitySupport.selectedNoteId(testCase)
        verify(targetId >= 0, "the click left one primary note selected")
        var before = VelocitySupport.noteVelocity(testCase, targetId)
        var raised = center.y - 24
        mousePress(input, center.x, center.y, Qt.LeftButton)
        mouseMove(input, center.x, raised, -1, Qt.LeftButton)
        compare(VelocitySupport.velocityModel(testCase).interactionActive, true,
                "a live drag reports an active interaction to the container")
        mouseRelease(input, center.x, raised, Qt.LeftButton)
        tryVerify(function() {
            return VelocitySupport.noteVelocity(testCase, targetId) !== before
        }, 1000, "the released drag committed one velocity change")
        compare(VelocitySupport.velocityModel(testCase).interactionActive, false,
                "the release ended the page's interaction")
    }

    function test_productionVelocityNumericInput() {
        if (testCase.containerPhase) skip("production composition only")
        VelocitySupport.mountProductionVelocity(testCase, "velocity-numeric-input")
        VelocitySupport.clickNode(testCase, VelocitySupport.velocityNodes(testCase)[0])
        var noteId = VelocitySupport.selectedNoteId(testCase)
        var before = VelocitySupport.noteVelocity(testCase, noteId)
        session.performGridCommand(bootstrap.setVelocityCommand())
        var model = VelocitySupport.velocityModel(testCase)
        tryVerify(function() { return model.promptOpen }, 1000)
        var field = VelocitySupport.velocityPromptChild(testCase, "noteVelocityInput")
        var accept = VelocitySupport.velocityPromptChild(testCase, "noteVelocityAccept")
        var cancel = VelocitySupport.velocityPromptChild(testCase, "noteVelocityCancel")
        verify(field && accept && cancel, "the original numeric form is drawn")
        tryVerify(function() { return field.activeFocus }, 1000)
        keyClick(Qt.Key_5)
        keyClick(Qt.Key_0)
        keyClick(Qt.Key_Tab)
        compare(accept.activeFocus, true)
        compare(field.text, "50")
        keyClick(Qt.Key_Tab)
        compare(cancel.activeFocus, true)
        keyClick(Qt.Key_Tab)
        compare(field.activeFocus, true)
        var reverse = [cancel, accept, field]
        for (var i = 0; i < reverse.length; ++i) {
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
            compare(reverse[i].activeFocus, true)
        }
        keyClick(Qt.Key_Up)
        compare(field.text, "51")
        keyClick(Qt.Key_Down, Qt.ControlModifier)
        compare(field.text, "41")
        keyClick(Qt.Key_PageUp)
        compare(field.text, "51")
        keyClick(Qt.Key_PageDown)
        compare(field.text, "41")
        mouseWheel(field, field.width / 2, field.height / 2, 0, 60, Qt.NoButton)
        compare(field.text, "41", "a half-notch is retained, not rounded")
        mouseWheel(field, field.width / 2, field.height / 2, 0, 60, Qt.NoButton)
        tryCompare(field, "text", "42", 1000)
        mouseWheel(field, field.width / 2, field.height / 2, 0, 120,
                   Qt.NoButton, Qt.ControlModifier)
        tryCompare(field, "text", "52", 1000, "Control wheel steps by ten")
        var threshold = field.parent.appearance.dragThreshold
        var x = field.width / 2
        var y = field.height / 2
        mousePress(field, x, y, Qt.LeftButton)
        mouseMove(field, x, y - threshold + 1, -1, Qt.LeftButton)
        compare(field.text, "52", "motion below the scrub threshold writes nothing")
        mouseMove(field, x, y - threshold - 30, -1, Qt.LeftButton)
        mouseRelease(field, x, y - threshold - 30, Qt.LeftButton)
        tryCompare(field, "text", "67", 1000, "normal scrub accumulates half a step per pixel")
        mousePress(field, x, y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(field, x, y - threshold - 30, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseRelease(field, x, y - threshold - 30, Qt.LeftButton, Qt.ShiftModifier)
        tryCompare(field, "text", "73", 1000, "Shift scrub accumulates one fifth step per pixel")
        compare(VelocitySupport.noteVelocity(testCase, noteId), before, "numeric interaction remains a draft")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 1000)
        compare(VelocitySupport.noteVelocity(testCase, noteId), 73, "acceptance commits the scrubbed draft")
    }

    // Hiding the section cancels the page's live gesture without a write, and a
    // stale document change cancels instead of retargeting.
    function test_productionVelocityCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity-cancel"
        VelocitySupport.mountProductionVelocity(testCase, location)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the page drew at least one node")
        var input = VelocitySupport.velocityPlotInput(testCase)
        var node = nodes[0]
        var center = node.mapToItem(input, node.width / 2, node.height / 2)
        mousePress(input, center.x, center.y, Qt.LeftButton)
        mouseMove(input, center.x, center.y - 24, -1, Qt.LeftButton)
        var model = VelocitySupport.velocityModel(testCase)
        compare(model.interactionActive, true, "the gesture is live before the hide")
        var selected = model.selectedCount
        compare(selected > 0, true, "the gesture owns a selection")

        // The container's own hide path cancels the page synchronously.
        LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        tryVerify(function() { return !testCase.section(testCase.velocityKind).visible }, 1000,
                  "the section hid")
        compare(model.interactionActive, false, "hiding the section cancelled the gesture")
        mouseRelease(input, center.x, center.y - 24, Qt.LeftButton)
        compare(model.interactionActive, false, "the released pointer committed nothing")
        LayoutSupport.clickToggle(testCase, testCase.velocityKind)
        tryVerify(function() { return testCase.section(testCase.velocityKind).visible }, 1000,
                  "the section is visible again")
    }

    function test_productionVelocityPlayheadPerformance() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity-playhead"
        VelocitySupport.mountProductionVelocity(testCase, location)
        verify(bootstrap.pausePlayheadPolling(),
               "the lane holds the production polling task for determinism")
        bootstrap.presentPlayheadObservation(1000, 2)
        var builds = bootstrap.velocityContentBuilds()
        var presented = bootstrap.velocityPlayheadPresentations()
        var published = bootstrap.publishedPlayheadPresentations()
        var slot = bootstrap.velocityPresentedSlot()
        // 128 distinct shared ticks, one per presentation: the presenter publishes
        // every one of them and the page consumes every publication.
        var updates = 128
        for (var step = 1; step <= updates; ++step)
            bootstrap.presentPlayheadObservation((1 + step) * 1000, 2)
        var expected = published + updates
        tryVerify(function() {
            return bootstrap.publishedPlayheadPresentations() === expected
        }, 2000, "the presenter published all " + updates + " shared presentations ("
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        tryVerify(function() {
            return bootstrap.velocityPlayheadPresentations() === presented + updates
        }, 2000, "every published presentation reached the page's diagnostics (page "
                  + (bootstrap.velocityPlayheadPresentations() - presented) + ", presenter "
                  + (bootstrap.publishedPlayheadPresentations() - published) + ")")
        compare(bootstrap.velocityPresentedSlot(), slot,
                "every presented tick stayed inside its own voice context")
        compare(bootstrap.velocityContentBuilds(), builds,
                "128 shared-playhead presentations rebuilt no velocity content")
    }

    // The page's unsupported-context diagnostic: the staged fixture's programs
    // are parsed top-level voices, so the page must be editing exactly.
    function test_productionVelocityContextIsExact() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-velocity-context"
        VelocitySupport.mountProductionVelocity(testCase, location)
        compare(bootstrap.velocityContextUnsupported(), false,
                "the staged fixture resolves an exact top-level map")
        compare(VelocitySupport.velocityModel(testCase).contextDiagnostic, "",
                "an exact context publishes no diagnostic")
    }
}
