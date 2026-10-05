import QtQuick
import QtQuick.Controls
import QtTest

ShellEventListSupport {
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
        let show = null
        tryVerify(function() {
            show = findChild(page, "eventListMenuRow_2")
            return show && show.active && show.itemData.text === "Show voice in voicegroup"
        }, 3000, "program row exposes the rendered voice reveal action")
        mouseClick(show, show.width / 2, show.height / 2)
        tryCompare(voice, "revealRequest", beforeReveal + 1, 3000,
                   "rendered Show voice requests the mounted voicegroup")
        compare(voice.revealSlotId, 0, "track-one program points at voice zero")
        compare(voice.currentSlot, 0, "the voicegroup selects voice zero")
        tryCompare(presenter, "menuOpen", false, 3000)
        tryVerify(function() { return findChild(page, "quickMenuPanelRoot") === null },
                  3000, "the dismissed menu releases the table before another right click")

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
    function test_menuKeyboardNavigation() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const filter = findChild(fixture.page, "eventListFilter")
        verify(filter && filter.enabled, "the rendered filter toolbar control is enabled")
        mouseClick(filter, filter.width / 2, filter.height / 2)
        tryCompare(presenter, "menuOpen", true, 3000)
        let menu = null
        tryVerify(function() {
            menu = findChild(fixture.page, "quickMenuPanelRoot")
            return menu && menu.rowCount === 7
        }, 3000, "the filter menu opens with the seven category rows")
        for (let row = 0; row < menu.rowCount; ++row) {
            const item = menu.rowItem(row)
            verify(item && item.active, "every filter category is interactive")
            compare(item.itemData.checked,
                    (presenter.filterMask & item.itemData.actionId) !== 0,
                    "menu ticks mirror the checked role")
        }
        compare(menu.highlightedRow, -1, "the menu opens without a highlighted row")
        keyClick(Qt.Key_Up)
        tryCompare(menu, "highlightedRow", 6, 3000,
                   "Up with no highlight wraps to the last active row")
        const hovered = menu.rowItem(1)
        mouseMove(hovered, hovered.width / 2, hovered.height / 2)
        tryCompare(menu, "highlightedRow", 1, 3000,
                   "hover highlights the category row")
        mouseMove(fixture.page, fixture.page.width - 1, fixture.page.height - 1)
        keyClick(Qt.Key_M)
        tryCompare(menu, "highlightedRow", 6, 3000,
                   "type-ahead selects the matching category")
        keyClick(Qt.Key_Down)
        tryCompare(menu, "highlightedRow", 0, 3000,
                   "Down wraps onto the first category")
        const mask = presenter.filterMask
        keyClick(Qt.Key_Return)
        tryCompare(presenter, "filterMask", mask ^ 1, 3000,
                   "Return toggles the highlighted category")
        tryCompare(presenter, "menuOpen", true, 3000,
                   "activating a category keeps the session open on a rebuilt model")
        tryVerify(function() {
            const rebuilt = findChild(fixture.page, "quickMenuPanelRoot")
            const row = rebuilt && rebuilt.rowItem(0)
            return rebuilt && row && row.itemData.actionId === 1
                && !row.itemData.checked
        }, 3000, "the rebuilt menu updates the activated category")
        tryCompare(findChild(fixture.page, "quickMenuPanelRoot"), "highlightedRow", 0, 3000,
                   "the rebuilt menu restores the highlight by id")
        const maskBeforeEscape = presenter.filterMask
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "Escape cancels the filter menu without activating")
        compare(presenter.filterMask, maskBeforeEscape,
                "Escape preserves the filter mask after the highlighted category changed")
        const cell = cellAt(fixture.table, 0, 5)
        mouseClick(cell, cell.width / 2, cell.height / 2)
        compare(presenter.currentRow, 0, "a bare Data-cell click selects the original event row")
        compare(fixture.page.currentColumn, 5,
                "the bare Data-cell click makes Data the active event column")
        compare(presenter.editing, false,
                "selecting the event row without editing leaves the cell editor closed")
        mouseClick(filter, filter.width / 2, filter.height / 2)
        tryCompare(presenter, "menuOpen", true, 3000)
        const sourceRow = presenter.currentRow
        const maskBeforePress = presenter.filterMask
        let reopened = null
        tryVerify(function() {
            reopened = findChild(fixture.page, "quickMenuPanelRoot")
            return reopened !== null
        }, 3000, "the reopened filter menu is rendered")
        const pressX = cell.width - 1
        const position = cell.mapToItem(fixture.page, pressX, cell.height / 2)
        verify(position.x < reopened.menuOrigin.x
               || position.x > reopened.menuOrigin.x + reopened.menuWidth
               || position.y < reopened.menuOrigin.y
               || position.y > reopened.menuOrigin.y + reopened.menuHeight,
               "the table-cell press is outside the menu frame")
        mousePress(cell, pressX, cell.height / 2)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "a table-cell press while the menu is open only closes the menu")
        compare(presenter.currentRow, sourceRow,
                "the menu-underlay Data cell press preserves the original event cursor")
        compare(presenter.editing, false,
                "the menu-underlay Data cell press does not open an editor")
        compare(presenter.filterMask, maskBeforePress,
                "the menu-underlay Data cell press activates no filter category")
        mouseRelease(cell, pressX, cell.height / 2)
        compare(presenter.editing, false,
                "the paired release never starts an editor")
    }
    function test_fullFilterMatrixThroughMountedMenu() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const table = fixture.table
        const categories = [1, 2, 4, 8, 16, 32, 64]
        const counts = {}
        for (const bit of categories)
            counts[bit] = 0
        const bitForType = [1, 1, 16, 2, 4, 16, 8, 32, 32, 64, 64]
        const total = presenter.rowCount
        verify(total > 1, "the loaded song exposes real filterable event rows")
        for (let row = 0; row < total - 1; ++row)
            counts[bitForType[presenter.rowType(row)]]++
        compare(categories.reduce(function(sum, bit) { return sum + counts[bit] }, 0),
                total - 1, "every mounted row belongs to exactly one filter category")
        const filter = findChild(fixture.page, "eventListFilter")
        mouseClick(filter, filter.width / 2, filter.height / 2)
        tryCompare(presenter, "menuOpen", true, 3000)
        let expected = total
        for (let index = 0; index < categories.length; ++index) {
            const bit = categories[index]
            let menu = null
            let item = null
            tryVerify(function() {
                menu = findChild(fixture.page, "quickMenuPanelRoot")
                item = menu ? menu.rowItem(index) : null
                return item && item.active && item.itemData.actionId === bit
                    && item.itemData.checked
            }, 3000, "the visible category row is checked before its click")
            const label = item.itemData.text
            mouseClick(item, item.width / 2, item.height / 2)
            expected -= counts[bit]
            tryCompare(presenter, "rowCount", expected, 3000,
                       "hiding " + label + " shrinks the table to its ledger count")
            tryCompare(table, "rows", expected, 3000)
            compare(presenter.filterMask & bit, 0, "the clicked category is excluded")
            compare(presenter.menuOpen, true, "the filter menu survives category toggles")
        }
        compare(presenter.rowCount, 1, "an empty mask leaves only the EOT row")
        compare(presenter.rowKind(0), 2, "the remaining mounted row is the EOT")
        for (let index = 0; index < categories.length; ++index) {
            const bit = categories[index]
            let menu = null
            let item = null
            tryVerify(function() {
                menu = findChild(fixture.page, "quickMenuPanelRoot")
                item = menu ? menu.rowItem(index) : null
                return item && item.active && item.itemData.actionId === bit
                    && !item.itemData.checked
            }, 3000, "the hidden category remains available to restore")
            const label = item.itemData.text
            mouseClick(item, item.width / 2, item.height / 2)
            expected += counts[bit]
            tryCompare(table, "rows", expected, 3000,
                       "restoring " + label + " returns its mounted rows")
        }
        compare(presenter.rowCount, total, "all categories restore every original event row")
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "menuOpen", false, 3000)
    }
    function test_rowMenuRetiresOnContextMoves() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        presenter.selectRow(0, Qt.NoModifier)
        presenter.openRowMenu(0, 0)
        tryCompare(presenter, "menuOpen", true, 3000)
        presenter.selectRow(1, Qt.NoModifier)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "a moved row context retires the row menu")
        presenter.openRowMenu(0, 0)
        tryCompare(presenter, "menuOpen", true, 3000)
        presenter.selectRow(2, Qt.ControlModifier)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "a selection change retires the row menu")
        presenter.openFilterMenu(0, 0)
        presenter.selectRow(3, Qt.NoModifier)
        tryCompare(presenter, "menuOpen", true, 3000,
                   "row changes leave the filter menu open")
        presenter.dismissMenu()
        presenter.openRowMenu(0, 0)
        tryCompare(presenter, "menuOpen", true, 3000)
        const originalChunk = presenter.chunkIndex
        const otherChunk = presenter.chunkIndex === 0 ? 1 : 0
        presenter.setChunk(otherChunk, false)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "a chunk switch retires the row menu")
        presenter.setChunk(originalChunk, false)
        presenter.selectRow(0, Qt.NoModifier)
        presenter.openRowMenu(0, 0)
        tryCompare(presenter, "menuOpen", true, 3000)
        const count = presenter.rowCount
        presenter.addEvent()
        tryCompare(presenter, "rowCount", count + 1, 3000)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "a document edit retires the row menu")
    }
    function test_rowMenuContextThroughRenderedTable() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const page = fixture.page
        let sourceRow = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 3 && presenter.tickString(row) === "0") {
                sourceRow = row
                break
            }
        }
        verify(sourceRow >= 0, "the mounted fixture has its tick-zero control row")
        const first = cellAt(fixture.table, sourceRow, 5)
        mouseClick(first, first.width / 2, first.height / 2, Qt.RightButton)
        tryCompare(presenter, "menuOpen", true, 3000,
                   "right-clicking a row opens its menu on that row")
        compare(presenter.currentRow, sourceRow, "the row menu captures its selected row")
        compare(page.currentColumn, 5,
                "the row menu opens from the original control row's Data column")
        const grid = fixture.session.songTabs.selectedPage.gridPresenter()
        const sourceNotes = grid.fetchNoteSummary()
        const sourceRevision = grid.appliedRevisionText
        const sourceTrack = grid.trackIndex
        verify(grid.renderedNoteCount > 0 && JSON.parse(sourceNotes).some(function(note) {
            return !note.ghost && note.track === sourceTrack
        }), "the original source notes are visible before the raw Event List insertion")
        const beforeCount = presenter.rowCount
        let insert = null
        tryVerify(function() {
            const menu = findChild(page, "quickMenuPanelRoot")
            insert = menu && menu.rowCount > 0 ? menu.rowItem(0) : null
            return insert && insert.active && insert.itemData.text === "Insert event"
        }, 3000, "the Insert row is rendered")
        mouseClick(insert, insert.width / 2, insert.height / 2)
        tryCompare(presenter, "menuOpen", false, 3000)
        compare(presenter.rowCount, beforeCount + 1,
                "activating Insert closes the menu and inserts one event")
        compare(grid.trackIndex, sourceTrack,
                "mounted insertion keeps the roll bound to its original engine owner")
        compare(grid.fetchNoteSummary(), sourceNotes,
                "mounted raw insertion preserves the source note projections")
        verify(grid.appliedRevisionText !== sourceRevision,
               "mounted raw insertion publishes the edited document revision")
        verify(fixture.session.canUndo, "the Insert action is undoable")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "the Insert action has one undo transition")
        compare(presenter.rowCount, beforeCount, "undo restores the previous row count")
        compare(grid.trackIndex, sourceTrack, "raw insertion undo restores the header owner")
        compare(grid.fetchNoteSummary(), sourceNotes, "raw insertion undo restores the visible notes")
        fixture.session.requestRedo()
        verify(waitForNative(function() { return presenter.rowCount === beforeCount + 1 }, 3000),
               "redo restores the inserted row")
        compare(grid.trackIndex, sourceTrack, "raw insertion redo rebinds the header owner")
        compare(grid.fetchNoteSummary(), sourceNotes, "raw insertion redo retains the source note values")
        const target = cellAt(fixture.table, sourceRow === 0 ? 1 : 0, 5)
        mouseClick(target, target.width / 2, target.height / 2, Qt.RightButton)
        tryCompare(presenter, "menuOpen", true, 3000)
        compare(page.currentColumn, 5,
                "the outside-cancel row menu originates from a Data-column cell")
        const selected = presenter.currentRow
        let menu = null
        tryVerify(function() {
            menu = findChild(page, "quickMenuPanelRoot")
            return menu !== null
        }, 3000, "the row menu is mounted")
        verify(page.width - 1 > menu.menuOrigin.x + menu.menuWidth
               || page.height - 1 > menu.menuOrigin.y + menu.menuHeight,
               "the press location lies outside the menu frame")
        mousePress(page, page.width - 1, page.height - 1, Qt.RightButton)
        tryCompare(presenter, "menuOpen", false, 3000,
                   "an outside right press cancels the menu without moving the current row")
        compare(presenter.currentRow, selected)
        mouseRelease(page, page.width - 1, page.height - 1, Qt.RightButton)
        compare(presenter.currentRow, selected,
                "the paired outside right release preserves the original event cursor")
        compare(presenter.menuOpen, false, "the paired right release reopens nothing")
    }
    function test_mountedConductorPromotionRebindsRoll() {
        const fixture = openEventListFixture()
        const presenter = fixture.presenter
        const grid = fixture.session.songTabs.selectedPage.gridPresenter()
        const originalTrack = grid.trackIndex
        const originalNotes = grid.fetchNoteSummary()
        const originalRevision = grid.appliedRevisionText
        const promotedNotes = JSON.parse(originalNotes)
        verify(promotedNotes.length > 0 && promotedNotes.some(function(note) {
            return !note.ghost && note.track === originalTrack
        }), "mounted promotion starts with the original owner's exact visible source note set")
        for (let index = 0; index < promotedNotes.length; ++index)
            promotedNotes[index].track += 1
        const expectedPromotedNotes = JSON.stringify(promotedNotes)
        presenter.setChunk(0, false)
        let sourceRow = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 10 && presenter.isCellEditable(row, 1)) {
                sourceRow = row
                break
            }
        }
        verify(sourceRow >= 0, "the mounted conductor has a retypable raw metadata event")
        const typeCell = cellAt(fixture.table, sourceRow, 1)
        mouseDoubleClickSequence(typeCell, typeCell.width / 2, typeCell.height / 2)
        tryCompare(presenter, "menuOpen", true, 3000)
        let typeMenu = null
        tryVerify(function() {
            typeMenu = findChild(fixture.page, "quickMenuPanelRoot")
            const controlChange = typeMenu && typeMenu.rowItem(3)
            return controlChange && controlChange.active
                && controlChange.itemData.text === "Control change"
        }, 3000, "the rendered Type menu offers the channel control event")
        const controlChange = typeMenu.rowItem(3)
        mouseClick(controlChange, controlChange.width / 2, controlChange.height / 2)
        tryCompare(presenter, "menuOpen", false, 3000)
        compare(grid.trackIndex, originalTrack + 1,
                "the mounted roll follows its old owner to the new engine address")
        compare(grid.fetchNoteSummary(), expectedPromotedNotes,
                "mounted promotion retains every source note ID time pitch velocity and ghost flag at its new owner")
        verify(grid.appliedRevisionText !== originalRevision,
               "conductor promotion publishes a new roll projection")
        fixture.session.requestUndo()
        verify(waitForNative(function() { return fixture.session.canRedo }, 3000),
               "one history undo restores conductor metadata")
        compare(grid.trackIndex, originalTrack, "promotion undo rebinds the original roll owner")
        compare(grid.fetchNoteSummary(), originalNotes, "promotion undo restores original note projections")
        fixture.session.requestRedo()
        verify(waitForNative(function() { return grid.trackIndex === originalTrack + 1 }, 3000),
               "one history redo restores the promoted owner")
        compare(grid.fetchNoteSummary(), expectedPromotedNotes,
                "mounted promotion redo restores every remapped source note value")
    }
}
