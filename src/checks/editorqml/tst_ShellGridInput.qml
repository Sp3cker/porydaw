import QtQuick
import QtTest
import "GatedVisualsHelpers.js" as Helpers

ShellGridInputSupport {
    function test_headerRenameFocusAndLifecycle() {
        var session = openRoute101()
        var surface = selectedSurface()
        var headers = surface.headersModel
        var input = findChild(surface, "timelineTrackHeadersInput")
        var field = findChild(surface, "timelineTrackHeaderRename")
        var rows = findChild(surface, "timelineTrackHeaderRows")
        verify(input && field && rows && rows.itemAt(0),
               "the loaded track header and rename field are mounted")
        var row = rows.itemAt(0)
        var title = row.titleRect
        var x = title.x + title.width / 2
        var y = title.y + title.height / 2
        mouseClick(input, x, y)
        tryCompare(input, "activeFocus", true, 3000,
                   "a real header click gives the track-header band active focus")
        verify(input.activeFocus, "A007 the loaded Quick header band accepts real pointer focus")
        verify(input.activeFocus && !field.activeFocus,
               "A008 the focused band is the track header rather than the rename editor")
        function openRename() {
            mouseDoubleClickSequence(input, x, y, Qt.LeftButton)
            tryCompare(headers, "renamingTrack", 0, 3000)
            tryCompare(field, "visible", true, 3000)
            tryCompare(field, "activeFocus", true, 3000)
        }
        openRename()
        verify(field.visible && field.activeFocus,
               "A010 the opened rename field is visible and holds active focus")
        for (var letter of "Rolled")
            keyClick(letter)
        compare(field.text, "Rolled",
                "A009 the focused Quick rename editor contains the literal Rolled draft")
        keyClick(Qt.Key_Return)
        tryCompare(field, "visible", false, 3000)
        compare(row.title, "1 · Rolled",
                "Return commits the header title through the loaded shell")
        openRename()
        verify(field.visible && field.activeFocus,
               "A012 the reopened rename field is visible and holds active focus")
        for (var discarded of "Discarded")
            keyClick(discarded)
        keyClick(Qt.Key_Escape)
        tryCompare(field, "visible", false, 3000)
        compare(row.title, "1 · Rolled",
                "Escape discards the reopened header draft")
        openRename()
        verify(field.visible && field.activeFocus,
               "A014 the loop-marker guard reopens a visible focused rename field")
        keyClick(Qt.Key_BracketLeft)
        compare(field.text, "[", "the third focused rename editor accepts a loop-marker draft")
        keyClick(Qt.Key_Return)
        tryCompare(field, "visible", false, 3000)
        compare(row.title, "1 · Rolled",
                "the loop-marker guard keeps the committed name")
    }

    function test_loadedRulerAndFixedInputSurfaces() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the empty shell mounts")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        compare(session.songTabs.tabCount, 0, "no song has no editable tab")
        compare(selectedSurface(), null, "no song exposes no roll, ruler or drawer input")
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        compare(session.songTabs.selectedPage.songOpen, true,
                "the published editor belongs to a loaded document")
        var fixedNames = ["swiftRollInput", "timelineRulerInput",
                          "timelineHorizontalScrollBar", "timelineRollScrollBar",
                          "timelineTrackHeadersInput", "timelineOtherEventsInput",
                          "timelineRulerControls", "timelineRulerDivisionControl",
                          "timelineRulerFeelControl", "drawerBarInput",
                          "drawerToggle_velocity", "drawerToggle_voiceChanges",
                          "drawerToggle_automation"]
        var fixedInputsLive = true
        for (var i = 0; i < fixedNames.length; ++i) {
            var input = findChild(surface, fixedNames[i])
            fixedInputsLive = fixedInputsLive && input !== null && input.enabled
                && input.width > 0 && input.height > 0
        }
        verify(fixedInputsLive,
               "the loaded roll, ruler, scrollbars, headers, other events and drawer controls accept input")
        var division = findChild(surface, "timelineRulerDivisionControl")
        var feel = findChild(surface, "timelineRulerFeelControl")
        verify(findChild(division, "gridControlLabel").text === grid.gridDivisionControlText
               && findChild(feel, "gridControlLabel").text === grid.gridFeelControlText
               && division.controlToolTip ===
                   "Editing snap grid. Auto follows the zoom one step finer than the drawn grid; a fixed division snaps to that note value; Clock snaps to the mid2agb clock grid."
               && feel.controlToolTip === "Straight or triplet beat subdivisions.",
               "the loaded division and feel labels and help match the live ruler")
        var ruler = findChild(surface, "timelineRulerInput")
        var clickX = Math.min(ruler.width - grid.baseFontPx, 4 * grid.beatWidth)
        var guide = session.playheadGuidesPresenter().edit
        var beforeCursorX = guide.contentX
        mouseClick(ruler, clickX, ruler.height * 3 / 4)
        verify(waitForNative(function() {
            return guide.contentX > beforeCursorX
        }, 3000), "a ready ruler click moves the document edit-cursor guide")
        verify(!session.gridCommandAvailable(17),
               "the released ruler click leaves no active time selection")
        var bar = findChild(surface, "timelineHorizontalScrollBar")
        grid.setCameraHScroll(0)
        var beforeScroll = grid.cameraScrollX
        mouseWheel(bar, bar.width / 2, bar.height / 2, 0, -120)
        verify(waitForNative(function() { return grid.cameraScrollX > beforeScroll }, 3000),
               "a ready horizontal scrollbar wheel moves the camera")
        var vertical = findChild(surface, "timelineRollScrollBar")
        var beforeVertical = grid.cameraScrollY
        var wheelAngle = beforeVertical < grid.cameraMaxVScroll / 2 ? -120 : 120
        mouseWheel(vertical, vertical.width / 2, vertical.height / 2, 0, wheelAngle)
        verify(waitForNative(function() { return grid.cameraScrollY !== beforeVertical }, 3000),
               "a ready vertical scrollbar wheel moves the roll")
        var drawerKinds = ["velocity", "voiceChanges", "automation"]
        for (var section = 0; section < drawerKinds.length; ++section) {
            var toggle = findChild(surface, "drawerToggle_" + drawerKinds[section])
            var handle = findChild(surface, "drawerHandle_" + drawerKinds[section])
            verify(toggle && handle && toggle.enabled && toggle.visible,
                   "the loaded drawer section exposes its live toggle and resize grip")
            if (!handle.visible)
                mouseClick(toggle, toggle.width / 2, toggle.height / 2)
            tryCompare(handle, "visible", true, 3000,
                       "the drawer resize grip becomes live when its section opens")
            verify(handle.enabled && handle.width > 0 && handle.height > 0,
                   "the expanded drawer section exposes its usable resize grip")
        }
        var detent = findChild(surface, "drawerDetentInput")
        verify(detent !== null && detent.enabled && detent.width > 0
               && detent.height > 0
               && detent.parent.visible === (surface.velocityModel.detentsAvailable
                   && surface.drawerPresenter.velocitySection.visible),
               "the loaded velocity detent input follows its real section availability")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        var eventPage = null
        tryVerify(function() {
            eventPage = findChild(surface, "eventListPage")
            return eventPage !== null && eventPage.visible && eventPage.enabled
        }, 3000, "a loaded song exposes the live Event List")
        var eventInputs = ["eventListChunk", "eventListFilter", "eventListAdd"]
        var eventInputsLive = true
        for (var eventIndex = 0; eventIndex < eventInputs.length; ++eventIndex) {
            var eventInput = findChild(eventPage, eventInputs[eventIndex])
            eventInputsLive = eventInputsLive && eventInput !== null && eventInput.enabled
                && eventInput.visible && eventInput.width > 0 && eventInput.height > 0
        }
        verify(eventInputsLive, "the loaded Event List exposes its live chunk, filter and add controls")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", false, 3000)
    }

    function test_readyRulerControlHoverHelp() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        compare(shell.shellPresenter.session.songTabs.selectedPage.songOpen, true,
                "ruler control styling is inspected only after the song becomes ready")
        var tip = findChild(surface, "timelineRulerToolTip")
        var row = findChild(surface, "timelineRulerControls")
        verify(tip !== null && row !== null && !tip.visible,
               "ruler help starts hidden outside the clipped control row")
        var entries = [
            ["timelineRulerDivisionControl", "gridDivisionControlText",
             "Editing snap grid. Auto follows the zoom one step finer than the drawn grid; a fixed division snaps to that note value; Clock snaps to the mid2agb clock grid."],
            ["timelineRulerFeelControl", "gridFeelControlText",
             "Straight or triplet beat subdivisions."]
        ]
        for (var i = 0; i < entries.length; ++i) {
            var control = findChild(surface, entries[i][0])
            var label = findChild(control, "gridControlLabel")
            verify(control && control.enabled && control.width > 0 && control.height > 0,
                   "the ready ruler help target is live")
            if (i === 0) {
                compare(label.text, grid.gridDivisionControlText,
                        "the ready division control shows its canonical state")
                compare(control.controlToolTip, entries[i][2],
                        "the ready division control exposes its canonical help text")
            } else {
                compare(label.text, grid.gridFeelControlText,
                        "the ready feel control shows its canonical state")
                compare(control.controlToolTip, entries[i][2],
                        "the ready feel control exposes its canonical help text")
            }
            mouseMove(control, control.width / 2, control.height / 2)
            tryCompare(tip, "visible", true, 3000,
                       "hovering a ready ruler control shows its mounted help")
            compare(tip.toolTipText, entries[i][2],
                    "the hovered help belongs to the actual control")
            var origin = tip.mapToItem(surface, 0, 0)
            var rowBottom = row.mapToItem(surface, 0, row.height).y
            verify(tip.parent === surface && tip.width > 0 && tip.height > 0
                   && rowBottom + tip.height <= surface.height,
                   "the hovered help has space below the real ruler row")
            verify(origin.y >= rowBottom,
                   "hover help floats below rather than covering the ruler row")
            verify(origin.y + tip.height <= surface.height,
                   "hover help remains inside the bottom of the real canvas")
            verify(origin.x >= 0 && origin.x + tip.width <= surface.width,
                   "hover help remains inside both sides of the real canvas")
            mouseMove(surface, surface.width / 2, surface.height / 2)
            tryCompare(tip, "visible", false, 3000,
                       "leaving either ruler control hides its help")
        }
    }

    function test_modifiedRulerSweepPaintsExactNoteScope() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var ruler = findChild(surface, "timelineRulerInput")
        var plot = findChild(surface, "timelineQuickRollPlot")
        verify(ruler !== null && plot !== null, "the mounted roll and ruler accept a scope sweep")
        function rasterBottom(item) {
            if (!item || !item.visible || item.width < 5 || item.height < 5)
                return null
            var inPlot = item.mapToItem(plot, item.width / 2, 0)
            var bottom = item.mapToItem(plot, item.width / 2, item.height)
            if (inPlot.x < 2 || inPlot.x >= plot.width - 2
                    || inPlot.y < 2 || bottom.y >= plot.height - 2)
                return null
            return item.mapToItem(shell.contentItem, item.width / 2, item.height)
        }
        var scale = grid.beatWidth / grid.ticksPerBeat
        var notes = gridNotes(grid)
        var secondary = null
        for (var i = 0; i < notes.length; ++i) {
            var candidate = notes[i]
            var item = findChild(surface, "gridNote_" + candidate.id)
            var left = candidate.tick * scale - grid.cameraScrollX
            var right = (candidate.tick + candidate.duration) * scale - grid.cameraScrollX
            var primaryOverlap = notes.some(function(other) {
                var primaryItem = findChild(surface, "gridNote_" + other.id)
                return other.track === grid.trackIndex && !other.ghost
                    && other.tick >= candidate.tick
                    && other.tick < candidate.tick + candidate.duration
                    && rasterBottom(primaryItem) !== null
            })
            if (candidate.ghost && rasterBottom(item) !== null && primaryOverlap
                    && left > ruler.width * 0.15 && right < ruler.width * 0.6) {
                secondary = candidate
                break
            }
        }
        verify(secondary !== null, "a rendered secondary note anchors the modified sweep")
        var startX = (secondary.tick - grid.snapTicks) * scale - grid.cameraScrollX
        var endX = (secondary.tick + secondary.duration + grid.snapTicks) * scale
                   - grid.cameraScrollX
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(ruler, endX, y, Qt.LeftButton, Qt.ControlModifier)
        verify(shell.shellPresenter.session.gridCommandAvailable(17),
               "the mounted modified sweep publishes an active time selection")
        waitForRendering(shell.contentItem)
        var image = grabImage(shell.contentItem)
        verify(image.width > 0 && image.height > 0, "the modified selection renders pixels")
        var dpr = image.width / shell.contentItem.width
        var ring = Helpers.channels(grid.palette.selectionRing)
        var selectedTracks = {}
        selectedTracks[grid.trackIndex] = true
        var startTick = secondary.tick - grid.snapTicks
        var endTick = secondary.tick + secondary.duration + grid.snapTicks
        var probed = 0
        for (var index = 0; index < notes.length; ++index) {
            var note = notes[index]
            var rendered = findChild(surface, "gridNote_" + note.id)
            if (rasterBottom(rendered) === null)
                continue
            if (note.tick < endTick && note.tick + note.duration > startTick)
                selectedTracks[note.track] = true
        }
        verify(selectedTracks[secondary.track] === true && secondary.track !== grid.trackIndex,
               "the fixture includes a distinct secondary track")
        for (var track in selectedTracks) {
            var found = false
            for (var n = 0; n < notes.length; ++n) {
                var visible = notes[n]
                if (visible.track !== Number(track) || visible.tick >= endTick
                        || visible.tick + visible.duration <= startTick)
                    continue
                var rect = findChild(surface, "gridNote_" + visible.id)
                var bottom = rasterBottom(rect)
                if (bottom === null)
                    continue
                var px = Math.round(bottom.x * dpr)
                var py = Math.round(bottom.y * dpr) - 1
                if (px < 0 || px >= image.width || py < 0 || py >= image.height)
                    continue
                var actual = [image.red(px, py), image.green(px, py), image.blue(px, py)]
                verify(Helpers.colorsNear(actual, ring),
                       "modified ruler scope paints the selection-ring pixels of every overlapping track")
                found = true
                ++probed
                break
            }
            verify(found, "every selected overlap track retains a visible raster witness")
        }
        verify(probed >= 2, "the mounted sweep paints primary and secondary note rings")
        var coveredPrimary = notes.find(function(note) {
            if (note.track !== grid.trackIndex || note.ghost
                    || note.tick < startTick || note.tick >= endTick)
                return false
            var item = findChild(surface, "gridNote_" + note.id)
            if (rasterBottom(item) === null)
                return false
            return item.mapToItem(plot, 0, 0).y > grid.rowHeight + 2
        })
        verify(coveredPrimary !== undefined, "the selected span contains a primary note for key delivery")
        var roll = rollInput(surface)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        verify(waitForNative(function() {
            var transposed = noteById(grid, coveredPrimary.id)
            return transposed && transposed.pitch === coveredPrimary.pitch + 1
                && shell.shellPresenter.session.gridCommandAvailable(17)
        }, 5000), "mounted Up edits the covered primary while retaining the time range")
        waitForRendering(shell.contentItem)
        var keyedImage = grabImage(shell.contentItem)
        var keyedNote = findChild(surface, "gridNote_" + coveredPrimary.id)
        var keyedBottom = rasterBottom(keyedNote)
        verify(keyedBottom !== null,
               "the time-scoped keyboard edit leaves its primary note inside the rendered plot")
        var keyedX = Math.round(keyedBottom.x * dpr)
        var keyedY = Math.round(keyedBottom.y * dpr) - 1
        verify(keyedX >= 0 && keyedX < keyedImage.width
               && keyedY >= 0 && keyedY < keyedImage.height
               && Helpers.colorsNear([keyedImage.red(keyedX, keyedY),
                                      keyedImage.green(keyedX, keyedY),
                                      keyedImage.blue(keyedX, keyedY)], ring),
               "time-scoped Up leaves the edited note's selection ring painted")
        var session = shell.shellPresenter.session
        var blockedSummary = grid.noteSummary
        var blockedRevision = grid.appliedRevisionText
        var blockedCursor = grid.editCursorTick
        var blockedUndo = session.canUndo
        var blockedRedo = session.canRedo
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        compare(grid.noteSummary, blockedSummary,
                "mounted time selection blocks both resize keys without changing notes")
        compare(grid.appliedRevisionText, blockedRevision,
                "mounted time selection blocks resize without changing revision")
        compare(grid.editCursorTick, blockedCursor,
                "mounted time selection blocks resize without changing cursor")
        compare(session.canUndo, blockedUndo,
                "mounted time selection blocks resize without adding undo")
        compare(session.canRedo, blockedRedo,
                "mounted time selection blocks resize without changing redo")
        compare(session.gridCommandAvailable(17), true,
                "mounted blocked resize keys preserve the active time selection")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            var current = selectedSurface()
            return session.songTabs.pendingCloseId >= 0
                || (current && current.gridModel !== grid)
        }, 15000), "the reload either requests discard or installs the replacement")
        if (session.songTabs.pendingCloseId >= 0)
            session.songTabs.confirmDiscard()
        var mountedTabs = findChild(shell.sceneLoader.item, "songTabPages").parent
        verify(waitForNative(function() {
            var replacement = mountedTabs.selectedEditorSurface()
            return replacement && session.songTabs.selectedPage
                && replacement.gridModel !== grid
                && replacement.gridModel === session.songTabs.selectedPage.gridPresenter()
                && replacement.gridModel.renderedNoteCount > 0
        }, 15000), "the selected song reload replaces the grid after the active ruler range")
        compare(session.gridCommandAvailable(17), false,
                "reloading the selected song clears the old active time selection")
    }

}
