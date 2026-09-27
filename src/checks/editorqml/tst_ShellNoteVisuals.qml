import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellNoteVisuals"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var grabbed: null

    ShellQmlBootstrap { id: bootstrap }
    GatedVisualsProbe { id: probe }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component {
        id: smallFontShellComponent
        ShellWindow {
            width: 960
            height: 640
            visible: true
            typographyCaptureFont: Qt.font({ pixelSize: 4 })
        }
    }
    Component { id: physicalCaptureReader; Canvas { width: 1; height: 1 } }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
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

    function grabShell() {
        waitForRendering(shell.contentItem)
        var image = grabImage(shell.contentItem)
        if (image.width <= 0 || image.height <= 0)
            return null
        return image
    }
    function shellDpr(image) { return image.width / shell.contentItem.width }
    function win(item, x, y) {
        var corg = shell.contentItem.mapToItem(null, 0, 0)
        var w = item.mapToItem(null, x, y)
        return { x: w.x - corg.x, y: w.y - corg.y }
    }

    function publishedNotes(grid) {
        var parsed = JSON.parse(grid.noteSummary)
        for (var i = 0; i < parsed.length; ++i) {
            var e = parsed[i]
            if (!(e.id > 0) || typeof e.track !== "number" || typeof e.velocity !== "number")
                return null
        }
        return parsed
    }

    function noteItem(fills, id) {
        return findChild(fills, "gridNote_" + id)
    }

    function deviceRect(item, plot, image, dpr) {
        var topLeft = win(item, 0, 0)
        var size = win(item, item.width, item.height)
        var r = { x: Math.round(topLeft.x * dpr), y: Math.round(topLeft.y * dpr),
                  w: Math.max(1, Math.round((size.x - topLeft.x) * dpr)),
                  h: Math.max(1, Math.round((size.y - topLeft.y) * dpr)) }
        r.x = Math.max(0, r.x)
        r.y = Math.max(0, r.y)
        r.w = Math.min(r.w, image.width - r.x)
        r.h = Math.min(r.h, image.height - r.y)
        return r
    }

    function visibleNote(fills, plot, image, dpr, notes, selected) {
        var best = null
        var bestArea = -1
        for (var i = 0; i < notes.length; ++i) {
            var note = notes[i]
            if (selected !== undefined && note.selected !== selected)
                continue
            var item = noteItem(fills, note.id)
            if (!item || !item.visible)
                continue
            var topLeft = item.mapToItem(plot, 0, 0)
            var bottomRight = item.mapToItem(plot, item.width, item.height)
            if (topLeft.x < 1 || topLeft.y < 1
                    || bottomRight.x > plot.width - 1 || bottomRight.y > plot.height - 1)
                continue
            var rect = deviceRect(item, plot, image, dpr)
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

    function openNotes(captureFontPx) {
        var properties = captureFontPx === undefined
                ? {} : { typographyCaptureFont: Qt.font({ pixelSize: captureFontPx }) }
        shell = shellComponent.createObject(null, properties)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the staged song resolves")
        verify(session.songOpen, "Route 101 loads from the staged project")
        var surface = selectedSurface()
        verify(surface !== null, "the selected tab page is mounted")
        var grid = surface.gridModel
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the roll publishes notes")
        var plot = findChild(surface, "timelineQuickRollPlot")
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
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

    function trackFace(context, image, ghost) {
        var notes = publishedNotes(context.grid)
        verify(notes !== null, "the note summary is valid")
        var track = context.grid.trackIndex
        var candidates = notes.filter(function(note) {
            return (note.track !== track) === ghost
        })
        return visibleNote(context.fills, context.plot, image, shellDpr(image),
                           candidates, undefined)
    }

    function test_velocityColorRaster() {
        var context = openNotes()
        var baseline = grabShell()
        verify(baseline !== null, "the identity roll renders a frame")
        var ghost = trackFace(context, baseline, true)
        var note = trackFace(context, baseline, false)
        verify(ghost !== null, "a visible other-track note guards the ghost comparison")
        verify(note !== null, "a visible current-track note guards the fill probe")
        var before = rgb(baseline, note.rect.x + Math.floor(note.rect.w / 2),
                         note.rect.y + Math.floor(note.rect.h / 2))
        shell.shellPresenter.activate("view.velocity_colors")
        verify(waitForNative(function() { return context.session.velocityColorMode }, 5000),
               "the menu enables velocity-color rendering")
        var colored = grabShell()
        verify(colored !== null, "the velocity-color mode renders a frame")
        verify(regionIdentical(baseline, colored, ghost.rect),
               "velocity-color mode changes no ghost note pixel")
        var expected = Helpers.channels(probe.velocityFace(
            note.note.velocity, context.grid.palette.noteVelocityZero))
        var actual = rgb(colored, note.rect.x + Math.floor(note.rect.w / 2),
                         note.rect.y + Math.floor(note.rect.h / 2))
        verify(Helpers.colorsNear(actual, expected),
               "velocity-mode note interior matches velocityNoteColor")
        shell.shellPresenter.activate("view.velocity_colors")
        verify(waitForNative(function() { return !context.session.velocityColorMode }, 5000),
               "the menu disables velocity-color rendering")
        var restored = grabShell()
        verify(restored !== null, "the identity mode renders again")
        verify(Helpers.colorsNear(
            rgb(restored, note.rect.x + Math.floor(note.rect.w / 2),
                note.rect.y + Math.floor(note.rect.h / 2)), before),
            "disabling velocity-color mode restores the identity fill pixels")
    }

    function test_drawnNoteFillBorderAndAbuttingSeam() {
        var context = openNotes()
        verify(context.plot !== null, "the fixture mounts a timeline")
        var grid = context.grid
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the mounted pencil input is available")
        var notes = publishedNotes(grid)
        var ticksPerPixel = grid.ticksPerBeat / grid.beatWidth
        var snap = grid.snapTicks
        var start = Math.ceil((grid.cameraScrollX + roll.width / 3)
                              * ticksPerPixel / snap) * snap
        var span = Math.max(2 * snap, Math.ceil(2 * grid.drawThreshold * ticksPerPixel
                                               / snap) * snap)
        var x = start / ticksPerPixel - grid.cameraScrollX
        var end = (start + 2 * span) / ticksPerPixel - grid.cameraScrollX
        var pitch = -1
        for (var row = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2;
             row < Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight) - 2;
             ++row) {
            var candidate = 127 - row
            if (!notes.some(function(note) {
                return note.pitch === candidate && note.tick < start + 2 * span
                    && note.tick + note.duration > start
            })) {
                pitch = candidate
                break
            }
        }
        verify(pitch >= 0 && x > grid.rowHeight && end < roll.width - grid.rowHeight,
               "two adjacent displayed cells have an empty pitch row")
        var y = (127 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        var baseline = grabShell()
        verify(baseline !== null, "the empty row renders before painting")
        var originalIds = notes.map(function(note) { return note.id })
        var inset = Math.min(grid.drawThreshold / 2, snap / ticksPerPixel / 4)
        var firstEnd = (start + span) / ticksPerPixel - grid.cameraScrollX - inset
        mousePress(roll, x + inset, y, Qt.LeftButton)
        mouseMove(roll, firstEnd, y, -1, Qt.LeftButton)
        mouseRelease(roll, firstEnd, y, Qt.LeftButton)
        var first = null
        verify(waitForNative(function() {
            first = publishedNotes(grid).find(function(note) {
                return originalIds.indexOf(note.id) < 0
            })
            return first !== undefined
        }, 5000), "the first cell commits a drawn note")
        var firstImage = grabShell()
        verify(firstImage !== null, "the first pencil note renders a frame")
        var firstItem = noteItem(context.fills, first.id)
        verify(firstItem !== null, "the first drawn note box is mounted")
        var firstDpr = shellDpr(firstImage)
        var firstBox = deviceRect(firstItem, context.plot, firstImage, firstDpr)
        var firstRight = firstBox.x + firstBox.w
        var firstBottom = firstBox.y + firstBox.h
        var escaped = false
        for (var borderY = firstBox.y; borderY <= firstBottom; ++borderY) {
            if (!Helpers.colorsNear(rgb(firstImage, firstRight, borderY),
                                    rgb(baseline, firstRight, borderY), 0)) {
                escaped = true
                break
            }
        }
        for (var borderX = firstBox.x; borderX <= firstRight && !escaped; ++borderX) {
            if (!Helpers.colorsNear(rgb(firstImage, borderX, firstBottom),
                                    rgb(baseline, borderX, firstBottom), 0))
                escaped = true
        }
        verify(!escaped, "note color does not escape its border box")
        var adjacentX = (first.tick + first.duration) / ticksPerPixel - grid.cameraScrollX
        var secondStart = adjacentX + span / ticksPerPixel / 2
        var secondEnd = adjacentX + span / ticksPerPixel
        mousePress(roll, secondStart, y, Qt.LeftButton)
        mouseMove(roll, secondEnd, y, -1, Qt.LeftButton)
        mouseRelease(roll, secondEnd, y, Qt.LeftButton)
        var second = null
        verify(waitForNative(function() {
            second = publishedNotes(grid).find(function(note) {
                return originalIds.indexOf(note.id) < 0 && note.id !== first.id
                    && note.pitch === pitch
            })
            return second !== undefined
        }, 5000), "the next displayed cell commits the second note")
        var secondItem = null
        tryVerify(function() {
            secondItem = noteItem(context.fills, second.id)
            return secondItem !== null
        }, 3000)
        var center = secondItem.mapToItem(roll, secondItem.width / 2, secondItem.height / 2)
        var shift = (second.tick - first.tick - first.duration) / ticksPerPixel
        verify(shift > grid.drawThreshold, "the drawn notes leave a movable snapped gap")
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, center.x - shift, center.y, -1, Qt.LeftButton)
        mouseRelease(roll, center.x - shift, center.y, Qt.LeftButton)
        var secondId = second.id
        verify(waitForNative(function() {
            second = publishedNotes(grid).find(function(note) { return note.id === secondId })
            return second !== undefined && second.tick === first.tick + first.duration
        }, 5000), "the next drawn note abuts the first on the same row")
        var image = grabShell()
        verify(image !== null, "the adjacent pencil notes render a frame")
        verify(secondItem !== null, "the second drawn note box is mounted")
        var dpr = shellDpr(image)
        var box = deviceRect(firstItem, context.plot, image, dpr)
        var nextBox = deviceRect(secondItem, context.plot, image, dpr)
        var cy = box.y + Math.floor(box.h / 2)
        var cx = box.x + Math.floor(box.w / 2)
        var expected = Helpers.channels(probe.noteFace(
            first.track, first.velocity, grid.palette.noteVelocityZero))
        verify(Helpers.colorsNear(rgb(image, cx, cy), expected),
               "a drawn note paints its interior in the velocity fill")
        var seamStart = box.x
        var seamEnd = nextBox.x + nextBox.w - 1
        var seamPainted = true
        for (var seamX = seamStart; seamX <= seamEnd; ++seamX) {
            if (Helpers.colorsNear(rgb(image, seamX, cy),
                                   rgb(baseline, seamX, cy), 0)) {
                seamPainted = false
                break
            }
        }
        verify(nextBox.x <= box.x + box.w && nextBox.x + nextBox.w > seamStart
               && seamPainted, "abutting notes leave no unpainted gap column")
    }

    function test_noteNameRaster() {
        var context = openNotes()
        context.grid.handleWheel(0, 1600, 0, 0, Qt.ControlModifier, 0,
                                 false, 0, context.plot.height / 2)
        context.grid.setCameraHScroll(context.grid.cameraMinHScroll)
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll pointer surface is mounted")
        var ghost = null
        var lane = null
        var step = context.plot.height / 2
        var attempts = Math.ceil(context.grid.cameraMaxVScroll / step) + 1
        for (var index = 0; index <= attempts; ++index) {
            context.grid.setCameraVScroll(Math.min(context.grid.cameraMaxVScroll, index * step))
            var frame = grabShell()
            if (frame === null)
                continue
            ghost = trackFace(context, frame, true)
            if (ghost === null)
                continue
            var grid = context.grid
            var ppt = grid.beatWidth / grid.ticksPerBeat
            var snap = grid.snapTicks
            var tick = Math.ceil(((grid.cameraScrollX + 24) / ppt) / snap) * snap
            if ((tick + 12 * snap) * ppt - grid.cameraScrollX > context.plot.width - 24)
                continue
            var occupied = publishedNotes(grid)
            var first = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2
            var last = Math.floor((grid.cameraScrollY + context.plot.height)
                                  / grid.rowHeight) - 2
            for (var row = first; row <= last; ++row) {
                var pitch = 127 - row
                if (!occupied.some(function(n) { return n.pitch === pitch })) {
                    lane = { tick: tick, pitch: pitch }
                    break
                }
            }
            if (lane !== null)
                break
        }
        verify(ghost !== null && lane !== null,
               "a visible ghost and free wide-note lane share the fixture viewport")
        var beforeCount = publishedNotes(context.grid).length
        var x0 = lane.tick * ppt - context.grid.cameraScrollX + 1
        var x1 = (lane.tick + 12 * snap) * ppt - context.grid.cameraScrollX - 1
        var y0 = (127 - lane.pitch + 0.5) * context.grid.rowHeight
            - context.grid.cameraScrollY
        mousePress(roll, x0, y0, Qt.LeftButton)
        mouseMove(roll, x1, y0, -1, Qt.LeftButton)
        mouseRelease(roll, x1, y0, Qt.LeftButton)
        verify(waitForNative(function() {
            return publishedNotes(context.grid).length === beforeCount + 1
        }, 5000), "the mounted roll seeds a wide name-bearing note")
        var baseline = grabShell()
        verify(baseline !== null, "the unlabeled roll renders a frame")
        shell.shellPresenter.activate("view.note_names")
        verify(waitForNative(function() { return context.session.noteNameMode }, 5000),
               "the menu enables note-name rendering")
        var named = grabShell()
        verify(named !== null, "the named roll renders a frame")
        verify(regionIdentical(baseline, named, ghost.rect),
               "note-name mode changes no ghost note pixel")
        var notes = publishedNotes(context.grid)
        var inkPixels = 0
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].track !== context.grid.trackIndex)
                continue
            var item = noteItem(context.fills, notes[i].id)
            if (!item || !item.visible)
                continue
            var noteRect = deviceRect(item, context.plot, named, shellDpr(named))
            if (noteRect.w <= 20 || noteRect.h <= 12)
                continue
            var noteFill = probe.noteFace(
                notes[i].track, notes[i].velocity, context.grid.palette.noteVelocityZero)
            var ink = Helpers.channels(context.grid.palette.noteLabelInk(noteFill))
            for (var y = noteRect.y + 2; y < noteRect.y + noteRect.h - 2; ++y)
                for (var x = noteRect.x + 2; x < noteRect.x + noteRect.w - 2; ++x) {
                    var painted = rgb(named, x, y)
                    if (Helpers.colorsNear(painted, ink)
                            && !Helpers.colorsNear(rgb(baseline, x, y), ink)
                            && contrast(painted, Helpers.channels(noteFill)) >= 2.5)
                        ++inkPixels
                }
        }
        verify(inkPixels > 0, "wide-note label ink contrasts with its fill")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return publishedNotes(context.grid).length === beforeCount
        }, 5000), "undo removes the seeded name fixture note")
    }

    function test_velocityValueRaster() {
        var context = openNotes()
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll pointer surface is mounted")
        var initial = grabShell()
        verify(initial !== null, "the idle roll renders a frame")
        var target = trackFace(context, initial, false)
        verify(target !== null, "a visible note guards the velocity drag")
        var anchor = target.item.mapToItem(context.plot, target.item.width / 2, 0)
        context.grid.handleWheel(0, 600, 0, 0, 0, 0, false, anchor.x, 0)
        var idle = grabShell()
        verify(idle !== null, "the zoomed idle roll renders a frame")
        target = trackFace(context, idle, false)
        verify(target !== null && target.rect.w > 45 && target.rect.h > 8,
               "a visible wide note guards the velocity drag")
        var summary = context.grid.noteSummary
        var dpr = shellDpr(idle)
        var origin = win(target.item, 0, 0)
        var rollOrigin = win(roll, 0, 0)
        var px = origin.x - rollOrigin.x + target.item.width / 2
        var py = origin.y - rollOrigin.y + target.item.height / 2
        mousePress(roll, px, py, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, px, py - context.grid.dragDistance - 2,
                  -1, Qt.LeftButton, Qt.ControlModifier)
        verify(waitForNative(function() {
            return context.grid.statusText.indexOf("velocity") >= 0
        }, 5000), "the control gesture enters velocity preview")
        var dragged = grabShell()
        verify(dragged !== null, "the velocity drag renders a frame")
        var inkPixels = 0
        var fillPixel = rgb(idle, target.rect.x + Math.floor(target.rect.w / 2),
                            target.rect.y + Math.floor(target.rect.h / 2))
        for (var iy = target.rect.y + Math.ceil(target.rect.h / 4);
             iy < target.rect.y + Math.floor(3 * target.rect.h / 4); ++iy)
            for (var ix = target.rect.x + Math.ceil(target.rect.w / 4);
                 ix < target.rect.x + Math.floor(3 * target.rect.w / 4); ++ix)
                if (!Helpers.colorsNear(rgb(idle, ix, iy), rgb(dragged, ix, iy), 0)
                        && contrast(rgb(dragged, ix, iy), fillPixel) >= 2.5)
                    ++inkPixels
        verify(inkPixels > 2, "velocity drag renders value ink inside the note box")
        var plotRect = deviceRect(context.plot, context.plot, idle, dpr)
        var margin = target.rect.h
        var left = Math.max(plotRect.x, target.rect.x - margin)
        var top = Math.max(plotRect.y, target.rect.y - margin)
        var right = Math.min(plotRect.x + plotRect.w, target.rect.x + target.rect.w + margin)
        var bottom = Math.min(plotRect.y + plotRect.h, target.rect.y + target.rect.h + margin)
        for (var y = top; y < bottom; ++y)
            for (var x = left; x < right; ++x) {
                var inBox = x >= target.rect.x && x < target.rect.x + target.rect.w
                    && y >= target.rect.y && y < target.rect.y + target.rect.h
                if (!inBox)
                    verify(Helpers.colorsNear(rgb(idle, x, y), rgb(dragged, x, y), 0),
                           "velocity drag changes no pixel outside the note box clip at "
                           + x + "," + y)
            }
        mouseRelease(roll, px, py - context.grid.dragDistance - 2,
                     Qt.LeftButton, Qt.ControlModifier)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var now = publishedNotes(context.grid)
            return now && now.length === JSON.parse(summary).length
                && now.some(function(n) {
                    return n.id === target.note.id && n.velocity === target.note.velocity
                })
        }, 5000), "undo restores the original note document")
    }

    function test_tinyNoteFrameRaster() {
        var context = openNotes(5)
        var grid = context.grid
        var plot = context.plot
        var zoomDelta = Math.round(1200 * Math.log(grid.baseFontPx / grid.rowHeight) / Math.LN2)
        grid.handleWheel(0, zoomDelta, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() {
            return grid.baseFontPx === 5 && Math.abs(grid.rowHeight - grid.baseFontPx) < 0.01
        }, 5000), "the mounted five-pixel key height matches the small font: "
               + grid.baseFontPx + "/" + grid.rowHeight)
        var notes = publishedNotes(grid)
        var target = notes.find(function(note) {
            var x = note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
            return !note.ghost && !note.selected && note.tick > grid.ticksPerBeat
                && x > grid.baseFontPx * 2 && x < plot.width - grid.baseFontPx * 3
        })
        verify(target !== undefined, "a painted tiny note has a visible time cell")
        var scrollY = Math.max(0, Math.min(grid.cameraMaxVScroll,
                (127 - target.pitch + 0.5) * grid.rowHeight - plot.height / 2))
        grid.setCameraVScroll(scrollY)
        var image = grabShell()
        verify(image !== null, "the five-pixel-key roll renders a frame")
        var item = noteItem(context.fills, target.id)
        verify(item !== null && item.visible, "the tiny note is mounted in the roll")
        var rect = deviceRect(item, plot, image, shellDpr(image))
        verify(rect.h >= 3 && rect.h <= grid.baseFontPx * shellDpr(image),
               "the mounted tiny note spans a border and a face: rect=" + JSON.stringify(rect)
               + ", row=" + grid.rowHeight + ", font=" + grid.baseFontPx
               + ", dpr=" + shellDpr(image))
        var fitted = Helpers.fittedFrameThickness(rect.w, rect.h,
                                                  Math.max(1, Math.round(shellDpr(image))), 0)
        verify(fitted > 0 && rect.h > 2 * fitted,
               "the tiny raster has room inside its fitted border")
        var border = frameFailure(image, rect, 0, fitted,
                                  Helpers.channels(grid.palette.noteBorder), "tiny frame")
        verify(border === "", "the tiny note paints its fitted top and bottom border: " + border)
        var cx = rect.x + Math.floor(rect.w / 2)
        var cy = rect.y + Math.floor(rect.h / 2)
        verify(Helpers.colorsNear(rgb(image, cx, cy), Helpers.channels(probe.noteFace(
                   target.track, target.velocity, grid.palette.noteVelocityZero))),
               "the tiny note paints its face between the thin borders")
    }

    function test_preRollPadAndRulerRaster() {
        var context = openNotes()
        var grid = context.grid
        grid.setCameraHScroll(grid.cameraMinHScroll)
        var image = grabShell()
        verify(image !== null, "the mounted roll and ruler produce a raster")
        var dpr = shellDpr(image)
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
            var p = win(plot, x, y)
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
            var p = win(ruler, grid.keyboardWidth + x, y)
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
        var zero = win(ruler, grid.keyboardWidth + tickZero, 0)
        var rulerTop = Math.round(win(ruler, 0, 0).y * dpr)
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
        var captionLeft = Math.round(win(ruler, grid.keyboardWidth + grid.baseFontPx * 0.3, 0).x * dpr)
        var captionRight = Math.round(win(ruler, grid.keyboardWidth + tickZero
                                          - grid.baseFontPx * 0.3, 0).x * dpr)
        verify(captionRight > captionLeft, "the pre-zero ruler has room for a caption probe")
        var captionInk = 0
        for (var cy = rulerTop; cy < rulerTop + Math.floor(ruler.height * dpr) - 1; ++cy)
            for (var cx = captionLeft; cx < captionRight; ++cx)
                if (channelDelta(rgb(image, cx, cy), upper) > 12)
                    ++captionInk
        compare(captionInk, 0, "no placeholder caption paints before tick zero")
    }

    function test_ghostEdgesAndMinimumZoomFace() {
        var context = openNotes()
        var grid = context.grid
        var image = grabShell()
        verify(image !== null, "the ghost roll produces a raster")
        var ghost = trackFace(context, image, true)
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
        var zoom = grabShell()
        verify(zoom !== null, "the minimum-time-zoom roll produces a raster")
        var notes = publishedNotes(grid)
        var narrow = null
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].ghost)
                continue
            var item = noteItem(context.fills, notes[i].id)
            if (!item || !item.visible)
                continue
            var point = item.mapToItem(context.plot, 0, 0)
            if (point.x < 2 || point.y < 2
                    || point.x + item.width > context.plot.width - 2
                    || point.y + item.height > context.plot.height - 2)
                continue
            var rect = deviceRect(item, context.plot, zoom, shellDpr(zoom))
            if (rect.w >= 3 && rect.h >= 3 && (!narrow || rect.w < narrow.rect.w))
                narrow = { note: notes[i], rect: rect }
        }
        verify(narrow !== null && narrow.rect.w <= 3 * shellDpr(zoom),
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

    function test_noteRasterParity() {
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
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        verify(plot !== null, "the roll plot is mounted")
        verify(fills !== null, "the note fill layer is mounted")

        grid.handleWheel(0, -120, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() {
            return Math.abs(grid.rowHeight - Math.round(grid.rowHeight)) > 0.1
        }, 5000), "the mounted note frame uses a fractional key height")

        var unselectedImage = grabShell()
        verify(unselectedImage !== null, "the unselected roll renders a frame")
        var dpr = shellDpr(unselectedImage)
        var notes = publishedNotes(grid)
        verify(notes !== null, "the note summary parses as note entries")
        var frameNotes = notes.filter(function(note) {
            return note.tick > grid.ticksPerBeat
                && note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                    > -grid.cameraScrollX + grid.baseFontPx * 2
        })
        var unselected = visibleNote(fills, plot, unselectedImage, dpr, frameNotes, false)
        verify(unselected !== null, "a fully visible unselected note is available for probing")

        var expectedFace = Helpers.channels(
                    probe.noteFace(unselected.note.track, unselected.note.velocity,
                                   grid.palette.noteVelocityZero))
        var unselectedFace = [unselectedImage.red(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2)),
                unselectedImage.green(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2)),
                unselectedImage.blue(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2))]
        verify(Helpers.colorsNear(unselectedFace, expectedFace),
                "note " + unselected.note.id + " face follows the track/velocity contract: expected "
                + Helpers.hexOf(expectedFace) + ", actual " + Helpers.hexOf(unselectedFace))

        var borderRequest = Math.max(1, Math.round(dpr))
        var unselectedBorder = Helpers.fittedFrameThickness(
                    unselected.rect.w, unselected.rect.h, borderRequest, 0)
        compare(unselectedBorder, borderRequest, "the unselected border keeps its requested width")
        verify(blackFrameFailure(unselectedImage, unselected.rect, 0, unselectedBorder,
                                 "unselected note " + unselected.note.id
                                 + " lost its display-scaled black border") === "",
                "the unselected black border renders")
        var unselectedSides = sideFrameFailure(
                    unselectedImage, unselected.rect, 0, unselectedBorder,
                    Helpers.channels(grid.palette.noteBorder), "unselected side borders")
        verify(unselectedSides === "",
               "the unselected note bounds its face on both sides: " + unselectedSides)
        var below = rgb(unselectedImage,
                        unselected.rect.x + Math.floor(unselected.rect.w / 2),
                        unselected.rect.y + unselected.rect.h)
        verify(!Helpers.colorsNear(below, expectedFace),
               "the unselected note face stops below its bottom border")

        grid.performCommand(4)
        verify(waitForNative(function() {
            var after = publishedNotes(grid)
            for (var i = 0; i < after.length; ++i)
                if (after[i].id === unselected.note.id)
                    return after[i].selected
            return false
        }, 5000), "select-all publishes the probed note as selected")

        var selectedImage = grabShell()
        verify(selectedImage !== null, "the selected roll renders a frame")
        var selectedItem = noteItem(fills, unselected.note.id)
        verify(selectedItem && selectedItem.visible, "the selected note delegate stays visible")
        var selectedRect = deviceRect(selectedItem, plot, selectedImage, dpr)
        var ringRequest = Math.max(1, Math.round(grid.baseFontPx * (1.0 / 8.0) * dpr))
        var ring = Helpers.fittedFrameThickness(selectedRect.w, selectedRect.h, ringRequest, 0)
        verify(ring > 0, "the selected note retains a visible selection ring")
        var expectedRing = Helpers.channels(grid.palette.selectionRing)
        verify(frameFailure(selectedImage, selectedRect, 0, ring, expectedRing,
                            "selected note " + unselected.note.id + " outer ring") === "",
                "the selection ring uses the selection role color")
        var ringSides = sideFrameFailure(selectedImage, selectedRect, 0, ring,
                                         expectedRing, "selected side ring")
        verify(ringSides === "", "the selection ring continues around both side edges: "
               + ringSides)
        var selectedBorder = Helpers.fittedFrameThickness(
                    selectedRect.w, selectedRect.h, borderRequest, ring)
        verify(selectedBorder > 0, "the selected note keeps room for its inset black border")
        verify(blackFrameFailure(selectedImage, selectedRect, ring, selectedBorder,
                                 "selected note " + unselected.note.id
                                 + " lost its inset black border") === "",
                "the inset black border renders inside the ring")
        var insetSides = sideFrameFailure(
                    selectedImage, selectedRect, ring, selectedBorder,
                    Helpers.channels(grid.palette.noteBorder), "selected inset sides")
        verify(insetSides === "", "the selected inset border paints both left and right edges: "
               + insetSides)
        var darkFrame = Helpers.channels(grid.palette.noteBorder)
        var topInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                        selectedBorder, darkFrame, "top")
        verify(topInset === "", "the selected inset top border paints: " + topInset)
        var bottomInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                           selectedBorder, darkFrame, "bottom")
        verify(bottomInset === "", "the selected inset bottom border paints: " + bottomInset)
        var leftInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                         selectedBorder, darkFrame, "left")
        verify(leftInset === "", "the selected inset left border paints: " + leftInset)
        var rightInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                          selectedBorder, darkFrame, "right")
        verify(rightInset === "", "the selected inset right border paints: " + rightInset)
        verify(!Helpers.colorsNear(rgb(selectedImage,
                                       selectedRect.x + Math.floor(selectedRect.w / 2),
                                       selectedRect.y + ring), expectedRing),
               "the selection ring stops at its display-scaled inset")
        var selectedFace = [selectedImage.red(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2)),
                selectedImage.green(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2)),
                selectedImage.blue(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2))]
        verify(Helpers.colorsNear(selectedFace, unselectedFace)
               && Helpers.colorsNear(selectedFace, expectedFace),
                "the selection frame preserves the note face")

        var smallFontPx = borderRequest > 1 ? 4.0 : 7.0
        cleanup()
        var smallContext = openNotes(smallFontPx)
        grid = smallContext.grid
        plot = smallContext.plot
        fills = smallContext.fills
        grid.performCommand(4)
        verify(waitForNative(function() { return grid.baseFontPx === smallFontPx }, 5000),
               "the small-font viewport is published")
        grid.resetCameraScroll()
        var maxSmallScrollY = Math.max(0, 128.0 * grid.rowHeight - plot.height)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraMaxVScroll - maxSmallScrollY) < 0.01
        }, 5000), "the published vertical bound is the projected row height")
        verify(waitForNative(function() {
            var count = 0
            for (var i = 0; i < fills.children.length; ++i) {
                var c = fills.children[i]
                if (c && c.fillColor !== undefined && c.visible)
                    ++count
            }
            return count > 0
        }, 5000), "the small viewport still draws note fills")
        var smallImage = grabShell()
        verify(smallImage !== null, "the small-font roll renders a frame")
        var smallNotes = publishedNotes(grid)
        verify(smallNotes !== null, "the small-font note summary parses")
        var smallRingRequest = Math.max(
                    1, Math.round(grid.baseFontPx * (1.0 / 8.0) * (shellDpr(smallImage))))
        var smallBorderRequest = Math.max(1, Math.round(shellDpr(smallImage)))
        var small = null
        if (smallBorderRequest > 1) {
            var bestArea = -1
            for (var n = 0; n < smallNotes.length; ++n) {
                if (!smallNotes[n].selected)
                    continue
                var item = noteItem(fills, smallNotes[n].id)
                if (!item || !item.visible)
                    continue
                var rect = deviceRect(item, plot, smallImage, shellDpr(smallImage))
                var tryRing = Helpers.fittedFrameThickness(rect.w, rect.h, smallRingRequest, 0)
                var tryBorder = Helpers.fittedFrameThickness(
                            rect.w, rect.h, smallBorderRequest, tryRing)
                if (tryRing > 0 && tryBorder > 0 && tryBorder < smallBorderRequest
                        && rect.w * rect.h > bestArea) {
                    small = { note: smallNotes[n], rect: rect }
                    bestArea = rect.w * rect.h
                }
            }
            verify(small !== null, "a thinned selected note is exposed at the small font")
        } else {
            small = visibleNote(fills, plot, smallImage, shellDpr(smallImage),
                                smallNotes, true)
            verify(small !== null, "a fully visible selected note is exposed at the small font")
        }
        var smallRing = Helpers.fittedFrameThickness(
                    small.rect.w, small.rect.h, smallRingRequest, 0)
        var smallBorder = Helpers.fittedFrameThickness(
                    small.rect.w, small.rect.h, smallBorderRequest, smallRing)
        verify(smallRing > 0 && smallBorder > 0,
                "the small note preserves both ring and inset border")
        if (smallBorderRequest > 1)
            verify(smallBorder < smallBorderRequest,
                    "the small note exercises physical border thinning")
        verify(frameFailure(smallImage, small.rect, 0, smallRing, expectedRing,
                            "small selected note " + small.note.id + " fitted ring") === "",
                "the small fitted selection ring renders")
        verify(blackFrameFailure(smallImage, small.rect, smallRing, smallBorder,
                                 "small selected note " + small.note.id + " border") === "",
                "the small border thins instead of vanishing")
        var smallExpectedFace = Helpers.channels(
                    probe.noteFace(small.note.track, small.note.velocity,
                                   grid.palette.noteVelocityZero))
        var smallFace = [smallImage.red(small.rect.x + Math.floor(small.rect.w / 2),
                                        small.rect.y + Math.floor(small.rect.h / 2)),
                smallImage.green(small.rect.x + Math.floor(small.rect.w / 2),
                                 small.rect.y + Math.floor(small.rect.h / 2)),
                smallImage.blue(small.rect.x + Math.floor(small.rect.w / 2),
                                small.rect.y + Math.floor(small.rect.h / 2))]
        verify(Helpers.colorsNear(smallFace, smallExpectedFace),
                "the small frame preserves the note face")
    }

    function test_dpr2SmallFontThinning() {
        if (Screen.devicePixelRatio !== 2) {
            skip("the physical border-thinning capture requires dpr2")
            return
        }
        shell = smallFontShellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads for dpr2")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000),
               "Route 101 loads for the dpr2 note capture")
        var surface = selectedSurface()
        verify(surface !== null, "the dpr2 roll is mounted")
        var grid = surface.gridModel
        var plot = findChild(surface, "timelineQuickRollPlot")
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        verify(plot !== null && fills !== null, "the dpr2 plot and note fills are mounted")
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the dpr2 roll publishes notes")
        grid.performCommand(4)
        verify(waitForNative(function() {
            var notes = publishedNotes(grid)
            return notes && notes.some(function(note) { return note.selected })
        }, 5000), "the dpr2 roll publishes a selected note")
        var dpr = Screen.devicePixelRatio
        verify(waitForNative(function() { return grid.baseFontPx === 4.0 }, 5000),
               "the dpr2 small-font viewport is published")
        var originalRowHeight = grid.rowHeight
        grid.handleWheel(0, -1600, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() { return grid.rowHeight < originalRowHeight }, 5000),
               "the dpr2 small-font roll zooms into the thinning height")
        var anchor = publishedNotes(grid).find(function(note) { return note.selected })
        var targetScroll = Math.max(0, Math.min(
                    grid.cameraMaxVScroll,
                    (127 - anchor.pitch + 0.5) * grid.rowHeight - plot.height / 2))
        grid.setCameraVScroll(targetScroll)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraScrollY - targetScroll) < 0.01
        }, 5000), "the dpr2 selected note row is centered")
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the dpr2 small-font plot still publishes notes")
        verify(waitForRendering(plot, 3000), "the dpr2 note plot has rendered")
        var notes = publishedNotes(grid)
        var ringRequest = Math.max(1, Math.round(grid.baseFontPx * (1.0 / 8.0) * dpr))
        var borderRequest = Math.max(1, Math.round(dpr))
        var small = null
        var bestArea = Infinity
        for (var n = 0; n < notes.length; ++n) {
            if (!notes[n].selected)
                continue
            var item = noteItem(fills, notes[n].id)
            if (!item || !item.visible)
                continue
            var topLeft = item.mapToItem(plot, 0, 0)
            if (topLeft.x < 1 || topLeft.y < 1
                    || topLeft.x + item.width > plot.width - 1
                    || topLeft.y + item.height > plot.height - 1)
                continue
            var width = Math.round(item.width * dpr)
            var height = Math.round(item.height * dpr)
            var ring = Helpers.fittedFrameThickness(width, height, ringRequest, 0)
            var border = Helpers.fittedFrameThickness(width, height, borderRequest, ring)
            if (ring > 0 && border > 0 && width * height < bestArea) {
                small = { note: notes[n], ring: ring, border: border }
                bestArea = width * height
            }
        }
        verify(small !== null && borderRequest > 1,
               "the dpr2 small-font viewport exposes a selected note whose border request exceeds one pixel")
        verify(small.border >= 1 && small.border < Math.max(1, Math.round(dpr)),
               "the dpr2 selected note thins its physical border without vanishing")
        verify(small.border < borderRequest,
               "the small note exercises physical border thinning")
        var capture = null
        verify(plot.grabToImage(function(result) { capture = result }),
               "the dpr2 plot accepts a physical-pixel capture")
        tryVerify(function() { return capture !== null }, 3000)
        verify(capture.saveToFile(bootstrap.projectRoot + "/notevisuals-dpr2-small-font.png"),
               "the dpr2 selected note frame is saved")
        var selectedItem = noteItem(fills, small.note.id)
        var noteOrigin = selectedItem.mapToItem(plot, 0, 0)
        var physical = { x: Math.floor(noteOrigin.x * dpr),
                         y: Math.floor(noteOrigin.y * dpr),
                         w: Math.ceil((noteOrigin.x + selectedItem.width) * dpr)
                            - Math.floor(noteOrigin.x * dpr),
                         h: Math.ceil((noteOrigin.y + selectedItem.height) * dpr)
                            - Math.floor(noteOrigin.y * dpr) }
        var reader = physicalCaptureReader.createObject(plot)
        verify(reader !== null, "the physical DPR2 capture has an image reader")
        tryCompare(reader, "available", true, 3000)
        var imageUrl = "file://" + bootstrap.projectRoot + "/notevisuals-dpr2-small-font.png"
        reader.loadImage(imageUrl)
        tryVerify(function() { return reader.isImageLoaded(imageUrl) }, 3000)
        var pixels = reader.getContext("2d").createImageData(imageUrl)
        verify(pixels !== null && Math.abs(pixels.width - plot.width * dpr) <= 1
               && Math.abs(pixels.height - plot.height * dpr) <= 1,
               "the DPR2 note capture retains physical-sized image data: "
               + (pixels ? pixels.width + "x" + pixels.height : "null")
               + " expected " + Math.round(plot.width * dpr)
               + "x" + Math.round(plot.height * dpr))
        var capturedPixels = {
            red: function(x, y) { return pixels.data[(y * pixels.width + x) * 4] },
            green: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 1] },
            blue: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 2] }
        }
        var physicalRect = physical
        var ringInk = Helpers.channels(grid.palette.selectionRing)
        var borderInk = Helpers.channels(grid.palette.noteBorder)
        var centerX = physicalRect.x + Math.floor(physicalRect.w / 2)
        var topEdge = -1, bottomEdge = -1
        for (var offset = -1; offset <= 1; ++offset) {
            var topY = physicalRect.y + offset
            var bottomY = physicalRect.y + physicalRect.h - 1 + offset
            if (topEdge < 0 && Helpers.colorsNear(rgb(capturedPixels, centerX, topY), ringInk))
                topEdge = topY
            if (Helpers.colorsNear(rgb(capturedPixels, centerX, bottomY), ringInk))
                bottomEdge = bottomY
        }
        verify(topEdge >= 0 && bottomEdge > topEdge,
               "the captured DPR2 selected ring brackets the note's physical bounds")
        physicalRect.y = topEdge
        physicalRect.h = bottomEdge - topEdge + 1
        var ringFailure = frameFailure(capturedPixels, physicalRect, 0,
                                       small.ring, ringInk, "DPR2 outer ring")
        verify(ringFailure === "",
               "the captured small-font DPR2 note paints its selected ring: " + ringFailure)
        var borderFailure = frameFailure(capturedPixels, physicalRect, small.ring,
                                         small.border, borderInk, "DPR2 inset border")
        verify(borderFailure === "",
               "the captured small-font DPR2 note paints its fitted inset border: "
               + borderFailure)
        var face = rgb(capturedPixels,
                       physicalRect.x + Math.floor(physicalRect.w / 2),
                       physicalRect.y + Math.floor(physicalRect.h / 2))
        verify(Helpers.colorsNear(face, Helpers.channels(probe.noteFace(
                   small.note.track, small.note.velocity, grid.palette.noteVelocityZero))),
               "the captured small-font DPR2 note keeps a face inside the thinned border")
        reader.destroy()
    }
}
