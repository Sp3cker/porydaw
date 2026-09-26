import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellEventList"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    property var typographyPage: null
    FontMetrics { id: eventTableMetrics; font: typographyPage ? typographyPage.tableFont : Qt.application.font }
    ShellQmlBootstrap { id: bootstrap }
    SignalSpy { id: copySpy; signalName: "activated" }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }


    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "closing reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "the scene is released")
        }
        copySpy.target = null
        typographyPage = null
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_keyboardSelectionStaysOnMountedEventRows() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        let surface = null
        tryVerify(function() {
            const tab = findChild(shell.sceneLoader.item,
                                  "songTab_" + session.songTabs.selectedId)
            surface = tab ? findChild(tab, "swiftRollOverlay") : null
            return surface && surface.gridModel.renderedNoteCount > 0
        }, 5000, "the mounted roll publishes selectable notes")
        const grid = surface.gridModel
        const roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible)
        const notes = JSON.parse(grid.noteSummary)
        let chosenNote = null
        for (const note of notes) {
            const item = findChild(surface, "gridNote_" + note.id)
            if (!item)
                continue
            const center = item.mapToItem(roll, item.width / 2, item.height / 2)
            if (center.x > 1 && center.y > 1 && center.x < roll.width - 1
                && center.y < roll.height - 1) {
                mouseClick(roll, center.x, center.y)
                chosenNote = note
                break
            }
        }
        verify(chosenNote !== null, "the roll exposes a note for window Copy")
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === chosenNote.id && note.selected
            })
        }, 3000, "a real roll click selects the note before event-list focus")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event list is mounted")
        const presenter = session.eventListPresenter()
        verify(presenter.rowCount >= 4, "event-list fixture has at least four rows")
        page.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(page, "activeFocus", true, 3000, "event list owns keyboard focus")
        presenter.selectRow(0, Qt.NoModifier)
        keyClick(Qt.Key_Down)
        compare(presenter.currentRow, 1, "Down moves the event-row cursor")
        keyClick(Qt.Key_Up)
        compare(presenter.currentRow, 0, "Up moves the event-row cursor")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.isSelected(row), "Select All targets every event row")
        let copyShortcut = null
        for (const delegate of shell.contentItem.children) {
            const objects = delegate.data
            for (const object of objects || []) {
                if (object.objectName === "shellShortcut_roll.copy")
                    copyShortcut = object
            }
        }
        verify(copyShortcut !== null, "window Copy shortcut is mounted")
        copySpy.target = copyShortcut
        copySpy.clear()
        keySequence(StandardKey.Copy)
        compare(copySpy.count, 1, "window Copy runs exactly once under event-list focus")
        const clip = JSON.parse(bootstrap.copiedClipSummary())
        compare(clip[0], 1, "window Copy exports the selected roll track")
        compare(clip[1], 1, "window Copy exports one selected roll note")
        compare(clip[2], chosenNote.pitch, "clipboard retains the selected note pitch")
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.isSelected(row), "Copy does not retarget the event-row selection")
        const playhead = session.playheadPresenter()
        compare(playhead.playing, false)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "event-list focus yields Space to the window transport")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)
        let moveRow = -1
        for (let row = 1; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && presenter.rowKind(row - 1) === 0
                && presenter.isLegalDrop(row, row - 1)
                && presenter.cellDisplay(row, 6) !== presenter.cellDisplay(row - 1, 6)) {
                moveRow = row
                break
            }
        }
        verify(moveRow > 0, "fixture has distinguishable same-tick event neighbors")
        const beforeMoveCount = presenter.rowCount
        const earlierSummary = presenter.cellDisplay(moveRow - 1, 6)
        const movedSummary = presenter.cellDisplay(moveRow, 6)
        presenter.selectRow(moveRow, Qt.NoModifier)
        keyClick(Qt.Key_Up, Qt.AltModifier)
        compare(presenter.cellDisplay(moveRow - 1, 6), movedSummary,
                "Alt+Up moves the selected event ahead of its same-tick neighbor")
        compare(presenter.cellDisplay(moveRow, 6), earlierSummary,
                "the displaced event remains in the next row")
        compare(presenter.rowCount, beforeMoveCount, "reordering preserves the event count")
        const afterMoveNote = JSON.parse(grid.noteSummary).find(function(note) {
            return note.id === chosenNote.id
        })
        verify(afterMoveNote !== undefined && afterMoveNote.selected
               && afterMoveNote.tick === chosenNote.tick
               && afterMoveNote.pitch === chosenNote.pitch,
               "same-tick reorder preserves the unrelated selected roll note")
        let protectedRow = -1
        for (let row = 0; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && presenter.rowTick(row) === chosenNote.tick) {
                protectedRow = row
                break
            }
        }
        verify(protectedRow >= 0, "the selected roll note has an event-list row")
        function uniqueTick(row) {
            const tick = presenter.rowTick(row)
            for (let other = 0; other < presenter.rowCount; ++other) {
                if (other !== row && presenter.rowTick(other) === tick)
                    return false
            }
            return true
        }
        let victim = -1
        for (let row = 0; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && uniqueTick(row)
                && presenter.rowTick(row) !== chosenNote.tick
                && presenter.rowTick(row) !== chosenNote.tick + chosenNote.duration) {
                victim = row
                break
            }
        }
        verify(victim >= 0, "fixture has a deletable raw event")
        presenter.selectRow(victim, Qt.NoModifier)
        const table = findChild(page, "eventListTable")
        verify(table !== null, "the mounted table is available for in-cell editing")
        table.positionViewAtRow(victim, TableView.Contain)
        tryVerify(function() {
            return table.itemAtCell(Qt.point(page.currentColumn, victim)) !== null
        }, 3000, "the selected event cell is rendered before F2")
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000,
                   "F2 opens the focused event cell")
        let editor = null
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "event cell receives text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        compare(editor.selectedText, editor.text,
                "Select All stays in the focused cell while editing")
        verify(presenter.isSelected(victim), "cell Select All leaves the event selection intact")
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "editing", false, 3000)
        tryCompare(page, "activeFocus", true, 3000,
                   "leaving the event cell restores page navigation focus")
        compare(page.navigationEnabled, true)
        let secondVictim = -1
        for (let row = victim + 1; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && uniqueTick(row)
                && presenter.rowTick(row) !== chosenNote.tick
                && presenter.rowTick(row) !== chosenNote.tick + chosenNote.duration) {
                secondVictim = row
                break
            }
        }
        verify(secondVictim > victim, "fixture has two unrelated raw event rows")
        const firstTick = presenter.rowTick(victim)
        const secondTick = presenter.rowTick(secondVictim)
        presenter.selectRow(-1, Qt.NoModifier)
        let firstCell = null
        table.positionViewAtRow(victim, TableView.Contain)
        tryVerify(function() {
            firstCell = table.itemAtCell(Qt.point(0, victim))
            return firstCell !== null
        }, 3000, "first victim is visible for the pointer")
        mouseClick(firstCell, firstCell.width / 2, firstCell.height / 2)
        let secondCell = null
        table.positionViewAtRow(secondVictim, TableView.Contain)
        tryVerify(function() {
            secondCell = table.itemAtCell(Qt.point(0, secondVictim))
            return secondCell !== null
        }, 3000, "second victim is visible for the pointer")
        mouseClick(secondCell, secondCell.width / 2, secondCell.height / 2,
                   Qt.LeftButton, Qt.ControlModifier)
        verify(presenter.isSelected(victim) && presenter.isSelected(secondVictim),
               "Ctrl-click selects both unrelated event rows")
        tryCompare(page, "activeFocus", true, 3000)
        const beforeDelete = presenter.rowCount
        keyClick(Qt.Key_Delete)
        tryCompare(presenter, "rowCount", beforeDelete - 2, 3000,
                   "Delete removes exactly two event rows, not the roll selection")
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.rowTick(row) !== firstTick
                   && presenter.rowTick(row) !== secondTick,
                   "both deleted raw-event ticks are absent from the Event List")
        const survivor = JSON.parse(grid.noteSummary).find(function(note) {
            return note.id === chosenNote.id
        })
        verify(survivor !== undefined && survivor.selected
               && survivor.tick === chosenNote.tick && survivor.pitch === chosenNote.pitch
               && survivor.duration === chosenNote.duration && survivor.duration > 0,
               "event-row Delete preserves the unrelated selected roll note")
    }


    function test_filterAndEditOnMountedPage() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const shellPresenter = shell.shellPresenter
        const session = shellPresenter.session
        verify(!shellPresenter.actionEnabled("view.event_list"),
               "MIDI Event List is disabled until the selected tab is ready")
        compare(shellPresenter.actionLabel("view.event_list"), "MIDI Event List")
        compare(shellPresenter.viewActionIds[0], "view.event_list",
                "MIDI Event List leads the View menu")
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        verify(shellPresenter.actionEnabled("view.event_list"),
               "the ready tab enables MIDI Event List")
        const tab = findChild(shell.sceneLoader.item, "songTab_" + session.songTabs.selectedId)
        verify(tab !== null, "selected song page is present")
        const presenter = session.eventListPresenter()
        compare(presenter.visible, false, "event list is hidden until requested")
        compare(session.songTabs.selectedTabShowsEvents, false)
        shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        tryCompare(presenter, "visible", true, 3000)
        const page = findChild(tab, "eventListPage")
        verify(page !== null, "existing event-list page is rendered")
        typographyPage = page
        tryVerify(function() {
            return page.headerFont.pixelSize === presenter.appearance.headerFont.pixelSize
        }, 3000, "mounted caption follows the current presenter typography")
        function matchesFont(text, role, label) {
            verify(text, label + " is mounted")
            compare(text.font.family, role.family, label + " family")
            compare(text.font.pixelSize, role.pixelSize, label + " pixel size")
            compare(text.font.weight, role.weight, label + " weight")
        }
        const fonts = session.typographyFonts
        for (const button of ["eventListChunk", "eventListFilter",
                               "eventListAdd", "eventListRemove"])
            matchesFont(findChild(page, button + "Text"), fonts.body, button + " text")
        for (const button of ["eventListChunk", "eventListFilter"])
            matchesFont(findChild(page, button + "Arrow"), fonts.body, button + " arrow")
        matchesFont(findChild(page, "eventListColumnHeaderLabel0"), fonts.caption,
                    "column header")
        compare(page.tableFont.family, "Atkinson Hyperlegible Mono",
                "mounted table uses the fork mono face")
        compare(page.controlFont.family, "Atkinson Hyperlegible Next",
                "mounted controls use the fork proportional face")
        compare(page.tableFont.pixelSize, page.controlFont.pixelSize,
                "mono table and control fonts share the body size")
        verify(page.headerFont.pixelSize < page.controlFont.pixelSize,
               "caption is smaller than the mounted body font")
        verify(Math.abs(page.tableFont.letterSpacing + page.headerFont.pixelSize / 26)
               < 1 / 64 + 1e-6,
               "mounted table tracks at minus one twenty-sixth of the base after font quantization")
        const forkWidths = [70, 120, 36, 56, 56, 140]
        for (let column = 0; column < forkWidths.length; ++column) {
            compare(page.persistedColumnWidth(column),
                    Math.max(page.minimumColumnWidth(column),
                             Math.round(page.headerFont.pixelSize * forkWidths[column] / 13)),
                    "mounted column " + column + " derives from the base font")
        }
        compare(page.rowHeight, Math.ceil(eventTableMetrics.height + 6),
                "mounted rows follow the compact mono metrics")
        const surface = findChild(tab, "swiftRollOverlay")
        verify(surface !== null, "editor stays mounted beneath the event list")
        const band = findChild(surface, "swiftRollBand")
        const drawer = findChild(surface, "editorDrawer")
        const ruler = findChild(surface, "timelineQuickRuler")
        const controls = findChild(surface, "timelineRulerControls")
        const headers = findChild(surface, "timelineQuickTrackHeaders")
        const horizontal = findChild(surface, "timelineHorizontalScrollBar")
        const status = findChild(surface, "mouseHintStatus")
        const rollGutter = findChild(surface, "timelineQuickRollGutter")
        const rollPlot = findChild(surface, "timelineQuickRollPlot")
        const rollInput = findChild(surface, "swiftRollInput")
        const rollContent = findChild(surface, "rollContentBand")
        const vertical = findChild(surface, "timelineRollScrollBar")
        verify(band && drawer && ruler && controls && headers && horizontal && status
               && rollGutter && rollPlot && rollInput && rollContent && vertical,
               "editor bands remain addressable when the list replaces the roll")
        verify(waitForNative(function() {
            const location = page.mapToItem(surface, 0, 0)
            return location.x === surface.headersModel.trackHeaderWidth
                && location.y === surface.gridModel.rulerHeight
                && page.width === surface.width - surface.headersModel.trackHeaderWidth
                && page.height === drawer.y - surface.gridModel.rulerHeight
        }, 3000), "event list occupies only the roll band up to the drawer")
        verify(waitForNative(function() {
            return ruler.visible && controls.visible && headers.visible
                && drawer.visible && horizontal.visible && status.visible
        }, 3000), "ruler with Grid controls, headers, drawer, scrollbar and status remain visible")
        verify(waitForNative(function() {
            return !rollGutter.visible && !rollPlot.visible && !rollInput.visible
                && !rollContent.visible && !vertical.externalVisible
        }, 3000), "roll keyboard, plot/input/content and vertical scrollbar hide behind the list")
        const chunk = findChild(page, "eventListChunk")
        verify(waitForNative(function() {
            return chunk && chunk.label === "Chunk 1 — Track 1"
                && presenter.chunkLabels[0] === "Chunk 0 (tempo/meta)"
                && presenter.chunkLabels[2] === "Chunk 2 — Track 2"
        }, 3000), "mus_route101 combo and chunk choices use fork track and conductor labels")
        verify(waitForNative(function() { return page.activeFocus }, 3000),
               "showing the list transfers focus to its keyboard input")
        const rollClip = findChild(surface, "sharedPlayheadRollClip")
        const rollBody = rollClip ? findChild(rollClip, "sharedPlayheadBody") : null
        const editRollGuide = findChild(surface, "sharedPlayheadEditRollGuide")
        const hoverRollGuide = findChild(surface, "sharedPlayheadHoverRollGuide")
        verify(rollClip && rollBody && editRollGuide && hoverRollGuide,
               "ruler triangle and roll playhead/guide segments remain addressable")
        verify(waitForNative(function() {
            return !rollBody.visible && !editRollGuide.available
                && !hoverRollGuide.available && rollClip.available
        }, 3000), "list hides roll playhead body and guides without hiding the ruler triangle")
        const division = findChild(surface, "timelineRulerDivisionControl")
        const feel = findChild(surface, "timelineRulerFeelControl")
        verify(division && feel && division.visible && feel.visible && division.enabled
               && feel.enabled, "Grid division and feel controls stay interactive with the list")
        mouseClick(division)
        verify(waitForNative(function() { return surface.gridModel.gridMenuKind === 1 }, 3000),
               "Grid division opens its ruler menu above the mounted event list")
        surface.gridModel.dismissGridMenu()
        const velocityToggle = findChild(drawer, "drawerToggle_velocity")
        verify(velocityToggle && velocityToggle.visible && velocityToggle.enabled,
               "velocity drawer toggle remains available with the list")
        const velocityWasVisible = surface.drawerPresenter.velocitySection.visible
        mouseClick(velocityToggle)
        verify(waitForNative(function() {
            return surface.drawerPresenter.velocitySection.visible !== velocityWasVisible
        }, 3000), "velocity drawer can expand or collapse while the list is shown")
        verify(waitForNative(function() {
            return page.height === drawer.y - surface.gridModel.rulerHeight
        }, 3000), "event list follows the drawer's changed top edge")
        mouseClick(velocityToggle)
        verify(waitForNative(function() {
            return surface.drawerPresenter.velocitySection.visible === velocityWasVisible
        }, 3000), "velocity drawer returns to its original state")
        tryVerify(function() {
            const item = findChild(shell, "shellAction_view.event_list")
            return item !== null && item.checked && item.enabled
        }, 3000, "the View menu check mirrors the visible event list")
        const table = findChild(page, "eventListTable")
        verify(table !== null, "existing seven-column table is rendered")
        compare(table.columns, 7)
        tryVerify(function() { return table.rows === presenter.rowCount }, 3000,
                  "the seven-column table syncs to the published rows")
        table.forceLayout()
        tryVerify(function() {
            return findChild(page, "eventListRowHeaderLabel") !== null
                && findChild(page, "eventListCell_0_0") !== null
                && findChild(page, "eventListCell_0_1") !== null
        }, 3000, "the visible row header and numeric/text cells are instantiated")
        matchesFont(findChild(page, "eventListRowHeaderLabel"), fonts.caption,
                    "row header")
        matchesFont(findChild(page, "eventListCell_0_0"), fonts.tableMono,
                    "numeric table cell")
        matchesFont(findChild(page, "eventListCell_0_1"), fonts.body,
                    "text table cell")
        table.positionViewAtRow(20, TableView.AlignTop)
        table.forceLayout()
        tryVerify(function() {
            const label = findChild(page, "eventListRowHeaderLabel")
            return table.topRow > 0 && label && Number(label.text) === table.topRow + 1
        }, 3000, "row headers follow the first visible event after vertical scrolling")
        table.positionViewAtRow(0, TableView.AlignTop)
        table.forceLayout()
        tryVerify(function() {
            const label = findChild(page, "eventListRowHeaderLabel")
            return table.topRow === 0 && label && Number(label.text) === 1
        }, 3000, "returning to the first row restores its header")
        const horizontalScroll = findChild(page, "eventListHorizontalScrollBar")
        const summaryLabel = findChild(page, "eventListColumnHeaderLabel6")
        verify(horizontalScroll && summaryLabel,
               "mounted Summary header and horizontal scroll lane are addressable")
        const originalWidth = shell.width
        const fittingWidth = originalWidth + Math.max(0,
            Math.ceil(page.persistedColumnsWidth() + page.summaryMinimumWidth - table.width)) + 1
        shell.width = fittingWidth
        tryVerify(function() { return table.contentWidth <= table.width + 0.5 },
                  3000, "Summary consumes the remaining table width without overflow")
        compare(horizontalScroll.maximum, 0,
                "fitting Summary has no horizontal scroll range")
        compare(summaryLabel.truncated, false,
                "fitting Summary heading is readable without truncation")
        verify(page.columnOffset(6) + page.columnWidth(6) <= table.width + 0.5,
               "fitting Summary right edge stays within the table")
        shell.width = originalWidth - Math.max(120,
            Math.ceil(table.width - page.persistedColumnsWidth() - page.summaryMinimumWidth) + 40)
        tryVerify(function() {
            return page.columnWidth(6) === page.summaryMinimumWidth
                && horizontalScroll.maximum > 0
        }, 3000, "narrowing the window pins Summary and opens the scroll range")
        compare(summaryLabel.truncated, false,
                "minimum Summary column still fits its own label under table overflow")
        shell.width = fittingWidth
        tryCompare(horizontalScroll, "maximum", 0, 3000,
                   "restoring the window removes horizontal overflow")
        verify(presenter.rowCount > 1, "fixture contains editable events")
        compare(presenter.rowKind(presenter.rowCount - 1), 2,
                "end-of-track remains the last row")

        let note = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 1) {
                note = row
                break
            }
        }
        verify(note >= 0, "fixture includes a note-on")
        const beforeTick = presenter.cellDisplay(note, 0)
        const initialRows = presenter.rowCount
        presenter.selectRow(note, Qt.NoModifier)
        compare(presenter.currentRow, note)
        presenter.openFilterMenu(0, 0)
        presenter.activateMenuAction(1)
        compare(presenter.filterMask & 1, 0, "Notes category is excluded")
        tryVerify(function() {
            return presenter.rowCount < initialRows && table.rows === presenter.rowCount
        }, 1000)
        for (let row = 0; row < presenter.rowCount - 1; ++row)
            verify(presenter.rowType(row) !== 1, "notes are hidden by the category filter")
        compare(presenter.rowKind(presenter.rowCount - 1), 2,
                "the end sentinel stays visible under filtering")
        presenter.activateMenuAction(1)
        compare(presenter.filterMask & 1, 1, "Notes category is restored")
        tryVerify(function() {
            for (let row = 0; row < presenter.rowCount - 1; ++row) {
                if (presenter.rowType(row) === 1
                    && presenter.cellDisplay(row, 0) === beforeTick)
                    return true
            }
            return false
        }, 1000)
        let restored = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 1
                && presenter.cellDisplay(row, 0) === beforeTick) {
                restored = row
                break
            }
        }
        presenter.selectRow(restored, Qt.NoModifier)
        compare(presenter.beginEditing(restored, 3), true)
        const oldPitch = Number(presenter.cellDisplay(restored, 3))
        const changedPitch = oldPitch === 127 ? 126 : oldPitch + 1
        compare(presenter.finishEditing(String(changedPitch), true), true)
        tryCompare(presenter, "editing", false)
        compare(presenter.cellDisplay(restored, 3), String(changedPitch),
                "cell edit changed the document-backed table value")
        const cameraX = surface.gridModel.cameraScrollX
        const cameraY = surface.gridModel.cameraScrollY
        shellPresenter.activate("view.event_list")
        tryCompare(presenter, "visible", false)
        verify(waitForNative(function() {
            return rollGutter.visible && rollPlot.visible && rollInput.visible
                && rollContent.visible && vertical.externalVisible
                && rollBody.visible && editRollGuide.available && hoverRollGuide.available
        }, 3000), "hiding the list restores the entire roll and its playhead guides")
        verify(waitForNative(function() { return rollInput.activeFocus }, 3000),
               "hiding the list returns keyboard focus to the roll input")
        compare(surface.gridModel.cameraScrollX, cameraX,
                "showing the event list does not move the horizontal camera")
        compare(surface.gridModel.cameraScrollY, cameraY,
                "showing the event list does not move the vertical camera")
    }

    function test_tickBoundariesThroughMountedEditor() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event list is mounted")
        const presenter = session.eventListPresenter()
        verify(presenter.rowCount >= 3, "fixture has editable rows and an EOT sentinel")
        const table = findChild(page, "eventListTable")
        verify(table !== null, "the mounted table is available for in-cell editing")
        tryCompare(table, "rows", presenter.rowCount, 3000,
                   "EOT fixture rows populate the mounted table before cell lookup")

        function eotLabel() {
            const eotRow = presenter.rowCount - 1
            const cell = table.itemAtCell(Qt.point(1, eotRow))
            if (!cell)
                return null
            for (const child of cell.children) {
                if (child instanceof Text && child.text === "End of track")
                    return child
            }
            return null
        }
        function mountedEotLabel() {
            table.positionViewAtRow(presenter.rowCount - 1, TableView.AlignBottom)
            table.forceLayout()
            tryVerify(function() {
                return table.itemAtCell(Qt.point(1, presenter.rowCount - 1)) !== null
            }, 3000, "the EOT Type cell is instantiated")
            tryVerify(function() { return eotLabel() !== null }, 3000,
                      "the EOT label cell is rendered")
            return eotLabel()
        }
        compare(mountedEotLabel().color, presenter.rowCount % 2 === 0 ? page.tableText
                                                                   : page.tableSecondaryText,
                "the EOT label resolves muted ink for the base stripe or row ink on the alternate stripe")

        let note = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 1) {
                note = row
                break
            }
        }
        verify(note >= 0, "fixture has a note-on row")
        page.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(page, "activeFocus", true, 3000)
        page.currentColumn = 0
        presenter.selectRow(note, Qt.NoModifier)
        compare(presenter.currentRow, note)
        table.positionViewAtRow(note, TableView.Contain)
        tryVerify(function() {
            return table.itemAtCell(Qt.point(0, note)) !== null
        }, 3000, "the tick cell is rendered before F2")
        const originalTick = presenter.tickString(note)
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000, "F2 opens the tick cell")
        let editor = null
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "the tick editor takes text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        const noTick = "4294967295"
        for (let i = 0; i < noTick.length; ++i)
            keyClick(noTick.charCodeAt(i))
        keyClick(Qt.Key_Return)
        verify(presenter.editing, "typed kNoTick keeps the editor open")
        compare(presenter.tickString(note), originalTick,
                "typed kNoTick leaves the displayed tick unchanged")
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "editing", false, 3000)
        tryCompare(page, "activeFocus", true, 3000,
                   "leaving the tick cell restores page navigation focus")
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000, "F2 re-opens the tick cell")
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "the reopened tick editor takes text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        const maxTick = "4294967294"
        for (let i = 0; i < maxTick.length; ++i)
            keyClick(maxTick.charCodeAt(i))
        compare(editor.text, maxTick, "the typed kMaxTick digits replace the cell text")
        keyClick(Qt.Key_Return)
        tryCompare(presenter, "editing", false, 3000,
                   "typed kMaxTick commits and closes the editor")
        let moved = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === maxTick) {
                moved = row
                break
            }
        }
        verify(moved >= 0, "the committed row republishes at kMaxTick")
        compare(presenter.rowType(moved), 1,
                "the kMaxTick row keeps its note-on type")

        tryCompare(page, "activeFocus", true, 3000)
        const beforeDelete = presenter.rowCount
        presenter.selectRow(0, Qt.NoModifier)
        keyClick(Qt.Key_Delete)
        tryCompare(presenter, "rowCount", beforeDelete - 1, 3000,
                   "deleting one row flips the EOT row's stripe parity")
        compare(mountedEotLabel().color, (presenter.rowCount - 1) % 2 === 1 ? page.tableText
                                                                          : page.tableSecondaryText,
                "the flipped stripe parity keeps the muted EOT ink AA against its fill")
    }

    function test_eventListRowsFollowAppliedTheme() {
        settings.setString("theme.mode", "dark-neutral-high")
        settings.setInt("theme.grid-line-contrast", 50)
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event list is mounted")
        verify(session.eventListPresenter().rowCount >= 3,
               "fixture has event rows behind the table")

        const palette = session.palette
        verify(Qt.colorEqual(page.tableBackground, palette.menuBackground),
               "row backgrounds use the theme's item surface, not the roll color")
        verify(Qt.colorEqual(page.tableAlternateBackground, palette.alternateBackground),
               "alternate rows use the theme's alternate item surface")
        verify(Qt.colorEqual(page.tableText, palette.windowText),
               "row text uses the theme's item text")
        verify(Qt.colorEqual(page.tableSelectedBackground, palette.tabSelectedBackground),
               "selected rows use the theme's selection surface")
        verify(Qt.colorEqual(page.headerBackground, palette.chromeBackground),
               "the header band uses chrome")

        settings.setString("theme.mode", "vanilla")
        shell.shellPresenter.restoreAppearance()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla", 3000)
        tryVerify(function() {
            return Qt.colorEqual(page.tableBackground, session.palette.menuBackground)
        }, 3000, "the mounted table rebinds its row background to the new theme")
        verify(Qt.colorEqual(page.tableAlternateBackground, session.palette.alternateBackground),
               "alternate stripes follow the theme swap")

        settings.setString("theme.mode", "dark-neutral-high")
        shell.shellPresenter.restoreAppearance()
        tryCompare(shell.shellPresenter, "themeMode", "dark-neutral-high", 3000)
        tryVerify(function() {
            return Qt.colorEqual(page.tableBackground, session.palette.menuBackground)
        }, 3000, "the mounted table returns to the dark item surface")
    }
    function openEventListFixture() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "event-list fixture loads")
        verify(session.songOpen, session.lastSaveError)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event-list page mounts")
        const table = findChild(page, "eventListTable")
        verify(table, "event-list table mounts")
        return { session: session, page: page, table: table,
                 presenter: session.eventListPresenter() }
    }

    function cellAt(table, row, column) {
        table.positionViewAtRow(row, TableView.Contain)
        table.forceLayout()
        tryVerify(function() {
            return table.itemAtCell(Qt.point(column, row)) !== null
        }, 3000, "the target event cell is rendered")
        return table.itemAtCell(Qt.point(column, row))
    }

    function test_rowMenuActionAndVoiceReveal() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        const table = fixture.table
        let program = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 4 && presenter.tickString(row) === "0") {
                program = row
                break
            }
        }
        verify(program >= 0, "track-one program row is present")
        const voice = fixture.session.voiceListController()
        const beforeReveal = voice.revealRequest
        const source = cellAt(table, program, 0)
        mouseClick(source, source.width / 2, source.height / 2, Qt.RightButton)
        tryCompare(presenter, "menuOpen", true, 3000,
                   "real right release opens the program row menu")
        let menu = null
        tryVerify(function() {
            menu = findChild(page, "quickMenuPanelRoot")
            return menu !== null && menu.rowCount === 7
        }, 3000, "program menu renders all seven fork rows")
        const show = findChild(page, "eventListMenuRow_2")
        verify(show && show.active && show.itemData.text === "Show voice in voicegroup",
               "program row exposes the rendered voice reveal action")
        mouseClick(show, show.width / 2, show.height / 2)
        tryCompare(voice, "revealRequest", beforeReveal + 1, 3000,
                   "rendered Show voice requests the mounted voicegroup")
        compare(voice.revealSlotId, 0, "track-one program points at voice zero")
        compare(voice.currentSlot, 0, "the voicegroup selects voice zero")
        tryCompare(presenter, "menuOpen", false, 3000)

        let movable = -1
        for (let row = 1; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 3 && presenter.rowType(row - 1) === 3
                && presenter.tickString(row) === "0"
                && presenter.cellDisplay(row, 6) !== presenter.cellDisplay(row - 1, 6)
                && presenter.isLegalDrop(row, row - 1)) {
                movable = row
                break
            }
        }
        verify(movable > 0, "fixture offers adjacent same-tick controls")
        const earlier = presenter.cellDisplay(movable - 1, 6)
        const moved = presenter.cellDisplay(movable, 6)
        const movingCell = cellAt(table, movable, 0)
        mouseClick(movingCell, movingCell.width / 2, movingCell.height / 2, Qt.RightButton)
        tryCompare(presenter, "menuOpen", true, 3000)
        let up = null
        tryVerify(function() {
            const currentMenu = findChild(page, "quickMenuPanelRoot")
            up = currentMenu && currentMenu.rowCount === 6 ? currentMenu.rowItem(2) : null
            return up && up.active && up.itemData.text === "Move Event Up (Same Tick)"
        }, 3000, "the rendered move action uses the canonical label")
        const menuWithShortcuts = findChild(page, "quickMenuPanelRoot")
        verify(up.itemData.shortcutText.length > 0, "Move action has a native shortcut")
        compare(menuWithShortcuts.showsShortcuts, true,
                "the Event List allocates a shortcut column")
        let shortcutPainted = false
        for (const child of up.children) {
            if (child.text === up.itemData.shortcutText && child.visible
                && child.width > 0 && child.text.length > 0)
                shortcutPainted = true
        }
        verify(shortcutPainted, "the native Move shortcut is painted beside its menu label")
        mouseClick(up, up.width / 2, up.height / 2)
        tryCompare(presenter, "menuOpen", false, 3000)
        compare(presenter.cellDisplay(movable - 1, 6), moved,
                "menu Move row moves the current event through the canonical command once")
        compare(presenter.cellDisplay(movable, 6), earlier,
                "the displaced neighbor follows the moved row")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "menu move undo reaches document history")
        compare(presenter.cellDisplay(movable - 1, 6), earlier,
                "one undo restores the menu's single reorder")
        compare(presenter.cellDisplay(movable, 6), moved,
                "the displaced event returns after menu undo")

        presenter.selectRow(movable - 1, Qt.NoModifier)
        page.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Down, Qt.AltModifier)
        compare(presenter.cellDisplay(movable, 6), earlier,
                "Alt+Down reaches the same move command")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "shortcut move undo reaches document history")
        compare(presenter.cellDisplay(movable - 1, 6), earlier,
                "one undo restores the shortcut's reorder")
        compare(presenter.cellDisplay(movable, 6), moved,
                "the displaced event returns after shortcut undo")
        const firstSelected = cellAt(table, movable - 1, 0)
        mouseClick(firstSelected, firstSelected.width / 2, firstSelected.height / 2)
        const control = cellAt(table, movable, 0)
        mouseClick(control, control.width / 2, control.height / 2,
                   Qt.LeftButton, Qt.ControlModifier)
        mouseClick(control, control.width / 2, control.height / 2, Qt.RightButton)
        tryCompare(presenter, "menuOpen", true, 3000)
        let deleteRow = null
        tryVerify(function() {
            const currentMenu = findChild(page, "quickMenuPanelRoot")
            deleteRow = currentMenu && currentMenu.rowCount === 6
                        ? currentMenu.rowItem(5) : null
            return deleteRow && deleteRow.itemData.text === "Delete 2 event(s)"
        }, 3000, "two control-clicked raw rows publish the mounted Delete count")
    }

    function test_dragReordersOnlySameTickRows() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        const table = fixture.table
        let sourceRow = -1
        for (let row = 1; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 3 && presenter.rowType(row - 1) === 3
                && presenter.tickString(row) === "0"
                && presenter.isLegalDrop(row, row - 1)
                && presenter.cellDisplay(row, 6) !== presenter.cellDisplay(row - 1, 6)) {
                sourceRow = row
                break
            }
        }
        verify(sourceRow > 0, "the table has draggable same-tick neighbors")
        const earlier = presenter.cellDisplay(sourceRow - 1, 6)
        const moved = presenter.cellDisplay(sourceRow, 6)
        const cell = cellAt(table, sourceRow, 0)
        mousePress(cell, cell.width / 2, cell.height / 2)
        mouseMove(cell, cell.width / 2, -page.rowHeight)
        mouseRelease(cell, cell.width / 2, -page.rowHeight)
        compare(presenter.cellDisplay(sourceRow - 1, 6), moved,
                "real row drag swaps same-tick event neighbors")
        compare(presenter.currentRow, sourceRow - 1,
                "the row drag cursor follows its moved event")
        verify(fixture.session.canUndo, "drag creates an undoable transaction")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "drag undo reaches document history")
        compare(presenter.cellDisplay(sourceRow - 1, 6), earlier,
                "one undo restores the dragged row")
        compare(presenter.cellDisplay(sourceRow, 6), moved,
                "the displaced row returns after drag undo")
        let crossGap = -1
        for (let row = sourceRow + 1; row < presenter.rowCount; ++row) {
            if (presenter.tickString(row) !== "0") {
                crossGap = row
                break
            }
        }
        verify(crossGap > sourceRow && !presenter.isLegalDrop(sourceRow, crossGap),
               "the next tick is not a legal row-drop destination")
        const refused = cellAt(table, sourceRow, 0)
        const dropY = (crossGap - sourceRow + 0.5) * page.rowHeight
        mousePress(refused, refused.width / 2, refused.height / 2)
        mouseMove(refused, refused.width / 2, dropY)
        compare(page.dragDropGap, -1, "cross-tick pointer gap is refused")
        mouseRelease(refused, refused.width / 2, dropY)
        compare(presenter.cellDisplay(sourceRow - 1, 6), earlier,
                "a cross-tick row drop leaves the neighbors in place")
        compare(fixture.session.canRedo, true, "refused drop pushes no undo step")
        compare(presenter.editing, false, "a refused drag does not enter cell editing")
    }
    function test_drawerFocusCommitsAndOwnsDelete() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        const table = fixture.table
        let sourceRow = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 3 && presenter.tickString(row) === "0") {
                sourceRow = row
                break
            }
        }
        verify(sourceRow >= 0, "the mounted fixture exposes its tick-zero control target")
        const moved = presenter.cellDisplay(sourceRow, 6)

        page.forceActiveFocus(Qt.OtherFocusReason)
        page.currentColumn = 0
        presenter.selectRow(sourceRow, Qt.NoModifier)
        cellAt(table, sourceRow, 0)
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000)
        const editor = findChild(page, "eventListTickEditor")
        verify(editor && editor.activeFocus, "F2 focuses the mounted tick editor")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        compare(editor.selectedText, editor.text,
                "Select All replaces the focused tick editor contents")
        keyClick(Qt.Key_6)
        keyClick(Qt.Key_0)
        compare(editor.text, "60", "the edited tick is pending on focus loss")
        const tab = findChild(shell.sceneLoader.item,
                              "songTab_" + fixture.session.songTabs.selectedId)
        const drawer = findChild(tab, "editorDrawer")
        const toggle = drawer ? findChild(drawer, "drawerToggle_velocity") : null
        verify(toggle && toggle.visible, "the drawer has a focusable velocity toggle")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        toggle.forceActiveFocus(Qt.MouseFocusReason)
        tryCompare(toggle, "activeFocus", true, 3000,
                   "the focused velocity drawer control owns active focus")
        tryCompare(presenter, "editing", false, 3000)
        let committed = false
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === "60"
                && presenter.cellDisplay(row, 6) === moved)
                committed = true
        }
        verify(committed, "focus leaving the cell commits its tick without reclaiming focus")
        compare(toggle.activeFocus, true,
                "drawer retains active focus after the tick commit")
        const beforeDelete = presenter.rowCount
        keyClick(Qt.Key_Delete)
        compare(presenter.rowCount, beforeDelete,
                "Delete under drawer focus leaves event rows untouched")
        compare(toggle.activeFocus, true, "drawer retains focus after Delete")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "focus-loss edit has an undo step after drawer Delete")
        let restored = false
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === "0"
                && presenter.cellDisplay(row, 6) === moved)
                restored = true
        }
        verify(restored, "one undo restores the edit; drawer Delete pushed no step")
    }
}
