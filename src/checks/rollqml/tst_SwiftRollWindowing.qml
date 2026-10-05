// Windowing acceptance for the Swift roll window, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_SwiftRollWindowing.qml
//
// The Swift-side counterpart of nativegraphics/tst_nativewindowing.cpp's
// portable assertions: the header band's selection/voice-request path, the
// palette-driven grid repaint, and the roll background the window presents.
// The lane hosts the production composition by relative URL and drives it
// through its real seams; every expectation is read from the production
// session, from the drawn item or from a rendered pixel.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
// The production composition, reached exactly as the brief specifies: the
// relative path to ../../ui/songview/quick/swiftroll/SwiftRollOverlay.qml, the
// same file the application's resource engine loads. A directory import keeps
// one composition root -- the lane never copies, forks or re-declares it.
import Porydaw.Ui

RollLaneSupport {
    id: testCase

    name: "SwiftRollWindowing"
    // Only the rendered window gates the cases: `when` also gates initTestCase,
    // so it must never depend on the song the open assertion waits for. That
    // assertion carries the diagnostics and gates the remaining cases itself.
    when: windowShown
    width: 960
    height: 640
    // In Qt 6.11 a root TestCase item is invisible unless it says otherwise, and
    // effective visibility ANDs the whole chain: without this the mounted
    // surface renders nothing and the chrome takes neither pointer nor keyboard
    // input.
    visible: true

    includeStagedLabels: true
    property var voiceRequests: []


    Connections {
        target: session

        function onChangeTrackVoiceRequested(track) {
            testCase.voiceRequests.push(track)
        }
    }


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
        testCase.voiceRequests = []
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

    // ---- shared lookups ------------------------------------------------------

    function headers() {
        return session.trackHeadersPresenter()
    }

    function headerInput() {
        return findChild(testCase.surface(), "timelineTrackHeadersInput")
    }

    function headerRows() {
        return findChild(testCase.surface(), "timelineTrackHeaderRows")
    }

    function rollPlot() {
        return findChild(testCase.surface(), "timelineQuickRollPlot")
    }

    function pixelNear(image, x, y, expected, tolerance) {
        return Math.abs(image.red(x, y) - expected.r * 255) <= tolerance
               && Math.abs(image.green(x, y) - expected.g * 255) <= tolerance
               && Math.abs(image.blue(x, y) - expected.b * 255) <= tolerance
    }

    // ---- the cases ------------------------------------------------------------

    // The portable half of the C++ replacementBackgroundBeforeFirstFrame
    // oracle: the scene's background item carries the session palette's roll
    // background and the first presented frame paints it — no stale erase can
    // flash. The Win32 WM_ERASEBKGND half stays NATIVE.
    function test_windowClearColorBeforeFirstFrame() {
        var surface = testCase.surface()
        verify(surface, "the production surface is mounted")
        var background = findChild(surface, "swiftRollBackground")
        verify(background && background.visible,
               "the roll background item is mounted and visible")
        verify(background.width >= surface.width - 1
               && background.height >= surface.height - 1,
               "the roll background covers the surface")
        compare(background.color.toString(),
                session.palette.rollBackground.toString(),
                "the background item carries the session palette's roll background")
        var image = grabImage(surface)
        verify(image.width > 0 && image.height > 0,
               "the window framebuffer holds the rendered surface")
        var found = false
        for (var y = 0; y < image.height && !found; ++y)
            for (var x = 0; x < image.width; ++x)
                if (testCase.pixelNear(image, x, y, session.palette.rollBackground, 24)) {
                    found = true
                    break
                }
        verify(found, "the first presented frame paints the roll background")
    }

    // C++ headerSelectionAndVoicePicker: delegate geometry, pointer input,
    // and the mounted picker journey; presenter coverage is in swiftcore.
    function test_headerSelectionAndVoiceRequest() {
        var surface = testCase.surface()
        var input = testCase.headerInput()
        var repeater = testCase.headerRows()
        var headers = testCase.headers()
        verify(surface && input && repeater && headers,
               "the header band's production items are mounted")

        // The model publishes one row per engine track plus the add row.
        var addRows = 0
        var selectedRow = -1
        for (var row = 0; row < repeater.count; ++row) {
            var delegate = repeater.itemAt(row)
            verify(delegate, "row " + row + " has a live delegate")
            if (delegate.isAddTrack) {
                addRows += 1
                continue
            }
            verify(delegate.track >= 0, "row " + row + " resolves an engine track")
            if (delegate.titleBold)
                selectedRow = row
        }
        compare(addRows, 1, "exactly one add row follows the tracks")
        verify(selectedRow >= 0, "the session's selected track resolves to a row")
        var alternateRow = selectedRow === 0 ? 1 : 0
        verify(alternateRow < repeater.count - 1,
               "an alternate row exists beside the selection")
        var target = repeater.itemAt(alternateRow)
        var targetTrack = target.track
        verify(targetTrack >= 0, "the alternate row resolves an engine track")

        // Geometry is populated and stays populated after the band scrolls.
        var rowHeight = headers.rowHeight
        verify(target.titleRect.width > 0 && target.titleRect.height > 0,
               "the target row's title rect is populated")
        var scrollBefore = headers.scrollY
        headers.scrollY = scrollBefore + rowHeight
        verify(target.titleRect.width > 0 && target.titleRect.height > 0,
               "the title rect stays populated after scroll")
        headers.scrollY = scrollBefore

        // Hover reaches the header input item.
        mouseMove(input, 2, 2)
        tryCompare(input, "containsMouse", true)

        // Clicking the other row's title selects its track and focuses the input.
        mouseClick(input, target.titleRect.x + target.titleRect.width / 2,
                   target.titleRect.y + target.titleRect.height / 2 + alternateRow * rowHeight)
        tryCompare(target, "titleBold", true)
        verify(input.activeFocus, "the header input takes focus on click")

        // Double-clicking its voice line requests the picker for that track.
        var voiceRect = headers.voiceLineRect
        verify(voiceRect.width > 0 && voiceRect.height > 0,
               "the voice line rect is populated")
        var revision = session.gridPresenter().appliedRevisionText
        var undoIndex = bootstrap.timeSigUndoIndex()
        var undoCount = bootstrap.timeSigUndoCount()
        mouseDoubleClickSequence(input,
                                 voiceRect.x + voiceRect.width / 2,
                                 voiceRect.y + voiceRect.height / 2 + alternateRow * rowHeight)
        verify(testCase.waitForNative(function() {
            return testCase.voiceRequests.length === 1
        }, 5000), "the voice double-click requests the picker once")
        compare(testCase.voiceRequests[0], targetTrack,
                "the picker request carries the clicked track")

        var loader = findChild(surface, "headerVoicePickerLoader")
        verify(loader && loader.active, "the header voice picker loader activates")
        tryVerify(function() { return loader.item !== null }, 5000,
                  "the production header voice prompt mounts")
        var picker = loader.item
        tryCompare(picker, "visible", true, 5000,
                   "A030: the requested header voice picker is visible")
        var list = findChild(picker, "voicePickerList")
        verify(list, "the mounted header picker has a voice list")
        tryCompare(list, "visible", true, 5000,
                   "A031: the header voice list is visible")
        var search = findChild(picker, "voicePickerSearch")
        verify(search, "the mounted header picker has a search field")
        tryCompare(search, "activeFocus", true, 5000,
                   "A032: the header voice search takes active focus")

        keyClick("1")
        keyClick("2")
        keyClick("7")
        tryCompare(search, "text", "127", 5000,
                   "typing program 127 filters the mounted header picker")
        tryVerify(function() {
            var row = findChild(list, "voicePickerRow_127")
            if (!row || !row.visible || !list.visible || row.width <= 0 || row.height <= 0)
                return false
            var position = row.mapToItem(list, 0, 0)
            return position.x < list.width && position.x + row.width > 0
                && position.y < list.height && position.y + row.height > 0
        }, 5000, "A033: program 127 is visible inside the header voice list viewport")

        keySequence(StandardKey.SelectAll)
        var unmatched = "zz-no-such-voice"
        for (var i = 0; i < unmatched.length; ++i)
            keyClick(unmatched.charAt(i))
        tryCompare(search, "text", "zz-no-such-voice", 5000,
                   "the header voice search receives the unmatched filter")
        var accept = findChild(picker, "voicePickerAccept")
        verify(accept, "the mounted picker has an acceptance control")
        tryCompare(accept, "enabled", false, 5000,
                   "A034: an unmatched voice search disables acceptance")
        keyClick(Qt.Key_Return)
        compare(loader.item, picker, "Return with no match leaves the header picker mounted")
        compare(session.gridPresenter().appliedRevisionText, revision,
                "Return with no match changes no document revision")
        compare(bootstrap.timeSigUndoIndex(), undoIndex,
                "Return with no match changes no undo index")
        compare(bootstrap.timeSigUndoCount(), undoCount,
                "Return with no match adds no undo command")

        keySequence(StandardKey.SelectAll)
        keyClick(Qt.Key_Backspace)
        tryCompare(search, "text", "", 5000,
                   "clearing the header voice search restores the full list")
        tryVerify(function() {
            var row = findChild(list, "voicePickerRow_0")
            if (!row || !row.visible || !list.visible || row.width <= 0 || row.height <= 0)
                return false
            var position = row.mapToItem(list, 0, 0)
            return position.x < list.width && position.x + row.width > 0
                && position.y < list.height && position.y + row.height > 0
        }, 5000, "A035: clearing the search reveals program 0 in the list viewport")

        keyClick(Qt.Key_Escape)
        tryCompare(loader, "item", null, 5000,
                   "A036: Escape unmounts the header voice picker")
        compare(session.headerVoicePickerOpen, false,
                "Escape closes the header voice picker session")
        compare(session.gridPresenter().appliedRevisionText, revision,
                "a cancelled picker writes nothing")
        compare(bootstrap.timeSigUndoIndex(), undoIndex,
                "a cancelled picker leaves the undo index unchanged")
        compare(bootstrap.timeSigUndoCount(), undoCount,
                "a cancelled picker adds no undo command")
        var rename = findChild(surface, "timelineTrackHeaderRename")
        verify(rename && !rename.visible, "the rename editor stays hidden")
    }

    // The ready half of gate.cpp's gatedAndReadyRollZoom: a real wheel over
    // the mounted roll plot reaches the production presenter and changes zoom.
    // The MIDI-only loading-stage gate is not represented by this surface.
    function test_readyRollWheelZoom() {
        var surface = testCase.surface()
        verify(surface, "the ready roll surface is mounted")
        var input = findChild(surface, "swiftRollInput")
        var grid = session.gridPresenter()
        verify(input && grid && input.width > 80 && input.height > 100,
               "the ready roll's wheel target is mounted")
        var before = grid.beatWidth
        mouseWheel(input, 80, 100, 0, 120)
        tryVerify(function() {
            return grid.beatWidth > before
        }, 5000, "a ready roll wheel changes the visible time zoom")
        mouseWheel(input, 80, 100, 0, -120)
        tryVerify(function() {
            return Math.abs(grid.beatWidth - before) < 0.001
        }, 5000, "the opposite wheel restores the ready roll zoom")
    }

    function test_gridContrastPreviewAndApply() {
        var surface = testCase.surface()
        var plot = testCase.rollPlot()
        verify(surface && plot, "the roll plot is mounted")
        var palette = session.palette
        var grid = session.gridPresenter()

        var gridRoles = ["gridLine", "gridLineSub1", "gridLineSub2", "gridLineSub3",
                         "gridLineBeat", "gridLineBeatFine", "gridLineBar", "rowLine"]
        var original = {}
        for (var i = 0; i < gridRoles.length; ++i) {
            const color = palette[gridRoles[i]]
            original[gridRoles[i]] = Qt.rgba(color.r, color.g, color.b, color.a)
        }

        function grab() {
            wait(0)
            return grabImage(plot)
        }
        function push(contrast) {
            // The host's palette push, expressed at the palette seam: a soft
            // preview keeps the faint lines, a strong one drives them to full
            // black. reloadVisuals is the same re-bake the host calls.
            var color = contrast === 0 ? "#10040000" : "#FF000000"
            for (var i = 0; i < gridRoles.length; ++i)
                palette[gridRoles[i]] = color
            grid.reloadVisuals()
        }
        function restore() {
            for (var i = 0; i < gridRoles.length; ++i)
                palette[gridRoles[i]] = original[gridRoles[i]]
            grid.reloadVisuals()
        }
        function framesEqual(a, b) {
            if (a.width !== b.width || a.height !== b.height)
                return false
            for (var y = 0; y < a.height; ++y)
                for (var x = 0; x < a.width; ++x)
                    if (a.pixel(x, y) !== b.pixel(x, y))
                        return false
            return true
        }

        var baseline = grab()
        verify(baseline.width > 0 && baseline.height > 0, "the baseline frame grabbed")
        push(100)
        var strong = grab()
        verify(!framesEqual(strong, baseline),
               "a stronger grid-line palette repaints the existing grid")
        restore()
        verify(waitForNative(function() {
            return framesEqual(grab(), baseline)
        }, 5000), "restoring the palette restores the baseline frame")
        push(100)
        verify(waitForNative(function() {
            return framesEqual(grab(), strong)
        }, 5000), "re-applying the palette repaints the strong frame")
        restore()
    }
    function test_zCameraSurvivesMountedRemapsAndResize() {
        var surface = testCase.surface()
        var grid = session.gridPresenter()
        var input = findChild(surface, "swiftRollInput")
        var headerInput = testCase.headerInput()
        var rows = testCase.headerRows()
        var headers = testCase.headers()
        verify(grid && input && headerInput && rows && headers && rows.count >= 3,
               "mounted grid and at least two real tracks are ready")
        grid.setEditCursorTick(24)
        session.goToStart()
        tryCompare(grid, "editCursorTick", 0, 5000,
                   "A091 Go to Start leaves the mounted edit cursor at tick zero")
        grid.setCameraHScroll(21.5)
        tryCompare(grid, "cameraScrollX", 21.5)
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8,
                   Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() { return grid.cameraScrollX === 29.5 }, 5000,
                  "mounted wheel pan advances the fractional camera before remap")
        var initialZoom = grid.beatWidth
        mouseWheel(input, input.width / 2, input.height / 2, 0, 120)
        tryVerify(function() { return grid.beatWidth > initialZoom }, 5000,
                  "a mounted wheel zooms before the remap")
        var zoom = grid.beatWidth
        var scroll = grid.cameraScrollX

        var first = rows.itemAt(0)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mousePress(headerInput, x, y, Qt.LeftButton)
        var destination = Math.min(headerInput.height - 2, y + headers.rowHeight * 1.8)
        mouseMove(headerInput, x, destination, 10, Qt.LeftButton)
        tryCompare(findChild(surface, "timelineTrackHeaderReorderMarker"), "visible", true)
        var revision = grid.appliedRevisionText
        mouseRelease(headerInput, x, destination, Qt.LeftButton)
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 5000,
                  "the header drag commits a track reorder")
        compare(grid.cameraScrollX, scroll,
                "the mounted camera offset survives reorder publication")
        compare(grid.beatWidth, zoom,
                "the mounted camera zoom survives reorder publication")

        function chooseMenu(track, action) {
            tryVerify(function() {
                return findChild(surface, "quickMenuPanelRoot") === null
            }, 5000, "the previous header menu releases its modal input")
            var row = rows.itemAt(track)
            mouseClick(headerInput, row.titleRect.x + row.titleRect.width / 2,
                       row.titleRect.y + row.titleRect.height / 2
                       + track * headers.rowHeight, Qt.RightButton)
            tryCompare(headers, "menuOpen", true)
            var menuRow = null
            tryVerify(function() {
                menuRow = findChild(surface, "headerMenuRow_" + action)
                return menuRow !== null
            }, 5000, "the mounted header menu exposes action " + action)
            mouseClick(menuRow, menuRow.width / 2, menuRow.height / 2)
            tryCompare(headers, "menuOpen", false)
        }

        var count = rows.count
        chooseMenu(0, 4)
        tryCompare(rows, "count", count + 1, 5000,
                   "the mounted Duplicate track action publishes its remap")
        compare(grid.cameraScrollX, scroll,
                "the mounted camera offset survives duplicate publication")
        compare(grid.beatWidth, zoom,
                "the mounted camera zoom survives duplicate publication")

        chooseMenu(0, 5)
        tryCompare(rows, "count", count, 5000,
                   "the mounted Delete track action publishes its remap")
        compare(grid.cameraScrollX, scroll,
                "the mounted camera offset survives delete publication")
        compare(grid.beatWidth, zoom,
                "the mounted camera zoom survives delete publication")
        var length = bootstrap.timelineLengthTicks()
        grid.setCameraHScroll(1e9)
        var oldEnd = grid.cameraScrollX
        chooseMenu(1, 5)
        tryCompare(rows, "count", count - 1, 5000,
                   "the mounted header menu deletes the trailing lead track")
        verify(bootstrap.timelineLengthTicks() < length,
               "deleting the terminal track shrinks the real timeline")
        var newEnd = bootstrap.timelineLengthTicks() * bootstrap.cameraPxPerTick()
        tryVerify(function() {
            return Math.abs(grid.cameraScrollX - newEnd) <= 0.001
        }, 5000, "a shrinking remap reclamps the mounted camera to the new timeline end")
        verify(newEnd < oldEnd && grid.beatWidth === zoom,
               "timeline shrink retains time zoom while moving only the bounded offset")

        grid.setCameraHScroll(19.25)
        tryCompare(grid, "cameraScrollX", 19.25)
        var originalWidth = testCase.overlay.width
        try {
            testCase.overlay.width = originalWidth - headers.rowHeight
            tryVerify(function() {
                return Math.abs(grid.cameraScrollX - 19.25) < 0.001
            }, 5000, "fractional camera scroll persists on mounted viewport resize")
        } finally {
            testCase.overlay.width = originalWidth
        }
    }
}
