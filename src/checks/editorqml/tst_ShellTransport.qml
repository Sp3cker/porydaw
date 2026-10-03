import QtQuick
import QtTest

ShellTransportSupport {

    function test_chromeTypographyAndSpacing() {
        const bar = openShell()
        const session = shell.shellPresenter.session
        const body = session.typographyFonts.body
        const mono = session.typographyFonts.bodyMono
        const clock = findChild(bar, "transportTimeLabel")
        const rootCombo = findChild(bar, "transportScaleRoot")
        const typeCombo = findChild(bar, "transportScaleType")
        const volume = findChild(bar, "transportMasterVolumeCaption")
        const output = findChild(bar, "transportOutputVolumeCaption")
        const input = findChild(bar, "transportMasterVolume")
        verify(clock && rootCombo && typeCombo && volume && output && input,
               "mounted transport exposes its text controls")
        for (const control of [rootCombo, typeCombo, volume, output]) {
            compare(control.font.family, body.family, "transport text uses the body family")
            compare(control.font.pixelSize, body.pixelSize, "transport text uses the body size")
            compare(control.font.weight, body.weight, "transport text keeps body weight")
        }
        compare(input.appearance.font.family, body.family, "volume editor binds the body family")
        compare(input.appearance.font.pixelSize, body.pixelSize, "volume editor binds body size")
        compare(input.appearance.font.weight, body.weight, "volume editor keeps body weight")
        compare(clock.font.family, mono.family, "clock uses the bodyMono family")
        compare(clock.font.pixelSize, mono.pixelSize, "clock uses the bodyMono size")
        compare(clock.font.weight, mono.weight, "clock uses the bodyMono weight")
        compare(bar.baseFontPx, session.baseFontPx, "transport geometry follows captured base")
        compare(bar.inset, session.layoutSpaces.one, "transport inset uses the One token")
        compare(bar.edgeMargin, Math.max(1, Math.round(session.baseFontPx / 6)),
                "transport edge derives from captured base")
    }

    function test_transportButtonMenuCommandParity() {
        var bar = openShell()
        const authority = shell.shellPresenter
        const ids = ["transport.go_to_start", "transport.play", "transport.pause",
                     "transport.stop", "transport.loop", "transport.follow_playhead",
                     "transport.resonance"]
        const names = ["transport.go-to-start", "transport.play", "transport.pause",
                       "transport.stop", "transport.loop", "transport.follow-playhead",
                       "transport.resonance"]
        function button(index) { return findChild(bar, names[index]) }
        function menu(index) { return findChild(shell, "shellAction_" + ids[index]) }
        function parity(index, expected) {
            const control = button(index)
            verify(control !== null, ids[index] + " button is mounted")
            compare(authority.actionEnabled(ids[index]), expected,
                    ids[index] + " reports its expected availability")
            tryCompare(control, "actionable", expected, 3000,
                       ids[index] + " button matches command authority")
            tryCompare(control, "enabled", expected, 3000,
                       ids[index] + " rendered enabled state matches authority")
            if (index < 6) {
                const item = menu(index)
                verify(item !== null, ids[index] + " menu item is mounted")
                tryCompare(item, "enabled", expected, 3000,
                           ids[index] + " menu availability matches the button")
            }
        }
        for (let index = 0; index < ids.length; ++index)
            parity(index, index === 5 || index === 6)

        bar = openSong()
        const transport = bar.presenter
        const clock = findChild(bar, "transportTimeLabel")
        parity(0, true)
        parity(1, true)
        parity(2, false)
        parity(3, false)
        parity(4, true)
        parity(5, true)
        const playPause = findChild(shell, "shellAction_transport.play_pause")
        verify(playPause !== null, "Play/Pause menu item is mounted")
        verify(authority.actionEnabled("transport.play_pause"),
               "Play/Pause command authority enables the window shortcut")
        compare(playPause.enabled, authority.actionEnabled("transport.play_pause"),
                "Play/Pause menu and shortcut share enabled authority")
        parity(6, true)

        mouseClick(button(1), button(1).width / 2, button(1).height / 2)
        tryCompare(transport, "state", 3, 3000,
                   "Play button starts real audio playback")
        parity(1, false)
        parity(2, true)
        parity(3, true)
        menu(2).triggered()
        tryCompare(transport, "state", 2, 3000,
                   "Pause menu pauses the same audio transport")
        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000,
                   "Play menu resumes the same audio transport")
        mouseClick(button(2), button(2).width / 2, button(2).height / 2)
        tryCompare(transport, "state", 2, 3000,
                   "Pause button produces the same paused audio state")
        mouseClick(button(3), button(3).width / 2, button(3).height / 2)
        tryCompare(transport, "state", 1, 3000,
                   "Stop button stops and rewinds audio")
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Stop button rewinds the real audio playhead")
        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000)
        menu(3).triggered()
        tryCompare(transport, "state", 1, 3000,
                   "Stop menu produces the same stopped audio state")
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Stop menu rewinds the real audio playhead")
        parity(3, false)

        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000)
        verify(waitForNative(function() {
            transport.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "playback advances before comparing the seek routes")
        var homeSurface = rollSurface()
        verify(homeSurface !== null, "the roll surface mounts before the home routes")
        var homeGrid = homeSurface.gridModel
        homeGrid.setEditCursorTick(homeGrid.ticksPerBeat * 4)
        verify(homeGrid.editCursorTick > 0, "the edit cursor starts away from the origin")
        mouseClick(button(0), button(0).width / 2, button(0).height / 2)
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Go to Start button seeks the actual audio playhead")
        compare(homeGrid.editCursorTick, 0, "Go to Start button homes the edit cursor")
        verify(waitForNative(function() {
            transport.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "audio advances again before the menu seek")
        menu(0).triggered()
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Go to Start menu seeks the same audio playhead")
        compare(homeGrid.editCursorTick, 0, "Go to Start menu keeps the edit cursor at the origin")
        menu(3).triggered()
        tryCompare(transport, "state", 1, 3000)

        const loopBefore = transport.loopEnabled
        mouseClick(button(4), button(4).width / 2, button(4).height / 2)
        compare(transport.loopEnabled, !loopBefore,
                "Loop button changes native audio loop state")
        tryCompare(menu(4), "checked", !loopBefore, 3000,
                   "Loop menu mirrors the button's checked state")
        menu(4).triggered()
        compare(transport.loopEnabled, loopBefore,
                "Loop menu changes the same audio loop state")
        tryCompare(button(4), "checked", loopBefore, 3000,
                   "Loop button mirrors the menu's checked state")

        const followBefore = transport.followPlayhead
        mouseClick(button(5), button(5).width / 2, button(5).height / 2)
        compare(transport.followPlayhead, !followBefore,
                "Follow button changes the playhead policy")
        tryCompare(menu(5), "checked", !followBefore, 3000,
                   "Follow menu mirrors the button's checked state")
        menu(5).triggered()
        compare(transport.followPlayhead, followBefore,
                "Follow menu restores the same playhead policy")
        tryCompare(button(5), "checked", followBefore, 3000,
                   "Follow button mirrors the menu's checked state")

        const resonanceBefore = transport.resonanceSuppression
        mouseClick(button(6), button(6).width / 2, button(6).height / 2)
        compare(transport.resonanceSuppression, !resonanceBefore,
                "resonance button updates native audio through command authority")
        authority.activate("transport.resonance")
        compare(transport.resonanceSuppression, resonanceBefore,
                "the authority restores the same native resonance state")
        tryCompare(button(6), "checked", resonanceBefore, 3000,
                   "resonance button mirrors the authority's checked state")
        compare(authority.session.documentDirty, false,
                "transport parity actions never dirty the document")
    }

    function test_transportControlTransitionsAndSettings() {
        var bar = openShell()
        var clock = findChild(bar, "transportTimeLabel")
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        var stop = findChild(bar, "transport.stop")
        var rewind = findChild(bar, "transport.go-to-start")
        compare(clock.text, "0:00.0 / 0:00.0", "unloaded clock is zeroed")
        compare(play.actionable, false, "unloaded song cannot play")
        compare(rewind.actionable, false, "unloaded song cannot seek")

        bar = openSong()
        var sceneTop = shell.sceneLoader.mapToItem(shell.contentItem, 0, 0).y
        var toolbarBottom = bar.mapToItem(shell.contentItem, 0, bar.height).y
        verify(sceneTop >= toolbarBottom, "editor viewport starts below the top transport bar")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text !== "0:00.0 / 0:00.0"
        }, 5000), "loaded song length reaches the clock after audio binding")
        verify(clock.text.startsWith("0:00.0 / "), "loaded clock includes current/total time")
        compare(bar.presenter.measureText, "1:1",
                "the accessible opening measure and beat are one-based")
        compare(play.actionable, true, "loaded song can start playback")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        tryCompare(play, "actionable", false, 3000,
                   "playing disables duplicate Play")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "the mounted clock follows the real audio playhead")
        compare(pause.actionable, true, "Pause becomes available during playback")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(bar.presenter, "state", 2, 3000)
        mouseClick(stop, stop.width / 2, stop.height / 2)
        tryCompare(bar.presenter, "state", 1, 3000)
        var stoppedSurface = rollSurface()
        verify(stoppedSurface !== null, "the roll surface mounts before the stopped rewind")
        var stoppedGrid = stoppedSurface.gridModel
        stoppedGrid.setEditCursorTick(stoppedGrid.ticksPerBeat * 4)
        verify(stoppedGrid.editCursorTick > 0, "the stopped edit cursor starts away from the origin")
        mouseClick(rewind, rewind.width / 2, rewind.height / 2)
        compare(stoppedGrid.editCursorTick, 0, "stopped rewind homes the edit cursor without seeking")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "stopped rewind leaves the rewound clock at the origin")

        var loop = findChild(bar, "transport.loop")
        var beforeLoop = bar.presenter.loopEnabled
        mouseClick(loop, loop.width / 2, loop.height / 2)
        compare(bar.presenter.loopEnabled, !beforeLoop, "loop switch reaches audio engine")
        var follow = findChild(bar, "transport.follow-playhead")
        var beforeFollow = bar.presenter.followPlayhead
        mouseClick(follow, follow.width / 2, follow.height / 2)
        compare(bar.presenter.followPlayhead, !beforeFollow, "follow switch updates playhead policy")
        var resonance = findChild(bar, "transport.resonance")
        compare(bar.presenter.outputVolume, 100, "the application output defaults to 100 percent")
        compare(shell.shellPresenter.session.documentDirty, false,
                "the song begins clean before app-level volume changes")
        var beforeResonance = bar.presenter.resonanceSuppression
        mouseClick(resonance, resonance.width / 2, resonance.height / 2)
        compare(bar.presenter.resonanceSuppression, !beforeResonance,
                "resonance switch reaches native audio")

        var output = findChild(bar, "transportOutputVolume")
        verify(output !== null && output.visible, "application volume dial is mounted")
        compare(output.value, 100, "the mounted dial displays the default output volume")
        mouseWheel(output, output.width / 2, output.height / 2, 0, -120)
        tryCompare(bar.presenter, "outputVolume", 90, 3000)
        compare(shell.shellPresenter.session.documentDirty, false,
                "changing output volume never dirties the song")
        bar.presenter.setOutputVolume(50)
        tryCompare(output, "value", 50, 1000)
        mouseClick(output, output.width / 2, output.height / 2)
        compare(bar.presenter.outputVolume, 50, "dial tap does not change its value")
        mousePress(output, output.width / 2, output.height / 2, Qt.LeftButton)
        mouseMove(output, output.width / 2, output.height / 2 + 11, -1, Qt.LeftButton)
        mouseRelease(output, output.width / 2, output.height / 2 + 11, Qt.LeftButton)
        verify(bar.presenter.outputVolume > 50, "dial drag down increases output volume")
        bar.presenter.setOutputVolume(50)
        tryCompare(output, "value", 50, 1000)
        mousePress(output, output.width / 2, output.height / 2, Qt.LeftButton)
        mouseMove(output, output.width / 2, output.height / 2 - 11, -1, Qt.LeftButton)
        mouseRelease(output, output.width / 2, output.height / 2 - 11, Qt.LeftButton)
        verify(bar.presenter.outputVolume < 50, "dial drag up decreases output volume")
        compare(shell.shellPresenter.session.documentDirty, false,
                "dial drags do not commit song settings")

        var master = findChild(bar, "transportMasterVolume")
        verify(master !== null, "song master volume is mounted")
        master.focusInput(Qt.OtherFocusReason)
        master.selectAll()
        keyClick(Qt.Key_8)
        keyClick(Qt.Key_7)
        keyClick(Qt.Key_Return)
        tryCompare(bar.presenter, "masterVolume", 87, 3000)
        compare(shell.shellPresenter.session.documentDirty, true,
                "song master volume does dirty the document")
        master.focusInput(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 3, 3000,
                   "Space still starts playback with the volume field focused")
        compare(master.value, 87, "Space does not insert into the numeric field")
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 2, 3000,
                   "the same Space shortcut pauses playback")
        var outputAcrossTabs = bar.presenter.outputVolume
        var session = shell.shellPresenter.session
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 || session.lastSaveError.length > 0
        }, 30000), "second song opens in its own tab")
        verify(session.songTabs.tabCount === 2, "both tabs are mounted")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.masterVolume !== 87
        }, 5000), "song master volume switches with the selected tab")
        compare(bar.presenter.outputVolume, outputAcrossTabs,
                "application output volume survives tab selection")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.masterVolume === 87
        }, 5000), "first song retains its edited master volume")
        tryCompare(master, "value", 87, 3000,
                   "the mounted master-volume field restores the edited song value")

        cleanup()
        bar = openShell()
        compare(bar.presenter.outputVolume, outputAcrossTabs,
                "application output preference survives a fresh shell session")
    }

    function test_transportClockAndSpacerSurviveTextAndResize() {
        const bar = openShell()
        const clock = findChild(bar, "transportTimeLabel")
        const scale = findChild(bar, "transportScaleSlot")
        const spacer = findChild(bar, "transportVolumeSpacer")
        const volume = findChild(bar, "transportMasterVolumeCaption")
        const field = findChild(bar, "transportMasterVolume")
        const output = findChild(bar, "transportOutputVolumeCaption")
        const dial = findChild(bar, "transportOutputVolume")
        compare(clock.text, "0:00.0 / 0:00.0",
                "empty toolbar keeps the combined clock zeroed")
        const reserved = clock.width
        const scaleX = scale.mapToItem(bar, 0, 0).x
        clock.text = "99:59.9 / 99:59.9"
        compare(clock.width, reserved,
                "worst-case clock text keeps the font-sized reserved strip width")
        compare(scale.mapToItem(bar, 0, 0).x, scaleX,
                "clock text cannot displace the adjacent scale controls")
        clock.text = Qt.binding(function() { return bar.presenter.timeText })
        openSong()
        verify(waitForNative(function() {
            return clock.text !== "0:00.0 / 0:00.0"
        }, 5000), "loaded clock samples a real song timeline")
        compare(clock.width, reserved,
                "loaded clock keeps the same reserved strip width")
        shell.width = 1200
        tryCompare(bar, "width", 1200, 3000)
        const wide = spacer.width
        shell.width = 1000
        tryCompare(bar, "width", 1000, 3000)
        verify(wide > spacer.width,
               "volume spacer absorbs additional width when toolbar grows")
        const positions = [spacer, volume, field, output, dial]
        for (let index = 1; index < positions.length; ++index)
            verify(positions[index - 1].mapToItem(bar, 0, 0).x
                   < positions[index].mapToItem(bar, 0, 0).x,
                   "volume chrome retains expanding spacer, Volume, field, Output, dial order " + index)
        shell.width = 1100
        tryCompare(bar, "width", 1100, 3000)
    }

    function test_unloadedTransportPreferencesStayActionable() {
        const bar = openShell()
        compare(findChild(bar, "transport.follow-playhead").actionable, true,
                "follow playhead stays enabled without an open song")
        compare(findChild(bar, "transport.resonance").actionable, true,
                "resonance suppression stays enabled without an open song")
    }

    function test_transportTogglePreferencesSurviveRelaunch() {
        settings.setBool("followPlayhead", true)
        settings.setBool("dsp.resonanceSuppression", false)
        settings.synchronize()
        var bar = openShell()
        const follow = findChild(bar, "transport.follow-playhead")
        const resonance = findChild(bar, "transport.resonance")
        mouseClick(follow, follow.width / 2, follow.height / 2)
        mouseClick(resonance, resonance.width / 2, resonance.height / 2)
        compare(bar.presenter.followPlayhead, false)
        compare(bar.presenter.resonanceSuppression, true)
        cleanup()
        bar = openShell()
        compare(bar.presenter.followPlayhead, false,
                "the follow-playhead preference survives a fresh shell session")
        compare(bar.presenter.resonanceSuppression, true,
                "the resonance-suppression preference survives a fresh shell session")
        bar.presenter.setFollowPlayhead(true)
        bar.presenter.setResonanceSuppression(false)
    }

    function test_visualReferenceProfiles_data() {
        return [ { tag: "font12", fontPx: 12 }, { tag: "font16", fontPx: 16 } ]
    }

    function test_visualReferenceProfiles(data) {
        var bar = openShell(data.fontPx)
        bar = openSong()
        const session = shell.shellPresenter.session
        compare(session.baseFontPx, data.fontPx,
                "transport profile captures the declared font before mounting")
        compare(bar.height, bar.toolExtent + session.layoutSpaces.two - 2,
                "toolbar height follows the base icon and Two token")
        var actionRegions = ["transport.go-to-start", "transport.play", "transport.pause",
                             "transport.stop", "transport.loop", "transport.follow-playhead",
                             "transport.resonance", "transportScaleRoot", "transportScaleType",
                             "transportScaleHighlight", "transportScaleFold"]
        wait(50)
        // References drop the two 6px separators: expanded bars grow the fill spacer by 2*(6 + spacing);
        // collapsed bars shift the master pair left by 6 + spacing.
        for (var dpr = 1; dpr <= 2; ++dpr) {
            var baseline = JSON.parse(bootstrap.transportReferenceJson(dpr, data.fontPx))
            compare(bar.width, baseline.image.width, "transport reference width")
            compare(bar.height, baseline.image.height, "transport reference height")
            for (var i = 0; i < baseline.regions.length; ++i) {
                var region = baseline.regions[i]
                if (region.name !== "transportTimeLabel"
                        && region.name !== "transportMasterVolume"
                        && region.name !== "transportMasterVolumeCaption"
                        && region.name !== "transportOutputVolume"
                        && region.name !== "transportOutputVolumeCaption"
                        && region.name !== "transportVolumeSpacer"
                        && actionRegions.indexOf(region.name) < 0)
                    continue
                var item = findChild(bar, region.name)
                verify(item !== null, region.name + " exists in the mounted transport")
                compare(item.visible, true, region.name + " matches baseline visibility")
                var origin = item.mapToItem(bar, 0, 0)
                verify(Math.abs(origin.x - region.x) <= 8,
                       region.name + " x differs from " + baseline.profile
                       + ": " + origin.x + " vs " + region.x)
                verify(Math.abs(origin.y - region.y) <= 4,
                       region.name + " y differs from " + baseline.profile
                       + ": " + origin.y + " vs " + region.y)
                if (region.name !== "transportVolumeSpacer")
                    verify(Math.abs(item.width - region.w) <= 6,
                           region.name + " width differs from " + baseline.profile
                           + ": " + item.width + " vs " + region.w)
            }
        }
        var captured = false
        verify(bar.grabToImage(function(result) {
            captured = result.saveToFile(bootstrap.transportCapturePath(data.fontPx))
        }), "transport capture starts")
        tryVerify(function() { return captured }, 3000, "the mounted pane screenshot is saved")
    }

    function test_transportGlyphTintMatchesEnabledState() {
        var bar = openShell()
        openSong()
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        verify(play !== null, "the play button is mounted")
        verify(pause !== null, "the pause button is mounted")
        tryCompare(play, "actionable", true, 3000)
        verify(!pause.actionable, "pause stays disabled while stopped")
        verify(glyphRendersInk(bar, play, bar.colors.buttonText),
               "the enabled play glyph renders in buttonText ink")
        verify(glyphRendersInk(bar, pause, bar.colors.disabledText),
               "the disabled pause glyph renders in disabledText ink")
    }
}
