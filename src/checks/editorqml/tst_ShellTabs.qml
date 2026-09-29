import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function test_startupRecipes() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "an empty recipe constructs the production shell")
        compare(shell.title, "porydaw", "an empty recipe keeps the generic title")
        compare(tabs().tabCount, 0, "an empty recipe opens no song tabs")
        shell.close()
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
               "the empty shell closes before the next recipe")
        shell.destroy()
        shell = null
        settings.setString("lastProjectDir", bootstrap.projectRoot + "/gone")
        settings.setString("lastSongLabel", "mus_route101")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "a vanished-project recipe constructs the production shell")
        verify(waitForNative(function() {
            return shell.shellPresenter.session.lastSaveError.length > 0
        }, 30000), "a vanished project reports its failed restore")
        compare(shell.title, "porydaw", "a vanished project keeps the generic title")
        compare(tabs().tabCount, 0, "a vanished project opens no phantom song tab")
        shell.close()
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
               "the vanished-project shell closes before the next recipe")
        shell.destroy()
        shell = null
        verify(bootstrap.resetPreferences(), "the project-only recipe begins with an empty store")
        settings.setString("lastProjectDir", bootstrap.projectRoot)
        shell = shellComponent.createObject(null)
        verify(shell !== null, "a project-only recipe constructs the production shell")
        verify(waitForNative(function() { return session().projectOpen }, 30000),
               "a project-only recipe restores its live project")
        compare(shell.title, bootstrap.projectRoot.split("/").pop() + " — porydaw",
                "a project-only restore shows its project title")
        compare(tabs().tabCount, 0, "a project-only restore creates no song tab")
        compare(findChild(shell, "shellStatusText").text,
                "Opened " + bootstrap.projectRoot,
                "a project-only restore publishes Opened on the mounted status bar")
    }

    function test_duplicateRecipeRestoresOrderedTabsWithoutWritingProject() {
        settings.setString("identityRecipeSentinel", "keep this value")
        bootstrap.seedStartupRecipe(bootstrap.projectRoot,
                                    ["mus_route102", "", "mus_route101", "mus_route102",
                                     "mus_littleroot_test", "mus_route101"], "mus_route101")
        var firstPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route102")
        var secondPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var thirdPath = fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test")
        var tablePath = bootstrap.projectRoot + "/sound/song_table.inc"
        var firstBytes = fileProbe.fileBytesBase64(firstPath)
        var secondBytes = fileProbe.fileBytesBase64(secondPath)
        var thirdBytes = fileProbe.fileBytesBase64(thirdPath)
        var tableBytes = fileProbe.fileBytesBase64(tablePath)
        verify(firstBytes.length > 0, "the first saved recipe song is readable before startup")
        verify(secondBytes.length > 0, "the second saved recipe song is readable before startup")
        verify(thirdBytes.length > 0, "the third saved recipe song is readable before startup")
        verify(tableBytes.length > 0, "the saved recipe project table is readable before startup")
        shell = shellComponent.createObject(null)
        verify(waitForNative(function() {
            return tabs().tabCount === 3 && tabOrderIds().length === 3
        }, 30000), "duplicate and empty recipe labels restore exactly three live tabs")
        var ids = tabOrderIds()
        waitForPage(ids[0])
        waitForPage(ids[1])
        waitForPage(ids[2])
        compare(pageOf(ids[0]).session.title, "mus_route102",
                "the first surviving recipe label is the first mounted page")
        compare(pageOf(ids[1]).session.title, "mus_route101",
                "the second surviving recipe label is the second mounted page")
        compare(pageOf(ids[2]).session.title, "mus_littleroot_test",
                "the third surviving recipe label is the third mounted page")
        compare(tabs().selectedId, ids[1],
                "the surviving saved selection activates its exact mounted page")
        compare(settings.string("lastSongLabel", ""), "mus_route101",
                "successful restore preserves the saved selection in preferences")
        compare(settings.string("lastProjectDir", ""), bootstrap.projectRoot,
                "successful restore preserves the saved project path")
        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && shell.sessionStatePersisted
        }, 30000), "the restored clean tabs close and persist their mounted order")
        compare(settings.string("identityRecipeSentinel", ""), "keep this value",
                "opening and closing the shell preserves unrelated preferences")
        compare(fileProbe.fileBytesBase64(firstPath), firstBytes,
                "opening and closing the shell preserves the first song file")
        compare(fileProbe.fileBytesBase64(secondPath), secondBytes,
                "opening and closing the shell preserves the second song file")
        compare(fileProbe.fileBytesBase64(thirdPath), thirdBytes,
                "opening and closing the shell preserves the third song file")
        compare(fileProbe.fileBytesBase64(tablePath), tableBytes,
                "opening and closing the shell preserves the project song table")
    }

    function test_missingSelectionFallsBackToFirstOrderedPage() {
        bootstrap.seedStartupRecipe(bootstrap.projectRoot,
                                    ["mus_route102", "mus_route101"], "mus_gym")
        shell = shellComponent.createObject(null)
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabOrderIds().length === 2
        }, 30000), "the missing-selection recipe restores both listed songs")
        var ids = tabOrderIds()
        waitForPage(ids[0])
        waitForPage(ids[1])
        compare(pageOf(ids[0]).session.title, "mus_route102",
                "a missing selection keeps the first listed page first")
        compare(pageOf(ids[1]).session.title, "mus_route101",
                "a missing selection keeps the second listed page second")
        compare(tabs().selectedId, ids[0],
                "a missing selected label falls back to the first mounted page")
        compare(settings.string("lastSongLabel", ""), "mus_gym",
                "the fallback does not rewrite the original missing selection")
    }

    function test_emptySelectionFallsBackToFirstOrderedPage() {
        bootstrap.seedStartupRecipe(bootstrap.projectRoot,
                                    ["mus_route101", "mus_littleroot_test"], "")
        shell = shellComponent.createObject(null)
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabOrderIds().length === 2
        }, 30000), "the empty-selection recipe restores both listed songs")
        var ids = tabOrderIds()
        waitForPage(ids[0])
        waitForPage(ids[1])
        compare(pageOf(ids[0]).session.title, "mus_route101",
                "an empty selection keeps the first listed page first")
        compare(pageOf(ids[1]).session.title, "mus_littleroot_test",
                "an empty selection keeps the second listed page second")
        compare(tabs().selectedId, ids[0],
                "an empty selected label falls back to the first mounted page")
        compare(settings.string("lastSongLabel", "missing"), "",
                "the fallback does not rewrite the original empty selection")
    }

    function test_emptyOrderedLabelsUseLegacySelectedSong() {
        bootstrap.seedStartupRecipe(bootstrap.projectRoot, ["", ""], "mus_route101")
        shell = shellComponent.createObject(null)
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabOrderIds().length === 1
        }, 30000), "an empty ordered recipe with a selected song restores exactly one tab")
        var ids = tabOrderIds()
        waitForPage(ids[0])
        compare(pageOf(ids[0]).session.title, "mus_route101",
                "the legacy selected song is the exact mounted page")
        compare(tabs().selectedId, ids[0],
                "the legacy selected song is active after startup")
    }

    function test_selectedSongOnlyStartupRecipe() {
        settings.setString("lastProjectDir", bootstrap.projectRoot)
        settings.setString("lastSongLabel", "mus_route101")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "a selected-song-only recipe constructs the production shell")
        verify(waitForNative(function() {
            return session().songOpen || session().lastSaveError.length > 0
        }, 30000), "the selected-song-only recipe opens a real document")
        compare(tabs().tabCount, 1, "a legacy selected song restores one tab")
        compare(tabs().selectedPage.title, "mus_route101",
                "a legacy selected song becomes the active tab")
        waitForPage(tabs().selectedId)
        var songs = session().songDockController().songListPresenter()
        verify(waitForNative(function() { return songs.totalCount > 0 }, 5000),
               "the restored Songs dock listing is ready before checking the selected row")
        verify(songs.selectedSongId >= 0, "the restored song has a visible Songs row")
        compare(songs.selectedSongId, songs.currentSongId,
                "the restored selected song is revealed in the Songs dock")
    }

    function test_missingSongStartupRecipe() {
        settings.setString("lastProjectDir", bootstrap.projectRoot)
        settings.setString("lastSongLabel", "mus_deleted_song")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "a missing-song recipe constructs the production shell")
        verify(waitForNative(function() { return session().projectOpen }, 30000),
               "a missing-song recipe still restores its live project")
        compare(tabs().tabCount, 0, "a deleted recipe song creates no phantom tab")
        compare(shell.title, bootstrap.projectRoot.split("/").pop() + " — porydaw",
                "a deleted recipe song leaves the project title visible")
        compare(settings.string("lastSongLabel", ""), "mus_deleted_song",
                "successful restore does not rewrite the missing-song recipe")
    }

    function test_kStartupRestoresTabsAndFreshCamera() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        tabs().moveTab(ids[1], 0)
        verify(waitForNative(function() {
            return tabOrderIds().join(",") === [ids[1], ids[0]].join(",")
        }, 5000), "the current strip order is different from opening order")
        clickSelectTab(ids[0])
        var grid = gridOf(ids[0])
        var freshScrollY = grid.cameraScrollY
        verify(grid.cameraMaxVScroll > 1, "fixture camera has vertical travel")
        grid.handleWheel(0, freshScrollY < grid.cameraMaxVScroll - 1 ? -120 : 120,
                         0, 0, 0, 0, true, 10, 10)
        verify(waitForNative(function() {
            return Math.abs(gridOf(ids[0]).cameraScrollY - freshScrollY) > 0.5
        }, 5000), "first tab's runtime camera moved before shutdown")

        verify(waitForNative(function() {
            return volumeAxisLabels(ids[0]).indexOf("127") >= 0
        }, 5000), "the initial volume axis shows its full-range maximum")
        var automation = pageOf(ids[0]).session.automationPage()
        verify(automation.openParameterMenu(0, 0, 0), "volume's real range menu opens")
        verify(automation.consumeMenuAction(16), "the 0–64 range is a cosmetic lane change")
        verify(!session().documentDirty, "changing an editor lane preference does not dirty MIDI")
        verify(waitForNative(function() {
            return volumeAxisLabels(ids[0]).indexOf("64") >= 0
        }, 5000), "setting the first tab's editor range updates its rendered value axis")
        clickSelectTab(ids[1])
        verify(waitForNative(function() {
            return volumeAxisLabels(ids[1]).indexOf("64") >= 0
        }, 5000), "setting the editor range propagates to the other tab's value axis")
        clickSelectTab(ids[0])

        verify(waitForNative(function() {
            return session().songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before choosing a category")
        var search = findChild(shell, "songListSearch")
        var sort = findChild(shell, "songListSort")
        var category = findChild(shell, "songListCategory")
        verify(search && sort && category, "the real Songs controls are mounted before close")
        mouseClick(category)
        mouseClick(category.popup.contentItem.itemAtIndex(1))
        var categoryPrefix = session().songDockController().songListPresenter().categoryPrefix()
        verify(categoryPrefix.length > 0, "the selected category has a stored prefix")
        mouseClick(sort)
        mouseClick(sort.popup.contentItem.itemAtIndex(1))
        search.forceActiveFocus()
        for (var key of [Qt.Key_F, Qt.Key_I, Qt.Key_L, Qt.Key_T,
                        Qt.Key_E, Qt.Key_R, Qt.Key_M, Qt.Key_E]) {
            search.forceActiveFocus()
            keyClick(key)
        }
        tryCompare(search, "text", "filterme", 3000)
        var priorWidth = shell.width
        var priorHeight = shell.height
        shell.width += shell.shellPresenter.session.baseFontPx * 2
        shell.height += shell.shellPresenter.session.baseFontPx
        verify(waitForNative(function() {
            return shell.normalFrame && shell.normalFrame.width === shell.width
                && shell.normalFrame.height === shell.height
                && shell.width > priorWidth && shell.height > priorHeight
        }, 5000), "the font-relative resize settles its exact normal-frame fields")
        var savedFrame = shell.normalFrame

        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && shell.sessionStatePersisted
        }, 30000), "the clean host close persists state after releasing its tab pages")
        compare(settings.string("lastSongLabel", ""), "mus_route101",
                "final-close walk retains the previously selected tab")
        compare(settings.string("windowGeometry", ""),
                [savedFrame.x, savedFrame.y, savedFrame.width, savedFrame.height].join(","),
                "host close saves the exact resized normal frame")
        compare(settings.string("songFilterText", ""), "filterme",
                "host close saves the entered Songs search")
        compare(settings.int("songFilterSort", -1), 1,
                "host close saves the chosen Songs sort")
        compare(settings.string("songFilterCategory", ""), categoryPrefix,
                "host close saves the chosen Songs category")

        shell.destroy()
        shell = null
        wait(0)

        shell = shellComponent.createObject(null)
        verify(shell !== null, "a second production shell mounts")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabsRoot() !== null
        }, 30000), "startup reconstructs the prior two-tab recipe")
        var restored = tabOrderIds()
        compare(restored.length, 2)
        waitForPage(restored[0])
        waitForPage(restored[1])
        compare(pageOf(restored[0]).session.title, "mus_littleroot_test")
        compare(pageOf(restored[1]).session.title, "mus_route101")
        compare(tabs().selectedId, restored[1], "startup restores the selected tab")
        compare(shell.title, "mus_route101 — " + bootstrap.projectRoot.split("/").pop()
                + " — porydaw", "restart restores the project and selected-song window title")
        verify(waitForNative(function() {
            return session().songDockController().songListPresenter().totalCount > 0
        }, 5000), "the restored Songs dock catalog is ready before checking its category")
        compare(findChild(shell, "songListSearch").text, "filterme",
                "restart restores the entered search on the mounted control")
        compare(findChild(shell, "songListSort").currentIndex, 1,
                "restart restores the mounted alphabetical sort")
        compare(session().songDockController().songListPresenter().categoryPrefix(), categoryPrefix,
                "restart restores the selected Songs category")
        compare(findChild(shell, "songListCategory").currentIndex, 1,
                "restart restores the mounted category selection")
        fuzzyCompare(gridOf(restored[1]).cameraScrollY, freshScrollY, 0.01,
                     "reopened tab starts with a fresh camera, not a saved camera")
        verify(waitForNative(function() {
            return volumeAxisLabels(restored[1]).indexOf("64") >= 0
        }, 5000), "the selected tab renders its saved editor range after relaunch")
        clickSelectTab(restored[0])
        verify(waitForNative(function() {
            return volumeAxisLabels(restored[0]).indexOf("64") >= 0
        }, 5000), "the sibling tab renders the same editor range after relaunch")
    }
    function test_oFreshTabViewStateDefaults() {
        var ids = openShell(["mus_route101", "mus_route102"])
        var first = gridOf(ids[0])
        var fresh = gridOf(ids[1])
        verify(fresh.renderedNoteCount > 0, "a fresh tab has a valid rendered document")
        compare(fresh.beatWidth, first.beatWidth,
                "a fresh tab uses the default pixels per beat")
        compare(fresh.rowHeight, first.rowHeight,
                "a fresh tab uses the default keyboard row height")
        compare(fresh.cameraScrollX, fresh.cameraMinHScroll,
                "a fresh tab uses the default lead-pad horizontal scroll")
        var defaultScrollY = fresh.cameraScrollY
        var shiftedY = defaultScrollY < fresh.cameraMaxVScroll - 30
            ? defaultScrollY + 30 : defaultScrollY - 30
        fresh.setCameraVScroll(shiftedY)
        verify(Math.abs(fresh.cameraScrollY - defaultScrollY) > 1,
               "the fresh tab camera can move away from its default pitch position")
        fresh.setEditCursorTick(96)
        fresh.openGridMenu(1)
        fresh.activateGridMenuRow(16)
        fresh.openGridMenu(2)
        fresh.activateGridMenuRow(1)
        tabs().setSelectedTabEventsVisible(true)
        verify(fresh.editCursorTick === 96 && fresh.gridSelectionMenuId === 16
                && fresh.tripletGrid && tabs().selectedTabShowsEvents,
               "the closing song has non-default cursor, musical grid and event list")

        var close = closeButton(ids[1])
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(tabs(), "tabCount", 1, 5000)
        verify(waitForNative(function() { return pageOf(ids[1]) === null }, 5000),
               "the previous tab's page is released before reopening its song")
        compare(tabs().tabCount, 1, "closing one song leaves exactly its sibling")
        compare(tabOrderIds().join(","), [ids[0]].join(","),
                "closing one song preserves the sibling's exact strip order")
        compare(tabs().selectedPage.title, "mus_route101",
                "closing one song keeps the sibling's named content")
        verify(!tabOrderIds().includes(ids[1]) && tabs().selectedPage.title !== "mus_route102",
               "the closed song no longer resolves in the named tab strip")
        var closedNameAbsent = !tabOrderIds().includes(ids[1])
            && tabs().selectedPage.title !== "mus_route102"
        verify(gridOf(ids[0]).renderedNoteCount > 0,
               "the surviving sibling retains its rendered document")

        session().openSong("mus_route102")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 || session().lastSaveError.length > 0
        }, 30000), "the closed song reopens" + openDiagnostics(session()))
        compare(tabs().tabCount, 2, "the closed song installs a fresh tab"
                + openDiagnostics(session()))
        var reopenedId = tabs().selectedId
        verify(reopenedId !== ids[1], "reopening a closed song creates a fresh tab")
        waitForPage(reopenedId)
        compare(tabOrderIds().join(","), [ids[0], reopenedId].join(","),
                "the reopened song appends after the surviving sibling")
        compare(tabs().selectedPage.title, "mus_route102",
                "the reopened song publishes its named loaded content")
        verify(closedNameAbsent && tabOrderIds().filter(function(stripId) {
            return pageOf(stripId).session.title === "mus_route102"
        }).length === 1,
        "the closed song leaves the named strip and reopens as exactly one row")
        verify(gridOf(reopenedId).renderedNoteCount > 0,
               "the reopened song has a ready rendered grid")
        var restoredDrawer = surfaceOf(reopenedId).drawerPresenter
        verify(restoredDrawer.velocitySection.visible
               && restoredDrawer.automationSection.visible
               && restoredDrawer.voiceChangesSection.visible,
               "a fresh tab restores all three shared drawer section visibilities")
        compare(settings.int("editorDrawer.velocityHeight", -1), 173,
                "a fresh tab restores the shared Velocity section height")
        compare(settings.int("editorDrawer.automationHeight", -1), 200,
                "a fresh tab restores the shared Automation section height")
        compare(settings.int("editorDrawer.voiceChangesHeight", -1), 200,
                "a fresh tab restores the shared Voice Changes section height")
        compare(settings.string("editorDrawer.activePage", ""), "velocity",
                "a fresh tab restores the shared active drawer page")
        compare(gridOf(reopenedId).beatWidth, first.beatWidth,
                "reopened song uses the canonical default pixels per beat")
        compare(gridOf(reopenedId).rowHeight, first.rowHeight,
                "reopened song uses the canonical default keyboard row height")
        compare(gridOf(reopenedId).cameraScrollX, gridOf(reopenedId).cameraMinHScroll,
                "reopened song homes to its canonical horizontal scroll")

        fuzzyCompare(gridOf(reopenedId).cameraScrollY, defaultScrollY, 0.01,
                     "a fresh tab starts at its song's canonical vertical scroll")
        fresh = gridOf(reopenedId)
        compare(fresh.trackIndex, 0, "a fresh tab selects the first track")
        compare(fresh.editCursorTick, 0, "a fresh tab starts its edit cursor at zero")
        compare(fresh.gridDivisionControlText, "Auto",
                "a fresh tab starts with automatic grid selection")
        verify(!fresh.tripletGrid, "a fresh tab starts with straight grid feel")
        verify(!pageOf(reopenedId).session.showsEvents, "a fresh tab has no event list")
        verify(!tabs().selectedTabShowsEvents,
               "a fresh tab does not display the event list")
    }
}
