import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import PorydawRollTest
import Porydaw.Ui
import "../editorqml/RollNoteFaces.js" as RollNoteFaces

RollLaneSupport {
    id: testCase

    name: "SwiftRollSelection"
    when: windowShown
    width: 960
    height: 640
    visible: true

    verifySurface: true
    reserveRulerHeight: true


    CursorProbe { id: cursorProbe }


    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the staged route101 song opened" + testCase.openDiagnostics())
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        testCase.mountOverlay()
    }


    function init() {
        bootstrap.cancelInput()
        bootstrap.resumePlayheadPolling()
    }

    function cleanup() {
        bootstrap.cancelInput()
        wait(0)
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(),
                   "the session still presents its document while the scene exists")
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "the session released its document presentation after the"
                   + " acknowledged scene removal")
        }
    }


    function gridNotes(g) { return JSON.parse(g.fetchNoteSummary()) }

    function noteById(g, id) {
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function selectedNotes(g) {
        return gridNotes(g).filter(function(n) { return n.selected })
    }

    function publishedNoteCount(g) {
        var total = 0
        verify(waitForNative(function() {
            total = gridNotes(g).length
            return total > 0
        }, 10000), "the staged song publishes grid notes")
        return total
    }

    function noteItem(surf, id) {
        return RollNoteFaces.rect(findChild(surf, "timelineRendererPlot"), rollInput(), id)
    }

    function bandForNote(roll, surf, id) {
        var item = noteItem(surf, id)
        if (!item || item.width <= 0 || item.height <= 0)
            return null
        var topLeft = { x: item.x, y: item.y }
        var bottomRight = { x: item.x + item.width, y: item.y + item.height }
        var sx = topLeft.x - 3
        var sy = topLeft.y - 3
        var ex = bottomRight.x + 3
        var ey = bottomRight.y + 3
        if (sx < 1 || sy < 1 || ex > roll.width - 1 || ey > roll.height - 1)
            return null
        return { sx: sx, sy: sy, ex: ex, ey: ey }
    }

    function awaitPlotFace(surf, g) {
        var plot = findChild(surf, "timelineRendererPlot")
        if (plot)
            waitForRendering(plot)
        waitForNative(function() {
            if (!plot || plot.fetchedRevision <= 0)
                return false
            var notes = gridNotes(g)
            for (var n = 0; n < notes.length; ++n)
                if (RollNoteFaces.face(plot, notes[n].id) !== null)
                    return true
            return false
        }, 5000)
    }

    function firstBandedNote(g, surf, roll, unselectedOnly) {
        awaitPlotFace(surf, g)
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i) {
            if (unselectedOnly && list[i].selected)
                continue
            if (bandForNote(roll, surf, list[i].id) !== null)
                return list[i]
        }
        return null
    }
    function pointCovered(roll, surf, g, x, y) {
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i) {
            var item = noteItem(surf, list[i].id)
            if (!item || item.width <= 0 || item.height <= 0)
                continue
            var tl = { x: item.x, y: item.y }
            var br = { x: item.x + item.width, y: item.y + item.height }
            if (x >= tl.x - 4 && x <= br.x + 4 && y >= tl.y - 4 && y <= br.y + 4)
                return true
        }
        return false
    }

    function clearSelection(roll, surf, g) {
        if (selectedNotes(g).length === 0)
            return true
        var pts = [[8, 8], [roll.width - 8, 8], [8, roll.height - 8],
                   [roll.width - 8, roll.height - 8]]
        for (var k = 0; k < pts.length; ++k) {
            if (pointCovered(roll, surf, g, pts[k][0], pts[k][1]))
                continue
            mouseClick(roll, pts[k][0], pts[k][1], Qt.RightButton)
            if (selectedNotes(g).length === 0)
                return true
        }
        for (var gy = 24; gy < roll.height - 8; gy += 40) {
            for (var gx = 24; gx < roll.width - 8; gx += 40) {
                if (pointCovered(roll, surf, g, gx, gy))
                    continue
                mouseClick(roll, gx, gy, Qt.RightButton)
                if (selectedNotes(g).length === 0)
                    return true
            }
        }
        return selectedNotes(g).length === 0
    }

    function sweepBand(roll, band) {
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
    }

    function test_bandSelectsSweptNotes() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(clearSelection(roll, surf, g), "the suite starts with nothing selected")
        var plot = findChild(surf, "timelineRendererPlot")
        verify(waitForNative(function() {
            return plot.fetchedRevision === g.scene.displayRevision
        }, 5000), "the cleared selection reaches the renderer before its reference capture")
        waitForRendering(plot)
        var target = null
        var band = null
        for (var candidate of gridNotes(g)) {
            var candidateItem = noteItem(surf, candidate.id)
            var candidateBand = bandForNote(roll, surf, candidate.id)
            if (!candidate.selected && candidateBand && candidateItem
                    && candidateItem.width >= 8) {
                target = candidate
                band = candidateBand
                break
            }
        }
        verify(target !== null, "a fully visible wide note takes a band")
        var item = noteItem(surf, target.id)
        band.ex = band.sx + (item.width + 6) / 2
        var ringBefore = grabImage(testCase)
        sweepBand(roll, band)
        verify(waitForNative(function() {
            return g.statusText.indexOf("Selecting") !== -1
        }, 5000), "the held band previews its selection")
        var held = noteById(g, target.id)
        verify(held && !held.selected,
               "the band ring is provisional while committed selection stays empty")
        verify(waitForNative(function() {
            return plot.fetchedRevision === g.scene.displayRevision
        }, 5000), "the held selection band reaches the renderer before its capture")
        waitForRendering(plot)
        var ringProbe = roll.mapToItem(testCase, item.x + item.width - 3, item.y + 0.25)
        var ringDpr = ringBefore.width / testCase.width
        var ringX = Math.round(ringProbe.x * ringDpr)
        var ringY = Math.round(ringProbe.y * ringDpr)
        var ringAfter = grabImage(testCase)
        verify(ringAfter.red(ringX, ringY) !== ringBefore.red(ringX, ringY)
               || ringAfter.green(ringX, ringY) !== ringBefore.green(ringX, ringY)
               || ringAfter.blue(ringX, ringY) !== ringBefore.blue(ringX, ringY),
               "the held band adds a provisional selection frame to the scene")
        var image = grabImage(testCase)
        var center = roll.mapToItem(testCase, item.x + item.width - 3, item.y + 0.25)
        var dpr = image.width / testCase.width
        var px = Math.round(center.x * dpr)
        var py = Math.round(center.y * dpr)
        var ink = g.palette.selectionRing
        var red = Math.round(ink.r * 255)
        var green = Math.round(ink.g * 255)
        var blue = Math.round(ink.b * 255)
        verify(Math.abs(image.red(px, py) - red) <= 2
               && Math.abs(image.green(px, py) - green) <= 2
               && Math.abs(image.blue(px, py) - blue) <= 2,
               "the held band paints the swept note's provisional selection ring")
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(g, target.id)
            return current && current.selected
        }, 5000), "band release selects the swept note")
    }

    function test_bandCancelRestoresSelection() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(clearSelection(roll, surf, g), "the suite starts with nothing selected")
        var target = firstBandedNote(g, surf, roll, true)
        verify(target !== null, "a fully visible note takes a band")
        var band = bandForNote(roll, surf, target.id)
        verify(band !== null, "the band fits inside the roll")
        sweepBand(roll, band)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(g, target.id)
            return current && current.selected
        }, 5000), "the setup band selects its note")
        var before = g.fetchNoteSummary()
        sweepBand(roll, band)
        verify(waitForNative(function() {
            return g.statusText.indexOf("Selecting") !== -1
        }, 5000), "the second band is live")
        verify(bootstrap.cancelInput(), "the production cancel path runs")
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return g.fetchNoteSummary() === before && g.lastCancelReason === 2
        }, 5000), "cancel restores the band selection with reason 2")
    }

    function test_edgeHoverShowsResizeCursor() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(bootstrap.setCameraTimeZoom(140), "the lane widens the time zoom")
        verify(waitForNative(function() {
            var notes = gridNotes(g)
            for (var k = 0; k < notes.length; ++k) {
                var it = noteItem(surf, notes[k].id)
                if (it && it.width >= 16)
                    return true
            }
            return false
        }, 8000), "the zoomed song realizes a wide note")
        var list = gridNotes(g)
        var probed = false
        for (var i = 0; i < list.length && !probed; ++i) {
            var item = noteItem(surf, list[i].id)
            if (!item || item.width < 16 || item.height <= 0)
                continue
            var center = Qt.point(item.x + item.width / 2, item.y + item.height / 2)
            if (center.x < 8 || center.y < 8
                    || center.x > roll.width - 8 || center.y > roll.height - 8)
                continue
            var edge = Qt.point(item.x + item.width - 1, item.y + item.height / 2)
            mouseMove(roll, edge.x, edge.y)
            if (!waitForNative(function() { return g.cursorKind === 3 }, 3000))
                continue
            var cursor = findChild(surf, "swiftRollCursor")
            verify(cursor !== null, "the roll input carries its production cursor binding")
            verify(g.resizeCursorExtent > 0, "the grid publishes its cursor bitmap extent")
            var expectedExtent = g.resizeCursorExtent
            verify(cursorProbe.artDiffers("qrc:/cursors/left-drag.png",
                                          "qrc:/cursors/right-drag.png", expectedExtent,
                                          g.devicePixelRatio),
                   "left and right resize cursor bitmaps differ at the grid DPI")
            verify(waitForNative(function() {
                return roll.cursorShape === Qt.BitmapCursor
                    && String(cursor.source) === "qrc:/cursors/right-drag.png"
            }, 5000), "the right edge hover shows the right-drag cursor art")
            verify(cursorProbe.matchesArt(roll, "qrc:/cursors/right-drag.png", expectedExtent,
                                          g.devicePixelRatio),
                   "right note edge applies the DPI-matched right bitmap cursor")
            var leftEdge = Qt.point(item.x + 1, item.y + item.height / 2)
            mouseMove(roll, leftEdge.x, leftEdge.y)
            verify(waitForNative(function() {
                return g.cursorKind === 2 && roll.cursorShape === Qt.BitmapCursor
                    && String(cursor.source) === "qrc:/cursors/left-drag.png"
            }, 5000), "the left edge hover shows the left-drag cursor art")
            verify(cursorProbe.matchesArt(roll, "qrc:/cursors/left-drag.png", expectedExtent,
                                          g.devicePixelRatio),
                   "left note edge applies the DPI-matched left bitmap cursor")
            mouseMove(roll, center.x, center.y)
            verify(waitForNative(function() {
                return g.cursorKind === 0 && roll.cursorShape === Qt.ArrowCursor
            }, 5000), "the note body restores the arrow")
            probed = true
        }
        verify(probed, "a fully visible wide note takes the cursor probe")
    }
    function test_resizeAbuttingCursorArt() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        var savedZoom = g.beatWidth
        var originalIds = gridNotes(g).map(function(note) { return note.id })
        try {
            if (savedZoom !== 140)
                verify(bootstrap.setCameraTimeZoom(140),
                       "the abutting notes have room for both resize grips")
            verify(waitForNative(function() {
                return g.beatWidth === 140 && gridNotes(g).some(function(note) {
                    var item = noteItem(surf, note.id)
                    return item && item.width > 0 && item.height > 0
                })
            }, 8000), "the zoomed song realizes its existing notes")
            var snapWidth = g.snapTicks * g.beatWidth / g.ticksPerBeat
            var span = 2 * snapWidth
            var inset = surf.baseFontPx * 0.25 / 2
            var gripReach = 2 * inset
            var leftX = Math.ceil((g.cameraScrollX + roll.width * 0.3) / snapWidth)
                        * snapWidth - g.cameraScrollX
            var rowY = null
            var existing = gridNotes(g)
            for (var y = g.rowHeight * 2; y < roll.height - g.rowHeight * 2;
                 y += g.rowHeight) {
                var occupied = existing.some(function(note) {
                    var item = noteItem(surf, note.id)
                    return item && item.y <= y && item.y + item.height > y
                           && item.x < leftX + 2 * span + gripReach
                           && item.x + item.width > leftX - gripReach
                })
                if (!occupied) {
                    rowY = y
                    break
                }
            }
            verify(rowY !== null && leftX > gripReach
                   && leftX + 2 * span + gripReach < roll.width,
                   "a free visible key row fits two adjoining notes")

            mousePress(roll, leftX + span + inset, rowY, Qt.LeftButton)
            mouseMove(roll, leftX + 2 * span - inset, rowY, -1, Qt.LeftButton)
            mouseRelease(roll, leftX + 2 * span - inset, rowY, Qt.LeftButton)
            var right = null
            verify(waitForNative(function() {
                right = gridNotes(g).find(function(note) {
                    return originalIds.indexOf(note.id) < 0
                })
                return right !== undefined
            }, 5000), "the right-hand note is committed to the key row")

            mousePress(roll, leftX + inset, rowY, Qt.LeftButton)
            mouseMove(roll, leftX + span - inset, rowY, -1, Qt.LeftButton)
            mouseRelease(roll, leftX + span - inset, rowY, Qt.LeftButton)
            var left = null
            verify(waitForNative(function() {
                left = gridNotes(g).find(function(note) {
                    return originalIds.indexOf(note.id) < 0 && note.id !== right.id
                })
                return left !== undefined
            }, 5000), "the left-hand note is committed next to its neighbor")
            verify(left.pitch === right.pitch && left.track === right.track
                   && left.tick + left.duration === right.tick,
                   "the two notes share a key and meet at one tick boundary")
            var leftItem = null
            var rightItem = null
            verify(waitForNative(function() {
                leftItem = noteItem(surf, left.id)
                rightItem = noteItem(surf, right.id)
                return leftItem && rightItem && leftItem.width > 2 * gripReach
                       && rightItem.width > 2 * gripReach
            }, 8000), "both abutting notes realize with distinct resize grips")
            var boundary = rightItem.x
            var centerY = rightItem.y + rightItem.height / 2
            verify(g.resizeCursorExtent > 0, "the grid publishes its cursor bitmap extent")
            var expectedExtent = g.resizeCursorExtent
            mouseMove(roll, boundary - inset, centerY)
            verify(waitForNative(function() { return g.cursorKind === 3 }, 5000),
                   "boundary-left hover selects the first note's trailing grip")
            verify(waitForNative(function() {
                return cursorProbe.matchesArt(roll, "qrc:/cursors/right-drag.png", expectedExtent,
                                              g.devicePixelRatio)
            }, 5000),
                   "boundary-left applies the DPI-matched right-drag bitmap")
            mouseMove(roll, boundary + inset, centerY)
            verify(waitForNative(function() { return g.cursorKind === 2 }, 5000),
                   "boundary-right hover selects the second note's leading grip")
            verify(waitForNative(function() {
                return cursorProbe.matchesArt(roll, "qrc:/cursors/left-drag.png", expectedExtent,
                                              g.devicePixelRatio)
            }, 5000),
                   "boundary-right applies the DPI-matched left-drag bitmap")
        } finally {
            var remaining = gridNotes(g).filter(function(note) {
                return originalIds.indexOf(note.id) < 0
            }).length
            var undone = true
            for (var i = 0; i < remaining; ++i)
                if (!bootstrap.undoTimeSignature())
                    undone = false
            if (g.beatWidth !== savedZoom)
                verify(bootstrap.setCameraTimeZoom(savedZoom),
                       "the roll time zoom returns to its prior value")
            verify(undone, "the abutting note edits are undone")
        }
    }

    function test_clickLatchesVelocityForNextPencilNote() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        var source = firstBandedNote(g, surf, roll, false)
        verify(source !== null, "a rendered note can provide a pencil velocity")
        var item = noteItem(surf, source.id)
        var center = Qt.point(item.x + item.width / 2, item.y + item.height / 2)
        var initialVelocity = g.lastVelocity
        g.lastVelocity = source.velocity === 1 ? 127 : 1
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        compare(g.lastVelocity, source.velocity,
                "clicking a rendered note latches its velocity into the pencil")
        var span = Math.max(2 * g.drawThreshold,
                            2 * g.snapTicks * g.beatWidth / g.ticksPerBeat)
        var point = null
        for (var y = g.rowHeight * 2; y < roll.height - g.rowHeight * 2 && !point;
             y += g.rowHeight) {
            for (var x = Math.round(roll.width * 0.45); x + span < roll.width - span;
                 x += span) {
                if (!pointCovered(roll, surf, g, x, y)
                    && !pointCovered(roll, surf, g, x + span, y)) {
                    point = { x: x, y: y }
                    break
                }
            }
        }
        verify(point !== null, "a free visible cell accepts a new pencil note")
        var ids = gridNotes(g).map(function(note) { return note.id })
        mousePress(roll, point.x, point.y, Qt.LeftButton)
        mouseMove(roll, point.x + span, point.y, -1, Qt.LeftButton)
        mouseRelease(roll, point.x + span, point.y, Qt.LeftButton)
        var drawn = null
        tryVerify(function() {
            drawn = gridNotes(g).find(function(note) { return ids.indexOf(note.id) < 0 })
            return drawn !== undefined
        }, 3000)
        compare(drawn.velocity, source.velocity,
                "clicking a note latches its velocity for the next draw")
        g.lastVelocity = initialVelocity
    }

    function test_foldDragExceptionCommitsAfterRelease() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        var savedFoldV = g.cameraScrollY
        g.setScaleFold(true)
        var initialRows = g.visibleRowCount
        g.setScaleFold(false)
        g.setCameraVScroll((127 - 61 + 0.5) * g.rowHeight - roll.height / 2)
        var originalIds = gridNotes(g).map(function(note) { return note.id })
        function draw(pitch, x) {
            var y = (127 - pitch + 0.5) * g.rowHeight - g.cameraScrollY
            verify(y > g.rowHeight && y < roll.height - g.rowHeight,
                   "the requested pitch row is in the visible plot")
            var endX = x + Math.max(2 * g.drawThreshold,
                                    2 * g.snapTicks * g.beatWidth / g.ticksPerBeat)
            mousePress(roll, x, y, Qt.LeftButton)
            mouseMove(roll, endX, y, -1, Qt.LeftButton)
            mouseRelease(roll, endX, y, Qt.LeftButton)
            var created = null
            tryVerify(function() {
                created = gridNotes(g).find(function(note) {
                    return note.pitch === pitch && originalIds.indexOf(note.id) < 0
                })
                return created !== undefined
            }, 3000)
            originalIds.push(created.id)
            return created
        }
        draw(62, Math.round(roll.width * 0.65))
        g.setScaleFold(true)
        var rowsWithDestination = g.visibleRowCount
        g.setScaleFold(false)
        g.setCameraVScroll((127 - 61 + 0.5) * g.rowHeight - roll.height / 2)
        var exception = draw(61, Math.round(roll.width * 0.75))
        g.setScaleFold(true)
        tryCompare(g, "visibleRowCount", rowsWithDestination + 1)
        verify(g.visibleRowCount >= initialRows + 2,
               "fold gains the occupied off-scale row")
        waitForRendering(roll)
        var note = noteItem(surf, exception.id)
        verify(note !== null && note.width > 0, "the folded exception renders")
        var center = Qt.point(note.x + note.width / 2, note.y + note.height / 2)
        var stableRows = g.visibleRowCount
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, center.x, center.y - g.rowHeight, -1, Qt.LeftButton)
        wait(0)
        verify(g.visibleRowCount === stableRows && noteById(g, exception.id).pitch === 61
               && g.statusText.indexOf("Moving") !== -1,
               "fold drag grabs the off-scale note without rebuilding rows")
        mouseRelease(roll, center.x, center.y - g.rowHeight, Qt.LeftButton)
        tryVerify(function() {
            return noteById(g, exception.id).pitch === 62
        }, 3000, "fold drag commits the note to its scale degree")
        tryCompare(g, "visibleRowCount", stableRows - 1, 3000,
                   "fold collapses the off-scale row after the drag commit")
        g.setScaleFold(false)
        g.setCameraVScroll(savedFoldV)
    }

    function test_narrowBodyArrowRetired() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        var savedZoom = g.beatWidth
        verify(bootstrap.setCameraTimeZoom(4), "the narrow probe parks the time zoom at its minimum")
        verify(waitForNative(function() {
            var notes = gridNotes(g)
            for (var k = 0; k < notes.length; ++k) {
                var it = noteItem(surf, notes[k].id)
                if (it && it.width > 0 && it.height > 0)
                    return true
            }
            return false
        }, 8000), "the minimum zoom renders a note for the arrow probe")
        var narrow = null
        var narrowList = gridNotes(g)
        for (var n = 0; n < narrowList.length; ++n) {
            var narrowItem = noteItem(surf, narrowList[n].id)
            if (!narrowItem || narrowItem.width <= 0 || narrowItem.height <= 0)
                continue
            var narrowCenter = Qt.point(narrowItem.x + narrowItem.width / 2,
                                        narrowItem.y + narrowItem.height / 2)
            if (narrowCenter.x < 1 || narrowCenter.y < 1
                    || narrowCenter.x > roll.width - 1 || narrowCenter.y > roll.height - 1)
                continue
            narrow = narrowCenter
            break
        }
        verify(narrow !== null, "a rendered note takes the narrow-body arrow probe")
        mouseMove(roll, narrow.x, narrow.y)
        verify(waitForNative(function() { return g.cursorKind === 0 }, 5000),
               "the narrow note body shows the named arrow cursor")
        bootstrap.setCameraTimeZoom(savedZoom)
    }

}
