import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVoiceInputPressIsolatesAutomationAndCursor() {
        if (testCase.containerPhase) skip("production composition only")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the automation section co-attaches to the voice input")
        VoiceSupport.mountProductionVoice(testCase, "voice-routing-press",
            { "automationVisible": true, "voiceChangesVisible": true })
        var input = VoiceSupport.voicePlotInput(testCase)
        verify(input && input.width > 0 && input.height > 0,
               "the real mounted voice input has non-empty bounds before its press")
        var revision = bootstrap.automationDocumentRevision()
        var cursor = testCase.surface.gridModel.editCursorTick
        mousePress(input, input.width * 0.6, input.height / 2, Qt.LeftButton)
        compare(bootstrap.automationDocumentRevision(), revision,
                "the voice-area press leaves the automation document frozen")
        compare(testCase.surface.gridModel.editCursorTick, cursor,
                "the voice-area press leaves the edit cursor parked")
        compare(AutomationTabsSupport.automationModel(testCase).bandVisible, false,
                "the voice-area press previews no automation range")
        mouseRelease(input, input.width * 0.6, input.height / 2, Qt.LeftButton)
    }

    function test_productionVoiceDragCursorDraftAndBandIsolation() {
        if (testCase.containerPhase) skip("production composition only")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the co-mounted automation section attaches to the voice session")
        VoiceSupport.mountProductionVoice(testCase, "voice-routing-drag",
            { "automationVisible": true, "voiceChangesVisible": true })
        var marker = VoiceSupport.insertVoiceChange(testCase, 96)
        verify(marker, "the mounted voice route has a written marker")
        var input = VoiceSupport.voicePlotInput(testCase)
        var model = VoiceSupport.voiceModel(testCase)
        var automation = AutomationTabsSupport.automationModel(testCase)
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        var originalTick = marker.parent.model.tick
        var revision = bootstrap.automationDocumentRevision()
        compare(input.cursorShape, Qt.ArrowCursor, "the idle voice input shows the arrow cursor")
        mousePress(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, point.x + 45, point.y, -1, Qt.LeftButton)
        tryCompare(model, "cursorKind", 3, 1000,
                   "the held horizontal voice drag publishes the horizontal cursor")
        tryCompare(input, "cursorShape", Qt.SizeHorCursor, 1000,
                   "the held horizontal voice drag shows the size cursor")
        tryVerify(function() {
            var drawn = VoiceSupport.voiceMarkerLines(testCase)
            for (var i = 0; i < drawn.length; ++i) {
                if (drawn[i].parent.model.tick !== originalTick
                    && drawn[i].x > marker.x + 10)
                    return true
            }
            return false
        }, 3000, "the held voice drag republishes its moved marker draft")
        compare(bootstrap.automationDocumentRevision(), revision,
                "the voice marker draft writes nothing until release")
        compare(automation.bandVisible, false,
                "the held voice drag never previews an automation range")
        mouseRelease(input, point.x + 45, point.y, Qt.LeftButton)
        tryCompare(model, "cursorKind", 0)
        tryCompare(input, "cursorShape", Qt.ArrowCursor, 1000,
                   "releasing the voice drag restores the arrow cursor")
        compare(automation.bandVisible, false,
                "the released voice drag leaves the automation band clear")
        verify(bootstrap.automationDocumentRevision() !== revision,
               "the released voice drag commits its projected marker")
    }

    function test_productionVoiceJitterAndEscapeKeepArrowAndClearBand() {
        if (testCase.containerPhase) skip("production composition only")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the co-mounted automation section attaches to the voice session")
        VoiceSupport.mountProductionVoice(testCase, "voice-routing-cancel",
            { "automationVisible": true, "voiceChangesVisible": true })
        var marker = VoiceSupport.insertVoiceChange(testCase, 96)
        verify(marker, "the mounted cancellation route has a written marker")
        var input = VoiceSupport.voicePlotInput(testCase)
        verify(input && input.width > 0 && input.height > 0,
               "the mounted Escape journey has non-empty voice input bounds")
        var model = VoiceSupport.voiceModel(testCase)
        var automation = AutomationTabsSupport.automationModel(testCase)
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        var revision = bootstrap.automationDocumentRevision()
        mousePress(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, point.x, point.y + 3, -1, Qt.LeftButton)
        compare(model.cursorKind, 0, "stationary vertical voice jitter keeps the arrow cursor")
        compare(input.cursorShape, Qt.ArrowCursor,
                "the mounted jitter input keeps the arrow cursor")
        mouseRelease(input, point.x, point.y + 3, Qt.LeftButton)
        compare(automation.bandVisible, false,
                "the released vertical voice jitter leaves the automation band clear")
        mousePress(input, point.x, point.y, Qt.LeftButton)
        mouseMove(input, point.x + 45, point.y, -1, Qt.LeftButton)
        tryCompare(model, "cursorKind", 3, 1000,
                   "the held Escape journey publishes the horizontal cursor before cancellation")
        keyClick(Qt.Key_Escape)
        compare(model.cursorKind, 0, "Escape restores the voice arrow cursor")
        compare(input.cursorShape, Qt.ArrowCursor,
                "Escape restores the mounted voice input arrow cursor")
        compare(automation.bandVisible, false,
                "Escape leaves the automation range preview clear")
        mouseRelease(input, point.x + 45, point.y, Qt.LeftButton)
        compare(bootstrap.automationDocumentRevision(), revision,
                "the cancelled voice stroke commits nothing")
    }

    function test_productionVoiceCollisionAndAltCursorIsolation() {
        if (testCase.containerPhase) skip("production composition only")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the co-mounted automation section attaches to the voice session")
        VoiceSupport.mountProductionVoice(testCase, "voice-routing-collision",
            { "automationVisible": true, "voiceChangesVisible": true })
        var first = VoiceSupport.insertVoiceChange(testCase, 96)
        var second = VoiceSupport.insertVoiceChange(testCase, 240)
        verify(first && second, "two distinct voice markers are drawn for collision")
        var input = VoiceSupport.voicePlotInput(testCase)
        var model = VoiceSupport.voiceModel(testCase)
        var automation = AutomationTabsSupport.automationModel(testCase)
        var count = VoiceSupport.voiceMarkerLines(testCase).length
        var start = input.mapFromItem(first.parent, first.x + 1, first.y + first.height / 2)
        var end = input.mapFromItem(second.parent, second.x + 1, second.y + second.height / 2)
        mousePress(input, start.x, start.y, Qt.LeftButton)
        mouseMove(input, end.x, end.y, -1, Qt.LeftButton)
        tryCompare(model, "cursorKind", 3, 1000,
                   "the held collision drag publishes the horizontal cursor")
        mouseRelease(input, end.x, end.y, Qt.LeftButton)
        tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length === count - 1 }, 3000,
                  "the collision merges the two drawn occurrences")
        compare(model.cursorKind, 0, "a collision release restores the voice arrow cursor")
        compare(input.cursorShape, Qt.ArrowCursor,
                "the mounted collision release restores the arrow cursor")
        compare(automation.bandVisible, false,
                "the collision release leaves the automation band clear")

        var remaining = VoiceSupport.voiceMarkerLines(testCase)
        var dragged = null
        for (var i = 0; i < remaining.length; ++i) {
            if (Math.abs(remaining[i].x - second.x) < 2)
                dragged = remaining[i]
        }
        verify(dragged, "the collided voice marker remains rendered for an Alt drag")
        var point = input.mapFromItem(dragged.parent, dragged.x + 1,
                                      dragged.y + dragged.height / 2)
        var revision = bootstrap.automationDocumentRevision()
        mousePress(input, point.x, point.y, Qt.LeftButton, Qt.AltModifier)
        mouseMove(input, point.x + 35, point.y, -1, Qt.LeftButton, Qt.AltModifier)
        tryCompare(model, "cursorKind", 3, 1000,
                   "the held Alt drag publishes the horizontal cursor")
        tryCompare(input, "cursorShape", Qt.SizeHorCursor, 1000,
                   "the held Alt drag shows the mounted horizontal cursor")
        compare(automation.bandVisible, false,
                "the held Alt drag previews no automation range")
        mouseRelease(input, point.x + 35, point.y, Qt.LeftButton, Qt.AltModifier)
        compare(model.cursorKind, 0, "the released Alt drag restores the arrow cursor")
        compare(automation.bandVisible, false,
                "the released Alt drag leaves the automation band clear")
        verify(bootstrap.automationDocumentRevision() !== revision,
               "the released Alt drag commits the fine-snapped voice marker")
    }

    function test_productionVoiceChangesCameraTransactions() {
        if (testCase.containerPhase) skip("production composition only")
        var page = VoiceSupport.mountProductionVoice(testCase, "voice-camera")
        var input = VoiceSupport.voicePlotInput(testCase)
        var plot = VoiceSupport.voicePlot(testCase)
        var gutter = findChild(page, "voiceGutter")
        var grid = testCase.surface.gridModel
        fuzzyCompare(plot.x, testCase.surface.timelineSplitX, 0.01,
                     "the plot begins at the shared gutter split")
        fuzzyCompare(input.width, plot.width, 0.01, "the input spans the plot width")
        fuzzyCompare(input.height, plot.height, 0.01, "the input spans the plot height")
        fuzzyCompare(gutter.width, grid.keyboardWidth + (grid.trackHeaderWidth || 0), 0.01,
                     "the gutter occupies the shared fixed-width column")
        fuzzyCompare(gutter.height, page.height, 0.01,
                     "the gutter spans the body height")
        var x = input.width / 2
        var y = input.height / 2
        var beforeWidth = grid.beatWidth
        var anchorTick = (x + grid.cameraScrollX) * grid.ticksPerBeat / beforeWidth
        mouseWheel(input, x, y, 0, 120, Qt.NoButton, Qt.NoModifier)
        tryVerify(function() { return grid.beatWidth > beforeWidth }, 1000,
                  "the real plot wheel zooms the shared camera")
        verify(Math.abs(anchorTick * grid.beatWidth / grid.ticksPerBeat
                        - grid.cameraScrollX - x) <= 1,
               "the anchor tick remains within one display pixel")
        grid.setCameraHScroll(-1e6)
        var floor = grid.cameraScrollX
        grid.setCameraHScroll(floor + 120)
        var start = grid.cameraScrollX
        verify(start > floor, "the camera has room to pan toward pre-roll")
        mousePress(input, x, y, Qt.MiddleButton)
        mouseMove(input, x + start - floor + 120, y, -1, Qt.MiddleButton)
        mouseRelease(input, x + start - floor + 120, y, Qt.MiddleButton)
        compare(grid.cameraScrollX, floor, "the middle-drag clamps at the pre-roll floor")
    }
}
