.import "ShellDrawerParityRasterSupport.js" as Raster
.import "ShellDrawerParityVelocityInputSupport.js" as VelocityInput

    function dragMountedVelocity(testCase, unlockAtPress) {
        testCase.openDrawerShell("velocity")
        var model = testCase.session().velocityPage()
        var input = testCase.velocityPlotInput()
        var detent = testCase.findChild(testCase.selectedSurface(), "drawerDetent")
        testCase.verify(model && input && detent && input.visible,
               "the real velocity page, input delegate and detent control are mounted")
        var grid = testCase.gridModel()
        grid.setTrack(0)
        testCase.verify(!detent.visible,
               "the direct-sound context hides the composed detent before PSG staging")
        var voiceInput = testCase.voicePlotInput()
        var voicePage = testCase.voiceModel()
        testCase.verify(voiceInput && voiceInput.visible && voicePage,
               "the mounted voice-change delegate can stage a square program before the drag")
        grid.setCameraHScroll(0)
        var insertionX = grid.beatWidth * 2.5
        testCase.verify(insertionX > 0 && insertionX < voiceInput.width,
               "the program-change column is visible before the chosen notes")
        testCase.mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2, Qt.LeftButton)
        testCase.tryCompare(voicePage, "pickerOpen", true)
        var search = testCase.findChild(testCase.selectedSurface(), "voicePickerSearch")
        testCase.verify(testCase.waitForNative(function() { return search && search.activeFocus }, 3000),
               "the actual voice picker focuses its search field")
        testCase.keyClick(Qt.Key_0)
        testCase.keyClick(Qt.Key_0)
        testCase.keyClick(Qt.Key_4)
        testCase.tryCompare(voicePage, "pickerHasMatch", true)
        testCase.keyClick(Qt.Key_Return)
        testCase.tryCompare(voicePage, "pickerOpen", false)
        var originalNotes = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return note.track === 0 && !note.ghost
        })
        testCase.verify(originalNotes.length >= 6 && originalNotes[3].velocity === 98
               && originalNotes[4].velocity === 104 && originalNotes[5].velocity === 110,
               "the three staged notes after the square change are literal 98/104/110")
        var notes = [originalNotes[3], originalNotes[5], originalNotes[4]]
        var capture = testCase.shell.contentItem
        var page = testCase.velocityPageItem()
        var unselectedFill = testCase.collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[0].id)
        })
        testCase.verify(unselectedFill, "the staged ordinary velocity node is mounted before selection")
        testCase.waitForRendering(testCase.tabsRoot())
        var ordinaryFrame = testCase.grabImage(capture)
        testCase.verify(Raster.nearestPaintedColor(testCase, ordinaryFrame, capture, unselectedFill,
                                   page.gridPalette.noteBorder) <= 16,
               "an ordinary velocity node paints the antialiased semantic black outline")
        testCase.verify(Raster.paintedColor(testCase, ordinaryFrame, capture, unselectedFill,
                            page.gridPalette.noteFill(0, 127)),
               "an ordinary velocity node paints its track identity fill")
        var roll = testCase.rollInput()
        grid.setCameraVScroll((127 - (notes[0].pitch + notes[1].pitch) / 2 + 0.5)
                              * grid.rowHeight - roll.height / 2)
        for (var i = 0; i < 2; ++i) {
            var position = testCase.gridPointFor(notes[i].tick + notes[i].duration / 2,
                                        notes[i].pitch)
            testCase.verify(position.x > 0 && position.x < roll.width
                   && position.y > 0 && position.y < roll.height,
                   "each staged drag note maps into the mounted roll")
            testCase.mouseClick(roll, position.x, position.y, Qt.LeftButton,
                       i === 0 ? Qt.NoModifier : Qt.ControlModifier)
        }
        testCase.verify(testCase.waitForNative(function() {
            return model.selectedCount === 2 && model.detentsAvailable
                && detent.visible && detent.enabled
        }, 5000), "the selected square notes enable the rendered detent control: "
           + JSON.stringify({ selectedCount: model.selectedCount, available: model.detentsAvailable,
                              visible: detent.visible, enabled: detent.enabled, slot: model.contextSlot,
                              selected: JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
                                  return note.selected
                              }).map(function(note) { return [note.id, note.velocity] }) }))
        var plot = testCase.findChild(page, "velocityPlot")
        var ruler = testCase.findChild(page, "velocityRuler")
        var drawer = testCase.findChild(testCase.selectedSurface(), "editorDrawer")
        var bar = testCase.findChild(drawer, "drawerBar")
        var velocityToggle = testCase.findChild(drawer, "drawerToggle_velocity")
        var automationToggle = testCase.findChild(drawer, "drawerToggle_automation")
        testCase.verify(plot && ruler && bar && velocityToggle && automationToggle,
               "the composed velocity plot, ruler and drawer chrome are visible")
        var bounds = detent.mapToItem(drawer, 0, 0)
        var band = ruler.mapToItem(drawer, 0, 0)
        var plotLeft = plot.mapToItem(drawer, 0, 0).x
        testCase.verify(bar.visible && velocityToggle.visible
               && velocityToggle.x >= bar.x
               && velocityToggle.x + velocityToggle.width <= bar.x + bar.width
               && velocityToggle.y >= bar.y
               && velocityToggle.y + velocityToggle.height <= bar.y + bar.height,
               "the rendered velocity toggle is wholly inside its visible bar")
        testCase.compare(velocityToggle.x, automationToggle.x + automationToggle.width
                + Math.round(grid.baseFontPx / 4),
                "velocity chrome follows automation by base-font spacing")
        testCase.verify(Math.abs(bounds.x - band.x) <= 1 / testCase.devicePixelRatioFor(page)
               && Math.abs(bounds.y + detent.height - band.y - ruler.height)
                  <= 1 / testCase.devicePixelRatioFor(page)
               && bounds.x + detent.width < plotLeft,
               "the visible detent aligns with the band bottom to the left of the plot")
        var graduation = testCase.collectByName(ruler, "velocityRulerGraduations", [])
        testCase.verify(graduation.length === 1,
               "the composed ruler has an intrinsic graduation paint layer")
        var ring = testCase.findChild(testCase.collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[0].id)
        }).parent, "velocityNodeRing")
        var outsiderFill = testCase.collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[2].id)
        })
        var outsiderStem = testCase.findChild(outsiderFill.parent, "velocityNodeStem")
        testCase.verify(ring && outsiderStem && outsiderFill, "selected and unselected note paint is mounted")
        testCase.waitForRendering(testCase.tabsRoot())
        var selectedFrame = testCase.grabImage(capture)
        testCase.verify(Raster.paintedColor(testCase, selectedFrame, capture, ring, page.gridPalette.selectionRing),
               "the selected velocity ring paints the semantic highlight ink")
        var expectedStem = Raster.forkStemShade(testCase, page.gridPalette.noteFill(0, 127))
        testCase.verify(Raster.nearestPaintedColor(testCase, selectedFrame, capture, outsiderStem, expectedStem) <= 16,
               "the outsider stem paints the independent one-third Oklab track shade")
        testCase.verify(Raster.paintedColor(testCase, selectedFrame, capture, outsiderFill, page.gridPalette.outline),
               "the unselected note paints the semantic dimmed mid ink")
        testCase.compare(outsiderFill.border.width, 0,
                "a dimmed note no longer paints an ordinary black outline")
        testCase.mouseMove(input, outsiderFill.parent.model.x + VelocityInput.velocityPlotOrigin(grid),
                           outsiderFill.parent.model.y, -1, Qt.NoButton)
        testCase.verify(testCase.waitForNative(function() {
            return model.hoveredNoteText === String(notes[2].id)
        }, 3000), "hovering the outsider selects its own ruler context")
        var hoverFrame = testCase.grabImage(capture)
        testCase.verify(Raster.paintedColor(testCase, hoverFrame, capture, graduation[0],
                            page.gridPalette.selectionRing),
               "the active ruler graduation paints the semantic separator accent")
        testCase.mouseMove(input, input.width - 3, input.height - 3, -1, Qt.NoButton)
        var checkedFrame = Raster.grabRegionStable(testCase, capture, Raster.regionOf(testCase, selectedFrame, capture, detent))
        testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
        testCase.tryVerify(function() { return testCase.accessibleChecked(detent) === false })
        var uncheckedFrame = Raster.grabUntilDifferent(testCase, capture, checkedFrame,
                                                 Raster.regionOf(testCase, checkedFrame, capture, detent))
        testCase.verify(Raster.changedPixels(testCase, checkedFrame, uncheckedFrame,
                             Raster.regionOf(testCase, checkedFrame, capture, detent), 0) > 0,
               "clicking the detent visibly repaints its unchecked ink")
        testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
        testCase.tryVerify(function() { return testCase.accessibleChecked(detent) === true })
        var restoredFrame = Raster.grabUntilDifferent(testCase, capture, uncheckedFrame,
                                                Raster.regionOf(testCase, uncheckedFrame, capture, detent))
        testCase.verify(Raster.changedPixels(testCase, uncheckedFrame, restoredFrame,
                             Raster.regionOf(testCase, restoredFrame, capture, detent), 0) > 0,
               "clicking the detent visibly repaints its checked ink")
        testCase.compare(model.axisMode, 1, "the mounted square context publishes its intrinsic axis")
        testCase.compare(testCase.accessibleChecked(detent), model.detentsEnabled,
                "the rendered detent control reflects the enabled page preference")
        testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
        testCase.tryCompare(model, "detentsEnabled", false)
        testCase.tryVerify(function() { return !testCase.accessibleChecked(detent) }, 3000,
                   "the rendered detent control unchecks on click")
        testCase.mouseClick(detent, detent.width / 2, detent.height / 2)
        testCase.tryCompare(model, "detentsEnabled", true)
        testCase.tryVerify(function() { return testCase.accessibleChecked(detent) }, 3000,
                   "the rendered detent control checks on click")
        var tickX = input.width * 0.4
        var anchoredTick = (tickX + grid.cameraScrollX) * grid.ticksPerBeat / grid.beatWidth
        var oldBeatWidth = grid.beatWidth
        testCase.mouseWheel(input, tickX, input.height / 2, 0, 120, Qt.NoButton, Qt.NoModifier)
        testCase.verify(testCase.waitForNative(function() { return grid.beatWidth > oldBeatWidth }, 3000),
               "the velocity plot routes a real wheel zoom into the shared camera")
        testCase.verify(Math.abs(anchoredTick * grid.beatWidth / grid.ticksPerBeat
                        - grid.cameraScrollX - tickX)
               <= 1 / testCase.devicePixelRatioFor(page),
               "a real velocity wheel holds its tick under the pointer within one physical pixel")
        testCase.mouseWheel(input, tickX, input.height / 2, 0, -120, Qt.NoButton, Qt.NoModifier)
        testCase.verify(testCase.waitForNative(function() { return grid.beatWidth <= oldBeatWidth }, 3000),
               "the reverse velocity wheel restores the gesture's original time zoom")
        grid.setCameraHScroll(0)
        var velocityBody = testCase.findChild(drawer, "drawerBody_velocity")
        var bodyHeight = velocityBody.height
        var rowCount = testCase.collectByName(page, "velocityNodeFill", []).length
        var textRowCount = ruler.children.filter(function(item) {
            return item.labelText !== undefined
        }).length
        testCase.verify(textRowCount > 0, "the mounted velocity ruler has painted text rows")
        testCase.mouseClick(velocityToggle, velocityToggle.width / 2, velocityToggle.height / 2)
        testCase.tryCompare(velocityBody, "visible", false)
        testCase.compare(testCase.settings.int("editorDrawer.velocityHeight", -1), bodyHeight,
                "hiding velocity retains its requested section height in preferences")
        testCase.mouseClick(velocityToggle, velocityToggle.width / 2, velocityToggle.height / 2)
        testCase.tryCompare(velocityBody, "visible", true)
        testCase.compare(velocityBody.height, bodyHeight,
                "showing velocity restores its requested body height")
        testCase.compare(testCase.collectByName(page, "velocityNodeFill", []).length, rowCount,
                "velocity hide and show retain every painted note row")
        testCase.compare(ruler.children.filter(function(item) {
            return item.labelText !== undefined
        }).length, textRowCount,
        "velocity hide and show retain every ruler text row")
        var first = testCase.velocityHandleFor(notes[0].id)
        var later = testCase.velocityHandleFor(notes[1].id)
        var outside = testCase.velocityHandleFor(notes[2].id)
        testCase.verify(first && later && outside && first.selected && later.selected
               && !outside.selected, "the drawn velocity handles retain the exact drag selection")
        var pressX = first.x + VelocityInput.velocityPlotOrigin(grid)
        var pressY = first.y
        var endY = unlockAtPress
            ? Math.round(pressY - (pressY - later.y) * 7 / 8)
            : later.y
        testCase.verify(pressX > 0 && pressX < input.width
               && pressY > 0 && pressY < input.height
               && endY > 0 && endY < input.height,
               "published handle and intrinsic axis geometry keep the drag inside the plot")
        var before = testCase.revision()
        var original = grid.fetchNoteSummary()
        var pressModifier = unlockAtPress ? Qt.ControlModifier : Qt.NoModifier
        var moveModifier = unlockAtPress ? Qt.NoModifier : Qt.ControlModifier
        testCase.mousePress(input, pressX, pressY, Qt.LeftButton, pressModifier)
        testCase.mouseMove(input, pressX, endY, -1, Qt.LeftButton, moveModifier)
        var quietValue = unlockAtPress ? 105 : 108
        var laterValue = unlockAtPress ? 117 : 116
        testCase.verify(testCase.waitForNative(function() {
            var quiet = testCase.velocityHandleFor(notes[0].id)
            var companion = testCase.velocityHandleFor(notes[1].id)
            return quiet && companion && quiet.preview && companion.preview
                && quiet.value === quietValue && companion.value === laterValue
        }, 3000), (unlockAtPress
            ? "an unlocked press retains the raw seven-step delta after modifier release"
            : "a late modifier preserves the snapped levels captured at press")
            + ": " + JSON.stringify({
                first: testCase.velocityHandleFor(notes[0].id)
                    ? [testCase.velocityHandleFor(notes[0].id).preview, testCase.velocityHandleFor(notes[0].id).value]
                    : null,
                later: testCase.velocityHandleFor(notes[1].id)
                    ? [testCase.velocityHandleFor(notes[1].id).preview, testCase.velocityHandleFor(notes[1].id).value]
                    : null,
                active: model.interactionActive, pressed: [pressX, pressY], target: endY,
                selection: model.selectedCount, axis: model.axisMode
            }))
        testCase.compare(testCase.velocityHandleFor(notes[2].id).preview, false,
                "the outside drawn handle has no held velocity preview")
        testCase.compare(testCase.revision(), before, "the mounted drag holds the document revision")
        testCase.compare(grid.fetchNoteSummary(), original,
                "the mounted preview leaves the published roll note summary unchanged")
        testCase.mouseRelease(input, pressX, endY, Qt.LeftButton, moveModifier)
        testCase.verify(testCase.waitForNative(function() {
            var current = JSON.parse(grid.fetchNoteSummary())
            return current.some(function(note) {
                return note.id === notes[0].id && note.velocity === quietValue && note.selected
            }) && current.some(function(note) {
                return note.id === notes[1].id && note.velocity === laterValue && note.selected
            })
        }, 5000), "the mounted release commits exact selected velocities once")
        testCase.verify(testCase.revision() !== before, "the mounted release advances the document revision")
        var committed = JSON.parse(grid.fetchNoteSummary())
        testCase.compare(committed.find(function(note) { return note.id === notes[2].id }).velocity,
                104, "the outside roll note keeps its literal velocity on release")
        testCase.compare(testCase.velocityHandleFor(notes[0].id).preview, false,
                "the mounted release retires its drawn preview")
        if (unlockAtPress) {
            VelocityInput.mountedVelocityRulerAndPaint(testCase, model, detent, input, grid, notes, 76)
            VelocityInput.mountedRawVelocityGesture(testCase, input, grid, notes)
            VelocityInput.mountedRawVelocityRamp(testCase, input, grid, notes)
            for (var family of [{ slot: 6, snap: 64 }, { slot: 7, snap: 76 }]) {
                testCase.mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2,
                                         Qt.LeftButton)
                testCase.tryCompare(voicePage, "pickerOpen", true)
                var familySearch = testCase.findChild(testCase.selectedSurface(), "voicePickerSearch")
                testCase.verify(testCase.waitForNative(function() {
                    return familySearch && familySearch.activeFocus
                }, 3000), "the real voice picker focuses before a family replacement")
                familySearch.selectAll()
                testCase.keyClick(Qt.Key_0)
                testCase.keyClick(Qt.Key_0)
                testCase.keyClick(Qt.Key_0 + family.slot)
                testCase.tryCompare(voicePage, "pickerHasMatch", true)
                testCase.keyClick(Qt.Key_Return)
                testCase.tryCompare(voicePage, "pickerOpen", false)
                testCase.tryCompare(model, "contextSlot", family.slot)
                testCase.compare(model.axisMode, 1,
                        "the selected wave or noise voice presents its intrinsic axis")
                if (family.slot === 6) {
                    var firstRow = testCase.collectByName(ruler, "velocityGraduation", [])[0]
                    testCase.verify(firstRow, "the staged wave paints its lowest graduation")
                    var waveBounds = detent.mapToItem(drawer, 0, 0)
                    var waveCenter = firstRow.mapToItem(drawer, firstRow.width / 2,
                                                         firstRow.height / 2)
                    testCase.verify(waveCenter.y < waveBounds.y
                           || waveCenter.y > waveBounds.y + detent.height,
                           "the actual wave first graduation stays clear of the bottom detent")
                }
                VelocityInput.mountedVelocityRulerAndPaint(testCase, model, detent, input, grid, notes, family.snap)
                VelocityInput.mountedRawVelocityGesture(testCase, input, grid, notes)
                VelocityInput.mountedRawVelocityRamp(testCase, input, grid, notes)
            }
            var ramp = testCase.findChild(page, "velocityRamp")
            var rampStartX = input.width * 0.6
            var rampEndX = input.width * 0.8
            var rampStartY = input.height * 0.25
            var rampEndY = input.height * 0.4
            var quietRampFrame = testCase.grabImage(capture)
            testCase.mousePress(input, rampStartX, rampStartY, Qt.LeftButton, Qt.ShiftModifier)
            testCase.mouseMove(input, rampEndX, rampEndY, -1, Qt.LeftButton, Qt.ShiftModifier)
            testCase.verify(testCase.waitForNative(function() { return ramp.visible }, 3000),
                   "a real Shift drag paints the velocity ramp preview")
            var rampFrame = testCase.grabImage(capture)
            var rampMid = ramp.mapToItem(capture, ramp.width / 2, ramp.height / 2)
            var rampPixelX = Math.round(rampMid.x * rampFrame.width / capture.width)
            var rampPixelY = Math.round(rampMid.y * rampFrame.height / capture.height)
            var rampInk = Raster.colorChannels(testCase, page.gridPalette.primaryText)
            var liveRampInk = false
            for (var px = rampPixelX - 2; px <= rampPixelX + 2; ++px) {
                for (var py = rampPixelY - 2; py <= rampPixelY + 2; ++py) {
                    if (Raster.pixelDistance(testCase, rampFrame, px, py, rampInk) <= 24
                        && Raster.pixelsDiffer(testCase, quietRampFrame, rampFrame, px, py))
                        liveRampInk = true
                }
            }
            testCase.verify(liveRampInk, "the live ramp paints new semantic edit-preview outline pixels")
            testCase.mouseRelease(input, rampEndX, rampEndY, Qt.LeftButton, Qt.ShiftModifier)
            testCase.tryCompare(ramp, "visible", false)
            var bandStartX = input.width * 0.65
            var bandEndX = input.width * 0.85
            var bandStartY = input.height * 0.55
            var bandEndY = input.height * 0.75
            var restingFrame = testCase.grabImage(capture)
            testCase.mousePress(input, bandStartX, bandStartY, Qt.RightButton)
            testCase.mouseMove(input, bandEndX, bandEndY, -1, Qt.RightButton)
            var bandFrame = Raster.grabUntilDifferent(testCase, capture, restingFrame,
                                                Raster.regionOf(testCase, restingFrame, capture, plot))
            testCase.verify(model.interactionActive,
                   "a real right-band drag owns an active selection gesture")
            var edgeOrigin = input.mapToItem(capture,
                                              bandStartX + 2 / testCase.devicePixelRatioFor(page),
                                              bandStartY)
            var edgeX = Math.round(edgeOrigin.x * bandFrame.width / capture.width)
            var edgeY = Math.round(edgeOrigin.y * bandFrame.height / capture.height)
            var edgeInk = Raster.colorChannels(testCase, page.gridPalette.selectionEdge)
            var paintedEdge = null
            for (var ex = edgeX - 2; ex <= edgeX + 2; ++ex) {
                for (var ey = edgeY - 2; ey <= edgeY + 2; ++ey) {
                    if (Raster.pixelDistance(testCase, bandFrame, ex, ey, edgeInk) <= 16
                        && Raster.pixelsDiffer(testCase, restingFrame, bandFrame, ex, ey))
                        paintedEdge = { x: ex, y: ey }
                }
            }
            testCase.verify(paintedEdge !== null,
                   "the new band boundary paints a semantic dashed edge over the resting plot")
            var midPoint = input.mapToItem(capture, (bandStartX + bandEndX) / 2,
                                           (bandStartY + bandEndY) / 2)
            var midX = Math.round(midPoint.x * bandFrame.width / capture.width)
            var midY = Math.round(midPoint.y * bandFrame.height / capture.height)
            var underlyingFill = [restingFrame.red(midX, midY),
                                  restingFrame.green(midX, midY),
                                  restingFrame.blue(midX, midY)]
            testCase.verify(Raster.pixelDistance(testCase, bandFrame, midX, midY,
                                 Raster.compositedColor(testCase, underlyingFill,
                                                 page.gridPalette.selectionFill)) <= 4
                   && Raster.pixelsDiffer(testCase, restingFrame, bandFrame, midX, midY),
                   "the band interior composites its palette selection fill over the real plot")
            testCase.mouseRelease(input, bandEndX, bandEndY, Qt.RightButton)
            testCase.verify(testCase.waitForNative(function() { return !model.interactionActive }, 3000),
                   "releasing the right-band gesture relinquishes its pointer capture")
            var clearedFrame = testCase.grabImage(capture)
            testCase.verify(!Raster.pixelsDiffer(testCase, restingFrame, clearedFrame, midX, midY)
                   && !Raster.pixelsDiffer(testCase, restingFrame, clearedFrame, paintedEdge.x, paintedEdge.y),
                   "releasing the right band clears both its fill and dashed edge pixels")
            var editGuide = testCase.findChild(testCase.selectedSurface(), "sharedPlayheadEditVelocityGuide")
            var timelineRuler = testCase.findChild(testCase.selectedSurface(), "timelineRulerInput")
            testCase.verify(editGuide && timelineRuler,
                   "the real timeline ruler and shared velocity edit guide are mounted")
            testCase.mouseClick(timelineRuler, grid.beatWidth / 2, timelineRuler.height / 2)
            testCase.verify(testCase.waitForNative(function() { return editGuide.visible }, 3000),
                   "the first ruler click paints the shared edit guide in the velocity plot")
            var guideX = editGuide.guide.contentX
            testCase.mouseClick(timelineRuler, grid.beatWidth * 1.5, timelineRuler.height / 2)
            testCase.verify(testCase.waitForNative(function() {
                return editGuide.guide.contentX !== guideX
            }, 3000), "moving the real edit cursor relocates its painted velocity guide")
            var guideFrame = testCase.grabImage(capture)
            testCase.verify(Raster.paintedColor(testCase, guideFrame, capture, editGuide, page.gridPalette.editCursor),
                   "the moved edit guide paints its semantic cursor ink in the velocity band")
            var beforeStack = JSON.parse(grid.fetchNoteSummary())
            var drawStart = testCase.gridPointFor(notes[0].tick + 8, notes[0].pitch + 1)
            var drawEnd = testCase.gridPointFor(notes[0].tick + 20, notes[0].pitch)
            testCase.verify(drawStart.x > 0 && drawEnd.x < roll.width
                   && drawStart.y > 0 && drawStart.y < roll.height
                   && drawEnd.y > 0 && drawEnd.y < roll.height,
                   "the real roll can draw a stacked note across adjacent pitch rows")
            testCase.mousePress(roll, drawStart.x, drawStart.y, Qt.LeftButton)
            testCase.mouseMove(roll, drawEnd.x, drawEnd.y, -1, Qt.LeftButton)
            testCase.mouseRelease(roll, drawEnd.x, drawEnd.y, Qt.LeftButton)
            var newStack = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
                return note.track === 0 && !beforeStack.some(function(old) {
                    return old.id === note.id
                })
            })
            testCase.verify(newStack.length === 1 && newStack[0].pitch === notes[0].pitch
                   && newStack[0].tick > notes[0].tick
                   && newStack[0].tick < notes[0].tick + notes[0].duration
                   && newStack[0].selected,
                   "drawing in the real roll commits one selected note stacked over the first stem")
            var stackedHandle = testCase.velocityHandleFor(newStack[0].id)
            testCase.verify(stackedHandle, "the stacked roll note paints a velocity handle")
            var stackedRing = testCase.collectByName(page, "velocityNodeRing", []).find(function(ring) {
                return ring.parent.model.noteIdText === String(newStack[0].id)
            })
            testCase.verify(stackedRing && stackedRing.visible,
                   "the stacked velocity node owns a visible selected ring")
            testCase.mousePress(input, stackedHandle.x + VelocityInput.velocityPlotOrigin(grid), stackedHandle.y, Qt.LeftButton)
            var leftStackFrame = testCase.grabImage(capture)
            testCase.verify(Raster.paintedColor(testCase, leftStackFrame, capture, stackedRing,
                                page.gridPalette.selectionRing),
                   "left-pressing the selected stacked velocity node paints highlight ink")
            testCase.mouseRelease(input, stackedHandle.x + VelocityInput.velocityPlotOrigin(grid), stackedHandle.y, Qt.LeftButton)
            testCase.mousePress(input, stackedHandle.x + VelocityInput.velocityPlotOrigin(grid), stackedHandle.y, Qt.RightButton)
            var pressedStackFrame = testCase.grabImage(capture)
            testCase.verify(Raster.paintedColor(testCase, pressedStackFrame, capture, stackedRing,
                                page.gridPalette.selectionRing),
                   "right-pressing the selected stacked velocity node keeps its highlight ink")
            testCase.mouseRelease(input, stackedHandle.x + VelocityInput.velocityPlotOrigin(grid), stackedHandle.y, Qt.RightButton)
            grid.setCameraHScroll(1e9)
            var timelineEndTick = grid.cameraScrollX * grid.ticksPerBeat / grid.beatWidth
            var barsAfterEnd = testCase.collectByName(plot, "velocityGrid", []).filter(function(row) {
                var tick = (row.x + row.width / 2 + grid.cameraScrollX)
                           * grid.ticksPerBeat / grid.beatWidth
                return String(row.fillColor).toLowerCase()
                           === String(page.gridPalette.gridLineBar).toLowerCase()
                    && tick > timelineEndTick && row.x > 3 && row.x < input.width - 8
            })
            testCase.verify(barsAfterEnd.length > 0,
                   "the grid exposes a painted bar after the camera's authoritative timeline end")
            var pastBar = barsAfterEnd[0]
            var gridFrame = testCase.grabImage(capture)
            var pastPoint = pastBar.mapToItem(capture, pastBar.width / 2, input.height * 0.82)
            var pixelX = Math.round(pastPoint.x * gridFrame.width / capture.width)
            var pixelY = Math.round(pastPoint.y * gridFrame.height / capture.height)
            var neighborInk = [gridFrame.red(pixelX + 5, pixelY),
                               gridFrame.green(pixelX + 5, pixelY),
                               gridFrame.blue(pixelX + 5, pixelY)]
            var expectedBarInk = Raster.compositedColor(testCase, neighborInk, page.gridPalette.gridLineBar)
            var pastEndBarPainted = false
            for (var offset = -2; offset <= 2; ++offset) {
                if (Raster.pixelDistance(testCase, gridFrame, pixelX + offset, pixelY, expectedBarInk) <= 16
                    && Raster.pixelDistance(testCase, gridFrame, pixelX + offset, pixelY, neighborInk) > 6)
                    pastEndBarPainted = true
            }
            testCase.verify(pastEndBarPainted,
                   "a bar beyond the authoritative timeline paints palette grid ink against its background")
            grid.setCameraHScroll(0)
            testCase.mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2,
                                     Qt.LeftButton)
            testCase.tryCompare(voicePage, "pickerOpen", true)
            var directSearch = testCase.findChild(testCase.selectedSurface(), "voicePickerSearch")
            testCase.verify(testCase.waitForNative(function() {
                return directSearch && directSearch.activeFocus
            }, 3000), "the real voice picker opens for a PSG-to-direct-sound change")
            directSearch.selectAll()
            testCase.keyClick(Qt.Key_0)
            testCase.keyClick(Qt.Key_0)
            testCase.keyClick(Qt.Key_0)
            testCase.tryCompare(voicePage, "pickerHasMatch", true)
            testCase.keyClick(Qt.Key_Return)
            testCase.tryCompare(voicePage, "pickerOpen", false)
            testCase.verify(testCase.waitForNative(function() {
                return model.contextSlot === 0 && !model.detentsAvailable && !detent.visible
            }, 3000), "changing the staged PSG voice back to direct sound hides its detent")
        }
    }
