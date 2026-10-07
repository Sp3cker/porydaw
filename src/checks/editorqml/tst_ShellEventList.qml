import QtQuick
import QtQuick.Controls
import QtTest

ShellEventListSupport {

    function test_closedRowsAreRebuiltOnOpen() {
        failOnWarning(/QQmlVMEMetaObject|ReferenceError|TypeError|Binding loop/)
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        waitForShellScene()
        const router = shell.shellPresenter
        const session = router.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        const presenter = session.eventListPresenter()
        compare(presenter.visible, false)
        compare(presenter.rowCount, 0)
        compare(presenter.rowHandle(0), null)
        router.activate("view.event_list")
        tryCompare(presenter, "visible", true, 3000)
        let surface = null
        tryVerify(function() {
            surface = findChild(shell.sceneLoader.item, "swiftRollOverlay")
            return surface !== null && findChild(surface, "eventListPage") !== null
        }, 3000)
        const grid = surface.gridModel
        const notes = JSON.parse(grid.fetchNoteSummary())
        let target = null
        let targetRow = -1
        for (let index = 0; index < presenter.rowCount && target === null; ++index) {
            if (presenter.rowType(index) !== 1)
                continue
            const tick = presenter.rowTick(index)
            const pitch = Number(presenter.cellDisplay(index, 3))
            if (pitch >= 127 || notes.some(function(note) {
                return note.tick === tick && note.pitch === pitch + 1
            }))
                continue
            target = notes.find(function(note) {
                return !note.ghost && note.tick === tick && note.pitch === pitch
            }) || null
            if (target !== null)
                targetRow = index
        }
        verify(target !== null, "an unambiguous note can move up without clipping")
        const tick = target.tick
        const pitch = target.pitch
        const chunk = presenter.chunkIndex
        presenter.selectRow(targetRow, Qt.NoModifier)
        tryCompare(presenter, "currentRow", targetRow, 3000)
        const rowsBeforeClose = presenter.rowCount
        const rowHandles = []
        for (let index = 0; index < rowsBeforeClose; ++index)
            rowHandles.push(presenter.rowHandle(index))
        function rowSnapshot() {
            return rowHandles.map(function(row) {
                return [row.c0, row.c1, row.c3]
            })
        }
        const publishedBeforeClose = rowSnapshot()
        router.activate("view.event_list")
        tryCompare(presenter, "visible", false, 3000)
        compare(presenter.rowCount, rowsBeforeClose)
        compare(rowSnapshot(), publishedBeforeClose)
        tryVerify(function() {
            return findChild(surface, "eventListPage") === null
        }, 3000)
        const roll = findChild(surface, "swiftRollInput")
        verify(roll !== null)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        router.activate("roll.select_all")
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === target.id && note.pitch === pitch + 1 && note.selected
            })
        }, 3000)
        wait(0)
        compare(presenter.rowCount, rowsBeforeClose)
        compare(rowSnapshot(), publishedBeforeClose)
        router.activate("view.event_list")
        tryCompare(presenter, "visible", true, 3000)
        compare(presenter.chunkIndex, chunk)
        compare(presenter.currentRow, targetRow)
        let page = null
        tryVerify(function() {
            page = findChild(surface, "eventListPage")
            return page !== null
        }, 3000)
        const table = findChild(page, "eventListTable")
        verify(table !== null)
        tryCompare(table, "rows", presenter.rowCount, 3000)
        let refreshedRow = -1
        for (let index = 0; index < presenter.rowCount; ++index) {
            if (presenter.rowType(index) === 1 && presenter.rowTick(index) === tick
                && presenter.cellDisplay(index, 3) === String(pitch + 1)) {
                refreshedRow = index
                break
            }
        }
        verify(refreshedRow >= 0)
        const cell = cellAt(table, refreshedRow, 3)
        const label = findChild(cell, "eventListCell_" + refreshedRow + "_3")
        verify(label !== null)
        compare(label.text, String(pitch + 1))
    }

    function test_filterAndEditOnMountedPage() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const shellPresenter = shell.shellPresenter
        const session = shellPresenter.session
        verify(!shellPresenter.action("view.event_list").enabled,
               "MIDI Event List is disabled until the selected tab is ready")
        compare(shellPresenter.action("view.event_list").label, "MIDI Event List")
        compare(shellPresenter.viewActionIds[0], "view.event_list",
                "MIDI Event List leads the View menu")
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        waitForShellScene()
        verify(shellPresenter.action("view.event_list").enabled,
               "the ready tab enables MIDI Event List")
        const tab = findChild(shell.sceneLoader.item, "songTab_" + session.songTabs.selectedId)
        verify(tab !== null, "selected song page is present")
        const presenter = session.eventListPresenter()
        compare(presenter.visible, false, "event list is hidden until requested")
        compare(session.songTabs.selectedTabShowsEvents, false)
        shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        tryCompare(presenter, "visible", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(tab, "eventListPage")
            return page !== null
        }, 3000, "the requested event-list page is rendered")
        typographyPage = page
        tryVerify(function() {
            return page.headerFont.pixelSize === presenter.fonts.caption.pixelSize
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
        const rulerMarks = findChild(ruler, "timelineQuickRulerMarks")
        const controls = findChild(surface, "timelineRulerControls")
        const headers = findChild(surface, "timelineQuickTrackHeaders")
        const horizontal = findChild(surface, "timelineHorizontalScrollBar")
        const rollGutter = findChild(surface, "timelineQuickRollGutter")
        const rollPlot = findChild(surface, "timelineQuickRollPlot")
        const rollInput = findChild(surface, "swiftRollInput")
        const rollContent = findChild(surface, "rollContentBand")
        const vertical = findChild(surface, "timelineRollScrollBar")
        verify(band && drawer && ruler && rulerMarks && rulerMarks.list === 2
               && controls && headers && horizontal
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
            return ruler.visible && rulerMarks.visible && controls.visible && headers.visible
                && drawer.visible && horizontal.visible
        }, 3000), "ruler with Grid controls, headers, drawer and scrollbar remain visible")
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
        for (let column = 2; column <= 4; ++column) {
            const numeric = findChild(page, "eventListCell_0_" + column)
            matchesFont(numeric, fonts.tableMono, "numeric table cell " + column)
            compare(numeric.font.letterSpacing, page.tableFont.letterSpacing,
                    "numeric columns keep the mono tracking")
        }
        const lastRow = presenter.rowCount - 1
        table.positionViewAtRow(lastRow, TableView.AlignBottom)
        table.forceLayout()
        tryVerify(function() {
            return table.itemAtCell(Qt.point(0, lastRow)) !== null
                && table.itemAtCell(Qt.point(4, lastRow)) !== null
        }, 3000, "the final event row renders its numeric columns")
        for (const column of [0, 2, 3, 4]) {
            const numeric = findChild(page, "eventListCell_" + lastRow + "_" + column)
            matchesFont(numeric, fonts.tableMono, "final row numeric column " + column)
            compare(numeric.font.letterSpacing, page.tableFont.letterSpacing,
                    "the final event row retains mono tracking")
        }
        table.positionViewAtRow(0, TableView.AlignTop)
        table.forceLayout()
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

}
