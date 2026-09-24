import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "GatedVisualsHelpers.js" as Helpers

TestCase {
    id: testCase
    name: "ShellReticleVisuals"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var grabbed: null

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function cleanup() {
        grabbed = null
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

    function noteDelegates(fills) {
        var items = []
        for (var i = 0; i < fills.children.length; ++i) {
            var c = fills.children[i]
            if (c && c.fillColor !== undefined && c.fillColor && c.visible)
                items.push(c)
        }
        return items
    }

    function nearNote(delegates, x, y) {
        for (var i = 0; i < delegates.length; ++i) {
            var c = delegates[i]
            if (x >= c.x - 3 && x <= c.x + c.width + 3
                    && y >= c.y - 3 && y <= c.y + c.height + 3)
                return true
        }
        return false
    }

    function sourceOver(fgHex, bgPixel) {
        var fg = Helpers.channels(fgHex)
        function ch(s, d) { return Math.round((s * fg[3] + d * (255 - fg[3])) / 255) }
        return [ch(fg[0], bgPixel[0]), ch(fg[1], bgPixel[1]), ch(fg[2], bgPixel[2])]
    }

    function test_selectionReticleRasterTranslucency() {
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
        var input = findChild(surface, "swiftRollInput")
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        var overlay = findChild(surface, "timelineQuickPianoOverlay")
        verify(plot !== null, "the roll plot is mounted")
        verify(input !== null, "the roll input is mounted")
        verify(fills !== null, "the note fill layer is mounted")
        verify(overlay !== null, "the overlay layer is mounted")
        verify(waitForNative(function() { return noteDelegates(fills).length > 0 }, 5000),
               "the fill layer draws note delegates")

        var sx = plot.width * 0.15
        var sy = plot.height * 0.20
        var fx = plot.width * 0.85
        var fy = plot.height * 0.80
        var reticle = { x: Math.min(sx, fx), y: Math.min(sy, fy),
                        w: Math.abs(fx - sx), h: Math.abs(fy - sy) }
        verify(reticle.w > 80, "the reticle spans the plot horizontally")
        verify(reticle.h > 80, "the reticle spans the plot vertically")
        verify(sx >= 0 && sy >= 0 && fx <= plot.width && fy <= plot.height,
                "the reticle stays inside the roll input")

        var corg = shell.contentItem.mapToItem(null, 0, 0)
        function win(x, y) {
            var w = plot.mapToItem(null, x, y)
            return { x: w.x - corg.x, y: w.y - corg.y }
        }
        function shellDpr(image) { return image.width / shell.contentItem.width }
        function flatPlot(image, dpr, x, y) {
            var w = win(x, y)
            return Helpers.flatAt(image, dpr, w.x, w.y)
        }
        function pixelPlot(image, dpr, x, y) {
            var w = win(x, y)
            return Helpers.devicePixel(image, dpr, w.x, w.y)
        }
        var baseline = grabImage(shell.contentItem)
        verify(baseline.width > 0 && baseline.height > 0,
                "the baseline roll renders a frame")
        var dpr = shellDpr(baseline)

        var probes = []
        var ix0 = reticle.x + 12, iy0 = reticle.y + 12
        var ix1 = reticle.x + reticle.w - 12, iy1 = reticle.y + reticle.h - 12
        var first = null
        for (var py = iy0; py <= iy1 && probes.length < 2; py += 2)
            for (var px = ix0; px <= ix1 && probes.length < 2; px += 2) {
                var color = flatPlot(baseline, dpr, px, py)
                if (color === null)
                    continue
                if (first === null) {
                    first = { x: px, y: py, baseline: color }
                    continue
                }
                var diff = Math.max(Math.abs(color[0] - first.baseline[0]),
                                    Math.abs(color[1] - first.baseline[1]),
                                    Math.abs(color[2] - first.baseline[2]))
                if (diff >= 8) {
                    probes.push(first)
                    probes.push({ x: px, y: py, baseline: color })
                }
            }
        verify(probes.length === 2, "two distinct flat pixels sit under the reticle")

        var delegates = noteDelegates(fills)
        var noteProbe = null
        for (var d = 0; d < delegates.length && noteProbe === null; ++d) {
            var nc = delegates[d]
            var fill = Helpers.channels(String(nc.fillColor))
            var nx0 = Math.max(nc.x + 3, reticle.x + 3)
            var ny0 = Math.max(nc.y + 3, reticle.y + 3)
            var nx1 = Math.min(nc.x + nc.width - 3, reticle.x + reticle.w - 3)
            var ny1 = Math.min(nc.y + nc.height - 3, reticle.y + reticle.h - 3)
            for (var ny = ny0; ny <= ny1 && noteProbe === null; ++ny)
                for (var nx = nx0; nx <= nx1 && noteProbe === null; ++nx) {
                    var nb = flatPlot(baseline, dpr, nx, ny)
                    if (nb !== null && Helpers.colorsNear(nb, fill))
                        noteProbe = { x: nx, y: ny, baseline: nb }
                }
        }
        verify(noteProbe !== null, "a visible note face is covered by the reticle")

        var outside = []
        for (var oy = 5; oy <= plot.height - 5 && outside.length < 3; oy += 2)
            for (var ox = 5; ox <= plot.width - 5 && outside.length < 3; ox += 2) {
                if (ox >= reticle.x - 6 && ox <= reticle.x + reticle.w + 6
                        && oy >= reticle.y - 6 && oy <= reticle.y + reticle.h + 6)
                    continue
                if (nearNote(delegates, ox, oy))
                    continue
                var separated = true
                for (var k = 0; k < outside.length; ++k)
                    if (Math.abs(ox - outside[k].x) + Math.abs(oy - outside[k].y) < 40)
                        separated = false
                if (!separated)
                    continue
                var oc = flatPlot(baseline, dpr, ox, oy)
                if (oc !== null)
                    outside.push({ x: ox, y: oy, baseline: oc })
            }
        verify(outside.length === 3, "three untouched flat pixels sit outside the reticle")

        var selectionFill = String(grid.palette.selectionFill)
        mouseMove(plot, sx, sy)
        mousePress(plot, sx, sy, Qt.RightButton)
        mouseMove(plot, fx, fy, -1, Qt.RightButton)
        verify(waitForNative(function() {
            var total = 0
            var fill = 0
            for (var i = 0; i < overlay.children.length; ++i) {
                var c = overlay.children[i]
                if (!c || c.fillColor === undefined || !c.fillColor || !c.visible)
                    continue
                if (c.x + c.width > reticle.x && c.x < reticle.x + reticle.w
                        && c.y + c.height > reticle.y && c.y < reticle.y + reticle.h) {
                    ++total
                    if (String(c.fillColor).toUpperCase() === selectionFill.toUpperCase())
                        ++fill
                }
            }
            return total >= 5 && fill >= 1
        }, 5000), "the drag publishes the selection band over the reticle")

        var during = grabImage(shell.contentItem)
        verify(during.width > 0, "the roll renders a frame during the drag")
        compare(during.width, baseline.width, "the drag frame keeps its size")
        compare(during.height, baseline.height, "the drag frame keeps its pixel ratio")
        mouseRelease(plot, fx, fy, Qt.RightButton)

        for (var o = 0; o < outside.length; ++o) {
            var actualOutside = pixelPlot(during, dpr, outside[o].x, outside[o].y)
            verify(Helpers.colorsNear(actualOutside, outside[o].baseline),
                    "selection fill escaped its reticle at (" + outside[o].x + ","
                    + outside[o].y + "): before " + Helpers.hexOf(outside[o].baseline)
                    + ", during " + Helpers.hexOf(actualOutside))
        }

        var actual = []
        for (var p = 0; p < probes.length; ++p) {
            var expected = sourceOver(selectionFill, probes[p].baseline)
            var got = pixelPlot(during, dpr, probes[p].x, probes[p].y)
            actual.push(got)
            verify(Helpers.colorsNear(got, expected),
                    "selection fill at (" + probes[p].x + "," + probes[p].y + "): baseline "
                    + Helpers.hexOf(probes[p].baseline) + ", expected " + Helpers.hexOf(expected)
                    + ", actual " + Helpers.hexOf(got))
        }
        verify(Helpers.hexOf(actual[0]) !== Helpers.hexOf(actual[1]),
                "the reticle preserves contrast between distinct underlying pixels")

        var expectedNote = sourceOver(selectionFill, noteProbe.baseline)
        var actualNote = pixelPlot(during, dpr, noteProbe.x, noteProbe.y)
        verify(Helpers.colorsNear(actualNote, expectedNote),
                "note face under selection fill: baseline " + Helpers.hexOf(noteProbe.baseline)
                + ", expected " + Helpers.hexOf(expectedNote)
                + ", actual " + Helpers.hexOf(actualNote))

        var edge = Helpers.channels(String(grid.palette.selectionEdge))
        var wret = win(reticle.x, reticle.y)
        var left = Math.floor(wret.x * dpr)
        var right = Math.ceil((wret.x + reticle.w) * dpr)
        var topLo = Math.floor((wret.y - 2.0) * dpr)
        var topHi = Math.ceil((wret.y + 2.0) * dpr)
        var span = right - left + 1
        var topMatches = 0
        for (var row = topLo; row <= topHi; ++row) {
            var rowMatches = 0
            for (var col = left; col <= right; ++col) {
                if (col < 0 || row < 0 || col >= during.width || row >= during.height)
                    continue
                var ep = [during.red(col, row), during.green(col, row), during.blue(col, row)]
                if (Helpers.colorsNear(ep, edge))
                    ++rowMatches
            }
            topMatches = Math.max(topMatches, rowMatches)
        }
        verify(topMatches >= 4, "the reticle horizontal dashed edge is visible")
        verify(topMatches <= span * 3 / 4, "the reticle horizontal edge is dashed, not solid")
        var ex0 = Math.floor((wret.x - 2.0) * dpr)
        var ex1 = Math.ceil((wret.x + 2.0) * dpr)
        var ey0 = Math.floor(wret.y * dpr)
        var ey1 = Math.ceil((wret.y + reticle.h) * dpr)
        var verticalMatches = 0
        for (var vy = ey0; vy <= ey1; ++vy)
            for (var vx = ex0; vx <= ex1; ++vx) {
                if (vx < 0 || vy < 0 || vx >= during.width || vy >= during.height)
                    continue
                var vp = [during.red(vx, vy), during.green(vx, vy), during.blue(vx, vy)]
                if (Helpers.colorsNear(vp, edge))
                    ++verticalMatches
            }
        verify(verticalMatches >= 4, "the reticle vertical dashed edge is visible")
    }
}
