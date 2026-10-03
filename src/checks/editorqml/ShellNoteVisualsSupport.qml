import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

TestCase {
    id: testCase
    name: "ShellNoteVisuals"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var grabbed: null
    property bool unsignedSongPrepared: false
    property int physicalRulerCaptureNumber: 0
    property int physicalSurfaceCaptureNumber: 0

    property alias bootstrap: _bootstrap
    property alias probe: _probe
    property alias shellComponent: _shellComponent
    property alias smallFontShellComponent: _smallFontShellComponent
    property alias physicalCaptureReader: _physicalCaptureReader

    ShellQmlBootstrap { id: _bootstrap }
    GatedVisualsProbe { id: _probe }

    Component { id: _shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component {
        id: _smallFontShellComponent
        ShellWindow {
            width: 960
            height: 640
            visible: true
            typographyCaptureFont: Qt.font({ pixelSize: 4 })
        }
    }
    Component { id: _physicalCaptureReader; Canvas { width: 1; height: 1 } }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function cleanup() {
        grabbed = null
        if (!shell) {
            if (unsignedSongPrepared) {
                verify(probe.restoreUnsignedSong(bootstrap.projectRoot, "mus_route101"),
                       "the signature-free song copy is restored after capture")
                unsignedSongPrepared = false
            }
            return
        }
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
        if (unsignedSongPrepared) {
            verify(probe.restoreUnsignedSong(bootstrap.projectRoot, "mus_route101"),
                   "the loaded unsigned song is restored after shell teardown")
            unsignedSongPrepared = false
        }
    }

    function selectedSurface() {
        var pages = shell && shell.sceneLoader ? shell.sceneLoader.item : null
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function grabShell() {
        wait(0)
        waitForRendering(shell.contentItem)
        var image = grabImage(shell.contentItem)
        if (image.width <= 0 || image.height <= 0)
            return null
        return image
    }
    function shellDpr(image) { return image.width / shell.contentItem.width }
    function grabSurface(context) {
        var item = context.surface
        waitForRendering(item)
        var capture = null
        verify(item.grabToImage(function(result) { capture = result }),
               "the mounted note surface accepts a physical framebuffer capture")
        tryVerify(function() { return capture !== null }, 3000)
        var file = bootstrap.projectRoot + "/note-surface-dpr2-"
                   + (++physicalSurfaceCaptureNumber) + ".png"
        verify(capture.saveToFile(file), "the mounted note surface saves its physical framebuffer")
        var reader = physicalCaptureReader.createObject(item)
        tryCompare(reader, "available", true, 3000)
        var url = "file://" + file
        reader.loadImage(url)
        tryVerify(function() { return reader.isImageLoaded(url) }, 3000)
        var pixels = reader.getContext("2d").createImageData(url)
        verify(pixels.width === Math.round(item.width * Screen.devicePixelRatio)
               && pixels.height === Math.round(item.height * Screen.devicePixelRatio),
               "the mounted note surface retains native device-pixel dimensions")
        reader.destroy()
        return {
            width: pixels.width, height: pixels.height,
            red: function(x, y) { return pixels.data[(y * pixels.width + x) * 4] },
            green: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 1] },
            blue: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 2] },
            alpha: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 3] }
        }
    }

    function win(item, x, y) {
        var corg = shell.contentItem.mapToItem(null, 0, 0)
        var w = item.mapToItem(null, x, y)
        return { x: w.x - corg.x, y: w.y - corg.y }
    }

    function publishedNotes(grid) {
        var parsed = JSON.parse(grid.fetchNoteSummary())
        for (var i = 0; i < parsed.length; ++i) {
            var e = parsed[i]
            if (!(e.id > 0) || typeof e.track !== "number" || typeof e.velocity !== "number")
                return null
        }
        return parsed
    }

    function noteItem(fills, id) {
        return RollNoteFaces.face(fills, id)
    }

    function deviceRect(item, plot, image, dpr, target) {
        var origin = target || shell.contentItem
        var face = item.mapToItem === undefined
        var source = face ? plot : item
        var left = face ? item.x : 0
        var top = face ? item.y : 0
        var topLeft = source.mapToItem(origin, left, top)
        var size = source.mapToItem(origin, left + item.width, top + item.height)
        var r = { x: Math.round(topLeft.x * dpr), y: Math.round(topLeft.y * dpr),
                  w: Math.max(1, Math.round((size.x - topLeft.x) * dpr)),
                  h: Math.max(1, Math.round((size.y - topLeft.y) * dpr)) }
        r.x = Math.max(0, r.x)
        r.y = Math.max(0, r.y)
        r.w = Math.min(r.w, image.width - r.x)
        r.h = Math.min(r.h, image.height - r.y)
        return r
    }

    function visibleNote(fills, plot, image, dpr, notes, selected, target) {
        var best = null
        var bestArea = -1
        for (var i = 0; i < notes.length; ++i) {
            var note = notes[i]
            if (selected !== undefined && note.selected !== selected)
                continue
            var item = noteItem(fills, note.id)
            if (!item)
                continue
            var topLeft = Qt.point(item.x, item.y)
            var bottomRight = Qt.point(item.x + item.width, item.y + item.height)
            if (topLeft.x < 1 || topLeft.y < 1
                    || bottomRight.x > plot.width - 1 || bottomRight.y > plot.height - 1)
                continue
            var rect = deviceRect(item, plot, image, dpr, target)
            var area = rect.w * rect.h
            if (rect.w >= 5 && rect.h >= 5 && area > bestArea) {
                best = { note: note, item: item, rect: rect }
                bestArea = area
            }
        }
        return best
    }

    function frameFailure(image, rect, inset, thickness, expected, label) {
        var cx = rect.x + Math.floor(rect.w / 2)
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var off = inset + pixel
            var points = [[cx, rect.y + off], [cx, rect.y + rect.h - 1 - off]]
            for (var i = 0; i < points.length; ++i) {
                var p = [image.red(points[i][0], points[i][1]),
                         image.green(points[i][0], points[i][1]),
                         image.blue(points[i][0], points[i][1])]
                if (!Helpers.colorsNear(p, expected))
                    return label + " at device pixel (" + points[i][0] + "," + points[i][1]
                        + "): expected " + Helpers.hexOf(expected) + ", actual " + Helpers.hexOf(p)
            }
        }
        return ""
    }

    function blackFrameFailure(image, rect, inset, thickness, label) {
        var cx = rect.x + Math.floor(rect.w / 2)
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var off = inset + pixel
            var points = [[cx, rect.y + off], [cx, rect.y + rect.h - 1 - off]]
            for (var i = 0; i < points.length; ++i) {
                var p = [image.red(points[i][0], points[i][1]),
                         image.green(points[i][0], points[i][1]),
                         image.blue(points[i][0], points[i][1])]
                if (!Helpers.isPhysicalBlack(p))
                    return label + " at device pixel (" + points[i][0] + "," + points[i][1]
                        + "): expected physical black, actual " + Helpers.hexOf(p)
            }
        }
        return ""
    }

    function sideFrameFailure(image, rect, inset, thickness, expected, label) {
        var cy = rect.y + Math.floor(rect.h / 2)
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var left = rgb(image, rect.x + inset + pixel, cy)
            var right = rgb(image, rect.x + rect.w - 1 - inset - pixel, cy)
            if (!Helpers.colorsNear(left, expected) || !Helpers.colorsNear(right, expected))
                return label + " at physical side offset " + pixel
                    + ": left " + Helpers.hexOf(left) + ", right " + Helpers.hexOf(right)
                    + ", left-1 " + Helpers.hexOf(rgb(image, rect.x + inset + pixel - 1, cy))
                    + ", left+1 " + Helpers.hexOf(rgb(image, rect.x + inset + pixel + 1, cy))
        }
        return ""
    }

    function edgeFrameFailure(image, rect, inset, thickness, expected, edge) {
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var x = rect.x + Math.floor(rect.w / 2)
            var y = rect.y + Math.floor(rect.h / 2)
            if (edge === "top")
                y = rect.y + inset + pixel
            else if (edge === "bottom")
                y = rect.y + rect.h - 1 - inset - pixel
            else if (edge === "left")
                x = rect.x + inset + pixel
            else
                x = rect.x + rect.w - 1 - inset - pixel
            var actual = rgb(image, x, y)
            if (!Helpers.colorsNear(actual, expected))
                return edge + " physical frame pixel (" + x + "," + y
                    + ") is " + Helpers.hexOf(actual)
        }
        return ""
    }

    function channelDelta(a, b) {
        return Math.max(Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]),
                        Math.abs(a[2] - b[2]))
    }

    function openNotes(captureFontPx, unsigned, division) {
        var properties = captureFontPx === undefined
                ? {} : { typographyCaptureFont: Qt.font({ pixelSize: captureFontPx }) }
        shell = shellComponent.createObject(null, properties)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        if (unsigned) {
            verify(probe.prepareUnsignedSong(bootstrap.projectRoot, "mus_route101",
                                             division || 24),
                   "the staged Route 101 copy has a removable explicit signature")
            unsignedSongPrepared = true
        }
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the staged song resolves")
        verify(session.songOpen, "Route 101 loads from the staged project")
        var surface = null
        verify(waitForNative(function() {
            surface = selectedSurface()
            return surface !== null && surface.visible
        }, 10000), "the selected tab page is mounted")
        var grid = surface.gridModel
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the roll publishes notes")
        var plot = findChild(surface, "timelineQuickRollPlot")
        var fills = findChild(surface, "timelineRendererPlot")
        verify(plot !== null && fills !== null, "the roll plot and fill layer are mounted")
        return { surface: surface, grid: grid, plot: plot, fills: fills,
                 session: session }
    }

    function rgb(image, x, y) {
        return [image.red(x, y), image.green(x, y), image.blue(x, y)]
    }
    function contrast(first, second) {
        function linear(channel) {
            var unit = channel / 255
            return unit <= 0.04045 ? unit / 12.92
                : Math.pow((unit + 0.055) / 1.055, 2.4)
        }
        function luminance(color) {
            return 0.2126 * linear(color[0]) + 0.7152 * linear(color[1])
                + 0.0722 * linear(color[2])
        }
        var a = luminance(first), b = luminance(second)
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
    }

    function regionChanged(before, after, rect, border) {
        for (var y = rect.y + border; y < rect.y + rect.h - border; ++y)
            for (var x = rect.x + border; x < rect.x + rect.w - border; ++x)
                if (!Helpers.colorsNear(rgb(before, x, y), rgb(after, x, y), 0))
                    return true
        return false
    }

    function regionIdentical(before, after, rect) {
        for (var y = rect.y; y < rect.y + rect.h; ++y)
            for (var x = rect.x; x < rect.x + rect.w; ++x)
                if (!Helpers.colorsNear(rgb(before, x, y), rgb(after, x, y), 0))
                    return false
        return true
    }

    function trackFace(context, image, ghost, target) {
        var notes = publishedNotes(context.grid)
        verify(notes !== null, "the note summary is valid")
        var track = context.grid.trackIndex
        var candidates = notes.filter(function(note) {
            return (note.track !== track) === ghost
        })
        return visibleNote(context.fills, context.plot, image,
                           image.width / (target || shell.contentItem).width,
                           candidates, undefined, target)
    }

    function unsignedRulerCapture(context, expectedBeat, expectedScroll, barTicks, physical,
                                  division) {
        var ruler = findChild(context.surface, "timelineQuickRuler")
        verify(ruler, "the signature-free loaded ruler is mounted")
        var image, dpr, reader = null
        if (physical) {
            dpr = Screen.devicePixelRatio
            var marks = findChild(ruler, "timelineQuickRulerMarks")
            verify(marks && marks.list === 2, "the physical ruler has a mounted scrolling content")
            tryVerify(function() {
                return marks.fetchedRevision === context.grid.scene.displayRevision
            }, 3000, "the physical ruler applies the requested camera scroll before capture")
            waitForRendering(ruler, 3000)
            var capture = null
            verify(ruler.grabToImage(function(result) { capture = result }),
                   "the loaded ruler accepts a physical-pixel capture")
            tryVerify(function() { return capture !== null }, 3000)
            var file = bootstrap.projectRoot + "/ruler-dpr2-unsigned-"
                       + (++physicalRulerCaptureNumber) + ".png"
            verify(capture.saveToFile(file), "the loaded ruler saves its physical-pixel framebuffer")
            reader = physicalCaptureReader.createObject(ruler)
            verify(reader, "the physical ruler capture has an image reader")
            tryCompare(reader, "available", true, 3000,
                       "the physical image reader has a ready canvas context")
            var url = "file://" + file
            reader.loadImage(url)
            tryVerify(function() { return reader.isImageLoaded(url) }, 3000)
            var pixels = reader.getContext("2d").createImageData(url)
            verify(pixels && Math.abs(pixels.width - ruler.width * dpr) <= 1
                   && Math.abs(pixels.height - ruler.height * dpr) <= 2,
                   "the ruler framebuffer retains native device-pixel dimensions")
            image = {
                width: pixels.width, height: pixels.height,
                red: function(x, y) { return pixels.data[(y * pixels.width + x) * 4] },
                green: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 1] },
                blue: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 2] }
            }
        } else {
            image = grabShell()
            dpr = shellDpr(image)
        }
        verify(image, "the signature-free loaded ruler produces a framebuffer")
        function pixelX(x) {
            return Math.round((physical ? x : win(ruler, x, 0).x) * dpr)
        }
        function pixelY(y) {
            return Math.round((physical ? y : win(ruler, 0, y).y) * dpr)
        }
        var gutter = Math.max(1, Math.round(context.grid.baseFontPx * 13 / 3))
        var background = Helpers.channels(context.session.palette.chromeBackground)
        var inkChannels = Helpers.channels(context.session.palette.gridLine)
        var ink = [0, 1, 2].map(function(index) {
            return Math.round((inkChannels[index] * inkChannels[3]
                             + background[index] * (255 - inkChannels[3])) / 255)
        })
        var text = Helpers.channels(context.session.palette.primaryText)
        var stemY = pixelY(ruler.height * 0.73)
        var counted = 0
        var captions = 0
        for (var tick of barTicks) {
            var x = gutter + tick / (division || 24) * expectedBeat - expectedScroll
            if (x < context.grid.baseFontPx || x > context.plot.width - context.grid.baseFontPx)
                continue
            var column = pixelX(x)
            var stem = false
            for (var offset = -1; offset <= 1; ++offset)
                stem = stem || channelDelta(rgb(image, column + offset, stemY), ink) <= 12
            verify(stem, "the fallback or regrouped bar stem paints at its independently computed physical pixel")
            var gapX = pixelX(x + expectedBeat * 0.4)
            verify(channelDelta(rgb(image, gapX, stemY), background) <= 12,
                   "the bar stem has chrome beside its precise device-pixel position")
            ++counted
            var captionFound = false
            for (var cy = pixelY(ruler.height * 0.55);
                 cy < pixelY(ruler.height * 0.92); ++cy)
                for (var cx = column + Math.max(1, Math.round(context.grid.baseFontPx * dpr / 4));
                     cx < column + Math.round(expectedBeat * dpr * 0.8); ++cx)
                    captionFound = captionFound || channelDelta(rgb(image, cx, cy), text) <= 12
            if (captionFound)
                ++captions
        }
        var beatCount = 0
        var ticksPerBeat = division || 24
        for (var beatTick = ticksPerBeat; beatTick <= barTicks[barTicks.length - 1];
             beatTick += ticksPerBeat) {
            if (barTicks.indexOf(beatTick) >= 0)
                continue
            var beatX = gutter + beatTick / ticksPerBeat * expectedBeat - expectedScroll
            if (beatX < gutter + context.grid.baseFontPx
                    || beatX > context.plot.width - context.grid.baseFontPx)
                continue
            var beatColumn = pixelX(beatX)
            var beatInk = false
            for (var beatOffset = -1; beatOffset <= 1; ++beatOffset)
                beatInk = beatInk
                    || channelDelta(rgb(image, beatColumn + beatOffset, stemY), ink) <= 12
            verify(beatInk, "each fallback or bound beat stem paints at its independently computed device pixel")
            ++beatCount
        }
        verify(beatCount > 0, "the loaded ruler paints visible non-bar beat stems")
        verify(counted >= 2, "the loaded ruler has at least two independently positioned visible bars")
        verify(captions >= 2, "at least two bar numbers paint as real native text on chrome")
        if (reader)
            reader.destroy()
        return image
    }

    function exactRulerColumns(context, image, beatWidth, scroll, physical) {
        var ruler = findChild(context.surface, "timelineQuickRuler")
        var dpr = physical ? Screen.devicePixelRatio : shellDpr(image)
        var gutter = Math.max(1, Math.round(context.grid.baseFontPx * 13 / 3))
        var background = Helpers.channels(context.session.palette.chromeBackground)
        var ink = Helpers.channels(context.session.palette.gridLine)
        var composite = [0, 1, 2].map(function(channel) {
            return Math.round((ink[channel] * ink[3]
                             + background[channel] * (255 - ink[3])) / 255)
        })
        var y0 = Math.round((physical ? ruler.height * 0.73
                             : win(ruler, 0, ruler.height * 0.73).y) * dpr)
        var y1 = Math.round((physical ? ruler.height * 0.88
                             : win(ruler, 0, ruler.height * 0.88).y) * dpr)
        var columns = []
        for (var bar = 0; bar < 6; ++bar) {
            var x = gutter + bar * 4 * beatWidth - scroll
            var expected = Math.round((physical ? x : win(ruler, x, 0).x) * dpr)
            if (x < context.grid.baseFontPx
                    || x > ruler.width - context.grid.baseFontPx) {
                columns.push(-1)
                continue
            }
            var detected = -1
            for (var offset = -1; offset <= 1 && detected < 0; ++offset) {
                var count = 0
                for (var y = y0; y <= y1; ++y)
                    if (channelDelta(rgb(image, expected + offset, y), composite) <= 12)
                        ++count
                if (count >= 2)
                    detected = expected + offset
            }
            columns.push(detected)
        }
        return columns
    }

    function unsignedRulerJourney(context, physical) {
        var grid = context.grid
        var beat = Math.round(13 * 8 / 3)
        var lead = Math.min(256, Math.max(48, Math.round(context.plot.width * 0.1)))
        var ruler = findChild(context.surface, "timelineQuickRuler")
        var initialHeight = ruler.height
        grid.setCameraHScroll(-lead)
        var initial = unsignedRulerCapture(context, beat, -lead,
                                           [0, 96, 192, 288, 384, 480], physical)
        context.session.openTimeSigPrompt(0)
        context.session.acceptTimeSigPrompt(3, 2)
        compare(ruler.height, initialHeight, "A048 binding three-four retains the mounted ruler height")
        var bound = unsignedRulerCapture(context, beat, -lead,
                                         [0, 72, 144, 216, 288, 360], physical)
        var dpr = physical ? Screen.devicePixelRatio : shellDpr(bound)
        var gutter = Math.max(1, Math.round(grid.baseFontPx * 13 / 3))
        var capOffset = grid.baseFontPx / 10
        var background = Helpers.channels(context.session.palette.chromeBackground)
        var gridInk = Helpers.channels(context.session.palette.gridLine)
        var ink = [0, 1, 2].map(function(index) {
            return Math.round((gridInk[index] * gridInk[3]
                             + background[index] * (255 - gridInk[3])) / 255)
        })
        var allCapsMoved = true
        for (var pair of [[72, 96], [144, 192]]) {
            var newPosition = gutter + pair[0] / 24 * beat + lead + capOffset
            var oldPosition = gutter + pair[1] / 24 * beat + lead + capOffset
            var movedX = Math.round((physical ? newPosition
                                    : win(ruler, newPosition, 0).x) * dpr)
            var oldX = Math.round((physical ? oldPosition
                                  : win(ruler, oldPosition, 0).x) * dpr)
            var capMoved = false
            for (var cy = Math.round((physical ? ruler.height * 0.15
                                     : win(ruler, 0, ruler.height * 0.15).y) * dpr);
                 cy < Math.round((physical ? ruler.height * 0.65
                                  : win(ruler, 0, ruler.height * 0.65).y) * dpr); ++cy) {
                if (channelDelta(rgb(bound, movedX, cy), ink) <= 12
                        && channelDelta(rgb(bound, oldX, cy), background) <= 12)
                    capMoved = true
            }
            allCapsMoved = allCapsMoved && capMoved
        }
        verify(allCapsMoved, "three-four bar caps paint at new ticks and not former four-four bar ticks")
        grid.setCameraHScroll(beat * 2)
        unsignedRulerCapture(context, beat, beat * 2, [0, 72, 144, 216, 288, 360], physical)
        grid.handleWheel(0, 120, 0, 0, Qt.NoModifier, 0, false, 0, 0)
        grid.setCameraHScroll(0)
        unsignedRulerCapture(context, beat * Math.pow(1.0015, 120), 0,
                             [0, 72, 144, 216, 288, 360], physical)
        compare(ruler.height, initialHeight, "the zoomed three-four ruler keeps its original height")
        return initial
    }

}
