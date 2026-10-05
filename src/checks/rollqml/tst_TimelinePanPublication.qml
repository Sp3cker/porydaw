import QtQuick
import QtTest

TimelinePanSupport {
    // timelinepan's coalesced-refresh assertions: a section resize changes the
    // drawer raster, and a full visual reload produces the identical capture.
    function test_coalescedRefreshMatchesFull() {
        var g = grid()
        var drawer = findChild(surface(), "editorDrawer")
        verify(drawer !== null, "the drawer item is realized")
        var presenter = drawer.presenter
        var automation = presenter.section(0)
        var voiceChanges = presenter.section(2)
        verify(automation !== null && automation.visible,
               "the automation section is attached and visible")
        verify(voiceChanges !== null && voiceChanges.visible,
               "the voice-changes section is attached and visible")

        var input = rollInput()
        var beforeX = g.cameraScrollX
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (beforeX + 8.0)) <= 0.01
        }, 5000, "the coalesced pan advances the camera by 8px")

        waitForRendering(drawer)
        var before = grabImage(drawer)
        verify(before.width > 0 && before.height > 0,
               "the coalesced drawer capture is non-null")

        // A section resize must change the drawer raster.
        var bodyBefore = automation.bodyHeight
        presenter.setSectionBodyHeight(0, bodyBefore + 24)
        tryVerify(function() {
            return presenter.section(0).bodyHeight === bodyBefore + 24
        }, 3000, "the section body height applies")
        waitForRendering(drawer)
        var resized = grabImage(drawer)
        verify(resized.width > 0 && resized.height > 0,
               "the resized drawer capture is non-null")
        verify(imagesDiffer(before, resized), "the resize changed the drawer raster")

        // A full visual reload produces the same raster as the coalesced path.
        g.reloadVisuals()
        waitForRendering(drawer)
        var full = grabImage(drawer)
        verify(full.width > 0 && full.height > 0,
               "the post-reload drawer capture is non-null")
        verify(!imagesDiffer(resized, full),
               "the coalesced refresh matches a full visual reload")
    }

    function test_drumPadNamesFollowInitialProgram() {
        var g = grid()
        var originalScroll = g.cameraScrollY
        var rows = findChild(surface(), "timelineTrackHeaderRows")
        var headerInput = findChild(surface(), "timelineTrackHeadersInput")
        verify(rows && headerInput && rows.count > 1,
               "the mounted header provides two selectable production tracks")
        var pickerModel = session.headerVoicePickerModel()
        var first = rows.itemAt(0)
        mouseDoubleClickSequence(headerInput,
            first.subtitleRect.x + first.subtitleRect.width / 2,
            first.subtitleRect.y + first.subtitleRect.height / 2)
        tryCompare(session, "headerVoicePickerOpen", true, 5000)
        var originalProgram = pickerModel.pickerIndex
        var loader = findChild(surface(), "headerVoicePickerLoader")
        tryVerify(function() { return loader.item !== null })
        findChild(loader.item, "voicePickerSearch").text = "11"
        tryCompare(pickerModel, "pickerIndex", 0, 5000)
        mouseClick(findChild(loader.item, "voicePickerAccept"))
        tryCompare(session, "headerVoicePickerOpen", false, 5000)

        try {
            g.setTrack(0)
            var gutter = gutterInput()
            g.setCameraVScroll((127 - 37) * g.rowHeight - gutter.height / 2)
            g.reloadVisuals()
            wait(0)
            function padLabel(text) {
                for (var pitch = 30; pitch <= 45; ++pitch) {
                    var row = keyRow(pitch)
                    if (rowVisible(row) && hoveredName(pitch) === text) {
                        row.text = text
                        return row
                    }
                }
                return null
            }
            var longName = "fixture_named_pad_long_label_123"
            tryVerify(function() { return padLabel(longName) !== null }, 5000,
                      "A038 the rendered fixed keyboard displays the full long drum name")
            var longPad = padLabel(longName)
            verify(padLabel("fixture_pluck") !== null && padLabel("fixture_drum") !== null,
                   "A036 the mounted drum keyboard displays adjacent real sample names")
            verify(padLabel("D#2") !== null,
                   "A044 an unnamed pad renders its exact pitch fallback")
            var band = findChild(surface(), "rollContentBand")
            function overflowEnd() {
                g.clearKeyboardHover()
                tryCompare(g, "hoverKey", -1, 5000)
                var image = grabItem(band)
                var box = gutterBox()
                var dpr = image.width / band.width
                var reach = box.mapToItem(band, 0, 0).x
                var limit = Math.round(Math.min(band.width, reach + g.keyboardWidth + 400) * dpr) - 1
                function backgroundRun(row, y) {
                    var x = Math.round((reach + 1) * dpr)
                    var r = image.red(x, y), gr = image.green(x, y), b = image.blue(x, y)
                    var end = x
                    while (++x < limit && x - end <= Math.ceil(row.height * dpr)) {
                        if (Math.abs(image.red(x, y) - r) <= 2
                            && Math.abs(image.green(x, y) - gr) <= 2
                            && Math.abs(image.blue(x, y) - b) <= 2)
                            end = x
                    }
                    return end / dpr
                }
                function labelEnd(row) {
                    var top = box.mapToItem(band, 0, row.y).y
                    return Math.max(backgroundRun(row, Math.ceil(top * dpr) + 1),
                                    backgroundRun(row, Math.ceil((top + row.height) * dpr) - 2))
                }
                return { end: labelEnd(keyRow(37)), plainEnd: labelEnd(keyRow(39)),
                         limit: band.width - 1 }
            }
            var overflow = overflowEnd()
            var keyboardEdge = gutterBox().mapToItem(band, g.keyboardWidth, 0).x
            verify(overflow.end > keyboardEdge && overflow.end > overflow.plainEnd
                   && longPad.x === 0,
                   "A039 the long label extends past the keyboard without clipping")
            verify(longPad.y >= 0 && longPad.y + longPad.height <= gutter.height,
                   "the loaded accidental pad scrolls into the visible gutter: y="
                   + longPad.y + " scroll=" + g.cameraScrollY
                   + " gutterHeight=" + gutter.height)
            var scene = g.scene
            var chip = findChild(surface(), "timelineQuickPianoHoverChip")
            var chipText = findChild(surface(), "timelineQuickPianoHoverChipText")
            function hover(label, expected) {
                mouseMove(gutter, gutter.width / 2, label.y + label.height / 2)
                tryCompare(g, "hoverKey", expected === longName ? 37
                    : expected === "D#2" ? 39 : 36, 5000)
                tryCompare(scene, "hoverChipText", expected, 5000)
                tryVerify(function() {
                    return chipText.text === expected && chip.visible
                        && chipText.contentWidth <= chip.width && scene.hoverChipX >= 0
                }, 5000, "the complete hover name fits its on-screen chip")
            }
            hover(longPad, longName)
            hover(padLabel("D#2"), "D#2")
            hover(padLabel("fixture_pluck"), "fixture_pluck")
            var keyboard = keyboardRenderer()
            var clipper = null
            for (var ancestor = keyboard.parent; ancestor && ancestor !== band;
                 ancestor = ancestor.parent) {
                if (ancestor.clip)
                    clipper = ancestor
            }
            verify(band && !band.clip && ancestor === band && clipper
                   && clipper.width > g.keyboardWidth && overflow.end > keyboardEdge,
                   "A041 the label overflows the gutter but clips at the roll-band bounds")
            verify(overflow.end < overflow.limit,
                   "A043 the overflow text is actually legible without elision")
            var originalY = longPad.y
            g.setCameraVScroll(g.cameraScrollY + g.rowHeight)
            tryVerify(function() {
                var shifted = padLabel(longName)
                return shifted !== null && Math.abs(shifted.y - (originalY - g.rowHeight)) < 1
                    && overflowEnd().end > keyboardEdge
            }, 5000, "A042 the overflowing label follows exactly one vertical camera scroll")

            g.setTrack(1)
            tryCompare(g, "trackIndex", 1, 5000)
            g.reloadVisuals()
            g.clearKeyboardHover()
            tryCompare(g, "hoverKey", -1, 5000)
            waitForRendering(gutterBox())
            var keys = grabItem(gutterBox())
            var melodicOk = true
            var sawC = false
            for (var p = 0; p < 128; ++p) {
                var keyRowP = keyRow(p)
                if (!rowVisible(keyRowP))
                    continue
                var ink = rowInk(keys, gutterBox(), keyRowP, g.keyboardWidth / 3,
                                 g.keyboardWidth - 1) >= 0
                if (p % 12 === 0) {
                    sawC = true
                    melodicOk = melodicOk && ink && /^C-?\d+$/.test(hoveredName(p))
                } else if ([2, 4, 5, 7, 9, 11].indexOf(p % 12) >= 0) {
                    melodicOk = melodicOk && !ink
                }
            }
            verify(sawC && melodicOk,
                   "A064 the melodic track renders only exact octave-C keyboard names")
            verify(padLabel(longName) === null,
                   "A065 the accidental drum name disappears on the melodic track")
            g.setTrack(0)
            tryCompare(g, "trackIndex", 0, 5000)
            g.reloadVisuals()
            verify(padLabel(longName) !== null,
                   "A069 switching back restores the same full loaded drum name")

            var voice = findChild(surface(), "voiceChangesPage")
            var plot = findChild(voice, "voicePlotInput")
            verify(voice && plot && plot.width > 0,
                   "the real voice-changes plot accepts later program edits")
            mouseDoubleClickSequence(plot, plot.width / 3, plot.height / 2)
            tryCompare(voice.model, "pickerOpen", true, 5000)
            var voicePicker = voice.picker
            tryVerify(function() { return voicePicker && voicePicker.visible })
            findChild(voicePicker, "voicePickerSearch").text = "0"
            tryCompare(voice.model, "pickerIndex", 0, 5000)
            mouseClick(findChild(voicePicker, "voicePickerAccept"))
            tryCompare(voice.model, "pickerOpen", false, 5000)
            var laterTick = Math.max(bootstrap.timelineLengthTicks(),
                                     g.ticksPerBeat * 16)
            tryCompare(voice.model, "contextSlot", 11, 5000,
                       "A079 the mounted initial drum program supplies voice context eleven")
            g.reloadVisuals()
            verify(padLabel(longName) !== null,
                   "A080 genuine synchronization at the initial program keeps the drum pad")
            g.setEditCursorTick(laterTick)
            tryCompare(g, "editCursorTick", laterTick, 5000,
                       "the production grid moves the real edit cursor beyond the voice event")
            tryCompare(voice.model, "contextSlot", 0, 5000,
                       "A081 the mounted cursor resolves the later melodic voice context")
            g.reloadVisuals()
            verify(padLabel(longName) !== null,
                   "A082 a later melodic cursor program leaves the initial drum pad")
            g.setEditCursorTick(0)
            tryCompare(g, "editCursorTick", 0, 5000)
            tryCompare(voice.model, "contextSlot", 11, 5000)
            bootstrap.presentPlayheadTick(laterTick, 2)
            tryVerify(function() {
                var playhead = findChild(surface(), "sharedPlayhead").presenter
                return playhead.playing && playhead.tick >= laterTick - 1
            }, 5000, "A083 the mounted playing tick passes the later voice program event")
            tryCompare(voice.model, "contextSlot", 0, 5000,
                       "A084 the mounted playhead resolves the later melodic voice context")
            g.reloadVisuals()
            verify(padLabel(longName) !== null,
                   "A085 the advanced playhead program leaves the initial drum pad")
            bootstrap.presentPlayheadTick(0, 2)
            tryCompare(voice.model, "contextSlot", 11, 5000,
                       "A086 resetting the mounted playhead restores initial drum voice context")
            g.reloadVisuals()
            verify(padLabel(longName) !== null,
                   "A087 resetting the playhead retains the initial drum pad")
        } finally {
            g.setEditCursorTick(0)
            bootstrap.presentPlayheadTick(0, 1)
            g.setCameraVScroll(originalScroll)
            if (originalProgram >= 0 && originalProgram !== 11) {
                wait(Qt.styleHints.mouseDoubleClickInterval + 1)
                mouseDoubleClickSequence(headerInput,
                    first.subtitleRect.x + first.subtitleRect.width / 2,
                    first.subtitleRect.y + first.subtitleRect.height / 2)
                tryCompare(session, "headerVoicePickerOpen", true, 5000)
                tryVerify(function() { return loader.item !== null })
                findChild(loader.item, "voicePickerSearch").text = String(originalProgram)
                tryCompare(pickerModel, "pickerIndex", 0, 5000)
                mouseClick(findChild(loader.item, "voicePickerAccept"))
                tryCompare(session, "headerVoicePickerOpen", false, 5000)
            }
        }
    }

}
