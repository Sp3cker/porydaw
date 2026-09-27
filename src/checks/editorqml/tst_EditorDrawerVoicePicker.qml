import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPixelSupport.js" as PixelSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function test_productionVoiceChangesPickerKeyboardAndCancellation() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice-keyboard"
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the automation section co-attaches for voice cancellation")
        var page = VoiceSupport.mountProductionVoice(testCase, location,
            { "automationVisible": true, "voiceChangesVisible": true })
        var automation = AutomationTabsSupport.automationModel(testCase)
        var model = VoiceSupport.voiceModel(testCase)
        var marker = VoiceSupport.insertVoiceChange(testCase, 60)
        verify(marker, "the case created a marker through the production picker")
        var before = VoiceSupport.voiceMarkerLines(testCase).length
        var column = VoiceSupport.freeVoiceColumn(testCase, 24)
        verify(column >= 0, "the staged song leaves a free voice-lane column")

        VoiceSupport.doubleClickPlot(testCase, column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker opened")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        var index = model.pickerIndex
        compare(index >= 0, true, "the picker publishes a current row")
        var search = findChild(testCase.surface, "voicePickerSearch")
        var list = findChild(testCase.surface, "voicePickerList")
        var accept = findChild(testCase.surface, "voicePickerAccept")
        var cancel = findChild(testCase.surface, "voicePickerCancel")
        verify(search && list && accept && cancel, "the picker draws its complete focus cycle")
        keyClick(Qt.Key_Down)
        tryVerify(function() { return list.activeFocus }, 1000,
                  "Down from search transfers focus to the list")
        compare(model.pickerIndex, index, "focus transfer does not skip the selected match")
        keyClick(Qt.Key_Down)
        tryVerify(function() { return model.pickerIndex === index + 1 }, 1000,
                  "Down in the list moves the current row")
        keyClick(Qt.Key_Up)
        tryVerify(function() { return model.pickerIndex === index }, 1000,
                  "the up arrow returned to the captured row")
        var forward = [accept, cancel, search, list]
        for (var f = 0; f < forward.length; ++f) {
            keyClick(Qt.Key_Tab)
            compare(forward[f].activeFocus, true, "Tab follows the picker cycle at " + f)
        }
        var backward = [search, cancel, accept, list]
        for (var b = 0; b < backward.length; ++b) {
            keyClick(Qt.Key_Backtab, Qt.ShiftModifier)
            compare(backward[b].activeFocus, true, "Backtab reverses the picker cycle at " + b)
        }
        var rows = VoiceSupport.voicePickerRowItems(testCase)
        compare(rows.length > 0, true, "the picker drew its visible rows")
        compare(String(rows[0].Accessible.name).length > 0, true,
                "a drawn row publishes its accessible name ('" + rows[0].Accessible.name + "')")
        compare(rows[0].Accessible.role, Accessible.ListItem,
                "a drawn row publishes the list-item role")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.pickerOpen }, 1000, "Escape closed the picker")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        compare(VoiceSupport.voiceMarkerLines(testCase).length, before, "Escape wrote nothing")
        compare(VoiceSupport.voicePlot(testCase).activeFocus, true,
                "focus returned to the page's plot after the picker closed")

        // An outside press dismisses without a write and without a gesture.
        VoiceSupport.doubleClickPlot(testCase, column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker reopened")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        var underlay = findChild(testCase.surface, "voicePickerUnderlay")
        verify(underlay, "the picker composed its dismissing underlay")
        mouseClick(underlay, 4, 4, Qt.LeftButton)
        tryVerify(function() { return !model.pickerOpen }, 1000,
                  "the outside press dismissed the picker")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        compare(model.interactionActive, false,
                "the dismissing press left no interaction behind")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, before, "the outside dismissal wrote nothing")

        // A live marker drag, cancelled by hiding the section, commits nothing.
        var input = VoiceSupport.voicePlotInput(testCase)
        var lines = VoiceSupport.voiceMarkerLines(testCase)
        var dragged = null
        for (var i = 0; i < lines.length; ++i) {
            if (Math.abs(lines[i].x - marker.x) < 1)
                dragged = lines[i]
        }
        verify(dragged, "the inserted marker is still drawn for the drag")
        var start = input.mapFromItem(dragged.parent, dragged.x + dragged.width / 2,
                                      dragged.y + dragged.height / 2)
        mousePress(input, start.x, start.y, Qt.LeftButton)
        mouseMove(input, start.x + 30, start.y, -1, Qt.LeftButton)
        compare(model.interactionActive, true, "the live drag reports an active interaction")
        compare(model.cursorKind, 3, "the live voice drag shows the horizontal cursor")
        tryCompare(input, "cursorShape", Qt.SizeHorCursor, 1000,
                   "the held mounted voice input shows the horizontal cursor")
        LayoutSupport.clickToggle(testCase, testCase.voiceChangesKind)
        tryVerify(function() { return !testCase.section(testCase.voiceChangesKind).visible }, 1000,
                  "the section hid")
        compare(model.interactionActive, false, "hiding the section cancelled the drag")
        compare(model.cursorKind, 0, "the hidden host restores the voice arrow cursor")
        compare(automation.bandVisible, false,
                "ungrabbing the hidden voice host leaves the automation band clear")
        mouseRelease(input, start.x + 30, start.y, Qt.LeftButton)
        compare(model.cursorKind, 0, "release after ungrab leaves the voice arrow cursor")
        compare(automation.bandVisible, false,
                "release after ungrab leaves the automation band clear")
        compare(model.interactionActive, false, "the released pointer committed nothing")
        compare(VoiceSupport.voiceMarkerLines(testCase).length, before, "the cancelled drag wrote nothing")
        LayoutSupport.clickToggle(testCase, testCase.voiceChangesKind)
        tryVerify(function() { return testCase.section(testCase.voiceChangesKind).visible }, 1000,
                  "the section is visible again")
    }

    function test_productionVoicePickerPointerAudition() {
        if (testCase.containerPhase) skip("production composition only")
        VoiceSupport.mountProductionVoice(testCase, "voice-picker-audition")
        VoiceSupport.doubleClickPlot(testCase, VoiceSupport.freeVoiceColumn(testCase, 24))
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        verify(bootstrap.observeVoiceAudition(), "the observer retains the production audio callback")
        var rows = VoiceSupport.voicePickerRowItems(testCase)
        var list = findChild(testCase.surface, "voicePickerList")
        var row = null
        for (var i = 0; i < rows.length; ++i) {
            var point = rows[i].mapToItem(list, rows[i].width / 2, rows[i].height / 2)
            if (point.y > 0 && point.y < list.height) {
                row = rows[i]
                break
            }
        }
        verify(row, "a picker row is visible inside the list viewport")
        var program = Number(row.objectName.substring("voicePickerRow_".length))
        var revision = bootstrap.automationDocumentRevision()
        mousePress(row, row.width / 2, row.height / 2, Qt.LeftButton)
        tryVerify(function() {
            return bootstrap.voiceAuditionEvents() === program + ":60:112"
        }, 2000, "the real row press auditions its own program at middle C")
        mouseRelease(row, row.width / 2, row.height / 2, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(),
                program + ":60:112," + program + ":60:0",
                "release stops the sounding program")
        compare(bootstrap.automationDocumentRevision(), revision, "audition does not edit the song")
        verify(bootstrap.observeVoiceAudition())
        mousePress(row, row.width / 2, row.height / 2, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(), program + ":60:112")
        keyClick(Qt.Key_Escape)
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        mouseRelease(testCase.surface, 1, 1, Qt.LeftButton)
        compare(bootstrap.voiceAuditionEvents(),
                program + ":60:112," + program + ":60:0",
                "Escape stops a held audition exactly once before physical release")
    }

    function test_productionVoiceChangesModalLayerComposition() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice-modal-layer"
        var values = testCase.chromeState({ "velocityVisible": true, "voiceChangesVisible": true })
        VelocitySupport.mountProductionVelocity(testCase, location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the composition hosts both document-bound pages")
        testCase.resetChrome(location, values)
        PageSupport.showSection(testCase, testCase.voiceChangesKind)
        var marker = VoiceSupport.insertVoiceChange(testCase, 120)
        verify(marker, "the case created a marker through the production picker")

        var column = VoiceSupport.freeVoiceColumn(testCase, 240)
        verify(column >= 0, "the lane leaves a free column for the picker")
        VoiceSupport.doubleClickPlot(testCase, column)
        tryVerify(function() { return VoiceSupport.voiceModel(testCase).pickerOpen }, 1000,
                  "the picker opened")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        var layer = findChild(testCase.surface, "drawerModalLayer")
        var card = findChild(testCase.surface, "voicePickerCard")
        verify(layer && card, "the modal layer hosts the picker's card")
        var base = VoiceSupport.voiceModel(testCase).baseFontPx
        compare(card.minimumWidth, Math.round(base * 30), "original picker width floor")
        compare(findChild(card, "voicePickerList").height, Math.round(base * 110 / 3),
                "original picker list viewport, not the shortened replacement")
        compare(card.appearance.dialogPadding, Math.max(1, Math.round(base * 0.25)))
        compare(card.appearance.verticalPadding, Math.max(1, Math.round(base * 0.125)))
        compare(layer.width, testCase.Window.window.contentItem.width)
        compare(layer.height, testCase.Window.window.contentItem.height)
        var pickerRoot = findChild(testCase.surface, "voicePicker")
        verify(pickerRoot, "the picker root is composed")
        compare(pickerRoot.parent, layer,
                "the picker composes into the container's one modal layer")

        // The card crosses another section's body: that is where stacking matters.
        var velocityBody = findChild(testCase.drawer(), "drawerBody_" + LayoutSupport.keyName(testCase, testCase.velocityKind))
        verify(velocityBody, "the velocity body is hosted beside the voice body")
        var cardInDrawer = card.mapToItem(testCase.drawer(), 0, 0)
        var bodyInDrawer = velocityBody.mapToItem(testCase.drawer(), 0, 0)
        var left = Math.max(cardInDrawer.x, bodyInDrawer.x)
        var right = Math.min(cardInDrawer.x + card.width,
                             bodyInDrawer.x + velocityBody.width)
        var top = Math.max(cardInDrawer.y, bodyInDrawer.y)
        var bottom = Math.min(cardInDrawer.y + card.height,
                              bodyInDrawer.y + velocityBody.height)
        compare(right > left && bottom > top, true,
                "the picker's card overlaps the velocity body (card "
                + Math.round(cardInDrawer.x) + "," + Math.round(cardInDrawer.y) + " "
                + Math.round(card.width) + "x" + Math.round(card.height) + "; body "
                + Math.round(bodyInDrawer.x) + "," + Math.round(bodyInDrawer.y) + " "
                + Math.round(velocityBody.width) + "x" + Math.round(velocityBody.height) + ")")

        var drawer = testCase.drawer()
        var withModal = grabImage(drawer)
        verify(withModal && withModal.width > 0, "the drawer composited into an image")
        var scale = drawer.width > 0 ? withModal.width / drawer.width : 1
        var probeX = Math.min(withModal.width - 1,
                              Math.max(0, Math.round((left + (right - left) / 2) * scale)))
        var probeY = Math.min(withModal.height - 1,
                              Math.max(0, Math.round((top + (bottom - top) / 2) * scale)))
        verify(withModal.alpha(probeX, probeY) === 255,
               "the composited overlap pixel is opaque")
        var cardChannels = PixelSupport.channelsOf(testCase, card.appearance.background)
        var radius = Math.max(2, Math.round(4 * scale))
        var probeRegion = {
            "x0": Math.max(0, probeX - radius), "y0": Math.max(0, probeY - radius),
            "x1": Math.min(withModal.width - 1, probeX + radius),
            "y1": Math.min(withModal.height - 1, probeY + radius)
        }
        var cardFill = PixelSupport.nearestPixel(testCase, withModal, probeRegion, cardChannels)
        verify(cardFill.distance <= 6,
               "the composited overlap region carries the card's own fill ("
               + cardFill.pixel.join("/") + " vs " + cardChannels.join("/")
               + " at " + cardFill.at + ")")

        // An outside press inside the other section dismisses the modal and never
        // reaches that section's own input.
        var velocityBefore = bootstrap.velocitySelectedNoteIds()
        var velocityGesture = VelocitySupport.velocityModel(testCase).interactionActive
        // A point inside the other section's body that the card does not cover:
        // the dismissing press must reach the modal's underlay, not the card.
        var crossX = bodyInDrawer.x + 6
        var crossY = bodyInDrawer.y + velocityBody.height / 2
        compare(crossX < cardInDrawer.x || crossX > cardInDrawer.x + card.width
                || crossY < cardInDrawer.y || crossY > cardInDrawer.y + card.height, true,
                "the cross-section press point lies outside the card")
        var underlay = findChild(testCase.surface, "voicePickerUnderlay")
        verify(underlay, "the picker composed its dismissing underlay")
        var underlayPoint = underlay.mapFromItem(testCase.drawer(), crossX, crossY)
        compare(underlayPoint.x >= 0 && underlayPoint.x <= underlay.width
                && underlayPoint.y >= 0 && underlayPoint.y <= underlay.height, true,
                "the cross-section press point lies inside the modal layer's underlay")
        mouseClick(underlay, underlayPoint.x, underlayPoint.y, Qt.LeftButton)
        tryVerify(function() { return !VoiceSupport.voiceModel(testCase).pickerOpen }, 1000,
                  "the outside press inside another section dismissed the picker")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        compare(bootstrap.velocitySelectedNoteIds(), velocityBefore,
                "the dismissing press did not reach the other section's selection")
        compare(VelocitySupport.velocityModel(testCase).interactionActive, velocityGesture,
                "the dismissing press started no gesture in the other section")

        var withoutModal = grabImage(drawer)
        verify(withoutModal && withoutModal.width > 0, "the drawer composited again")
        var bodyFill = PixelSupport.nearestPixel(testCase, withoutModal, probeRegion, cardChannels)
        verify(bodyFill.distance > cardFill.distance + 6,
               "the overlap region belongs to the section body once the modal is gone ("
               + cardFill.pixel.join("/") + " d=" + cardFill.distance + " -> "
               + bodyFill.pixel.join("/") + " d=" + bodyFill.distance + ")")
    }

    function test_productionVoiceChangesSpacePriority() {
        // This phase's own process: the container child released the production page's slot before it mounted.
        if (testCase.containerPhase) skip("the production cases run in the lane's own process")

        var location = "production-voice-space"
        var page = VoiceSupport.mountProductionVoice(testCase, location)
        var model = VoiceSupport.voiceModel(testCase)
        var marker = VoiceSupport.insertVoiceChange(testCase, 60)
        verify(marker, "the case created a marker for the menu")
        var propagations = testCase.spacePropagations

        // The plot: bare Space reaches the window's transport command.
        VoiceSupport.voicePlot(testCase).forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return testCase.spacePropagations === propagations + 1 }, 1000,
                  "the voice plot leaves bare Space to the window transport")

        // The picker's search field is the modal's one text-entry surface.
        var column = VoiceSupport.freeVoiceColumn(testCase, 120)
        verify(column >= 0, "the lane leaves a free column for the picker")
        VoiceSupport.doubleClickPlot(testCase, column)
        tryVerify(function() { return model.pickerOpen }, 1000, "the picker opened")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        VoiceSupport.awaitVoicePickerFocus(testCase)
        var typed = String(model.pickerFilter).length
        keyClick(Qt.Key_Space)
        tryVerify(function() { return String(model.pickerFilter).length === typed + 1 }, 1000,
                  "the focused search field takes Space as text")
        compare(testCase.spacePropagations, propagations + 1,
                "the focused search field keeps Space out of the transport")

        // Original PromptButton Space is a local modal acceptance key.
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        var markerCount = VoiceSupport.voiceMarkerLines(testCase).length
        var accept = findChild(testCase.surface, "voicePickerAccept")
        verify(accept, "the picker composed its accept control")
        accept.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return !model.pickerOpen }, 1000,
                  "Space activates the focused original OK button")
        tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length === markerCount + 1 }, 1000,
                  "local Space acceptance inserts the selected voice exactly once")
        compare(testCase.spacePropagations, propagations + 1,
                "modal acceptance never leaks into transport")
        VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)

        // The original menu host contains Space as local type-ahead input.
        var input = VoiceSupport.voicePlotInput(testCase)
        var point = input.mapFromItem(marker.parent, marker.x + 1,
                                      marker.y + marker.height / 2)
        mouseClick(input, point.x, point.y, Qt.RightButton)
        tryVerify(function() { return model.menuOpen }, 1000, "the context menu opened")
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", true)
        tryVerify(function() {
            var menu = findChild(testCase.surface, "voiceChangeMenu")
            return menu && menu.activeFocus
        }, 1000, "the visible voice menu owns keyboard focus")
        var revision = bootstrap.automationDocumentRevision()
        keyClick(Qt.Key_Space)
        compare(testCase.spacePropagations, propagations + 1,
                "the modal menu contains Space instead of leaking into transport")
        compare(model.menuOpen, true, "Space does not activate a menu command")
        compare(bootstrap.automationDocumentRevision(), revision,
                "menu type-ahead does not edit the song")
        keyClick(Qt.Key_Escape)
        tryVerify(function() { return !model.menuOpen }, 1000, "Escape closed the menu")
        VoiceSupport.awaitVoiceModal(testCase, "voiceChangeMenu", false)
        compare(model.interactionActive, false, "the case left no interaction behind")
    }
}
