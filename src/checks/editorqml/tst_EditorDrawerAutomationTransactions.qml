import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerAutomationMenuSupport.js" as AutomationMenuSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    Component { id: bandImageReader; Canvas { width: 1; height: 1 } }

    function test_productionAutomationDomainRowsThroughInput() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-rows"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(volumeTab >= 0, "the catalog publishes the Volume parameter")
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active")

        // a) A drag sweep over the lane: every crossed lattice tick is written,
        // and the trailing held value is restored one step past the release.
        var before = bootstrap.automationLaneValues()
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        compare(nodes.length > 1, true,
                "the Volume lane projects more than one display point (" + nodes.length + ")")
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the lane leaves an empty press point for a sweep ("
               + AutomationGestureSupport.automationLaneNodes(testCase).length + " nodes)")
        mousePress(input, free.x, free.y, Qt.LeftButton)
        mouseMove(input, Math.min(input.width - 4, free.x + 80), free.y, -1, Qt.LeftButton)
        mouseMove(input, Math.min(input.width - 4, free.x + 160), free.y, -1, Qt.LeftButton)
        tryVerify(function() { return AutomationGestureSupport.automationPreviewItems(testCase).length > 0 }, 1000,
                  "the moving sweep published its draft markers")
        mouseRelease(input, Math.min(input.width - 4, free.x + 160), free.y, Qt.LeftButton)
        var swept = bootstrap.automationLaneValues()
        compare(swept !== before, true,
                "the released sweep committed a document change (" + swept + " of " + before + ")")
        compare(bootstrap.automationLaneTicks().split(",").length > 1, true,
                "sweepSteppingAndRampFinish: the swept lane carries more than one written tick")

        // b) A Shift sweep is the ramp: its end value differs from its anchor.
        AutomationGestureSupport.dragAutomationPlot(testCase, free.x, free.y, Math.min(input.width - 4, free.x + 220),
                                    free.y < input.height / 2 ? input.height * 0.8
                                                              : input.height * 0.2,
                                    Qt.ShiftModifier)
        compare(bootstrap.automationLaneValues() !== swept, true,
                "sweepSteppingAndRampFinish: the ramp sweep committed a document change")
        compare(session.canUndo, true, "the ramp sweep reached the document history")

        var panTab = bootstrap.automationPanIndex()
        verify(panTab >= 0, "the catalog publishes the Pan parameter")
        verify(AutomationMenuSupport.clearAutomationLane(testCase, panTab), "the Pan lane starts empty")
        var highColumn = AutomationGestureSupport.automationFreeColumn(testCase, 24)
        verify(highColumn > 0, "the empty Pan lane leaves a column for its first row")
        AutomationGestureSupport.dragAutomationPlot(testCase, highColumn, Math.round(input.height * 0.15),
                                    Math.min(input.width - 4, highColumn + 96),
                                    Math.round(input.height * 0.15))
        tryVerify(function() { return bootstrap.automationLaneEventCount() > 0 }, 2000,
                  "the Pan sweep wrote its first row")
        var lowColumn = AutomationGestureSupport.automationFreeColumn(testCase, highColumn + 140)
        verify(lowColumn > 0, "the lane leaves a column for its second row")
        AutomationGestureSupport.dragAutomationPlot(testCase, lowColumn, Math.round(input.height * 0.85),
                                    Math.min(input.width - 4, lowColumn + 96),
                                    Math.round(input.height * 0.85))
        tryVerify(function() { return AutomationGestureSupport.automationLaneNodes(testCase).length > 1 }, 2000,
                  "the Pan lane projects both written rows")
        var neutralRow = AutomationGestureSupport.automationRowForValue(testCase, 64)
        compare(neutralRow > 0, true,
                "the drawn rows name the neutral's own row (" + Math.round(neutralRow) + ")")
        var panNodes = AutomationGestureSupport.automationLaneNodes(testCase)
        var panItem = null
        for (var p = 0; p < panNodes.length; ++p) {
            if (!panNodes[p].model.projected && Math.abs(panNodes[p].model.value - 64) >= 20) {
                panItem = panNodes[p]
                break
            }
        }
        verify(panItem, "the written Pan lane draws a node away from the neutral ("
               + panNodes.length + " drawn)")
        var panPoint = AutomationGestureSupport.automationNodePoint(testCase, panItem)
        verify(panPoint, "the Pan node projects a drawn centre")
        var panTick = String(panItem.model.tick)
        var panValue = panItem.model.value
        var panBefore = bootstrap.automationLaneValues()
        compare(panBefore.indexOf(panTick + ":64") >= 0, false,
                "the dragged Pan node starts away from the neutral (" + panTick + ":"
                + panValue + " of " + panBefore + ")")
        var settleRow = neutralRow + 2
        AutomationGestureSupport.dragAutomationPlotRow(testCase, panPoint.x, panPoint.y, panPoint.y - 30, settleRow)
        var unsnapped = bootstrap.automationLaneValues()
        compare(unsnapped !== panBefore, true,
                "the same drag without the modifier moved the node (" + panTick + ":"
                + panValue + " of " + panBefore + " became " + unsnapped + ")")
        compare(unsnapped.indexOf(panTick + ":64") >= 0, false,
                "the same drag without the modifier keeps the pointer's own value ("
                + unsnapped + ")")
        verify(bootstrap.requestAutomationUndo(), "the production undo completed (error='"
               + session.lastSaveError + "')")
        compare(bootstrap.automationLaneValues(), panBefore, "Undo restored the written Pan lane")
        var restored = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        panPoint = restored < 0 ? null
                                : AutomationGestureSupport.automationNodePoint(testCase, AutomationGestureSupport.automationLaneNodes(testCase)[restored])
        verify(panPoint, "the restored Pan lane draws its node again")
        AutomationGestureSupport.dragAutomationPlotRow(testCase, panPoint.x, panPoint.y, panPoint.y - 30, settleRow,
                                       Qt.ControlModifier)
        var snapped = bootstrap.automationLaneValues()
        compare(snapped.indexOf(panTick + ":64") >= 0, true,
                "panNeutralSnap: the Control-armed drag committed the neutral 64 at the node's own"
                + " tick (" + snapped + ")")
        compare(snapped.split(",").length, panBefore.split(",").length,
                "the snap moved the value without adding or dropping an occurrence")

        // d) A node drag on the Volume lane moves one occurrence, and a
        // Shift-held stationary release deletes nothing.
        AutomationTabsSupport.clickAutomationTab(testCase, volumeTab)
        tryVerify(function() { return bootstrap.automationActiveParameterIndex() === volumeTab }, 2000,
                  "the Volume lane is active again")
        var dragged = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(dragged.length > 0, "the swept Volume lane still projects nodes")
        var first = AutomationGestureSupport.automationNodePoint(testCase, dragged[0])
        var valuesBefore = bootstrap.automationLaneValues()
        AutomationGestureSupport.dragAutomationPlot(testCase, first.x, first.y, first.x, first.y - 30)
        compare(bootstrap.automationLaneValues() !== valuesBefore, true,
                "nodeDragAndPhantomOutcomes: the released node drag moved its value ("
                + bootstrap.automationLaneValues() + ")")
        var afterMove = bootstrap.automationLaneValues()
        var shiftNode = AutomationGestureSupport.automationNodePoint(testCase, AutomationGestureSupport.automationLaneNodes(testCase)[0])
        AutomationGestureSupport.dragAutomationPlot(testCase, shiftNode.x, shiftNode.y, shiftNode.x, shiftNode.y,
                                    Qt.ShiftModifier)
        compare(bootstrap.automationLaneValues(), afterMove,
                "nodeDragAndPhantomOutcomes: a Shift-held stationary release deletes nothing")

        // e) The pencil tool: a stroke writes the point range it crossed.
        var pencilNode = AutomationGestureSupport.automationNodePoint(testCase, AutomationGestureSupport.automationLaneNodes(testCase)[0])
        model.isPencilMode = true
        wait(0)
        var beforeStroke = bootstrap.automationLaneValues()
        AutomationGestureSupport.dragAutomationPlot(testCase, pencilNode.x, pencilNode.y, pencilNode.x + 24, pencilNode.y + 6)
        compare(bootstrap.automationLaneValues() !== beforeStroke, true,
                "pointRangeAndPencilReplacements: the pencil stroke committed its range ("
                + bootstrap.automationLaneValues() + ")")
        model.isPencilMode = false
        wait(0)
        compare(session.canUndo, true, "the stroke reached the document history")
    }

    function test_productionAutomationBandHalfOpenPhysicalBoundaryDpr1() {
        if (testCase.containerPhase) skip("production composition only")
        if (Screen.devicePixelRatio !== 1) skip("DPR1 boundary runs in the DPR1 lane")
        verifyPhysicalBandBoundary(1)
    }

    function test_productionAutomationBandHalfOpenPhysicalBoundaryDpr2() {
        if (testCase.containerPhase) skip("production composition only")
        if (Screen.devicePixelRatio !== 2) skip("DPR2 boundary runs in the DPR2 lane")
        verifyPhysicalBandBoundary(2)
    }

    function verifyPhysicalBandBoundary(expectedDpr) {
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-band-physical-edge")
        var volume = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volume),
               "the mounted Volume lane has written calibration markers")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        var ticks = bootstrap.automationLaneTicks().split(",").map(Number)
        verify(ticks.length >= 2, "the fixture's written Volume sweep has two separate ticks")
        var startTick = ticks[0]
        var endTick = ticks[ticks.length - 1]
        var grid = testCase.surface.gridModel
        function xAt(tick) {
            return Math.round(tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX)
        }
        var startX = xAt(startTick)
        var endX = xAt(endTick)
        verify(endTick > startTick && startX > 2 && endX < input.width - 2
               && endX - startX > model.baseFontPx,
               "fixture ticks project both band endpoints inside the plot without drawn nodes")
        var free = AutomationGestureSupport.automationFreePoint(testCase)
        verify(free, "the band gesture has a free input row")
        var bandY = free.y
        function selectBand() {
            mousePress(input, startX, bandY, Qt.RightButton)
            mouseMove(input, endX, bandY, -1, Qt.RightButton)
            mouseRelease(input, endX, bandY, Qt.RightButton)
            compare(bootstrap.automationSelectionRange(), startTick + ":" + endTick,
                    "a real right drag publishes the calibration markers' half-open ticks")
        }
        var beforeCancel = bootstrap.automationLaneValues()
        var revisionBeforeCancel = bootstrap.automationDocumentRevision()
        var undoBeforeCancel = session.canUndo
        mousePress(input, startX, bandY, Qt.RightButton)
        mouseMove(input, endX, bandY, -1, Qt.RightButton)
        verify(bootstrap.automationInteractionActive(),
               "the right drag stages an active band before cancellation")
        compare(bootstrap.automationSelectionRange(), "",
                "a drafted band does not commit selection before release")
        verify(bootstrap.cancelInput(), "the mounted composition cancels the drafted band")
        mouseRelease(input, endX, bandY, Qt.RightButton)
        compare(bootstrap.automationLaneValues(), beforeCancel,
                "cancelling the staged band preserves original lane bytes")
        compare(bootstrap.automationDocumentRevision(), revisionBeforeCancel,
                "cancelling the staged band publishes no document revision")
        compare(session.canUndo, undoBeforeCancel,
                "cancelling the staged band adds no Undo entry")
        compare(bootstrap.automationSelectionRange(), "",
                "cancelling the staged band leaves no committed selection")
        selectBand()
        waitForRendering(testCase.surface)
        var frame = null
        verify(testCase.surface.grabToImage(function(result) { frame = result }),
               "the mounted drawer accepts a physical framebuffer capture")
        tryVerify(function() { return frame !== null }, 3000,
                  "the physical framebuffer capture completes")
        var imageFile = bootstrap.projectRoot + "/automation-band-physical.png"
        verify(frame.saveToFile(imageFile), "the physical framebuffer is saved to the copied fixture")
        var reader = bandImageReader.createObject(testCase.surface)
        tryCompare(reader, "available", true, 3000)
        var imageURL = "file://" + imageFile
        reader.loadImage(imageURL)
        tryVerify(function() { return reader.isImageLoaded(imageURL) }, 3000,
                  "the physical image bytes load for independent dimensions")
        var image = reader.getContext("2d").createImageData(imageURL)
        compare(Screen.devicePixelRatio, expectedDpr,
                "the declared physical-boundary lane observes its actual screen DPR")
        compare(image.width, Math.round(testCase.surface.width * expectedDpr),
                "the physical framebuffer width matches the declared lane DPR")
        compare(image.height, Math.round(testCase.surface.height * expectedDpr),
                "the physical framebuffer height matches the declared lane DPR")
        reader.destroy()
        mousePress(input, (startX + endX) / 2, bandY, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), startTick + ":" + endTick,
                "a real midpoint press preserves the selected Volume band")
        mouseRelease(input, (startX + endX) / 2, bandY, Qt.RightButton)
        model.dismissMenu()
        mousePress(input, endX, bandY, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "",
                "a real press on the exclusive displayed endpoint clears the band before snapping")
        mouseRelease(input, endX, bandY, Qt.RightButton)
        model.dismissMenu()
        selectBand()
        mousePress(input, startX - 1, bandY, Qt.RightButton)
        compare(bootstrap.automationSelectionRange(), "",
                "one logical pixel outside the displayed start clears the band before snapping")
        mouseRelease(input, startX - 1, bandY, Qt.RightButton)
        model.dismissMenu()
    }

    function test_productionAutomationPromptTransaction() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-automation-prompt"
        AutomationTabsSupport.mountProductionAutomation(testCase, location)
        var model = AutomationTabsSupport.automationModel(testCase)
        var volumeTab = bootstrap.automationVolumeIndex()
        verify(AutomationGestureSupport.writeVolumeLanePoints(testCase, volumeTab),
               "the case created a written Volume lane with a real sweep")
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var nodes = AutomationGestureSupport.automationLaneNodes(testCase)
        verify(nodes.length > 0, "the Volume lane projects a written node")
        var valuesBefore = bootstrap.automationLaneValues()

        // The node's own menu, driven by a real right press.
        var writtenIndex = AutomationGestureSupport.automationWrittenNodeIndex(testCase)
        verify(writtenIndex >= 0, "the Volume lane draws a written node")
        verify(AutomationMenuSupport.rightClickAutomationNode(testCase, writtenIndex), "the written node has a centre")
        tryVerify(function() { return bootstrap.automationMenuOpen() }, 2000,
                  "the right press on the node opened its menu")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationMenu", true)
        compare(bootstrap.automationMenuActions(), "1,2",
                "the point menu publishes Set Value and Delete")
        var panel = findChild(testCase.surface, "automationMenuPanel")
        verify(panel, "the menu composed its panel")
        compare(findChild(panel, "quickMenuFrame").Accessible.role, Accessible.PopupMenu,
                "the drawn menu frame publishes the popup-menu role")
        var rows = AutomationMenuSupport.automationMenuRowItems(testCase)
        compare(rows.length, 2, "the point menu drew its two rows")
        compare(rows[0].Accessible.role, Accessible.MenuItem, "a row publishes the menu-item role")
        compare(String(rows[0].Accessible.name).length > 0, true,
                "a row publishes its accessible name ('" + rows[0].Accessible.name + "')")
        PageSupport.auditVisibleTextInk(testCase, panel, "automation point menu")
        var menuRowTexts = PageSupport.collectVisibleTexts(testCase, rows[0], [])
        compare(menuRowTexts.length > 0 && String(menuRowTexts[0].text).length > 0, true,
                "the menu draws its row label ('" + (menuRowTexts.length > 0 ? menuRowTexts[0].text : "") + "')")

        // Set Value opens the captured form.
        compare(bootstrap.automationMenuActions().indexOf("1") >= 0, true,
                "the captured point menu publishes Set Value ("
                + bootstrap.automationMenuActions() + ")")
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 1), "the Set Value row is the current one")
        compare(bootstrap.automationPromptOpen(), true,
                "Set Value opened the captured form")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        var field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the prompt composed its value field")
        tryVerify(function() { return field.activeFocus }, 2000,
                  "the prompt took active focus in its field")
        compare(model.promptDraft.length > 0, true, "the prompt opened with the captured value")
        var autoPrompt = findChild(testCase.surface, "automationPrompt")
        verify(autoPrompt, "the prompt composed its production surface")
        PageSupport.auditVisibleTextInk(testCase, autoPrompt, "automation prompt")
        var promptCard = findChild(autoPrompt, "automationPromptCard")
        var promptTitle = findChild(autoPrompt, "automationPromptTitle")
        verify(promptCard && promptTitle, "the mounted automation prompt draws a title and card")
        compare(promptTitle.font.family, session.typographyFonts.body.family,
                "automation prompt uses the session body face")
        compare(promptTitle.font.pixelSize, session.typographyFonts.body.pixelSize,
                "automation prompt uses the session body size")
        compare(promptTitle.font.weight, session.typographyFonts.body.weight,
                "automation prompt uses the session body weight")
        compare(promptCard.appearance.dialogPadding, session.layoutSpaces.one,
                "automation prompt card uses one space of padding")
        compare(promptCard.appearance.buttonPadding, session.layoutSpaces.one,
                "automation prompt buttons use one space of padding")
        compare(promptCard.appearance.radius, session.layoutSpaces.half,
                "automation prompt radius uses half space")
        compare(field.parent.appearance.horizontalPadding, session.layoutSpaces.one,
                "automation prompt input uses one space of horizontal padding")

        // A typed draft commits exactly one transaction.
        field.selectAll()
        keyClick(Qt.Key_9)
        wait(0)
        compare(field.text, "9", "typing replaced the selected numeric text")
        compare(bootstrap.automationLaneValues(), valuesBefore, "typing committed nothing")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !model.promptOpen }, 2000, "Enter accepted the prompt")
        tryVerify(function() { return bootstrap.automationLaneValues() !== valuesBefore }, 2000,
                  "the accepted value reached the captured node ("
                  + bootstrap.automationLaneValues() + ")")
        compare(bootstrap.automationFrozenRevision() < 0, true,
                "an accepted prompt leaves no frozen revision behind")

        // An out-of-domain intermediate draft is refused locally by the original
        // IntValidator; Return leaves it open without document or history writes.
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)),
               "the written node's menu reopened for the draft case")
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 1), "the Set Value row is the current one")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        field = findChild(AutomationTabsSupport.automationPageItem(testCase), "automationPromptInput")
        verify(field, "the prompt composed its value field again")
        var invalid = String(Number(model.promptMaximum) + 1)
        var promptValues = bootstrap.automationLaneValues()
        var promptRevision = bootstrap.automationDocumentRevision()
        var undoBefore = session.canUndo
        field.selectAll()
        for (var digit = 0; digit < invalid.length; ++digit)
            keyClick(Qt.Key_0 + Number(invalid.charAt(digit)))
        wait(0)
        compare(field.text, invalid,
                "the field took the out-of-domain digits (" + invalid + ")")
        keyClick(Qt.Key_Return)
        wait(0)
        compare(bootstrap.automationPromptOpen(), true,
                "the refused acceptance left the prompt open")
        compare(bootstrap.automationLaneValues(), promptValues,
                "the refused acceptance wrote nothing")
        compare(bootstrap.automationDocumentRevision(), promptRevision,
                "the refused acceptance published no revision")
        compare(session.canUndo, undoBefore, "the refused acceptance recorded no history entry")
        var valid = String(Number(model.promptMaximum) - 1)
        field.selectAll()
        for (var validDigit = 0; validDigit < valid.length; ++validDigit)
            keyClick(Qt.Key_0 + Number(valid.charAt(validDigit)))
        compare(field.text, valid, "the user corrected the intermediate draft")
        keyClick(Qt.Key_Return)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "the valid draft accepted through the form's own route")

        // Escape cancels with no write, and leaves no frozen revision.
        var accepted = bootstrap.automationLaneValues()
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)),
               "the written node's menu reopened")
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 1),
               "the reopened menu's Set Value row is the current one")
        compare(bootstrap.automationPromptOpen(), true,
                "the prompt reopened")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        compare(bootstrap.automationFrozenRevision() >= 0, true,
                "an open prompt holds the revision it captured")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "Escape closed the prompt")
        compare(bootstrap.automationLaneValues(), accepted, "Escape wrote nothing")
        compare(bootstrap.automationFrozenRevision(), -1,
                "a cancelled prompt leaves no frozen revision behind")
        verify(bootstrap.cancelInput(), "the composition's own cancellation settles the page")
        compare(bootstrap.automationInteractionActive(), false,
                "the cancelled page reports no interaction")

        // An outside press dismisses without a write.
        verify(AutomationMenuSupport.openAutomationNodeMenu(testCase, AutomationGestureSupport.automationWrittenNodeIndex(testCase)),
               "the written node's menu opened once more")
        verify(AutomationMenuSupport.triggerAutomationMenuRow(testCase, 1),
               "the menu's Set Value row is the current one once more")
        compare(bootstrap.automationPromptOpen(), true,
                "the prompt reopened once more")
        AutomationMenuSupport.awaitAutomationModal(testCase, "automationPrompt", true)
        var underlay = findChild(testCase.surface, "automationPromptUnderlay")
        verify(underlay, "the prompt composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !bootstrap.automationPromptOpen() }, 2000,
                  "an outside press dismissed the prompt")
        compare(bootstrap.automationLaneValues(), accepted, "the outside dismissal wrote nothing")
        compare(bootstrap.automationFrozenRevision(), -1,
                "the dismissed prompt left no frozen revision either")
    }
}
