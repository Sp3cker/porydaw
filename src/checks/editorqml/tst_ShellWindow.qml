import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    TabsDrawerProbe { id: projectSwitchFileProbe }
    SignalSpy { id: projectReadySpy; signalName: "projectRootChanged" }

    function test_savedWindowFrameRestoresAcrossShellSessions() {
        bootstrap.resetPreferences()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const screen = Qt.application.screens[0]
        shell.x = screen.virtualX + Math.floor(screen.width / 6)
        shell.y = screen.virtualY + Math.floor(screen.height / 6)
        shell.width = 850
        shell.height = 580
        const frame = [shell.x, shell.y, shell.width, shell.height]
        cleanup()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        compare([shell.x, shell.y, shell.width, shell.height], frame,
                "a saved window frame restores across a fresh shell session")
    }

    function test_offscreenWindowFrameIsIgnored() {
        bootstrap.resetPreferences()
        settings.setString("windowGeometry", "-99999,-99999,850,580")
        shell = intrinsicShellComponent.createObject(null)
        verify(shell !== null)
        const session = shell.shellPresenter.session
        compare(shell.width === session.baseFontPx * 92 && shell.height === session.baseFontPx * 57,
                true, "an offscreen saved frame is ignored")
    }

    function test_maximizedAndDebuggerWindowStateRestores() {
        bootstrap.resetPreferences()
        settings.setString("windowState", "maximized,debugger")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        compare(shell.shellPresenter.windowMaximized && shell.visibility === Window.Maximized,
                true, "the maximized flag restores across a fresh shell session")
        compare(shell.shellPresenter.polyphonyVisible
                && findChild(shell, "shellPolyphonyDock").visible,
                true, "debugger visibility restores with the window state")
    }

    function test_sessionPreferencesRetainForkKeySpellings() {
        bootstrap.resetPreferences()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const transport = shell.shellPresenter.session.transportBarPresenter()
        transport.setFollowPlayhead(false)
        transport.setResonanceSuppression(true)
        transport.commitOutputVolume(72)
        const songs = shell.shellPresenter.session.songDockController().songListPresenter()
        songs.restoreFilters("route", 1, "mus_")
        shell.shellPresenter.polyphonyVisible = true
        cleanup()
        compare(settings.bool("followPlayhead", true) === false
                && settings.bool("dsp.resonanceSuppression", false) === true
                && settings.int("outputVolume", 0) === 72
                && settings.hasValue("windowGeometry") && settings.hasValue("windowState")
                && settings.string("songFilterText", "") === "route"
                && settings.int("songFilterSort", -1) === 1
                && settings.string("songFilterCategory", "") === "mus_"
                && !settings.hasValue("dsp/resonanceSuppression"),
                true, "preferences keep the fork's on-disk key spellings")
    }

    function test_chromeTypographyAndWindowGeometry() {
        bootstrap.resetPreferences()
        shell = intrinsicShellComponent.createObject(null)
        verify(shell !== null, "production window mounts at its natural size")
        const session = shell.shellPresenter.session
        const caption = session.typographyFonts.caption
        const body = session.typographyFonts.body
        const mono = session.typographyFonts.bodyMono
        compare(shell.width, session.baseFontPx * 92, "window width follows fontPx(92)")
        compare(shell.height, session.baseFontPx * 57, "window height follows fontPx(57)")
        compare(shell.chromeTypography.caption.pixelSize, caption.pixelSize,
                "shell role map follows captured session")
        compare(shell.font.pixelSize, body.pixelSize,
                "window font follows captured body role")
        const status = findChild(shell, "shellStatusText")
        const title = findChild(shell, "shellPolyphonyTitle")
        verify(status && title, "status and debugger heading are mounted")
        compare(status.font.family, caption.family, "status uses the caption family")
        compare(status.font.pixelSize, caption.pixelSize, "status uses the caption size")
        compare(status.font.weight, caption.weight, "status uses caption weight")
        compare(title.font.family, body.family, "debugger heading inherits body family")
        compare(title.font.pixelSize, body.pixelSize, "debugger heading inherits body size")
        compare(title.font.weight, body.weight, "debugger heading inherits body weight")
        for (const name of ["shellPolyPcmValue", "shellPolyCgbValue"]) {
            const value = findChild(shell, name)
            compare(value.font.family, mono.family, name + " uses the bodyMono family")
            compare(value.font.pixelSize, mono.pixelSize, name + " uses the bodyMono size")
            compare(value.font.weight, mono.weight, name + " uses bodyMono weight")
        }
        const lost = findChild(shell, "shellPolyLostValue")
        compare(lost.font.family, body.family, "lost notes inherit the body family")
        compare(lost.font.pixelSize, body.pixelSize, "lost notes inherit body size")
        const dock = findChild(shell, "shellPolyphonyDock")
        compare(dock.width, Math.min(session.baseFontPx * 32, shell.width * 0.48),
                "debugger width is bounded by the session base")
    }

    function test_aKeymapNativeSettingsSeeds() {
        settings.setString("keymap.roll·transpose_up", "Ctrl+Alt+U")
        settings.setString("keymap.transport·play_pause", "")
        settings.setString("keymap.roll·velocity_drag", "Shift")
        settings.setString("keymap.velocity·detent_unlock", "")
        settings.synchronize()
        compare(settings.string("keymap.roll·transpose_up", "?"), "Ctrl+Alt+U")
        compare(settings.string("keymap.transport·play_pause", "?"), "")
        compare(settings.string("keymap.roll·velocity_drag", "?"), "Shift")
        compare(settings.string("keymap.velocity·detent_unlock", "?"), "")
        var failures = bootstrap.registryFailures()
        compare(failures.length, 0, "the complete native keymap assertions: " + failures.join("; "))
    }

    function test_bThemeRepairThroughProductionShell() {
        // ThemeLayoutTest::settingsRepair: custom mode is obsolete, 80 survives,
        // and neither obsolete colour key survives restoration.
        settings.setString("theme.mode", "custom")
        settings.setString("theme.primary", "#000000")
        settings.setString("theme.accent", "#FFFFFF")
        settings.setString("theme.grid-line-contrast", "80")
        settings.setString("lastProjectDir", "")
        settings.synchronize()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell restores the seeded native theme")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        compare(shell.shellPresenter.gridLineContrast, 80)
        tryVerify(function() {
            return settings.string("theme.mode", "") === "vanilla"
                && settings.int("theme.grid-line-contrast", -1) === 80
                && !settings.hasValue("theme.primary")
                && !settings.hasValue("theme.accent")
        }, 3000, "another native Settings reader observes repaired persisted keys")
        compare(settings.string("theme.mode", ""), "vanilla")
        compare(settings.int("theme.grid-line-contrast", -1), 80)
        compare(settings.hasValue("theme.primary"), false)
        compare(settings.hasValue("theme.accent"), false)
    }

    function test_xProjectSwitchEmptiesTwoSongWorkspace() {
        const firstPath = bootstrap.projectRoot + "/sound/songs/midi/mus_route101.mid"
        const secondPath = bootstrap.projectRoot + "/sound/songs/midi/mus_littleroot_test.mid"
        compare(projectSwitchFileProbe.fileFingerprint(firstPath), "471:d31e7c4a0a32a53f",
                "the first outgoing song starts with independently pinned MIDI bytes")
        compare(projectSwitchFileProbe.fileFingerprint(secondPath), "425:c27d69bdefcd9207",
                "the second outgoing song starts with independently pinned MIDI bytes")

        const firstId = openTwoSongShell()
        const session = shell.shellPresenter.session
        const secondId = session.songTabs.selectedId
        compare(session.songTabs.tabCount === 2 && firstId !== secondId
                && session.songTabs.selectedPage.isReady, true,
                "A091: two fixture songs occupy distinct ready tabs")

        findChild(shell, "shellProjectPickerLoader").active = true
        const picker = findChild(shell, "shellProjectPicker")
        verify(picker !== null, "the mounted File Open Project picker exists")
        projectReadySpy.target = session
        projectReadySpy.clear()
        const fileMenu = findChild(shell, "shellFileMenu")
        verify(fileMenu !== null, "the mounted File menu exists")
        fileMenu.open()
        tryCompare(fileMenu, "visible", true, 3000)
        const openProject = findChild(fileMenu, "shellAction_file.open_project")
        verify(openProject !== null && openProject.enabled,
               "the File menu enables Open Project with two songs live")
        mouseClick(openProject, openProject.width / 2, openProject.height / 2)
        tryCompare(picker, "visible", true, 3000)
        picker.selectedFolder = "file://" + bootstrap.projectRoot
        picker.accept()

        verify(waitForNative(function() {
            return projectReadySpy.count === 1 && session.projectOpen
                && session.songCount() > 0 && session.lastSaveError === ""
        }, 30000), "A092: the requested project becomes ready after its tabs close")
        compare(session.songTabs.tabCount, 0,
                "A093: the completed project switch has an empty tab set")
        compare(session.songOpen, false, "the outgoing documents are no longer open")
        compare(session.songTabs.selectedPage, null, "no outgoing document remains selected")
        verify(findChild(shell.sceneLoader.item, "songTab_" + firstId) === null
               && findChild(shell.sceneLoader.item, "songTab_" + secondId) === null,
               "both outgoing song pages have been released")
        compare(projectSwitchFileProbe.fileFingerprint(firstPath), "471:d31e7c4a0a32a53f",
                "switching preserves the first outgoing song's pinned bytes")
        compare(projectSwitchFileProbe.fileFingerprint(secondPath), "425:c27d69bdefcd9207",
                "switching preserves the second outgoing song's pinned bytes")
        projectReadySpy.target = null
    }

    function test_yCleanSessionClosesWithoutPrompt() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var presenter = shell.shellPresenter
        var session = presenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the clean close fixture opens Route 101" + openDiagnostics(session))
        verify(session.songOpen && !session.documentDirty && !session.saveInProgress,
               "the close begins with an open, clean song")
        tryVerify(function() { return shell.sceneLoader.item !== null }, 5000,
                  "the opened song mounts its scene")
        var dialog = findChild(shell, "songTabCloseDialog")
        verify(dialog !== null && !dialog.visible, "the discard prompt starts hidden")
        var promptShown = false
        dialog.visibleChanged.connect(function() {
            if (dialog.visible)
                promptShown = true
        })
        compare(presenter.closeReady, false, "the close is not already ready")
        compare(presenter.beginClose(), false, "the close waits for tab and scene teardown")
        verify(waitForNative(function() { return presenter.closeReady }, 5000),
               "a clean close reaches the scene detach acknowledgement")
        verify(!promptShown && presenter.closeReady && session.songTabs.pendingCloseId === -1
               && session.songTabs.pendingCloseBankTitle.length === 0,
               "a clean session closes without the discard prompt")
    }

    function test_zWindowTitleAndStatusMeter() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell is mounted for chrome state")
        var presenter = shell.shellPresenter
        var session = presenter.session
        var projectName = bootstrap.projectRoot.split("/").filter(function(part) {
            return part.length > 0
        }).pop()
        var meter = findChild(shell, "shellPolyMeter")
        verify(meter !== null && !meter.visible, "the status meter is hidden with no song")
        compare(shell.title, "porydaw", "the empty shell names the application")
        compare(presenter.windowModified, false, "the empty shell is not modified")

        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen }, 30000),
               "the fixture project opens without selecting a tab" + openDiagnostics(session))
        compare(shell.title, projectName + " — porydaw",
                "an empty project title names the project directory")
        compare(meter.visible, false, "a project without a tab has no audio meter")

        session.openSong("mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000),
               "Route 101 opens for shell chrome" + openDiagnostics(session))
        verify(waitForNative(function() {
            return shell.title === "mus_route101 — " + projectName + " — porydaw"
        }, 5000), "the selected song and project appear in the window title; actual="
                 + shell.title)
        compare(presenter.windowModified, false, "the loaded clean song is not modified")
        verify(waitForNative(function() { return meter.visible }, 5000),
               "the selected loaded song exposes the status meter")
        compare(findChild(meter, "shellPolyPcmCaption").text, "PCM",
                "the first meter caption identifies PCM channels")
        compare(findChild(meter, "shellPolyPcmValue").text,
                "0/" + presenter.settingsStore.maxPcmChannels,
                "the PCM meter reports active channels and the configured limit")
        compare(findChild(meter, "shellPolyCgbCaption").text, "CGB",
                "the second meter caption identifies CGB channels")
        compare(findChild(meter, "shellPolyCgbValue").text, "0/4",
                "the CGB meter reports zero of four channels")
        compare(findChild(meter, "shellPolyLostValue").visible, false,
                "the lost-note readout stays hidden without losses")
        const footer = shell.footer
        const status = findChild(shell, "shellStatusText")
        verify(footer && status, "the loaded shell exposes its status region")
        const topInset = 3
        const bottomInset = 2
        const gripHeight = 13 + 4
        compare(footer.height,
                Math.max(footerCaptionMetrics.height, footerBodyMetrics.height, gripHeight)
                    + topInset + bottomInset,
                "footer matches the fork's QStatusBar strut plus vertical spacing")
        compare(status.text, "Song open", "the loaded song publishes the status message")
        const statusTop = status.mapToItem(footer, 0, 0).y
        verify(statusTop >= topInset && footer.height - statusTop - status.height >= bottomInset,
               "status text fits inside the status bar's top and bottom insets")
        for (const name of ["shellPolyPcmCaption", "shellPolyPcmValue",
                            "shellPolyCgbCaption", "shellPolyCgbValue"]) {
            const label = findChild(meter, name)
            verify(label !== null, name + " is mounted")
            const top = label.mapToItem(footer, 0, 0).y
            verify(top >= topInset && top + label.height <= footer.height - bottomInset,
                   name + " fits between the fork's status-bar insets")
        }

        var transport = session.transportBarPresenter()
        transport.setMasterVolume(86)
        verify(waitForNative(function() { return session.documentDirty }, 5000),
               "changing song master volume dirties the selected document")
        verify(waitForNative(function() { return presenter.windowModified }, 5000),
               "the title presenter publishes the dirty state")
        presenter.activate("file.save_song")
        verify(waitForNative(function() { return !session.documentDirty && !session.saveInProgress },
                             30000), "saving the edited song clears the dirty state")
        verify(waitForNative(function() { return !presenter.windowModified }, 5000),
               "saving clears the title modified state")
        var firstId = session.songTabs.selectedId
        var firstPage = session.songTabs.selectedPage
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 && session.songTabs.selectedId !== firstId
        }, 30000), "the second project song becomes the selected tab")
        verify(waitForNative(function() {
            return shell.title === "mus_littleroot_test — " + projectName + " — porydaw"
        }, 5000), "the window title follows the newly selected song")
        var secondId = session.songTabs.selectedId
        var secondPage = session.songTabs.selectedPage
        var selectedHeaders = secondPage.trackHeadersPresenter()
        var selectedEditor = selectedSurface()
        verify(selectedEditor && selectedEditor.visible,
               "the selected song mounts the production editor")
        var headerRows = findChild(selectedEditor, "timelineTrackHeaderRows")
        var headerInput = findChild(selectedEditor, "timelineTrackHeadersInput")
        verify(headerRows !== null && headerInput !== null,
               "the selected tab mounts its header input and rows")
        var firstHeaderRow = headerRows.itemAt(0)
        mouseClick(headerInput, firstHeaderRow.titleRect.x + firstHeaderRow.titleRect.width / 2,
                   firstHeaderRow.titleRect.y + firstHeaderRow.titleRect.height / 2,
                   Qt.RightButton)
        tryCompare(selectedHeaders, "menuOpen", true, 5000,
                   "the selected tab opens its header menu through the mounted input")
        firstPage.trackHeadersPresenter().activateAddTrack()
        compare(session.headerVoicePickerOpen, false,
                "a hidden tab's add request does not open the selected window's picker")
        compare(secondPage.headerVoicePickerModel().pickerOpen, false,
                "a hidden tab's add request leaves the selected tab's picker closed")
        compare(selectedHeaders.menuOpen, true,
                "a hidden tab's add request leaves the selected header menu open")
        compare(session.songTabs.selectedId, secondId,
                "a hidden tab's add request does not switch the selected tab")
        compare(session.documentDirty, false,
                "a hidden tab's add request does not mutate the selected song")
        firstPage.headerVoicePickerModel().cancelPicker()
        selectedHeaders.dismissHeaderMenu()
        session.songTabs.selectTab(firstId)
        verify(waitForNative(function() {
            return shell.title === "mus_route101 — " + projectName + " — porydaw"
        }, 5000), "switching tabs restores the first song's title")
        session.songTabs.requestClose(secondId)
        verify(waitForNative(function() { return session.songTabs.tabCount === 1 }, 5000),
               "closing the inactive clean tab preserves the selected song")
        session.songTabs.requestClose(session.songTabs.selectedId)
        verify(waitForNative(function() { return session.songTabs.tabCount === 0 }, 5000),
               "closing the clean tab leaves the project open")
        verify(waitForNative(function() {
            return shell.title === projectName + " — porydaw"
        }, 5000), "closing the last tab restores the project-only title")
        verify(waitForNative(function() { return !meter.visible }, 5000),
               "closing the last tab hides its audio meter")
        compare(findChild(meter, "shellPolyPcmValue").text, "",
                "unloaded PCM meter values are cleared")
        compare(findChild(meter, "shellPolyCgbValue").text, "",
                "unloaded CGB meter values are cleared")
    }

}
