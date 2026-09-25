import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers

TestCase {
    id: testCase
    name: "ShellChromeVisuals"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null

    ShellQmlBootstrap { id: bootstrap }
    GatedVisualsProbe { id: probe }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function rowCenter(pitch, rowHeight) {
        return (127.0 - pitch + 0.5) * rowHeight
    }

    function separatorDeviceRow(image, dpr, bx, by, expected) {
        var dx = Math.floor((bx + 0.5) * dpr)
        var row = Math.floor(by * dpr)
        for (var off = -2; off <= 2; ++off) {
            var p = [image.red(dx, row + off), image.green(dx, row + off),
                     image.blue(dx, row + off)]
            if (dx >= 0 && row + off >= 0 && dx < image.width && row + off < image.height
                    && Helpers.colorsNear(p, expected))
                return row + off
        }
        return -1
    }

    function findLine(image, dpr, winLeft, naturalWinY, accidentalWinY,
                      visibleLeft, visibleRight, expectedNatural, expectedAccidental) {
        var left = winLeft + visibleLeft
        var right = winLeft + visibleRight
        var first = Math.ceil(Math.min(left, right) * dpr - 0.5)
        var final = Math.floor(Math.max(left, right) * dpr - 0.5)
        var naturalRow = Math.round(naturalWinY * dpr - 0.5)
        var accidentalRow = Math.round(accidentalWinY * dpr - 0.5)
        for (var col = first; col <= final; ++col) {
            if (col < 0 || col >= image.width)
                continue
            var n = [image.red(col, naturalRow), image.green(col, naturalRow),
                     image.blue(col, naturalRow)]
            var a = [image.red(col, accidentalRow), image.green(col, accidentalRow),
                     image.blue(col, accidentalRow)]
            if (Helpers.colorsNear(n, expectedNatural) && Helpers.colorsNear(a, expectedAccidental))
                return true
        }
        return false
    }

    function test_chromeRasterParity() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the staged project")
        var surface = selectedSurface()
        verify(surface !== null, "the selected tab page is mounted")
        var grid = surface.gridModel
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the roll publishes notes")

        var plot = findChild(surface, "timelineQuickRollPlot")
        var gutter = findChild(surface, "timelineQuickRollGutter")
        var piano = findChild(surface, "pianoGridSurface")
        var rows = findChild(surface, "timelineQuickPianoGridRows")
        var time = findChild(surface, "timelineQuickPianoGridTime")
        var keys = findChild(surface, "timelineQuickPianoKeyboardKeys")
        var chip = findChild(surface, "timelineQuickPianoHoverChip")
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        verify(plot !== null, "the roll plot is mounted")
        verify(gutter !== null, "the roll gutter is mounted")
        verify(fills !== null, "the note fill layer is mounted")
        verify(piano !== null, "the piano grid surface is mounted")
        verify(rows !== null, "the row layer is mounted")
        verify(time !== null, "the time layer is mounted")
        verify(keys !== null, "the keyboard layer is mounted")
        verify(chip !== null, "the hover chip is mounted")

        var rowHeight = grid.rowHeight
        var keyboardWidth = grid.keyboardWidth
        verify(rowHeight > 0, "the row height is published")
        verify(keyboardWidth > 0, "the keyboard width is published")

        var image = grabImage(shell.contentItem)
        verify(image.width > 0 && image.height > 0, "the window renders a frame")
        var dpr = image.width / shell.contentItem.width
        var corg = shell.contentItem.mapToItem(null, 0, 0)
        function win(item, x, y) {
            var w = item.mapToItem(null, x, y)
            return { x: w.x - corg.x, y: w.y - corg.y }
        }
        var palette = grid.palette
        var natural = Helpers.channels(palette.rollBackground)
        var accidental = Helpers.channels(palette.accidentalLane)
        var scrollX = grid.cameraScrollX
        var scrollY = grid.cameraScrollY
        verify(Helpers.finite(scrollX), "the horizontal scroll is finite")
        verify(Helpers.finite(scrollY), "the vertical scroll is finite")
        var naturalY = rowCenter(60, rowHeight) - scrollY
        var accidentalY = rowCenter(61, rowHeight) - scrollY
        var visibleLeft = plot.width * 0.10
        var visibleRight = plot.width * 0.90

        var firstNatural = null
        var matching = 0
        var sampled = 0
        var samples = Math.max(1, Math.floor(visibleRight - visibleLeft))
        for (var s = 0; s <= samples; ++s) {
            var px = visibleLeft + (visibleRight - visibleLeft) * s / samples
            var nb = win(plot, px, naturalY)
            var ab = win(plot, px, accidentalY)
            var np = Helpers.devicePixel(image, dpr, nb.x, nb.y)
            var ap = Helpers.devicePixel(image, dpr, ab.x, ab.y)
            if (np !== null && ap !== null && Helpers.colorsNear(np, natural)
                    && Helpers.colorsNear(ap, accidental)) {
                ++matching
                if (firstNatural === null)
                    firstNatural = nb
            }
            ++sampled
        }
        verify(firstNatural !== null, "the C4/C#4 row centers expose the production role colors")
        verify(matching >= sampled / 4,
                "at least one quarter of the row-center region keeps both role colors")

        var naturalKey = win(gutter, keyboardWidth * 0.25, naturalY)
        var accidentalKey = win(gutter, keyboardWidth * 0.25, accidentalY)
        verify(Helpers.colorsNear(
                   Helpers.devicePixel(image, dpr, naturalKey.x, naturalKey.y),
                   Helpers.channels(palette.keyboardNatural)),
               "the C4 key uses the natural role color")
        verify(Helpers.colorsNear(
                   Helpers.devicePixel(image, dpr, accidentalKey.x, accidentalKey.y),
                   Helpers.channels(palette.keyboardBlack)),
               "the C#4 key uses the black-key role color")

        var cBoundary = (127.0 - 60 + 1.0) * rowHeight - scrollY
        var separator = Helpers.channels(palette.keyboardSeparator)
        var gutterBoundary = win(gutter, keyboardWidth * 0.25, cBoundary)
        var rollBoundary = { x: firstNatural.x,
                             y: win(plot, 0, cBoundary).y }
        var gutterRow = separatorDeviceRow(image, dpr, gutterBoundary.x, gutterBoundary.y,
                                           separator)
        var rollRow = separatorDeviceRow(image, dpr, rollBoundary.x, rollBoundary.y, separator)
        verify(gutterRow >= 0, "the keyboard C4 separator is role-colored")
        verify(rollRow >= 0, "the roll C4 separator is role-colored")
        verify(Math.abs(gutterRow - rollRow) <= 1,
                "the C4 separator aligns across keyboard and roll (gutter " + gutterRow
                + ", roll " + rollRow + ")")
        var barInk = palette.gridLineBar
        var beatInk = grid.visibleGridTicks === 1 ? palette.gridLineBeatFine
                                                  : palette.gridLineBeat
        var expectedBarNatural = Helpers.channels(probe.sourceOver(barInk, palette.rollBackground))
        var expectedBarAccidental = Helpers.channels(
                    probe.sourceOver(barInk, palette.accidentalLane))
        var expectedBeatNatural = Helpers.channels(
                    probe.sourceOver(beatInk, palette.rollBackground))
        var expectedBeatAccidental = Helpers.channels(
                    probe.sourceOver(beatInk, palette.accidentalLane))
        verify(!Helpers.colorsNear(expectedBarNatural, natural)
               && !Helpers.colorsNear(expectedBarAccidental, accidental),
               "the theme keeps bar lines distinguishable from both row roles")
        verify(!Helpers.colorsNear(expectedBeatNatural, natural)
               && !Helpers.colorsNear(expectedBeatAccidental, accidental),
               "the theme keeps beat lines distinguishable from both row roles")
        var winLeft = win(plot, 0, 0).x
        var naturalWinY = win(plot, 0, naturalY).y
        var accidentalWinY = win(plot, 0, accidentalY).y
        verify(findLine(image, dpr, winLeft, naturalWinY, accidentalWinY, visibleLeft,
                        visibleRight, expectedBarNatural, expectedBarAccidental),
               "a visible bar line composites the grid role over both rows")
        verify(findLine(image, dpr, winLeft, naturalWinY, accidentalWinY, visibleLeft,
                        visibleRight, expectedBeatNatural, expectedBeatAccidental),
               "a visible beat line composites the relative-alpha grid role over both rows")

        var initialScrollY = grid.cameraScrollY
        var maximumScrollY = grid.cameraMaxVScroll
        var wheelAngle = initialScrollY < maximumScrollY - 1.0 ? -120 : 120
        mouseWheel(gutter, gutter.width / 2, gutter.height / 2, 0, wheelAngle)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraScrollY - initialScrollY) > 0.5
        }, 5000), "the gutter wheel scrolls the camera")

        var scrolledY = grid.cameraScrollY
        var hoverRow = Math.min(127, Math.max(0, Math.floor(
                    (scrolledY + plot.height * 0.5) / rowHeight)))
        var hoverPitch = 127 - hoverRow
        var hoverViewportY = (hoverRow + 0.5) * rowHeight - scrolledY
        mouseMove(gutter, keyboardWidth * 0.5, hoverViewportY)
        verify(waitForNative(function() {
            return grid.hoverKey === hoverPitch && chip.visible
        }, 5000), "hovering the keyboard publishes the pitch and shows the chip")
        var chipCenter = win(chip, chip.width / 2, chip.height / 2)
        var hoverCenter = win(gutter, keyboardWidth * 0.5, hoverViewportY)
        verify(Math.abs(chipCenter.y - hoverCenter.y) <= 1.0 / dpr,
                "the hover chip centers on the hovered pitch row")
        mouseMove(plot, plot.width / 2, plot.height / 2)
    }
}
