import QtQuick
import QtQuick.Controls
import QtTest

ShellEventListSupport {
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
        const tab = findChild(shell.sceneLoader.item,
                              "songTab_" + fixture.session.songTabs.selectedId)
        const surface = tab ? findChild(tab, "swiftRollOverlay") : null
        verify(surface && surface.gridModel, "the mounted roll owns the document cursor")
        surface.gridModel.setEditCursorTick(100000)
        presenter.selectRow(-1, Qt.NoModifier)
        presenter.addEvent()
        let off = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === "100000") {
                off = row
                break
            }
        }
        verify(off >= 0, "a raw event is added after the fixture's ticks")
        presenter.selectRow(off, Qt.NoModifier)
        presenter.openTypeMenu(0, 0)
        presenter.activateMenuAction(0)
        compare(presenter.rowType(off), 0, "the setup event becomes a note-off")
        presenter.selectRow(off, Qt.NoModifier)
        presenter.addEvent()
        let partner = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === "100000" && row !== off) {
                partner = row
                break
            }
        }
        verify(partner >= 0, "a second event shares the note's tick")
        presenter.selectRow(partner, Qt.NoModifier)
        presenter.openTypeMenu(0, 0)
        presenter.activateMenuAction(1)
        let on = -1
        off = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) !== "100000")
                continue
            if (presenter.rowType(row) === 0)
                off = row
            if (presenter.rowType(row) === 1)
                on = row
        }
        verify(off >= 0 && on === off + 1,
               "the note-off is pinned ahead of its note-on")
        const beforeRun = cellAt(table, on, 0)
        const beforeRunSummary = presenter.cellDisplay(on, 6)
        const beforeRunY = -on * page.rowHeight
        mousePress(beforeRun, beforeRun.width / 2, beforeRun.height / 2)
        mouseMove(beforeRun, beforeRun.width / 2, beforeRunY)
        compare(page.dragDropGap, -1, "a drop before the run start has no legal gap")
        mouseRelease(beforeRun, beforeRun.width / 2, beforeRunY)
        compare(presenter.cellDisplay(on, 6), beforeRunSummary,
                "a drop before the run start refuses the reorder")
        compare(presenter.editing, false, "the before-run release starts no editor")
        const pinnedCell = cellAt(table, off, 0)
        mousePress(pinnedCell, pinnedCell.width / 2, pinnedCell.height / 2)
        mouseMove(pinnedCell, pinnedCell.width / 2, page.rowHeight)
        compare(page.dragDropGap, -1, "the pinned note rejects the pointer gap")
        mouseRelease(pinnedCell, pinnedCell.width / 2, page.rowHeight)
        compare(presenter.rowType(off), 0,
                "a drop across the pinned note refuses the reorder")
        compare(presenter.rowType(on), 1)
        compare(presenter.editing, false, "the pinned release starts no editor")
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
        verify(waitForNative(function() {
            const loader = drawer.sectionLoader(drawer.presenter.focusTarget)
            return loader && loader.item && loader.item.activeFocus
        }, 3000), "the pointer toggle lands on the visible drawer page before explicit control focus")
        toggle.forceActiveFocus(Qt.MouseFocusReason)
        tryCompare(toggle, "activeFocus", true, 3000,
                   "the focused velocity drawer control owns active focus")
        tryCompare(presenter, "editing", false, 3000,
                   "drawer focus loss commits and closes the mounted tick edit transaction")
        verify(findChild(page, "eventListTickEditor") === null,
               "drawer focus loss leaves no active mounted tick editor")
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
    function test_resizedHeaderAndDoubleClickEditor() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        const capturedBasePx = fixture.session.baseFontPx
        const handle = findChild(page, "eventListColumnResizeHandle1")
        verify(handle && handle.visible, "the Type handle is rendered")
        const before = presenter.savedColumnWidth(1)
        const x = handle.width / 2
        const y = handle.height / 2
        mousePress(handle, x, y)
        for (let move = 1; move <= 4; ++move)
            mouseMove(handle, x + move * 10, y)
        mouseRelease(handle, x + 40, y)
        tryVerify(function() {
            return presenter.savedColumnWidth(1) > before + 20
        }, 3000, "a real handle drag widens the persisted column")

        let row = -1
        for (let index = 0; index < presenter.rowCount - 1; ++index) {
            if (presenter.isCellEditable(index, 0)) {
                row = index
                break
            }
        }
        verify(row >= 0, "the mounted table has an editable tick")
        const cell = cellAt(fixture.table, row, 0)
        mouseDoubleClickSequence(cell, cell.width / 2, cell.height / 2)
        tryCompare(presenter, "editing", true, 3000,
                   "double-click opens the tick cell editor")
        let editor = null
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.visible
        }, 3000, "double-click instantiates the real tick editor")
        tickEditorFontInfo.font = editor.font
        compare(tickEditorFontInfo.family, "Atkinson Hyperlegible Mono",
                "the instantiated tick editor resolves the captured mono family")
        verify(Math.abs(editor.font.letterSpacing + capturedBasePx / 26) < 1 / 64 + 1e-6,
               "the instantiated tick editor uses absolute pixel tracking from the base font")
        verify(presenter.finishEditing("", false), "the editor cancels after its open proof")
    }
    function test_chunkWheelAndDrawerFocus() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        const table = fixture.table
        const scrollbar = findChild(page, "eventListVerticalScrollBar")
        verify(scrollbar && scrollbar.maximum > 0,
               "the mounted Event List exceeds its viewport")
        mouseWheel(scrollbar, scrollbar.width / 2, scrollbar.height / 2, 0, -72000)
        tryCompare(table, "contentY", scrollbar.maximum, 3000,
                   "wheel past either end clamps the table")
        mouseWheel(scrollbar, scrollbar.width / 2, scrollbar.height / 2, 0, 144000)
        tryCompare(table, "contentY", 0, 3000,
                   "the reverse wheel clamps at the top of the table")
        const chunkButton = findChild(page, "eventListChunk")
        verify(chunkButton && chunkButton.enabled, "the chunk selector is mounted")
        mouseClick(chunkButton, chunkButton.width / 2, chunkButton.height / 2)
        let menu = null
        tryVerify(function() {
            menu = findChild(page, "quickMenuPanelRoot")
            return menu && menu.rowCount > 1
        }, 3000, "chunk selection opens the rendered choices")
        const target = presenter.chunkIndex === 0 ? 1 : 0
        const choice = menu.rowItem(target)
        verify(choice && choice.active, "the target chunk is selectable")
        mouseClick(choice, choice.width / 2, choice.height / 2)
        tryCompare(presenter, "chunkIndex", target, 3000,
                   "a track selection echoes its chunk through the page")
        compare(presenter.chunk, target)
        tryCompare(table, "rows", presenter.rowCount, 3000,
                   "the table mirrors the chunk's events plus tempo rows and one EOT")
        const last = presenter.rowCount - 1
        verify(presenter.rowKind(last) === 2 && last >= 1,
               "the selected chunk keeps exactly one terminal row")


        const tab = findChild(shell.sceneLoader.item,
                              "songTab_" + fixture.session.songTabs.selectedId)
        const input = findChild(tab, "drawerBarInput")
        verify(input && input.visible, "the drawer bar input is mounted")
        presenter.selectRow(0, Qt.NoModifier)
        const row = presenter.currentRow
        mouseClick(input, input.width / 2, input.height / 2)
        const bar = input.parent
        tryCompare(bar, "activeFocus", true, 3000)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Up)
        compare(presenter.currentRow, row, "drawer focus keeps the event rows put")
        compare(bar.activeFocus, true, "the drawer retains focus through both keys")
    }
    function test_viewStateVisibilityFlag() {
        const fixture = openEventListFixture()
        const session = fixture.session
        const presenter = fixture.presenter
        verify(session.songTabs.selectedTabShowsEvents && presenter.visible,
               "the view state records the event list once visible")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", false, 3000,
                   "applying the hidden event-list flag hides the current tab")
        tryCompare(presenter, "visible", false, 3000)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000,
                   "showing the event list restores the flag")
        tryCompare(presenter, "visible", true, 3000)
    }
}
