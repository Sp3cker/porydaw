import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "Typography"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null

    ShellQmlBootstrap { id: bootstrap }
    Component { id: bodyTextComponent; Text { text: "probe" } }
    Component { id: shellComponent; ShellWindow { visible: true } }
    Component { id: capturedSessionComponent; ApplicationSession {} }
    Component {
        id: captionObserverComponent
        Text {
            required property QtObject observedSession
            font: Qt.font(observedSession.typographyFonts.caption)
            leftPadding: observedSession.layoutSpaces.two
            text: "caption"
        }
    }
    FontMetrics { id: normalTitleCheck }
    FontMetrics { id: boldTitleCheck }
    FontMetrics {
        id: editorBodyMetrics
        font: shell ? Qt.font(shell.shellPresenter.session.typographyFonts.body) : normalTitleCheck.font
    }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function cleanup() {
        if (!shell)
            return
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function openOneSongShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the staged project"
               + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        tryVerify(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000, "the real tab page is mounted and drawn")
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function centersClose(first, second) {
        return Math.abs(first.x - second.x) < 0.01 && Math.abs(first.y - second.y) < 0.01
    }

    function test_captureNotifiesPublishedFontsAndSpaces() {
        var captured = capturedSessionComponent.createObject(testCase)
        verify(captured, "the real application session exposes font maps")
        var observer = captionObserverComponent.createObject(testCase,
                                                              {observedSession: captured})
        verify(observer, "a mounted text label observes the session caption role")
        compare(observer.font.pixelSize, 13, "the default caption starts at the seed base")
        captured.configureTypography(12)
        tryCompare(observer.font, "pixelSize", 12, 3000)
        compare(observer.font.family, captured.typographyFonts.caption.family,
                "the observed caption keeps the bundled face after capture")
        compare(observer.font.weight, captured.typographyFonts.caption.weight,
                "the observed caption keeps Regular weight after capture")
        tryCompare(observer, "leftPadding", captured.layoutSpaces.two, 3000)
        compare(observer.leftPadding, 6,
                "the observed two-space inset follows the captured base")
        observer.destroy()
        captured.destroy()
    }
    function test_bodyFontAndMetrics() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        compare(Qt.application.organization, "sp3cker",
                "the shell keeps the production organization identity")
        tryVerify(function() {
            return shell.font.family === "Atkinson Hyperlegible Next"
        }, 5000, "the resolved base font carries the bundled Next family")
        compare(shell.font.pixelSize, shell.bodyFontPx,
                "the base font resolves to the threaded body size")
        compare(shell.font.hintingPreference, Font.PreferNoHinting,
                "the base font prefers no hinting")
        compare(shell.font.weight, Font.Normal, "the base font keeps Normal weight")
        compare(shell.font.features["tnum"], 1, "the base font enables tabular figures")
        verify(shell.bodyFontPx >= 1, "the threaded body size is never degenerate")
        var session = shell.shellPresenter.session
        var body = session.typographyFonts.body
        compare(shell.font.family, body.family,
                "the shell font resolves to the session body family")
        compare(shell.font.pixelSize, session.bodyFontPx,
                "the shell font resolves to the session body pixel size")
        compare(session.layoutSpaces.zero, 0,
                "the published Zero token preserves zero spacing")
        compare(session.layoutSpaces.two, Math.max(1, Math.round(session.baseFontPx / 2)),
                "the published Two token rounds half of the captured base")
        compare(session.layoutSpaces.eight, session.baseFontPx * 2,
                "the published Eight token doubles the captured base")
        var settings = findChild(shell, "shellSettingsDialog")
        var about = findChild(shell, "shellAboutDialog")
        verify(settings !== null && about !== null,
               "the two shell dialog roots are instantiated")
        compare(settings.font.family, body.family,
                "the separate Settings window resolves the session body family")
        compare(about.font.family, body.family,
                "the About popup resolves the session body family")
        compare(shell.width, session.baseFontPx * 92,
                "window width follows the captured base geometry")
        compare(shell.height, session.baseFontPx * 57,
                "window height follows the captured base geometry")
        var label = bodyTextComponent.createObject(shell.contentItem)
        verify(label !== null, "a body-text probe mounts in the real window")
        label.font = shell.font
        compare(label.font.family, "Atkinson Hyperlegible Next",
                "body text shows the restored Next family")
        label.destroy()
    }

    function test_selectedTitleCentering() {
        openOneSongShell()
        var surface = selectedSurface()
        verify(surface && surface.visible, "the selected production EditorSurface is visible")
        compare(surface.gridModel.baseFontPx, shell.shellPresenter.session.baseFontPx,
                "the mounted editor grid uses the captured session base rather than the body")
        var headers = findChild(surface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the original track header delegates are mounted")
        normalTitleCheck.font = Qt.font(surface.headersModel.normalTitleFont)
        boldTitleCheck.font = Qt.font(surface.headersModel.boldTitleFont)
        tryVerify(function() {
            for (var i = 0; i < headers.count; ++i) {
                var row = headers.itemAt(i)
                if (!row || !row.titleBold || row.isAddTrack)
                    continue
                var label = boldTitleCheck.elidedText(row.title, Text.ElideRight,
                                                      row.titleRect.width)
                var normal = normalTitleCheck.tightBoundingRect(label)
                var bold = boldTitleCheck.tightBoundingRect(label)
                var offset = row.selectedTitleOffset
                var displayed = {
                    x: bold.x + bold.width / 2 + offset.x,
                    y: bold.y + bold.height / 2 + offset.y
                }
                var reference = {
                    x: normal.x + normal.width / 2,
                    y: normal.y + normal.height / 2
                }
                if (centersClose(displayed, reference))
                    return true
            }
            return false
        }, 5000, "the bold title stays centered on the regular title")
        var row = null
        for (var j = 0; j < headers.count; ++j) {
            var candidate = headers.itemAt(j)
            if (candidate && candidate.titleBold && !candidate.isAddTrack) {
                row = candidate
                break
            }
        }
        verify(row !== null, "a selected bold title row is mounted")
        compare(row.titleFont.features["tnum"], 1,
                "the title map emits tabular figures")
        var rendered = bodyTextComponent.createObject(shell.contentItem)
        verify(rendered !== null, "a map-rendered probe mounts in the real window")
        rendered.font = Qt.font(row.titleFont)
        compare(rendered.font.hintingPreference, Font.PreferNoHinting,
                "the rendered title carries the unhinted preference")
        rendered.destroy()
    }
    function test_mountedEditorFontAndMenuGeometry() {
        openOneSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var body = session.typographyFonts.body
        var caption = session.typographyFonts.caption
        var space = session.layoutSpaces
        var gridLabel = findChild(surface, "timelineRulerGridLabel")
        var control = findChild(surface, "timelineRulerDivisionControl")
        var hint = findChild(surface, "mouseHintStatusText")
        verify(gridLabel && control && hint, "the ruler controls and status hint are mounted")
        compare(gridLabel.font.family, body.family, "the ruler control resolves the body face")
        compare(gridLabel.font.pixelSize, body.pixelSize, "the ruler control resolves the body size")
        compare(gridLabel.font.weight, body.weight, "the ruler control keeps Regular weight")
        compare(hint.font.family, caption.family, "the mouse hint resolves the caption face")
        compare(hint.font.pixelSize, caption.pixelSize, "the mouse hint resolves the caption size")
        compare(hint.font.weight, caption.weight, "the mouse hint keeps Regular weight")
        var headerBand = findChild(surface, "timelineQuickTrackHeaders")
        var headerRows = findChild(surface, "timelineTrackHeaderRows")
        verify(headerBand && headerRows && headerRows.count > 0,
               "the active track header band and rows are mounted")
        var insetEdge = headerBand.width - surface.headersModel.scrollbarWidth - space.one
        for (var headerIndex = 0; headerIndex < headerRows.count; ++headerIndex) {
            var headerRow = headerRows.itemAt(headerIndex)
            if (!headerRow || headerRow.isAddTrack)
                continue
            for (var label of ["Mute", "Solo"]) {
                var toggle = findChild(headerRow,
                                       "timelineHeader" + label + "_" + headerRow.track)
                verify(toggle && toggle.visible, label + " toggle is painted on track "
                       + headerRow.track)
                var right = toggle.mapToItem(headerBand, toggle.width, 0).x
                verify(right <= insetEdge + 0.01,
                       label + " right border clears the keyboard and scrollbar with fork inset")
                compare(toggle.width, Math.round(session.baseFontPx * 1.5),
                        label + " extent follows the captured base")
                var ink = toggle.children.filter(function(child) {
                    return child.text === (label === "Mute" ? "M" : "S")
                })[0]
                verify(ink, label + " paints its letter within the toggle")
                compare(ink.font.family, body.family, label + " uses the body family")
                compare(ink.font.pixelSize, body.pixelSize, label + " uses the body size")
                compare(ink.font.weight, body.weight, label + " keeps Regular weight")
            }
            verify(headerRow.titleRect.x + headerRow.titleRect.width <=
                   surface.headersModel.muteButtonRect.x,
                   "the title ends before the mute column")
            verify(headerRow.subtitleRect.x + headerRow.subtitleRect.width <=
                   surface.headersModel.soloButtonRect.x,
                   "the subtitle ends before the solo column")
        }

        surface.gridModel.openGridMenu(1)
        tryVerify(function() {
            var menu = findChild(surface, "quickMenuPanelRoot")
            return menu && menu.rowCount > 0
        }, 5000, "the real grid-division menu paints its typed rows")
        var menu = findChild(surface, "quickMenuPanelRoot")
        var widest = 0
        for (var i = 0; i < menu.rowCount; ++i) {
            var row = menu.rowItem(i)
            verify(row, "grid menu row " + i + " is rendered")
            widest = Math.max(widest, editorBodyMetrics.advanceWidth(row.itemData.text))
        }
        compare(menu.menuFont.family, body.family, "grid menu rows resolve the body family")
        compare(menu.menuFont.pixelSize, body.pixelSize, "grid menu rows resolve the body size")
        compare(menu.menuFont.weight, body.weight, "grid menu rows keep Regular weight")
        compare(menu.rowHeight, Math.round(editorBodyMetrics.height) + 2 * space.half,
                "grid menu row height follows body metrics and half-space padding")
        compare(menu.checkX, space.two, "the check begins at the two-space token")
        compare(menu.checkWidth, Math.floor(menu.rowHeight / 2),
                "the check width follows the row height")
        compare(menu.textX, space.two + menu.checkWidth + space.one,
                "grid menu text clears the check and one-space gap")
        compare(menu.menuWidth, 2 + menu.textX + Math.ceil(widest) + space.two,
                "grid menu width fits the longest rendered row and frame")
        compare(menu.menuHeight, 2 + menu.rowCount * menu.rowHeight,
                "grid menu height fits the rendered rows and frame")
        surface.gridModel.dismissGridMenu()
        session.openTimeSigPromptAtCursor()
        tryVerify(function() {
            return findChild(surface, "timeSignaturePrompt") !== null
        }, 5000, "the real time-signature prompt is mounted")
        var prompt = findChild(surface, "timeSignaturePrompt")
        function findPromptTitle(item) {
            if (item.text === session.timeSigPromptTitle)
                return item
            for (var child of item.children) {
                var found = findPromptTitle(child)
                if (found)
                    return found
            }
            return null
        }
        var promptTitle = findPromptTitle(prompt)
        verify(promptTitle, "the time-signature prompt paints its title")
        compare(promptTitle.font.family, body.family, "prompt text uses the body family")
        compare(promptTitle.font.pixelSize, body.pixelSize, "prompt text uses the body size")
        compare(promptTitle.font.weight, body.weight, "prompt text keeps Regular weight")
        session.cancelTimeSigPrompt()
    }
    function test_mountedPitchPopupFontRoles() {
        openOneSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var plot = findChild(surface, "timelineQuickRollPlot")
        var input = findChild(surface, "swiftRollInput")
        verify(plot && input, "the active roll input and plot are mounted")
        grid.setTrack(0)
        var notes = JSON.parse(grid.noteSummary)
        var note = notes.filter(function(candidate) {
            return candidate.track === 0 && candidate.duration >= 3
        })[0]
        verify(note, "the staged song contains an editable note")
        var horizontal = (note.tick + note.duration / 2)
                         * grid.beatWidth / grid.ticksPerBeat
        var vertical = (127 - note.pitch + 0.5) * grid.rowHeight
        grid.setCameraHScroll(Math.max(0, horizontal - plot.width / 2))
        grid.setCameraVScroll(Math.max(0, vertical - plot.height / 2))
        tryVerify(function() {
            var face = findChild(surface, "gridNote_" + note.id)
            return face && face.visible && face.width > 0 && face.height > 0
        }, 5000, "the selected note face appears in the roll")
        var face = findChild(surface, "gridNote_" + note.id)
        var point = face.mapToItem(input, face.width / 2, face.height / 2)
        mouseClick(input, point.x, point.y, Qt.LeftButton)
        grid.performCommand(6)
        tryVerify(function() {
            return findChild(surface, "pitchBendPopup") !== null
        }, 5000, "the selected note opens the real pitch popup")
        var popup = findChild(surface, "pitchBendPopup")
        var session = shell.shellPresenter.session
        var roles = session.typographyFonts
        var title = findChild(popup, "pitchBendTitle")
        var description = findChild(popup, "pitchBendDescription")
        var readout = findChild(popup, "pitchBendLiveValue")
        var spin = findChild(popup, "bendRangeSpin")
        verify(title && description && readout && spin,
               "the pitch title, caption, mono readout, and editable field are painted")
        for (var pair of [[title, roles.bodyBold, "pitch title"],
                         [description, roles.caption, "pitch description"],
                         [readout, roles.bodyMono, "pitch mono readout"]]) {
            compare(pair[0].font.family, pair[1].family, pair[2] + " uses its published family")
            compare(pair[0].font.pixelSize, pair[1].pixelSize, pair[2] + " uses its published size")
            compare(pair[0].font.weight, pair[1].weight, pair[2] + " uses its bundled weight")
        }
        var field = spin.children.filter(function(child) {
            return child.font !== undefined && child.text !== undefined
        })[0]
        verify(field, "the pitch drag input renders its numeric field")
        compare(field.font.family, roles.body.family, "drag input uses the body family")
        compare(field.font.pixelSize, roles.body.pixelSize, "drag input uses the body size")
        compare(field.font.weight, roles.body.weight, "drag input keeps Regular weight")
    }
}
