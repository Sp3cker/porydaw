import QtQuick
import QtTest
import PorydawApp
import EditorQmlCheck 1.0
import Porydaw.Ui
import "EditorDrawerLayoutSupport.js" as LayoutSupport
import "EditorDrawerPageSupport.js" as PageSupport
import "EditorDrawerVelocitySupport.js" as VelocitySupport
import "EditorDrawerAutomationTabsSupport.js" as AutomationTabsSupport
import "EditorDrawerAutomationGestureSupport.js" as AutomationGestureSupport
import "EditorDrawerVoiceSupport.js" as VoiceSupport

EditorDrawerTestSupport {
    id: testCase
    name: "EditorDrawerLane"

    function captureProfilePane(pane) {
        var page = VelocitySupport.velocityPageItem(testCase)
        var voicePage = VoiceSupport.voicePageItem(testCase)
        var target = pane === "editor-drawer" ? testCase.drawer()
                   : pane === "velocity-prompt" ? null
                   : pane === "voice-picker"
                     ? voicePage.modalHost
                   : pane === "automation-tabs"
                     ? testCase.pageItem(testCase.automationKind)
                   : pane === "track-headers"
                     ? findChild(testCase.surface, "timelineQuickTrackHeaders")
                   : page
        if (pane === "velocity-prompt") {
            var model = VelocitySupport.velocityModel(testCase)
            if (!model.promptOpen) {
                session.performGridCommand(bootstrap.setVelocityCommand())
                wait(0)
            }
            if (!model.promptOpen)
                return false
            target = VelocitySupport.velocityPromptChild(testCase, "velocityPromptCard")
        }
        verify(target, pane + " exposes its actual drawn capture root")
        if (pane === "automation-tabs") {
            var automationPage = testCase.pageItem(testCase.automationKind)
            if (!automationPage)
                return false
            // A representative band: the Volume lane, with points written through
            // the production sweep so the reference carries a curve and nodes.
            var automationTab = bootstrap.automationVolumeIndex()
            if (automationTab >= 0)
                AutomationGestureSupport.writeVolumeLanePoints(testCase, automationTab)
            tryVerify(function() {
                return findChild(automationPage, "automationPlot") !== null
            }, 2000, "the profile composition drew the automation plot")
            AutomationTabsSupport.verifyAutomationLabelsFitGutter(testCase)
        }
        if (pane === "voice-picker") {
            var voice = VoiceSupport.voiceModel(testCase)
            if (!voice.pickerOpen) {
                var column = VoiceSupport.freeVoiceColumn(testCase, 24)
                if (column >= 0)
                    VoiceSupport.doubleClickPlot(testCase, column)
                wait(0)
            }
            if (!voice.pickerOpen)
                return false
            VoiceSupport.awaitVoiceModal(testCase, "voicePicker", true)
        }
        verify(waitForPolish(target.Window.window), pane + " completed layout before capture")
        var captureWidth = Math.floor(target.width)
        var captureHeight = Math.floor(target.height)
        var origin = target.mapToItem(testCase.surface, 0, 0)
        var url = bootstrap.profilePngUrl(pane)
        var saved = false
        target.grabToImage(function(result) { saved = result.saveToFile(url) })
        tryVerify(function() { return saved }, 5000, pane + " rendered a PNG")
        var recorded = bootstrap.writeProfileMetadata(pane, page.Screen.devicePixelRatio,
                                              pane === "voice-picker"
                                              ? VoiceSupport.voiceModel(testCase).baseFontPx
                                          : pane === "automation-tabs"
                                              ? AutomationTabsSupport.automationModel(testCase).baseFontPx
                                          : pane === "track-headers"
                                              ? testCase.surface.gridModel.baseFontPx
                                              : VelocitySupport.velocityModel(testCase).baseFontPx,
                                              String(target.objectName),
                                              captureWidth, captureHeight,
                                              origin.x, origin.y,
                                              captureWidth, captureHeight)
        if (pane === "velocity-prompt") {
            VelocitySupport.velocityModel(testCase).cancelPrompt()
            VoiceSupport.awaitVoiceModal(testCase, "velocityPrompt", false)
            wait(0)
        } else if (pane === "voice-picker") {
            VoiceSupport.voiceModel(testCase).cancelPicker()
            VoiceSupport.awaitVoiceModal(testCase, "voicePicker", false)
        }
        return recorded
    }

    // The legacy fixture includes top chrome that EditorSurface does not host.
    // Reuse its band-local bounds at its original height, never its checked-in PNG.
    function captureTrackHeadersProfile() {
        var source = bootstrap.trackHeaderReferenceJson()
        verify(source.length > 0, "the checked-in track-header geometry is readable")
        var reference = JSON.parse(source)
        compare(reference.environment.fontPx, bootstrap.profileFontPx)
        compare(reference.image.dpr, bootstrap.profileDpr)
        var bandBounds = reference.regions.filter(function(region) {
            return region.name === "track-headers.band"
        })[0]
        var rowBounds = reference.regions.filter(function(region) {
            return region.name === "track-headers.rows"
        })[0]
        verify(bandBounds && rowBounds, "the reference names the band and row viewport")
        var band = findChild(testCase.surface, "timelineQuickTrackHeaders")
        var rows = findChild(band, "timelineTrackHeaderRows")
        verify(band && rows, "the mounted production band retains its automation identities")
        var originalHeight = testCase.surface.height
        try {
            for (var attempt = 0; attempt < 6; ++attempt) {
                testCase.surface.height += bandBounds.h - band.height
                testCase.surface.configureViewport()
                tryCompare(band, "height", bandBounds.h)
                wait(0)
                if (band.height === bandBounds.h)
                    break
            }
            compare(band.height, bandBounds.h,
                    "the band settled at the reference height")
            fuzzyCompare(band.width, Math.round(bootstrap.profileFontPx * 17.5), 0.01,
                         "headers retain their font-relative width (210 at 12, 280 at 16)")
            fuzzyCompare(band.width, bandBounds.w, 0.01, "band width matches the checked-in region")
            var origin = band.mapToItem(testCase.surface, 0, 0)
            fuzzyCompare(origin.x, bandBounds.x, 0.01, "the band starts at the left edge")
            compare(origin.y, testCase.surface.gridModel.rulerHeight, "the header band starts below the ruler")
            // The rows region includes the scrollbar, not just the narrower row delegates.
            var viewport = rows.parent.parent.parent
            var rowOrigin = viewport.mapToItem(band, 0, 0)
            fuzzyCompare(rowOrigin.x, rowBounds.x - bandBounds.x, 0.01)
            fuzzyCompare(rowOrigin.y, rowBounds.y - bandBounds.y, 0.01)
            fuzzyCompare(viewport.width, rowBounds.w, 0.01)
            fuzzyCompare(viewport.height, rowBounds.h, 0.01)
            tryVerify(function() { return rows.count > 1 }, 2000,
                      "the song draws track rows and its add-track row")
            for (var i = 0; i < rows.count; ++i) {
                var row = rows.itemAt(i)
                verify(row, "every header row is instantiated")
                fuzzyCompare(row.width + testCase.surface.headersModel.scrollbarWidth,
                             rowBounds.w, 0.01, "each row fills the width beside the scrollbar")
            }
            PageSupport.auditVisibleTextInk(testCase, band, "track headers")
            return testCase.captureProfilePane("track-headers")
        } finally {
            testCase.surface.height = originalHeight
            testCase.surface.configureViewport()
        }
    }

    function test_referenceProfileBeforeCapturePencilCursorScale() {
        if (!bootstrap.profileActive)
            skip("the custom pencil scale runs in the DPR-profile children")
        AutomationTabsSupport.mountProductionAutomation(testCase, "automation-pencil-" + bootstrap.profileName)
        var input = AutomationTabsSupport.automationPlotInput(testCase)
        var model = AutomationTabsSupport.automationModel(testCase)
        model.isPencilMode = true
        try {
            LayoutSupport.focusControl(testCase, input)
            waitForRendering(testCase.surface)
            mouseMove(input, input.width / 3, input.height / 4)
            var pencil = findChild(testCase.surface, "automationPlotCursor")
            verify(pencil !== null, "the profiled production automation page owns its pencil artwork")
            tryVerify(function() { return input.containsMouse }, 2000,
                      "real profile pointer movement enters the plotted automation input")
            tryVerify(function() {
                return input.cursorShape === Qt.BitmapCursor
                    && String(pencil.source) === "qrc:/cursors/pencil.png"
            }, 2000, "the profiled plot displays its custom pencil after real movement")
            compare(pencil.devicePixelRatio, bootstrap.profileDpr,
                    "the pencil cursor is built at the profile's device pixel ratio")
        } finally {
            model.isPencilMode = false
        }
    }

    function test_referenceProfileCapture() {
        if (!bootstrap.profileActive)
            skip("the reference capture runs in a dedicated profile child")
        var location = "profile-" + bootstrap.profileName
        var values = testCase.chromeState({ "velocityVisible": true, "voiceChangesVisible": true })
        var page = VelocitySupport.mountProductionVelocity(testCase, location, values)
        verify(bootstrap.attachProductionSection(testCase.voiceChangesKind),
               "the profile composition attaches the production Voice Changes page")
        testCase.resetChrome(location, values)
        PageSupport.showSection(testCase, testCase.voiceChangesKind)
        tryVerify(function() { return VoiceSupport.voiceMarkerLines(testCase).length > 0 }, 2000,
                  "the profile composition drew the voice change markers")
        verify(bootstrap.attachProductionSection(testCase.automationKind),
               "the profile composition attaches the production Automation page")
        PageSupport.showSection(testCase, testCase.automationKind)
        var nodes = VelocitySupport.velocityNodes(testCase)
        verify(nodes.length > 0, "the profile composition drew its nodes")
        VelocitySupport.clickNode(testCase, nodes[0])
        tryVerify(function() { return VelocitySupport.velocityModel(testCase).selectedCount === 1 }, 1000,
                  "the profile composition shows a selected note")
        compare(Math.round(Screen.devicePixelRatio), Math.round(bootstrap.profileDpr),
                "the child renders at its profile's device pixel ratio")
        compare(VelocitySupport.velocityModel(testCase).baseFontPx, bootstrap.profileFontPx,
                "the page received the profile's base font")
        compare(VoiceSupport.voiceModel(testCase).baseFontPx, bootstrap.profileFontPx,
                "the Voice Changes page received the profile's base font too")
        for (const lane of [[page, "velocityRuler", "velocityPlot"],
                            [VoiceSupport.voicePageItem(testCase), "voiceGutter", "voicePlot"],
                            [testCase.pageItem(testCase.automationKind), "automationGutter", "automationPlot"]]) {
            const lanePage = lane[0]
            const gutter = findChild(lanePage, lane[1])
            const plot = findChild(lanePage, lane[2])
            const origin = testCase.surface.gridModel.trackHeaderWidth
                         + testCase.surface.gridModel.keyboardWidth
            verify(gutter !== null && plot !== null, "profile lane rects are mounted")
            compare(lanePage.baseFontPx, bootstrap.profileFontPx, "profile lane font pin")
            compare(lanePage.plotOrigin, origin, "profile lane shared origin pin")
            compare(gutter.x, 0, "profile gutter x pin")
            compare(gutter.y, 0, "profile gutter y pin")
            compare(gutter.width, origin, "profile gutter width pin")
            compare(gutter.height, lanePage.height, "profile gutter height pin")
            compare(plot.x, origin, "profile plot x pin")
            compare(plot.y, 0, "profile plot y pin")
            compare(plot.width, Math.max(lanePage.width - origin, 0), "profile plot width pin")
            compare(plot.height, lanePage.height, "profile plot height pin")
        }

        var panes = bootstrap.profilePanes
        for (var i = 0; i < panes.length; ++i)
            verify(panes[i] === "track-headers" ? testCase.captureTrackHeadersProfile()
                                              : testCase.captureProfilePane(panes[i]),
                   "captured the " + panes[i] + " pane at " + bootstrap.profileName
                   + " (dpr " + Screen.devicePixelRatio + " of " + bootstrap.profileDpr
                   + ", automationFont " + AutomationTabsSupport.automationModel(testCase).baseFontPx
                   + " of " + bootstrap.profileFontPx + ")")
        compare(page.objectName, "velocityPage", "the capture composition is the production page")
    }

}
