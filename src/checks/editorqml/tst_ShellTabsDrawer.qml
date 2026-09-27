import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_sharedDrawerCloseAndReopen() {
        var firstId = openShell(["mus_route101"])[0]
        var beforeSecondOpen = JSON.parse(summaryOf(firstId))
        var initialFirstDrawn = drawNote(firstId)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && !JSON.parse(summaryOf(firstId)).some(function(note) {
                    return note.id === initialFirstDrawn.id
                })
                && JSON.parse(summaryOf(firstId)).length === beforeSecondOpen.length
        }, 5000), "the first song unwinds its initial edit before opening a second tab")
        session().openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 || session().lastSaveError.length > 0
        }, 30000), "the clean first song permits opening the second song"
                    + openDiagnostics(session()))
        var closingId = tabs().selectedId
        waitForPage(closingId)
        var path = fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test")
        var bytes = fileProbe.fileFingerprint(path)
        var initialSecondNotes = JSON.parse(summaryOf(closingId))
        var secondDrawn = drawNote(closingId)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && !JSON.parse(summaryOf(closingId)).some(function(note) {
                    return note.id === secondDrawn.id
                })
                && JSON.parse(summaryOf(closingId)).length === initialSecondNotes.length
        }, 5000), "the second song returns to clean before its first close")
        clickSelectTab(firstId)
        var initialFirstNotes = JSON.parse(summaryOf(firstId))
        var firstDrawn = drawNote(firstId)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && !JSON.parse(summaryOf(firstId)).some(function(note) {
                    return note.id === firstDrawn.id
                })
                && JSON.parse(summaryOf(firstId)).length === initialFirstNotes.length
        }, 5000), "the first song returns to clean before the second opens again")
        clickSelectTab(closingId)
        var velocityGrip = findChild(surfaceOf(closingId), "drawerHandle_velocity")
        verify(velocityGrip && velocityGrip.visible, "the shared velocity resize grip is mounted")
        var velocitySection = surfaceOf(closingId).drawerPresenter.velocitySection
        var originalHeight = velocitySection.bodyHeight
        var gripY = velocityGrip.height / 2
        var displacement = session().baseFontPx
        mousePress(velocityGrip, velocityGrip.width / 2, gripY, Qt.LeftButton)
        mouseMove(velocityGrip, velocityGrip.width / 2, gripY + displacement, -1, Qt.LeftButton)
        mouseRelease(velocityGrip, velocityGrip.width / 2, gripY + displacement, Qt.LeftButton)
        var resizedHeight = velocitySection.bodyHeight
        verify(resizedHeight < originalHeight,
               "dragging the real Velocity grip shrinks its mounted body")
        compare(settings.int("editorDrawer.velocityHeight", -1), resizedHeight,
                "the real resize persists the shared velocity section height")
        compare(settings.string("editorDrawer.activePage", ""), "velocity",
                "resizing preserves the selected shared drawer page")
        var surface = surfaceOf(closingId)
        var volumeTab = findChild(surface, "automationParameterTab0")
        verify(volumeTab && volumeTab.text === "Volume",
               "the second tab mounts its real Volume parameter")
        mouseClick(volumeTab, volumeTab.width / 2, volumeTab.height / 2, Qt.RightButton)
        var menu = findChild(surface, "automationMenuPanel")
        var rangeRow = null
        tryVerify(function() {
            if (!menu || !menu.visible) return false
            for (var index = 0; index < menu.rowCount; ++index) {
                var row = menu.rowItem(index)
                if (row && row.model.actionId === 12) rangeRow = row
            }
            return rangeRow && rangeRow.visible
        }, 3000, "the second tab opens the real Volume range menu")
        mouseMove(rangeRow, rangeRow.width / 2, rangeRow.height / 2)
        var submenu = findChild(surface, "automationMenuSubmenu")
        var halfRange = null
        tryVerify(function() {
            if (!submenu || !submenu.visible) return false
            for (var index = 0; index < submenu.rowCount; ++index) {
                var row = submenu.rowItem(index)
                if (row && row.model.actionId === 16) halfRange = row
            }
            return halfRange && halfRange.visible
        }, 3000, "hover exposes a real 0–64 Volume range choice")
        mouseClick(halfRange, halfRange.width / 2, halfRange.height / 2)
        verify(waitForNative(function() {
            return volumeAxisLabels(closingId).indexOf("64") >= 0
        }, 5000), "the second tab paints its changed lane range before close")
        var section = surfaceOf(closingId).drawerPresenter.automationSection
        var firstSection = surfaceOf(firstId).drawerPresenter.automationSection
        shell.shellPresenter.activate("view.automation_drawer")
        compare(section.visible, false,
                "hiding one section retains the other sections and the active page")
        tabs().selectTab(firstId)
        tryCompare(firstSection, "visible", false, 3000,
                   "the hidden section stays hidden when the sibling tab becomes active")
        compare(settings.int("editorDrawer.velocityHeight", -1), resizedHeight,
                "switching tabs retains the resized section preference")
        tabs().selectTab(closingId)
        shell.shellPresenter.activate("file.close_tab")
        tryCompare(tabs(), "tabCount", 1, 5000)
        compare(tabs().selectedId, firstId,
                "closing one tab keeps its sibling and the project bytes")
        compare(fileProbe.fileFingerprint(path), bytes,
                "closing one tab keeps its sibling and the project bytes")
        session().openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabs().selectedId !== closingId
        }, 30000), "the closed song opens on a fresh timeline")
        var reopenedId = tabs().selectedId
        waitForPage(reopenedId)
        compare(surfaceOf(reopenedId).drawerPresenter.automationSection.visible, false,
                "reopening restores the shared drawer state on a fresh timeline")
        compare(surfaceOf(reopenedId).drawerPresenter.velocitySection.visible, true,
                "a fresh tab carries the retained sibling drawer section")
        compare(settings.int("editorDrawer.velocityHeight", -1), resizedHeight,
                "reopening retains the real resized shared section height")
        compare(settings.string("editorDrawer.activePage", ""), "automations",
                "the reopened drawer retains its active page")
        compare(surfaceOf(reopenedId).drawerPresenter.voiceChangesSection.visible, true,
                "reopening retains the third shared drawer section")
        compare(settings.int("editorDrawer.automationHeight", -1), 200,
                "reopening retains the hidden automation section height")
        compare(settings.int("editorDrawer.voiceChangesHeight", -1), 200,
                "reopening retains the Voice Changes section height")
        compare(fileProbe.fileFingerprint(path), bytes,
                "reopening never rewrites the project song bytes")
        var firstNotes = summaryOf(firstId)
        var firstRevision = gridOf(firstId).appliedRevisionText
        var firstPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var firstBytes = fileProbe.fileFingerprint(firstPath)
        var reopenedGrid = gridOf(reopenedId)
        var roll = findChild(surfaceOf(reopenedId), "swiftRollInput")
        var plot = findChild(surfaceOf(reopenedId), "timelineQuickRollPlot")
        var tick = 960
        var scale = reopenedGrid.beatWidth / reopenedGrid.ticksPerBeat
        reopenedGrid.setCameraHScroll(Math.max(0, tick * scale - plot.width / 3))
        for (var zoom = 0; zoom < 10
                && pointFor(reopenedId, tick + reopenedGrid.snapTicks / 4, 60).x >= roll.width;
                ++zoom) {
            mouseWheel(roll, roll.width / 2, roll.height / 2, 0, -120)
        }
        var beforePair = JSON.parse(reopenedGrid.noteSummary)
        var firstRow = Math.ceil(reopenedGrid.cameraScrollY / reopenedGrid.rowHeight) + 2
        var lastRow = Math.floor((reopenedGrid.cameraScrollY + plot.height)
                                 / reopenedGrid.rowHeight) - 2
        var pitches = []
        for (var row = firstRow; row <= lastRow && pitches.length < 2; ++row) {
            var pitch = 127 - row
            if (!beforePair.some(function(note) {
                return note.pitch === pitch && note.tick <= tick
                       && note.tick + note.duration > tick
            })) pitches.push(pitch)
        }
        verify(pitches.length === 2, "the reopened roll offers two free tick-960 pitches")
        for (var i = 0; i < pitches.length; ++i) {
            var point = pointFor(reopenedId, tick + reopenedGrid.snapTicks / 4, pitches[i])
            verify(point.x > 0 && point.x < roll.width && point.y > 0
                   && point.y < roll.height, "the reopened tick-960 note is visible"
                   + " (point=" + point.x + "," + point.y
                   + "; roll=" + roll.width + "x" + roll.height
                   + "; plot=" + plot.width + "x" + plot.height
                   + "; camera=" + reopenedGrid.cameraScrollX + ","
                   + reopenedGrid.cameraScrollY + ")")
            mouseDoubleClickSequence(roll, point.x, point.y, Qt.LeftButton)
            tryVerify(function() {
                return JSON.parse(reopenedGrid.noteSummary).length === beforePair.length + i + 1
            }, 3000, "the reopened roll creates a fresh tick-960 note")
        }
        var pair = JSON.parse(reopenedGrid.noteSummary).filter(function(note) {
            return note.tick === tick && pitches.indexOf(note.pitch) >= 0
                   && !beforePair.some(function(prior) { return prior.id === note.id })
        })
        compare(pair.length, 2, "the reopened song owns both newly drawn tick-960 notes")
        var firstPoint = pointFor(reopenedId, tick + reopenedGrid.snapTicks / 4, pair[0].pitch)
        mouseClick(roll, firstPoint.x, firstPoint.y)
        var secondPoint = pointFor(reopenedId, tick + reopenedGrid.snapTicks / 4, pair[1].pitch)
        mouseClick(roll, secondPoint.x, secondPoint.y, Qt.LeftButton, Qt.ShiftModifier)
        tryVerify(function() {
            return pair.every(function(note) {
                return JSON.parse(reopenedGrid.noteSummary).some(function(current) {
                    return current.id === note.id && current.selected
                })
            })
        }, 3000, "the reopened roll selects both new notes with real pointer input")
        var reopenedSurface = surfaceOf(reopenedId)
        var automationToggle = findChild(reopenedSurface, "drawerToggle_automation")
        mouseClick(automationToggle, automationToggle.width / 2, automationToggle.height / 2)
        var reopenedPlot = null
        tryVerify(function() {
            var page = findChild(reopenedSurface, "automationPage")
            reopenedPlot = findChild(reopenedSurface, "automationPlotInput")
            return page && page.visible && reopenedPlot
                && reopenedPlot.visible && reopenedPlot.width > 0 && reopenedPlot.height > 0
        }, 3000, "the reopened tab remounts its real automation plot after drawer restore")
        verify(waitForNative(function() {
            return volumeAxisLabels(reopenedId).indexOf("64") >= 0
        }, 5000), "the reopened automation page paints the retained shared lane range")
        reopenedPlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(reopenedPlot, "activeFocus", true, 3000,
                   "the reopened tab's automation plot owns the routed keys")
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            return pair.every(function(note) {
                return JSON.parse(reopenedGrid.noteSummary).some(function(current) {
                    return current.id === note.id && current.tick === tick + reopenedGrid.snapTicks
                })
            })
        }, 3000, "reopened-tab Right routes to its newly selected note pair")
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return pair.every(function(note) {
                return JSON.parse(reopenedGrid.noteSummary).some(function(current) {
                    return current.id === note.id && current.pitch === note.pitch + 1
                })
            })
        }, 3000, "reopened-tab Up transposes only the new selected pair")
        compare(summaryOf(firstId), firstNotes,
                "reopened-tab Right and Up leave the first document unchanged")
        compare(gridOf(firstId).appliedRevisionText, firstRevision,
                "reopened-tab keys do not advance the first document revision")
        compare(fileProbe.fileFingerprint(firstPath), firstBytes,
                "reopened-tab keys preserve the first song's saved bytes")
        for (var undo = 0; undo < 8 && session().canUndo; ++undo) {
            var priorRevision = reopenedGrid.appliedRevisionText
            keySequence(StandardKey.Undo)
            verify(waitForNative(function() {
                return reopenedGrid.appliedRevisionText !== priorRevision
            }, 5000), "each routed Undo advances reopened history at step " + undo
                      + " (revision=" + priorRevision
                      + "; canUndo=" + session().canUndo + ")")
        }
        function noteContent(summary) {
            return JSON.parse(summary).map(function(note) {
                return [note.track, note.tick, note.pitch, note.duration,
                        note.velocity, note.ghost]
            }).sort(function(a, b) {
                return JSON.stringify(a).localeCompare(JSON.stringify(b))
            })
        }
        verify(waitForNative(function() {
            return !session().canUndo && !session().documentDirty
                && JSON.stringify(noteContent(summaryOf(reopenedId)))
                   === JSON.stringify(noteContent(JSON.stringify(beforePair)))
        }, 5000), "undoing the reopened pair and routed edits returns its song to clean"
                    + " (canUndo=" + session().canUndo + "; dirty=" + session().documentDirty
                    + "; notes=" + JSON.stringify(noteContent(summaryOf(reopenedId))) + ")")
    }

    function test_sharedAutomationParameterAndTrackFocusAcrossTabs() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        var first = surfaceOf(firstId)
        var second = surfaceOf(secondId)
        if (!second.drawerPresenter.automationSection.visible) {
            var toggle = findChild(second, "drawerToggle_automation")
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        }
        function parameterTab(surface, label) {
            var page = findChild(surface, "automationPage")
            if (!page)
                return null
            for (var index = 0; index < page.pageModel.tabCount; ++index) {
                var tab = findChild(page, "automationParameterTab" + index)
                if (tab && tab.text === label)
                    return tab
            }
            return null
        }
        var tempo = null
        tryVerify(function() {
            tempo = parameterTab(second, "Tempo")
            return tempo && tempo.visible && tempo.enabled
        }, 5000, "the second song mounts its real Tempo parameter label")
        var tempoPress = findChild(tempo, "automationParameterTabPress" + tempo.model.index)
        mouseClick(tempoPress, tempoPress.width / 2, tempoPress.height / 2)
        tryCompare(tempo, "checked", true, 3000,
                   "clicking the second song activates its Tempo lane")
        var firstBaseline = summaryOf(firstId)
        var firstRevision = gridOf(firstId).appliedRevisionText
        var firstBytes = fileProbe.fileFingerprint(
            fileProbe.songPath(bootstrap.projectRoot, "mus_route101"))
        var secondCount = JSON.parse(summaryOf(secondId)).length
        var routedSecond = drawNote(secondId)
        var secondRoll = findChild(second, "swiftRollInput")
        var secondPoint = pointFor(secondId, routedSecond.tick
                                   + gridOf(secondId).snapTicks / 4, routedSecond.pitch)
        mouseClick(secondRoll, secondPoint.x, secondPoint.y)
        var secondPlot = findChild(second, "automationPlotInput")
        secondPlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(secondPlot, "activeFocus", true, 3000,
                   "the second song's active Tempo plot accepts keyboard focus")
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            return JSON.parse(summaryOf(secondId)).some(function(note) {
                return note.id === routedSecond.id
                    && note.tick === routedSecond.tick + gridOf(secondId).snapTicks
            })
        }, 3000, "Right over the second song's Tempo plot moves its selected note")
        compare(summaryOf(firstId), firstBaseline,
                "automation-focused Right in B leaves the first song's notes untouched")
        compare(gridOf(firstId).appliedRevisionText, firstRevision,
                "automation-focused Right in B leaves the first song's revision unchanged")
        compare(fileProbe.fileFingerprint(
            fileProbe.songPath(bootstrap.projectRoot, "mus_route101")), firstBytes,
                "automation-focused Right in B leaves the first song's saved bytes exact")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(secondId)).some(function(note) {
                return note.id === routedSecond.id && note.tick === routedSecond.tick
            })
        }, 5000), "Undo reverses B's routed Right before the clean close")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && JSON.parse(summaryOf(secondId)).length === secondCount
        }, 5000), "B's automation-focused edits unwind to clean before tab switch")
        clickSelectTab(firstId)
        var pan = null
        tryVerify(function() {
            pan = parameterTab(first, "Pan")
            return pan && pan.visible && pan.enabled
        }, 5000, "the first song mounts its real Pan parameter label")
        var panPress = findChild(pan, "automationParameterTabPress" + pan.model.index)
        mouseClick(panPress, panPress.width / 2, panPress.height / 2)
        tryCompare(pan, "checked", true, 3000,
                   "clicking the first song activates its Pan lane")
        var secondBaseline = summaryOf(secondId)
        var secondRevision = gridOf(secondId).appliedRevisionText
        var secondBytes = fileProbe.fileFingerprint(
            fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test"))
        var firstCount = JSON.parse(summaryOf(firstId)).length
        var routedFirst = drawNote(firstId)
        var firstRoll = findChild(first, "swiftRollInput")
        var firstPoint = pointFor(firstId, routedFirst.tick
                                  + gridOf(firstId).snapTicks / 4, routedFirst.pitch)
        mouseClick(firstRoll, firstPoint.x, firstPoint.y)
        var firstPlot = findChild(first, "automationPlotInput")
        firstPlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(firstPlot, "activeFocus", true, 3000,
                   "the first song's active Pan plot accepts keyboard focus")
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return JSON.parse(summaryOf(firstId)).some(function(note) {
                return note.id === routedFirst.id
                    && note.pitch === routedFirst.pitch + 1
            })
        }, 3000, "Up over the first song's Pan plot transposes its selected note")
        compare(summaryOf(secondId), secondBaseline,
                "automation-focused Up in A leaves the second song's notes untouched")
        compare(gridOf(secondId).appliedRevisionText, secondRevision,
                "automation-focused Up in A leaves the second song's revision unchanged")
        compare(fileProbe.fileFingerprint(
            fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test")), secondBytes,
                "automation-focused Up in A leaves the second song's saved bytes exact")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(firstId)).some(function(note) {
                return note.id === routedFirst.id && note.pitch === routedFirst.pitch
            })
        }, 5000), "Undo reverses A's routed Up before tab switching")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && JSON.parse(summaryOf(firstId)).length === firstCount
        }, 5000), "A's automation-focused edits unwind to clean before tab switching")
        clickSelectTab(secondId)
        tryVerify(function() {
            var tab = parameterTab(second, "Tempo")
            return tab && tab.checked
        }, 3000, "A-to-B selection preserves the second song's active Tempo lane")
        clickSelectTab(firstId)
        tryVerify(function() {
            var tab = parameterTab(first, "Pan")
            return tab && tab.checked
        }, 3000, "B-to-A selection restores the first song's active Pan lane")
        var header = findChild(first, "timelineTrackHeadersInput")
        verify(header && first.headersModel.rowHeight > 0,
               "the mounted header exposes the first song's track rows")
        mouseWheel(header, header.width / 3, header.height / 2, 0, -120)
        var trackY = first.headersModel.rowHeight * 1.5 - first.headersModel.scrollY
        verify(trackY > 0 && trackY < header.height,
               "a real header scroll reveals the first song's second track")
        mouseClick(header, header.width / 3, trackY)
        tryCompare(first.gridModel, "trackIndex", 1, 3000,
                   "the real header changes the first song's primary track")
        tryVerify(function() {
            var tab = parameterTab(first, "Pan")
            return tab && tab.checked
        }, 3000, "Pan remains the active lane after the primary-track change")
        var trackOnePage = findChild(first, "automationPage")
        var trackOnePlot = findChild(first, "automationPlotInput")
        verify(trackOnePage && trackOnePlot && trackOnePlot.width > 0
               && trackOnePlot.height > 0 && trackOnePage.pageModel.nodeCount > 0,
               "the new primary track paints its Pan automation lane body")
        var trackOneCount = JSON.parse(summaryOf(firstId)).length
        var trackOneNote = drawNote(firstId)
        verify(trackOneNote.track === 1,
               "the mounted roll creates the new primary track's note")
        var trackOnePoint = pointFor(firstId, trackOneNote.tick
                                     + gridOf(firstId).snapTicks / 4, trackOneNote.pitch)
        mouseClick(findChild(first, "swiftRollInput"), trackOnePoint.x, trackOnePoint.y)
        trackOnePlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(trackOnePlot, "activeFocus", true, 3000,
                   "the new primary track's Pan plot accepts keyboard focus")
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return JSON.parse(summaryOf(firstId)).some(function(note) {
                return note.id === trackOneNote.id && note.track === 1
                    && note.pitch === trackOneNote.pitch + 1
            })
        }, 3000, "Up over track one's Pan plot transposes only its selected note")
        compare(summaryOf(secondId), secondBaseline,
                "track-one Pan routing leaves the other song's notes untouched")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(firstId)).some(function(note) {
                return note.id === trackOneNote.id && note.pitch === trackOneNote.pitch
            })
        }, 5000), "Undo reverses track one's Pan-focused transpose")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return !session().documentDirty && !session().canUndo
                && JSON.parse(summaryOf(firstId)).length === trackOneCount
        }, 5000), "the track-one Pan journey returns the first song to clean")
        clickSelectTab(secondId)
        tryVerify(function() {
            var tab = parameterTab(second, "Tempo")
            return tab && tab.checked
        }, 3000, "the other song still owns Tempo after the first track changes")
        clickSelectTab(firstId)
        tryCompare(first.gridModel, "trackIndex", 1, 3000,
                   "the selected first song restores its primary track after A-to-B-to-A")
        tryVerify(function() {
            var tab = parameterTab(first, "Pan")
            return tab && tab.checked
        }, 3000, "the restored first song presents Pan over its new primary track")
    }
}
