import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers

ShellNoteVisualsSupport {
    function test_unsignedRulerBarRasterAfterBindAndPan() {
        compare(Screen.devicePixelRatio, probe.expectedLaneDpr(),
                "the unsigned ruler executes at the requested framebuffer DPR")
        unsignedRulerJourney(openNotes(undefined, true), probe.expectedLaneDpr() === 2)
    }

    function test_explicitFourFourAndFortyEightTickRulerColumns() {
        var physical = probe.expectedLaneDpr() === 2
        compare(Screen.devicePixelRatio, probe.expectedLaneDpr(),
                "the explicit ruler executes at the requested framebuffer DPR")
        var context = openNotes(undefined, true)
        var grid = context.grid
        var lead = Math.min(256, Math.max(48, Math.round(context.plot.width * 0.1)))
        var beat = Math.round(13 * 8 / 3) * Math.pow(1.0015, -160)
        grid.handleWheel(0, -160, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        grid.setCameraHScroll(-lead)
        verify(Math.abs(grid.beatWidth - beat) < 0.1,
               "the mounted ruler uses the independently computed reduced beat zoom")
        var ticks24 = [0, 96, 192, 288, 384, 480]
        var gutter = Math.max(1, Math.round(grid.baseFontPx * 13 / 3))
        var scrolls = [-lead, gutter + 20 * beat - context.plot.width
                       + 2 * grid.baseFontPx]
        var beforeViews = []
        var beforeColumns = [-1, -1, -1, -1, -1, -1]
        for (var view = 0; view < scrolls.length; ++view) {
            grid.setCameraHScroll(scrolls[view])
            var initial = unsignedRulerCapture(context, beat, scrolls[view],
                                               ticks24, physical, 24)
            var detected = exactRulerColumns(context, initial, beat, scrolls[view],
                                             physical)
            beforeViews.push(detected)
            for (var bar = 0; bar < detected.length; ++bar)
                if (detected[bar] >= 0)
                    beforeColumns[bar] = detected[bar]
        }
        verify(beforeColumns.every(function(column) { return column >= 0 }),
               "A034 the six original four-four bar stems occupy detected framebuffer columns")
        context.session.openTimeSigPrompt(0)
        context.session.acceptTimeSigPrompt(4, 2)
        for (view = 0; view < scrolls.length; ++view) {
            grid.setCameraHScroll(scrolls[view])
            var bound = unsignedRulerCapture(context, beat, scrolls[view],
                                             ticks24, physical, 24)
            compare(exactRulerColumns(context, bound, beat, scrolls[view], physical),
                    beforeViews[view],
                    "A034 explicit four-four binding retains all six original raster bar columns")
        }

        cleanup()
        context = openNotes(undefined, true, 48)
        grid = context.grid
        grid.handleWheel(0, -160, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        compare(grid.ticksPerBeat, 48, "the loaded ruler uses a real 48-TPB song")
        verify(Math.abs(grid.beatWidth - beat) < 0.1,
               "the 48-TPB ruler retains the independently computed beat zoom")
        var ticks48 = [0, 192, 384, 576, 768, 960]
        var doubled = null
        var doubledColumns = [-1, -1, -1, -1, -1, -1]
        for (view = 0; view < scrolls.length; ++view) {
            grid.setCameraHScroll(scrolls[view])
            var image = unsignedRulerCapture(context, beat, scrolls[view],
                                             ticks48, physical, 48)
            if (view === 0)
                doubled = image
            detected = exactRulerColumns(context, image, beat, scrolls[view], physical)
            compare(detected, beforeViews[view],
                    "A041 each 48-TPB bar stem shares its actual 24-TPB framebuffer column")
            for (bar = 0; bar < detected.length; ++bar)
                if (detected[bar] >= 0)
                    doubledColumns[bar] = detected[bar]
        }
        verify(doubledColumns.every(function(column) { return column >= 0 }),
               "A041 the 48-TPB ruler paints all six bar stems on its actual framebuffer")
        compare(doubledColumns, beforeColumns,
                "A041 all six 48-TPB bar columns equal their 24-TPB framebuffer columns")
        var ruler = findChild(context.surface, "timelineQuickRuler")
        var dpr = physical ? Screen.devicePixelRatio : shellDpr(doubled)
        var background = Helpers.channels(context.session.palette.chromeBackground)
        var ink = Helpers.channels(context.session.palette.gridLine)
        var composite = [0, 1, 2].map(function(channel) {
            return Math.round((ink[channel] * ink[3]
                             + background[channel] * (255 - ink[3])) / 255)
        })
        var y = Math.round((physical ? ruler.height * 0.73
                            : win(ruler, 0, ruler.height * 0.73).y) * dpr)
        function beatColumn(index) {
            var position = gutter + index * beat + lead
            return Math.round((physical ? position : win(ruler, position, 0).x) * dpr)
        }
        function stemAt(index) {
            var x = beatColumn(index)
            for (var dx = -1; dx <= 1; ++dx)
                if (channelDelta(rgb(doubled, x + dx, y), composite) <= 12)
                    return true
            return false
        }
        function gapAfter(index) {
            var between = beatColumn(index) + Math.round(beat * dpr / 2)
            return channelDelta(rgb(doubled, between, y), background) <= 12
        }
        verify(stemAt(1), "A040 the bound 48-TPB first beat stem paints at its exact physical column")
        verify(gapAfter(1), "A040 the first 48-TPB beat stem has unmarked chrome after its column")
        verify(stemAt(2), "A040 the bound 48-TPB second beat stem paints at its exact physical column")
        verify(gapAfter(2), "A040 the second 48-TPB beat stem has unmarked chrome after its column")
        verify(stemAt(3), "A040 the bound 48-TPB third beat stem paints at its exact physical column")
        verify(gapAfter(3), "A040 the third 48-TPB beat stem has unmarked chrome after its column")
    }


    function test_preRollPadAndRulerRaster() {
        compare(Screen.devicePixelRatio, probe.expectedLaneDpr(),
                "the pre-roll raster executes at the requested framebuffer DPR")
        var physical = probe.expectedLaneDpr() === 2
        var context = openNotes()
        var grid = context.grid
        grid.setCameraHScroll(grid.cameraMinHScroll)
        var target = physical ? context.surface : shell.contentItem
        var image = physical ? grabSurface(context) : grabShell()
        verify(image !== null, "the mounted roll and ruler produce a raster")
        var dpr = image.width / target.width
        verify(dpr > 0, "the mounted roll capture has positive physical DPR")
        var plot = context.plot
        var ruler = findChild(context.surface, "timelineQuickRuler")
        verify(ruler && plot.width > 0 && plot.height > 0,
               "the pre-roll has a mounted ruler and roll band")
        var tickZero = -grid.cameraScrollX
        verify(tickZero > grid.baseFontPx && tickZero < plot.width - grid.baseFontPx,
               "tick zero leaves a font-scaled visible pre-roll pad")
        var row = Math.floor((grid.cameraScrollY + plot.height / 2) / grid.rowHeight)
        var natural = -1, accidental = -1
        for (var i = Math.max(0, row - 6); i <= Math.min(127, row + 6); ++i) {
            var pitch = 127 - i
            var y = (i + 0.5) * grid.rowHeight - grid.cameraScrollY
            if (y <= grid.rowHeight || y >= plot.height - grid.rowHeight)
                continue
            if ([1, 3, 6, 8, 10].indexOf(pitch % 12) >= 0)
                accidental = y
            else
                natural = y
        }
        verify(natural > 0, "a natural key row is visible inside the mounted roll")
        verify(accidental > 0, "an accidental key row is visible inside the mounted roll")
        var padX = tickZero / 2
        function plotPixel(x, y) {
            var p = plot.mapToItem(target, x, y)
            return rgb(image, Math.round(p.x * dpr), Math.round(p.y * dpr))
        }
        var naturalPad = plotPixel(padX, natural)
        var accidentalPad = plotPixel(padX, accidental)
        compare(naturalPad, accidentalPad,
                "natural and accidental rows paint identical pre-roll pad pixels")
        var naturalPlot = plotPixel(tickZero + grid.baseFontPx, natural)
        verify(channelDelta(naturalPlot,
                            Helpers.channels(grid.palette.rollBackground)) <= 2,
               "the adjacent natural-key plot sample is unoccupied background: "
               + Helpers.hexOf(naturalPlot))
        verify(channelDelta(naturalPad, naturalPlot) > 1,
               "the pre-roll pad differs from the natural-key plot")
        function rulerPixel(x, y) {
            var p = ruler.mapToItem(target, grid.keyboardWidth + x, y)
            return rgb(image, Math.round(p.x * dpr), Math.round(p.y * dpr))
        }
        var upper = rulerPixel(padX * 0.5, ruler.height * 0.5)
        var lower = rulerPixel(padX, ruler.height * 0.85)
        verify(channelDelta(upper, lower) <= 2,
               "the ruler pre-roll shade is uniform across upper and lower samples")
        var adjacentChrome = rulerPixel(tickZero + grid.baseFontPx, ruler.height * 0.08)
        verify(channelDelta(adjacentChrome,
                            Helpers.channels(grid.palette.chromeBackground)) <= 2,
               "the adjacent ruler sample paints unmarked chrome: "
               + Helpers.hexOf(adjacentChrome))
        verify(channelDelta(upper, adjacentChrome) > 1,
               "the ruler pad is distinct from adjacent chrome")
        var ink = Helpers.channels(grid.palette.primaryText)
        var chrome = rulerPixel(tickZero + grid.baseFontPx, ruler.height * 0.2)
        verify(channelDelta(ink, chrome) > 12,
               "the tick-zero stem ink differs from adjacent ruler chrome")
        var top = Math.floor(ruler.height * 0.05 * dpr)
        var bottom = Math.floor(ruler.height * 0.45 * dpr)
        var zero = ruler.mapToItem(target, grid.keyboardWidth + tickZero, 0)
        var rulerTop = Math.round(ruler.mapToItem(target, 0, 0).y * dpr)
        var longest = 0
        for (var dx = -1; dx <= 1; ++dx) {
            var count = 0
            for (var py = top; py <= bottom; ++py) {
                var pixel = rgb(image, Math.round(zero.x * dpr) + dx, rulerTop + py)
                if (channelDelta(pixel, ink) <= 12)
                    ++count
            }
            longest = Math.max(longest, count)
        }
        verify(longest >= (bottom - top) * 0.7,
               "tick zero paints a continuous upper ruler stem")
        var captionLeft = Math.round(ruler.mapToItem(
            target, grid.keyboardWidth + grid.baseFontPx * 0.3, 0).x * dpr)
        var captionRight = Math.round(ruler.mapToItem(
            target, grid.keyboardWidth + tickZero - grid.baseFontPx * 0.3, 0).x * dpr)
        verify(captionRight > captionLeft, "the pre-zero ruler has room for a caption probe")
        var captionInk = 0
        for (var cy = rulerTop; cy < rulerTop + Math.floor(ruler.height * dpr) - 1; ++cy)
            for (var cx = captionLeft; cx < captionRight; ++cx)
                if (channelDelta(rgb(image, cx, cy), upper) > 12)
                    ++captionInk
        compare(captionInk, 0, "no placeholder caption paints before tick zero")
    }

    function test_ghostEdgesAndMinimumZoomFace() {
        compare(Screen.devicePixelRatio, probe.expectedLaneDpr(),
                "the ghost raster executes at the requested framebuffer DPR")
        var physical = probe.expectedLaneDpr() === 2
        var context = openNotes()
        var grid = context.grid
        var target = physical ? context.surface : shell.contentItem
        var image = physical ? grabSurface(context) : grabShell()
        verify(image !== null, "the ghost roll produces a raster")
        var ghost = trackFace(context, image, true, target)
        verify(ghost !== null && ghost.rect.h >= 6,
               "an other-track note has room for edge and adjacent interior probes")
        var cx = ghost.rect.x + Math.floor(ghost.rect.w / 2)
        var top = ghost.rect.y, bottom = top + ghost.rect.h - 1
        verify(Helpers.colorsNear(rgb(image, cx, top), rgb(image, cx, top + 2), 0),
               "the ghost top edge matches its adjacent interior pixel")
        verify(Helpers.colorsNear(rgb(image, cx, bottom), rgb(image, cx, bottom - 2), 0),
               "the ghost bottom edge matches its adjacent interior pixel")
        var cy = top + Math.floor(ghost.rect.h / 2)
        verify(Helpers.colorsNear(rgb(image, ghost.rect.x, cy),
                                  rgb(image, ghost.rect.x + 2, cy), 0),
               "the ghost left edge has no plain-note border or selected ring")
        verify(Helpers.colorsNear(rgb(image, ghost.rect.x + ghost.rect.w - 1, cy),
                                  rgb(image, ghost.rect.x + ghost.rect.w - 3, cy), 0),
               "the ghost right edge has no plain-note border or selected ring")
        grid.handleWheel(0, -5000, 0, 0, 0, 0, false,
                         context.plot.width / 2, context.plot.height / 2)
        grid.setCameraHScroll(grid.cameraMinHScroll)
        verify(waitForNative(function() {
            return grid.beatWidth <= grid.baseFontPx / 3 + 0.01
        }, 5000), "the mounted note reaches the minimum time zoom")
        var zoom = physical ? grabSurface(context) : grabShell()
        verify(zoom !== null, "the minimum-time-zoom roll produces a raster")
        var notes = publishedNotes(grid)
        var narrow = null
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].ghost)
                continue
            var item = noteItem(context.fills, notes[i].id)
            if (!item)
                continue
            var point = context.fills.mapToItem(context.plot, item.x, item.y)
            if (point.x < 2 || point.y < 2
                    || point.x + item.width > context.plot.width - 2
                    || point.y + item.height > context.plot.height - 2)
                continue
            var rect = deviceRect(item, context.plot, zoom,
                                  zoom.width / target.width, target)
            if (rect.w >= 3 && rect.h >= 3 && (!narrow || rect.w < narrow.rect.w))
                narrow = { note: notes[i], rect: rect }
        }
        verify(narrow !== null && narrow.rect.w <= 3 * zoom.width / target.width,
               "a snap-cell narrow note remains visible at minimum time zoom: "
               + (narrow ? JSON.stringify(narrow.rect) : "no visible note"))
        var box = narrow.rect
        var centerX = box.x + Math.floor(box.w / 2)
        var centerY = box.y + Math.floor(box.h / 2)
        var face = rgb(zoom, centerX, centerY)
        var topOutline = rgb(zoom, centerX, box.y)
        verify(channelDelta(topOutline, Helpers.channels(grid.palette.noteBorder)) <= 16
               && zoom.alpha(centerX, box.y) > 0,
               "the minimum-zoom narrow note paints its top outline in the border role")
        verify(channelDelta(topOutline, face) > 16,
               "the minimum-zoom note outline differs visibly from its face")
        verify(Helpers.colorsNear(face, Helpers.channels(probe.noteFace(
                   narrow.note.track, narrow.note.velocity, grid.palette.noteVelocityZero))),
               "the minimum-zoom narrow note retains its painted face")
    }

}
