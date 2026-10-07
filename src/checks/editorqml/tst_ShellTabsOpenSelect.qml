import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_eventListRowsResumeWithTab() {
        failOnWarning(/QQmlVMEMetaObject|ReferenceError|TypeError|Binding loop/)
        const ids = openShell(["mus_route101", "mus_littleroot_test"])
        tabs().selectTab(ids[0])
        tabs().setSelectedTabEventsVisible(true)
        const surface = surfaceOf(ids[0])
        const presenter = surface.eventListPresenter
        tryCompare(presenter, "visible", true, 3000)
        tryVerify(function() {
            return findChild(surface, "eventListTable") !== null
        }, 3000, "the first tab's event page is mounted before switching")
        const rows = presenter.rowCount
        const firstType = presenter.cellDisplay(0, 1)
        verify(rows > 0, "the first tab initially renders its events")
        tabs().selectTab(ids[1])
        tryCompare(presenter, "visible", false, 3000)
        tryCompare(presenter, "rowCount", 0, 3000,
                   "the background tab releases its event rows")
        tabs().selectTab(ids[0])
        tryCompare(presenter, "visible", true, 3000)
        tryCompare(presenter, "rowCount", rows, 3000)
        let table = null
        tryVerify(function() {
            table = findChild(surface, "eventListTable")
            return table !== null
        }, 3000)
        tryCompare(table, "rows", rows, 3000)
        table.forceLayout()
        table.positionViewAtRow(0, TableView.Contain)
        table.forceLayout()
        tryVerify(function() {
            const cell = table.itemAtCell(Qt.point(1, 0))
            const label = cell ? findChild(cell, "eventListCell_0_1") : null
            return label !== null && label.text === firstType
        }, 3000, "returning to the mounted page restores its rendered events")

        tabs().selectTab(ids[1])
        tabs().setSelectedTabEventsVisible(true)
        tryVerify(function() {
            return findChild(surfaceOf(ids[1]), "eventListPage") !== null
        }, 3000)
        const oldBackgroundSession = pageOf(ids[1]).session
        session().openSong("mus_littleroot_test")
        tabs().selectTab(ids[0])
        verify(waitForNative(function() {
            return pageOf(ids[1]).session !== oldBackgroundSession
        }, 30000), "the background tab replaces its document")
        tryVerify(function() {
            const background = surfaceOf(ids[1])
            return background !== null
                && background.applicationSession === pageOf(ids[1]).session
                && findChild(background, "eventListPage") !== null
        }, 3000, "the replacement background tab mounts its retained event page")
        compare(tabs().selectedId, ids[0])
        compare(presenter.visible, true)
        compare(presenter.rowCount, rows)
        table.forceLayout()
        table.positionViewAtRow(0, TableView.Contain)
        table.forceLayout()
        tryVerify(function() {
            const cell = table.itemAtCell(Qt.point(1, 0))
            const label = cell ? findChild(cell, "eventListCell_0_1") : null
            return label !== null && label.text === firstType
        }, 3000, "background page creation cannot replace selected event content")
    }

    function test_aOpenSwitchAndGeometry() {
        var ids = openShell(["mus_route101", "mus_littleroot_test", "mus_route102"])
        var firstId = ids[0]
        var secondId = ids[1]
        var thirdId = ids[2]
        compare(tabs().tabCount, 3)
        compare(tabOrderIds().join(","), ids.join(","),
                "the strip appends tabs in open order")

        clickSelectTab(firstId)
        verify(tabButtonVisible(thirdId),
               "the three tabs do not fit the window, so the strip geometry is scrolled")

        var root = tabsRoot()
        var stripItem = strip()
        var pagesItem = pages()
        var button = selectButton(firstId)
        var close = closeButton(firstId)
        verify(stripItem && pagesItem && button && close,
               "the strip, pages and first tab controls are mounted")
        verify(stripItem.visible && pagesItem.visible,
               "the strip and the page stack are presented")

        verify(stripItem.x <= 1 && stripItem.y <= 1,
               "the strip starts at the mounted surface origin")
        fuzzyCompare(stripItem.width, root.width, 1.0, "the strip spans the surface width")
        var pagesOrigin = pagesItem.mapToItem(root, 0, 0)
        fuzzyCompare(pagesOrigin.y, stripItem.height, 1.0,
                     "the page stack begins at the strip's bottom edge")
        fuzzyCompare(pagesItem.width, root.width, 1.0,
                     "the page stack spans the surface width")

        var role = session().typographyFonts.body
        var spaces = session().layoutSpaces
        compare(button.font.family, role.family,
                "the tab title inherits the published body family")
        compare(button.font.pixelSize, role.pixelSize,
                "the tab title inherits the published body size")
        compare(button.font.weight, role.weight,
                "the tab title inherits the published Regular body weight")
        compare(root.tabMargin, spaces.half, "tab outer margin uses the half-space token")
        compare(root.tabPadding, spaces.two, "tab inset uses the two-space token")
        compare(Math.round(stripItem.height),
                Math.max(Math.round(tabBodyMetrics.lineSpacing), root.scrollExtent)
                + 2 * spaces.half + 2, "the strip follows the published body metrics")
        compare(Math.round(button.height),
                Math.max(root.closeExtent, Math.round(tabBodyMetrics.height))
                + 2 * spaces.half + 2, "the tab body follows the published body metrics")
        compare(close.width, 20, "the close control keeps its production extent")
        compare(close.height, 20, "the close control keeps its production extent")
        compare(Math.round(close.x), Math.round(button.width) - 21,
                "the close control keeps its production inset")
        compare(Math.round(close.y), Math.floor((button.height - close.height) / 2),
                "the close control stays vertically centered")
        var caption = null
        var texts = collectByName(button, "", []).filter(function(item) {
            return item.text !== undefined && String(item.text) === button.text
        })
        verify(texts.length > 0, "the tab button presents its caption")
        caption = texts[0]
        var captionWidth = caption.contentWidth !== undefined ? caption.contentWidth
                                                             : caption.implicitWidth
        verify(captionWidth > 0, "the caption measures its text")
        var captionLeft = caption.mapToItem(button, 0, 0).x
        verify(captionLeft >= -1, "the tab caption starts inside its tab body")
        verify(captionLeft + captionWidth <= close.x + 1,
               "the tab caption never reaches the close control")

        var controls = [button, close, scrollLeft(), scrollRight()]
        for (var i = 0; i < controls.length; ++i) {
            verify(controls[i], "strip control " + i + " is mounted")
            compare(controls[i].focusPolicy, Qt.NoFocus,
                    "strip control " + i + " never takes grid focus")
        }

        verify(button.checked, "the first tab is the checked tab")
        verify(!selectButton(secondId).checked, "the second tab is not checked")
        clickSelectTab(secondId)
        compare(tabs().selectedId, secondId)
        verify(selectButton(secondId).checked, "the clicked tab becomes checked")
        verify(!selectButton(firstId).checked, "the outgoing tab is unchecked")

        for (var t = 0; t < ids.length; ++t) {
            var page = pageOf(ids[t])
            verify(page, "tab " + ids[t] + " owns its page")
            verify(summaryOf(ids[t]).length > 2, "tab " + ids[t] + " owns its document")
        }
        verify(!pageOf(firstId).visible, "the outgoing tab's page is hidden")
        verify(pageOf(secondId).visible && pageOf(secondId).enabled,
               "the selected tab's page is presented")
        compare(summaryOf(firstId) === summaryOf(secondId), false,
                "sibling tabs never share a document")
        var selectedGrid = surfaceOf(secondId).gridModel
        compare(JSON.stringify(JSON.parse(selectedGrid.fetchNoteSummary())),
                JSON.stringify(JSON.parse(summaryOf(secondId))),
                "the mounted surface publishes the selected page's grid")
    }

    function test_bSelectionRepaintAndGlyph() {
        var ids = openShell(["mus_route101", "mus_littleroot_test", "mus_route102"])
        var firstId = ids[0]
        var secondId = ids[1]
        var thirdId = ids[2]
        clickSelectTab(firstId)
        var firstBodyProbe = regionOf(grabImage(tabsRoot()), tabsRoot(), selectButton(firstId))
        var selectedFrame = grabRegionStable(tabsRoot(), firstBodyProbe)
        verify(selectedFrame.width > 0, "the selected strip composited into an image")
        clickSelectTab(secondId)
        var otherFrame = grabUntilDifferent(tabsRoot(), selectedFrame, firstBodyProbe)
        compare(otherFrame.width, selectedFrame.width, "both frames share one size")
        compare(otherFrame.height, selectedFrame.height, "both frames share one size")

        var firstBody = regionOf(selectedFrame, tabsRoot(), selectButton(firstId))
        var secondBody = regionOf(selectedFrame, tabsRoot(), selectButton(secondId))
        verify(changedPixels(selectedFrame, otherFrame, firstBody, 16) > 16,
               "the deselected tab body repainted")
        verify(changedPixels(selectedFrame, otherFrame, secondBody, 16) > 16,
               "the selected state covers the complete tab body")
        var thirdButton = selectButton(thirdId)
        var thirdRegion = regionOf(selectedFrame, tabsRoot(), thirdButton)
        var stripRegion = regionOf(selectedFrame, tabsRoot(), strip())
        thirdRegion.y0 = Math.max(thirdRegion.y0, stripRegion.y0)
        thirdRegion.y1 = Math.min(thirdRegion.y1, stripRegion.y1)
        compare(changedPixels(selectedFrame, otherFrame, thirdRegion, 1), 0,
                "the untouched tab never repaints")

        var closeItem = closeButton(firstId)
        var closeRegion = regionOf(selectedFrame, tabsRoot(), closeItem)
        var background = [selectedFrame.red(closeRegion.x0 + 2, closeRegion.y0 + 2),
                          selectedFrame.green(closeRegion.x0 + 2, closeRegion.y0 + 2),
                          selectedFrame.blue(closeRegion.x0 + 2, closeRegion.y0 + 2)]
        var glyphPixels = 0
        for (var x = closeRegion.x0 + 4; x <= closeRegion.x1 - 4; ++x) {
            for (var y = closeRegion.y0 + 4; y <= closeRegion.y1 - 4; ++y) {
                if (pixelDistance(selectedFrame, x, y, background) > 24)
                    ++glyphPixels
            }
        }
        verify(glyphPixels > 4, "the close glyph renders inside its control")

        var surface = surfaceOf(secondId)
        var input = findChild(surface, "swiftRollInput")
        var notes = JSON.parse(summaryOf(secondId))
        verify(notes.length > 0, "the selected tab publishes notes")
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            var center = pointFor(secondId, notes[n].tick + notes[n].duration / 2,
                                  notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the selected tab has a note a click can reach")
        var pagesProbe = regionOf(grabImage(tabsRoot()), tabsRoot(), pages())
        var idleFrame = grabRegionStable(tabsRoot(), pagesProbe)
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(secondId)).some(function(note) {
                return note.selected
            })
        }, 5000), "the real roll click selected one note")
        var clickedFrame = grabUntilDifferent(tabsRoot(), idleFrame, pagesProbe)
        var pagesRegion = regionOf(clickedFrame, tabsRoot(), pages())
        verify(changedPixels(idleFrame, clickedFrame, pagesRegion, 4) > 4,
               "the selected page paints its selection inside the page stack")
    }

    function test_cScrollAndGridInput() {
        var ids = openShell(["mus_route101", "mus_littleroot_test", "mus_route102", "mus_gym"])
        var firstId = ids[0]
        var lastId = ids[3]
        compare(tabs().tabCount, 4)

        var narrowed = false
        for (var width = shell.width; width > 320; width -= 40) {
            shell.width = width
            wait(100)
            if (scrollLeft().visible) {
                narrowed = true
                break
            }
        }
        verify(narrowed, "the four tabs overflow the narrowed strip")
        verify(scrollLeft().visible && scrollRight().visible,
               "the overflowing strip exposes both scroll controls")

        verify(tabButtonVisible(lastId), "the selected last tab is revealed")
        verify(!tabButtonVisible(firstId), "the overflowing strip clipped its first tab")
        verify(scrollLeft().enabled, "the strip can scroll toward the first tab")
        revealTab(firstId)
        verify(!scrollLeft().enabled, "the left control disables at the row start")
        verify(!tabButtonVisible(lastId), "scrolling to the start clipped the last tab")
        clickSelectTab(firstId)

        var input = findChild(surfaceOf(firstId), "swiftRollInput")
        var notes = JSON.parse(summaryOf(firstId))
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            var center = pointFor(firstId, notes[n].tick + notes[n].duration / 2,
                                  notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the active tab has a note a click can reach")
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(firstId)).filter(function(note) {
                return note.selected
            }).length === 1
        }, 5000), "the real click selected one grid note")
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(firstId)).filter(function(note) {
                return note.selected
            }).length === 0
        }, 5000), "Escape cleared the grid selection")
        var drawn = drawNote(firstId)
        verify(drawn.id !== undefined, "a real pointer drag drew in the narrowed roll")

        revealTab(lastId)
        verify(!scrollRight().enabled, "the right control disables at the row end")
        clickSelectTab(lastId)
        compare(tabs().selectedId, lastId)
        verify(pageOf(lastId).visible, "the last tab's page is presented")
        shell.width = 1100
        wait(100)
    }

    function test_dOpenIndependentWorkspace() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        compare(tabs().tabCount, 2)
        compare(tabs().selectedId, secondId)
        compare(tabOrderIds().join(","), ids.join(","),
                "the appended tab keeps the open tab's row")
        compare(summaryOf(firstId) === summaryOf(secondId), false,
                "the appended tab never presents the open tab's document")
        verify(!pageOf(firstId).visible, "the outgoing tab's page is hidden")
        verify(pageOf(secondId).visible && pageOf(secondId).enabled,
               "the appended tab's page is presented")
        verify(pageOf(firstId) !== pageOf(secondId), "each tab owns its page")
        compare(pageOf(firstId).session.tabId, firstId, "each row presents its own session")
        compare(pageOf(secondId).session.tabId, secondId, "each row presents its own session")
        compare(pageOf(firstId).session.title, "mus_route101", "a tab keeps its song label")
        compare(pageOf(secondId).session.title, "mus_littleroot_test", "a tab keeps its song label")
        verify(pageOf(firstId).session !== pageOf(secondId).session,
               "sibling rows never share a session")
        var firstSurface = surfaceOf(firstId)
        var secondSurface = surfaceOf(secondId)
        verify(firstSurface !== secondSurface, "each tab owns its surface")
        compare(JSON.stringify(JSON.parse(firstSurface.gridModel.fetchNoteSummary())),
                JSON.stringify(JSON.parse(summaryOf(firstId))),
                "the open tab keeps its grid")
        compare(JSON.stringify(JSON.parse(secondSurface.gridModel.fetchNoteSummary())),
                JSON.stringify(JSON.parse(summaryOf(secondId))),
                "the appended tab publishes its own grid")
    }

    function test_eSwitchPreservesState() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        clickSelectTab(firstId)

        var firstBeforeEdit = summaryOf(firstId)
        var drawn = drawNote(firstId)
        var editedSummary = summaryOf(firstId)
        verify(session().canUndo, "the real edit armed the tab's history")
        var grid = gridOf(firstId)
        var gutter = findChild(surfaceOf(firstId), "timelineQuickRollGutter")
        verify(gutter, "the tab's roll gutter is mounted")
        var initialScrollY = grid.cameraScrollY
        var maximumScrollY = grid.cameraMaxVScroll
        verify(maximumScrollY > 1.0, "the roll can scroll vertically")
        grid.handleWheel(0, initialScrollY < maximumScrollY - 1.0 ? -120 : 120,
                         0, 0, 0, 0, true, 10, 10)
        verify(waitForNative(function() {
            return Math.abs(gridOf(firstId).cameraScrollY - initialScrollY) > 0.5
        }, 5000), "the wheel scrolled the tab's camera")
        var cameraX = grid.cameraScrollX
        var cameraY = grid.cameraScrollY
        var firstPage = pageOf(firstId)
        var firstSurface = surfaceOf(firstId)
        var siblingSummary = summaryOf(secondId)

        clickSelectTab(secondId)
        compare(summaryOf(secondId), siblingSummary, "the sibling tab is untouched")
        verify(!session().canUndo, "the sibling tab never inherits the edited history")
        session().requestUndo()
        compare(summaryOf(secondId), siblingSummary,
                "undo in the untouched sibling leaves its notes unchanged")
        verify(!session().documentDirty,
               "undo in the untouched sibling leaves its document clean")
        verify(!pageOf(firstId).visible, "the hidden tab's page is hidden")

        clickSelectTab(firstId)
        verify(pageOf(firstId) === firstPage, "switching back keeps the tab's page")
        verify(surfaceOf(firstId) === firstSurface, "switching back keeps the tab's surface")
        compare(summaryOf(firstId), editedSummary, "switching back keeps the edit")
        verify(session().canUndo, "switching back keeps the tab's history")
        fuzzyCompare(gridOf(firstId).cameraScrollX, cameraX, 0.01,
                     "switching back keeps the camera x")
        fuzzyCompare(gridOf(firstId).cameraScrollY, cameraY, 0.01,
                     "switching back keeps the camera y")
        verify(JSON.parse(editedSummary).some(function(note) {
            return note.id === drawn.id
        }), "the drawn note survived the round trip")
        session().requestUndo()
        verify(waitForNative(function() {
            return summaryOf(firstId) === firstBeforeEdit
        }, 5000), "undo in the edited tab restores only its original notes")
        verify(!session().documentDirty, "undo in the edited tab clears its dirty state")
        clickSelectTab(secondId)
        compare(summaryOf(secondId), siblingSummary,
                "the edited tab's undo never changes the sibling notes")
        verify(!session().documentDirty, "the edited tab's undo leaves the sibling clean")
        clickSelectTab(firstId)
        verify(session().canRedo, "the edited tab retains its own redo history")
    }

    function test_fReorderPreservesIdentities() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        clickSelectTab(firstId)
        var drawn = drawNote(firstId)
        var editedSummary = summaryOf(firstId)
        verify(session().canUndo, "the real edit armed the tab's history")
        var grid = gridOf(firstId)
        var initialScrollY = grid.cameraScrollY
        var maximumScrollY = grid.cameraMaxVScroll
        verify(maximumScrollY > 1.0, "the roll can scroll vertically")
        grid.handleWheel(0, initialScrollY < maximumScrollY - 1.0 ? -120 : 120,
                         0, 0, 0, 0, true, 10, 10)
        verify(waitForNative(function() {
            return Math.abs(gridOf(firstId).cameraScrollY - initialScrollY) > 0.5
        }, 5000), "the wheel scrolled the tab's camera")
        var cameraX = grid.cameraScrollX
        var cameraY = grid.cameraScrollY

        var source = selectButton(firstId)
        var destination = selectButton(secondId)
        verify(source && destination, "both strip buttons are mounted")
        var startWindow = source.mapToItem(null, source.width / 2, source.height / 2)
        var finishWindow = destination.mapToItem(null, destination.width / 2,
                                                 destination.height / 2)
        mousePress(source, source.width / 2, source.height / 2, Qt.LeftButton)
        for (var step = 1; step <= 4; ++step) {
            var slideWindow = { x: startWindow.x + (finishWindow.x - startWindow.x) * step / 4,
                                y: startWindow.y + (finishWindow.y - startWindow.y) * step / 4 }
            var slide = destination.mapFromItem(null, slideWindow.x, slideWindow.y)
            mouseMove(destination, slide.x, slide.y, 30, Qt.LeftButton)
        }
        mouseRelease(destination, destination.width / 2, destination.height / 2,
                     Qt.LeftButton)
        verify(waitForNative(function() {
            return tabOrderIds().join(",") === [secondId, firstId].join(",")
        }, 5000), "the pointer drag moved the tab to the dropped index")
        compare(tabs().selectedId, firstId, "the reorder keeps the selection")

        compare(tabOrderIds().join(","), [secondId, firstId].join(","),
                "the strip order is the dropped order")
        compare(summaryOf(firstId), editedSummary, "the moved tab keeps its edit")
        clickSelectTab(firstId)
        verify(session().canUndo, "the moved tab keeps its history")
        fuzzyCompare(gridOf(firstId).cameraScrollX, cameraX, 0.01,
                     "the moved tab keeps its camera x")
        fuzzyCompare(gridOf(firstId).cameraScrollY, cameraY, 0.01,
                     "the moved tab keeps its camera y")
        verify(JSON.parse(summaryOf(firstId)).some(function(note) {
            return note.id === drawn.id
        }), "the drawn note survived the reorder")
        verify(pageOf(firstId).visible && pageOf(secondId) !== null,
               "both pages survive the reorder")
    }
}
