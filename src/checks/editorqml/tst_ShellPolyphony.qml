import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui
import "TextContrastAudit.js" as Audit

ShellLaneSupport {
    id: testCase
    name: "ShellPolyphony"
    when: windowShown
    width: 960
    height: 760
    visible: true
    property var referencePane: null

    ShellQmlBootstrap { id: bootstrap }
    PolyphonyShellProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 960; height: 820; visible: true } }
    Component {
        id: profileShellComponent
        ShellWindow {
            width: 960
            height: 820
            visible: true
            typographyCaptureFont: Qt.font({ pixelSize: probe.profileName.indexOf("font16") >= 0
                                                       ? 16 : 12 })
        }
    }
    Component { id: referenceComponent; PolyphonyPanel {} }

    function init() {
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window state")
        verify(!bootstrap.preferences.hasValue("windowState"),
               "the prior shell's debugger state is cleared")
    }

    laneBootstrap: bootstrap

    function createShell() {
        shell = (probe.profileName.length > 0 ? profileShellComponent : shellComponent).createObject(null)
        verify(shell, "the production shell mounts")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented window mounts its deferred editor scene")
        return shell.shellPresenter
    }

    closeGateMessage: "the close gate completes"
    closeReadyMessage: "the shell retires its editor scene"
    function preCleanup() {
        if (referencePane) {
            referencePane.destroy()
            referencePane = null
        }
    }
    function preDestroyShell() { bootstrap.children.length = 0 }

    function panel() { return findChild(shell, "polyphonyPanel") }
    function dock() { return findChild(shell, "shellPolyphonyDock") }

    function test_mountedTypographyAndCellGeometry() {
        const presenter = createShell()
        presenter.activate("view.polyphony_debugger")
        const session = presenter.session
        const pane = panel()
        const body = session.typographyFonts.body
        const bold = session.typographyFonts.bodyBold
        const caption = session.typographyFonts.caption
        compare(pane.em, session.baseFontPx, "panel em follows the session base")
        compare(pane.gap, session.layoutSpaces.two, "panel gap follows the Two token")
        for (const name of ["polyphonyUsageHeading", "polyphonyOverflowHeading",
                            "polyphonyLogHeading"]) {
            const heading = findChild(pane, name)
            compare(heading.font.family, bold.family, name + " uses bodyBold family")
            compare(heading.font.pixelSize, bold.pixelSize, name + " uses bodyBold size")
            compare(heading.font.weight, bold.weight, name + " uses bodyBold weight")
        }
        for (const name of ["polyphonyInvert", "polyphonyReset", "polyphonyShadowNotice",
                            "polyphonyTableHeader", "polyphonyEmpty",
                            "polyphonyGroupCaption"]) {
            const text = findChild(pane, name)
            verify(text !== null, name + " mounts in the polyphony panel")
            compare(text.font.family, body.family, name + " uses the body family")
            compare(text.font.pixelSize, body.pixelSize, name + " uses the body size")
            compare(text.font.weight, body.weight, name + " keeps regular body weight")
        }
        verify(waitForNative(function() {
            return findChild(pane, "polyphonyChannelCell") !== null
        }, 5000), "the visible channel group publishes its first cells")
        const cell = findChild(pane, "polyphonyChannelCell")
        verify(cell !== null, "mounted channel group has a rendered cell")
        compare(cell.width, Math.round(session.baseFontPx * 46 / 12),
                "channel cell width follows fontPx(46/12)")
        const label = cell.children[0]
        compare(label.font.family, caption.family, "channel cell label uses caption family")
        compare(label.font.pixelSize, caption.pixelSize, "channel cell label uses caption size")
        compare(label.font.weight, caption.weight, "channel cell label keeps caption weight")
    }

    function verifyProfilePixels(surface, strip) {
        const heat = findChild(strip, "cpuProfileHeat")
        const palette = surface.gridModel.palette
        const meter = strip.meter
        const capture = shell.contentItem
        verify(waitForRendering(capture, 5000), "the shell submits the profile frame")
        const image = grabImage(capture)
        let nearest = 256
        let detail = "no visible cost-bearing span"
        for (let x = 1; x < heat.width - 1; ++x) {
            const cycles = strip.scene.cyclesAt(x)
            if (cycles <= 0)
                continue
            const base = cycles > 83776 ? palette.errorText
                : cycles > meter.budget ? palette.warningText : palette.polyphonyActiveFill
            const blend = cycles <= 83776 && cycles <= meter.budget
                ? Math.pow(Math.min(1, cycles / meter.budget), 1.5) * 0.75 : 0
            const warning = palette.warningText
            const expected = [
                Math.round(255 * (base.r * (1 - blend) + warning.r * blend)),
                Math.round(255 * (base.g * (1 - blend) + warning.g * blend)),
                Math.round(255 * (base.b * (1 - blend) + warning.b * blend))
            ]
            const point = heat.mapToItem(capture, x, heat.height / 2)
            const px = Math.floor(point.x * image.width / capture.width)
            const py = Math.floor(point.y * image.height / capture.height)
            if (px < 0 || px >= image.width || py < 0 || py >= image.height)
                continue
            const actual = [image.red(px, py), image.green(px, py), image.blue(px, py)]
            const distance = Math.max(Math.abs(actual[0] - expected[0]),
                                      Math.abs(actual[1] - expected[1]),
                                      Math.abs(actual[2] - expected[2]))
            if (distance < nearest) {
                nearest = distance
                detail = "cost " + cycles + "; pixel " + px + "," + py
                    + "; actual RGB " + actual + "; expected RGB " + expected
            }
            if (distance <= 8)
                break
        }
        verify(nearest <= 8, "a cost-bearing span paints its modeled theme color: " + detail)
    }

    function verifyHistoryPixels(palette) {
        const history = findChild(shell, "cpuHistory")
        verify(history && history.width > 0 && history.height > 0,
               "the mounted history has a visible paint area")
        const capture = shell.contentItem
        verify(waitForRendering(capture, 5000), "the shell submits the history frame")
        const image = grabImage(capture)
        const colors = [palette.polyphonyActiveFill, palette.warningText, palette.errorText]
        let painted = false
        for (let x = 0.5; x < history.width; ++x) {
            const point = history.mapToItem(capture, x, history.height - 2)
            const px = Math.floor(point.x * image.width / capture.width)
            const py = Math.floor(point.y * image.height / capture.height)
            if (px < 0 || px >= image.width || py < 0 || py >= image.height)
                continue
            painted = colors.some(function(color) {
                return Math.abs(image.red(px, py) - color.r * 255) <= 8
                    && Math.abs(image.green(px, py) - color.g * 255) <= 8
                    && Math.abs(image.blue(px, py) - color.b * 255) <= 8
            })
            if (painted)
                break
        }
        verify(painted, "history paints a modeled-cost bar in its theme severity color")
    }

    function test_cpuMeterAndOfflineProfile() {
        const presenter = createShell()
        const session = presenter.session
        const meter = presenter.cpuMeter
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && presenter.action("transport.play").enabled
        }, 30000), "a real song and audio renderer are ready")
        verify(waitForNative(function() {
            const readout = findChild(shell, "shellCpuValue")
            return readout && readout.visible && readout.width > 0
        }, 5000), "the status bar mounts its clickable CPU readout")
        const status = findChild(shell, "shellCpuValue")
        mouseClick(status, status.width / 2, status.height / 2)
        tryVerify(function() { return presenter.cpuMeterVisible && findChild(shell, "shellCpuDock").visible }, 3000,
                  "the status readout opens the production CPU panel")
        verify(findChild(shell, "cpuMeter") && findChild(shell, "cpuHistory"),
               "stacked terms and the frame history are mounted")
        presenter.activate("transport.play")
        verify(waitForNative(function() {
            meter.poll()
            return meter.valid && meter.historyCount > 0 && meter.peakVisible
        }, 10000), "real song playback publishes modeled GBA costs")
        compare(meter.total, meter.sequencer + meter.cgb + meter.mixer,
                "the displayed total is the sum of its three terms")
        verify(meter.peak >= meter.total && meter.peakTime.length > 0,
               "the panel keeps the peak and its song time")
        // Select the View action explicitly, independently of saved preferences.
        if (presenter.cpuProfileVisible) {
            presenter.activate("view.cpu_profile")
            tryCompare(presenter, "cpuProfileVisible", false, 3000)
        }
        presenter.activate("view.cpu_profile")
        tryCompare(presenter, "cpuProfileVisible", true, 3000)
        let surface = null
        verify(waitForNative(function() {
            surface = selectedSurface()
            return surface && surface.visible && surface.width > 0
        }, 10000), "the selected song's deferred editor surface mounts")
        if (surface.showEvents)
            presenter.activate("view.event_list")
        tryCompare(surface, "showEvents", false, 3000)
        let strip = null
        verify(waitForNative(function() {
            strip = findChild(surface, "cpuProfileStrip")
            return strip && strip.visible && strip.width > 0 && strip.height > 0
        }, 10000), "the selected song mounts its visible profile strip")
        const ruler = findChild(surface, "timelineQuickRuler")
        const heat = findChild(strip, "cpuProfileHeat")
        const hover = findChild(strip, "cpuProfileHover")
        verify(ruler && heat && hover, "the ruler, heat columns and hover target are mounted")
        fuzzyCompare(strip.mapToItem(surface, 0, 0).y,
                     ruler.mapToItem(surface, 0, ruler.height).y, 0.01,
                     "the profile strip starts immediately below the ruler")
        verify(waitForNative(function() {
            meter.poll()
            if (meter.profileStatus.length > 0)
                return false
            for (let x = 1; x < heat.width; ++x) {
                if (strip.scene.cyclesAt(x) > 0)
                    return true
            }
            return false
        }, 30000), "the isolated offline renderer fills the timeline heat strip")
        verifyHistoryPixels(surface.gridModel.palette)
        // Freeze follow-playhead movement while comparing the rendered columns
        // with the exact costs and theme colors used to paint them.
        presenter.activate("transport.pause")
        verify(waitForNative(function() {
            meter.poll()
            return !meter.playing && meter.peakVisible
        }, 5000), "pause retains the peak but stops showing a current frame")
        verifyProfilePixels(surface, strip)
        let hoverX = -1
        for (let x = 1; x < hover.width - 1; ++x) {
            if (strip.scene.cyclesAt(x) > 0) {
                hoverX = x
                break
            }
        }
        verify(hoverX >= 0, "a measured profile frame is reachable by pointer")
        mouseMove(hover, hoverX, hover.height / 2)
        tryVerify(function() {
            return hover.containsMouse && hover.cycles > 0
                && hover.cycles === strip.scene.cyclesAt(hover.mouseX)
                && hover.ToolTip.visible && hover.ToolTip.text.indexOf(String(hover.cycles)) >= 0
        }, 5000, "hovering a heat column displays its estimated cycle count")

        const grid = surface.gridModel
        const previousScroll = grid.cameraScrollX
        const forward = Math.min(grid.cameraMaxHScroll, previousScroll + grid.beatWidth)
        const targetScroll = forward > previousScroll + 0.5 ? forward
            : Math.max(grid.cameraMinHScroll, previousScroll - grid.beatWidth)
        verify(Math.abs(targetScroll - previousScroll) > 0.5, "the song has horizontal camera travel")
        const previousRevision = strip.scene.displayRevision
        grid.setCameraHScroll(targetScroll)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraScrollX - previousScroll) > 0.5
                && strip.scene.displayRevision !== previousRevision
                && hover.cycles === strip.scene.cyclesAt(hover.mouseX)
        }, 5000), "scrolling resamples the heat columns and updates the hovered value")
        verifyProfilePixels(surface, strip)

        const previousBeatWidth = grid.beatWidth
        const beforeZoom = strip.scene.displayRevision
        grid.handleWheel(0, 120, 0, 0, Qt.NoModifier, 0, false, heat.width / 2, 0)
        verify(waitForNative(function() {
            return grid.beatWidth !== previousBeatWidth && strip.scene.displayRevision !== beforeZoom
                && hover.cycles === strip.scene.cyclesAt(hover.mouseX)
        }, 5000), "zoom resamples the same pointer and camera projection")
        verifyProfilePixels(surface, strip)

        const palette = grid.palette
        const originalLow = palette.polyphonyActiveFill
        const originalWarning = palette.warningText
        const originalError = palette.errorText
        const beforeTheme = strip.scene.displayRevision
        palette.polyphonyActiveFill = "#179fc4"
        palette.warningText = "#e3a219"
        palette.errorText = "#d13397"
        verify(waitForNative(function() {
            return strip.scene.displayRevision !== beforeTheme
        }, 5000), "theme changes repaint the retained graph")
        verifyProfilePixels(surface, strip)
        palette.polyphonyActiveFill = originalLow
        palette.warningText = originalWarning
        palette.errorText = originalError

        presenter.activate("view.cpu_profile")
        tryVerify(function() { return !strip.visible && !presenter.cpuProfileVisible }, 3000,
                  "the View action hides the strip")
        compare(bootstrap.preferences.bool("cpuProfileStrip", true), false,
                "the hidden profile preference is persisted")
        presenter.activate("view.cpu_profile")
        tryVerify(function() { return strip.visible && presenter.cpuProfileVisible }, 3000,
                  "the View action restores the strip")
        compare(bootstrap.preferences.bool("cpuProfileStrip", false), true,
                "the restored profile preference is persisted")
        const retainedHistoryCount = meter.historyCount
        presenter.activate("view.cpu_meter")
        tryVerify(function() { return findChild(shell, "cpuHistory") === null }, 3000,
                  "closing the dock unloads the history graph")
        compare(meter.historyCount, retainedHistoryCount, "unloading the graph preserves playback history")
        presenter.activate("view.cpu_meter")
        tryVerify(function() { return findChild(shell, "cpuHistory") !== null }, 3000,
                  "reopening the dock remounts its retained history")
        compare(meter.historyCount, retainedHistoryCount, "remounting does not reset playback history")
        meter.reset()
        compare(meter.historyCount, 0, "reset clears the ten-second history")
        compare(meter.peakVisible, false, "reset clears the retained peak")
        const close = findChild(shell, "shellCpuClose")
        mouseClick(close, close.width / 2, close.height / 2)
        tryVerify(function() { return !presenter.cpuMeterVisible }, 3000, "the panel close button hides it")
    }

    function test_viewActionAndEventNavigation() {
        var presenter = createShell()
        var session = presenter.session
        var poly = session.polyphony
        verify(!presenter.polyphonyVisible && !dock().visible,
               "the debugger starts hidden")
        compare(presenter.action("view.polyphony_debugger").label, "Polyphony Debugger")
        verify(presenter.action("view.polyphony_debugger").enabled,
               "the View action is enabled before a document opens")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return presenter.polyphonyVisible }, 3000,
                  "ShellPresenter.activate toggles the tracked dock visibility")
        tryVerify(function() { return dock().visible }, 3000,
                  "ShellWindow dock reacts to the presenter visibility change")
        var mountedPanel = panel()
        verify(mountedPanel !== null && mountedPanel !== undefined,
               "PolyphonyPanel exists as a direct child of ShellWindow, outside the scene Loader")
        tryVerify(function() { return mountedPanel.visible }, 3000,
                  "the mounted polyphony pane follows its dock")
        var checkbox = findChild(panel(), "polyphonyInvert")
        verify(checkbox, "invert checkbox is mounted")
        mouseClick(checkbox, checkbox.width / 2, checkbox.height / 2)
        verify(poly.invertChecked, "the checkbox changes the renderer setting")
        var close = findChild(dock(), "shellPolyphonyClose")
        mouseClick(close, close.width / 2, close.height / 2)
        tryVerify(function() { return !presenter.polyphonyVisible }, 3000,
                  "close button dispatches the View action to ShellPresenter")
        tryVerify(function() { return !dock().visible }, 3000,
                  "closing hides the mounted dock and suspends its polling timer")
        verify(poly.invertChecked, "closing preserves the invert checkbox state")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return dock().visible }, 3000,
                  "the View action reopens the dock")
        verify(checkbox.checked, "reopening restores the checked option")

        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song loading completes")
        verify(session.songOpen, "the mounted panel has a live document")

        var fixture = probe.fixturePresenter()
        referencePane = referenceComponent.createObject(shell.contentItem, {
            presenter: fixture, colors: session.palette,
            typography: session.typographyFonts, layoutSpaces: session.layoutSpaces,
            baseFontPx: session.baseFontPx, width: 380, height: 600
        })
        verify(referencePane, "the production pane accepts the isolated diagnostic fixture")
        var row = findChild(referencePane, "polyphonyEventRow_2")
        verify(row, "the positioned event is rendered in the production log")
        const tail = findChild(referencePane, "polyphonyEventRow_1")
        const liveText = findChild(referencePane, "polyphonyEventRow_0")
        compare(fixture.eventCount, 3, "mounted diagnostic fixture retains all three fork events")
        verify(tail && liveText, "the middle tail and newest live rows are rendered")
        verify(tail.children[0].text.indexOf("3:2.0") >= 0
               && tail.children[0].text.indexOf("tail cut") >= 0,
               "mounted middle event shows tick 216 and the release tail cut")
        verify(row.children[0].text.indexOf("2:1.0") >= 0
               && row.children[0].text.indexOf("cut off by Trk 5") >= 0,
               "mounted oldest positioned event retains the steal position and source")
        verify(liveText.children[0].text.indexOf("live") >= 0
               && liveText.children[0].text.indexOf("dropped") >= 0,
               "mounted newest event retains the live drop")
        var scroll = findChild(referencePane, "polyphonyScroll")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        verify(waitForPolish(referencePane), "event log scrolls into the visible pane")
        var location = row.mapToItem(referencePane, 0, 0)
        verify(location.y >= 0 && location.y + row.height <= referencePane.height,
               "the positioned event row receives actual pointer input")
        var live = findChild(referencePane, "polyphonyEventRow_0")
        const body = session.typographyFonts.body
        const eventText = row.children[0]
        const counterText = findChild(referencePane, "polyphonyCounterText")
        verify(counterText !== null, "overflow counter text mounts in the fixture")
        for (const text of [eventText, counterText]) {
            compare(text.font.family, body.family, "polyphony data row uses the body family")
            compare(text.font.pixelSize, body.pixelSize, "polyphony data row uses the body size")
            compare(text.font.weight, body.weight, "polyphony data row keeps regular body weight")
        }
        compare(probe.lastJumpTick(), -1, "no event has requested a navigation")
        compare(probe.observedJumpCount(), 0, "no pointer action has emitted a jump")
        mouseClick(live, live.width / 2, live.height / 2)
        compare(probe.lastJumpTick(), -1,
                "live overflow cannot request a document cursor jump")
        mouseDoubleClickSequence(live, live.width / 2, live.height / 2, Qt.LeftButton)
        compare(probe.lastJumpTick(), -1,
                "double-clicking live overflow cannot request a document cursor jump")
        compare(probe.observedJumpCount(), 0,
                "live row pointer activation emits no navigation callback")
        mouseClick(row, row.width / 2, row.height / 2)
        compare(probe.lastJumpTick(), -1,
                "single-clicking a positioned log row does not jump")
        mouseDoubleClickSequence(row, row.width / 2, row.height / 2, Qt.LeftButton)
        compare(probe.lastJumpTick(), 96,
                "double-clicking a positioned log row requests the event's document tick")
        compare(probe.observedJumpCount(), 1,
                "positioned row double-click emits exactly one navigation callback")
        compare(probe.lastJumpTrack(), 2,
                "positioned row pointer navigation targets track index two")
        compare(probe.lastJumpKey(), 60,
                "positioned row pointer navigation targets middle C")
        compare(probe.lastJumpDpr(), referencePane.Screen.devicePixelRatio,
                "positioned row pointer navigation retains the rendered screen DPR")
        probe.bumpOverflowCounter()
        var overflowCell = findChild(referencePane, "polyphonyOverflowRow_1")
        verify(overflowCell, "the increasing track has a rendered counter row")
        var flashingRow = overflowCell.parent.parent
        verify(flashingRow.flashAlpha > 0.5, "counter increase highlights its track")
        var flashOverlay = findChild(flashingRow, "polyphonyFlashOverlay")
        verify(flashOverlay && flashOverlay.opacity > 0.5,
               "the counter row paints its translucent flash overlay")
        scroll.contentY = 0
        verify(waitForPolish(referencePane), "flashing track scrolls into the viewport")
        var flashingText = findChild(flashingRow, "polyphonyCounterText")
        waitForRendering(referencePane)
        var observation = Audit.measure(flashingText, grabImage(shell.contentItem), shell.contentItem)
        verify(observation !== null, "the flashing counter text is painted on the row")
        verify(observation.ratio >= observation.required,
               "flashing counter text meets WCAG AA on its faded row surface: "
               + observation.fg + " on " + observation.bg + " = " + observation.ratio)
        referencePane.height = referencePane.em * 30
        verify(waitForPolish(referencePane), "short pane settles its scroll extent")
        verify(scroll.contentHeight > scroll.height,
               "a short pane keeps the log reachable by scrolling")
        referencePane.height = 600
        verify(waitForPolish(referencePane), "reference pane returns to its original height")
        referencePane.height = referencePane.em * 980 / 12
        verify(waitForPolish(referencePane), "expanded pane settles its scroll extent")
        compare(Math.max(0, scroll.contentHeight - scroll.height), 0,
                "expanded pane has no vertical scroll range")
        var reset = findChild(referencePane, "polyphonyReset")
        mouseClick(reset, reset.width / 2, reset.height / 2)
        compare(fixture.eventCount, 0, "Reset clears visible diagnostic events")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return !dock().visible }, 3000,
                  "the same View action hides the mounted panel")
    }

    function test_mountedEventRowRevealsOnlySoundingNoteWithoutEditing() {
        const presenter = createShell()
        const session = presenter.session
        bootstrap.children.push(presenter)
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        const loadSettled = waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(loadSettled && session.songOpen && waitForNative(function() {
            const root = shell.sceneLoader.item
            const page = root && findChild(root, "songTab_" + session.songTabs.selectedId)
            const surface = page && findChild(page, "swiftRollOverlay")
            return !!surface && findChild(surface, "swiftRollInput") !== null
        }, 10000), "the real roll mounts before the event-row journey")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return dock().visible && panel().visible }, 3000,
                  "the View action opens the real debugger dock")

        const fixtureText = bootstrap.seedPolyphonyReveal()
        verify(fixtureText.length > 0, "the mounted song accepts three matched fixture notes")
        const fixture = JSON.parse(fixtureText)
        const earlier = fixture[0]
        const sounding = fixture[1]
        const otherTrack = fixture[3]
        const pane = panel()
        tryVerify(function() {
            return session.polyphony.eventCount === 3
                && findChild(pane, "polyphonyEventRow_2") !== null
        }, 3000, "all three event delegates mount on the production panel")
        const scroll = findChild(pane, "polyphonyScroll")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        verify(waitForPolish(pane), "the mounted event log settles inside the visible dock")
        const baseline = JSON.parse(bootstrap.polyphonyRevealState())
        verify(baseline.selected.length === 1 && baseline.selected[0] === fixture[2]
               && baseline.track === otherTrack && baseline.bytes.length > 0
               && baseline.noteX > baseline.viewportWidth,
               "the roll begins away from the event with a different note selected")

        function doubleClickEvent(index) {
            const row = findChild(pane, "polyphonyEventRow_" + index)
            verify(row !== null && row.width > 0 && row.height > 0,
                   "the addressed event delegate exists and has a pointer target")
            const location = row.mapToItem(pane, 0, 0)
            verify(location.y >= 0 && location.y + row.height <= pane.height,
                   "the addressed row is inside the visible debugger dock")
            mouseDoubleClickSequence(row, row.width / 2, row.height / 2, Qt.LeftButton)
        }

        doubleClickEvent(2)
        tryVerify(function() {
            return bootstrap.polyphonyRevealTrack() === 0
        }, 3000, "the real positioned-row gesture reaches the selected roll track")
        waitForRendering(pane)
        const hit = JSON.parse(bootstrap.polyphonyRevealState())
        verify(hit.scrollX > baseline.scrollX && hit.noteX >= 0
               && hit.noteX <= hit.viewportWidth && hit.selected[0] === sounding
               && hit.selected[0] !== earlier,
               "mounted row reveals the last still-sounding same-key note inside the roll")
        compare(hit.track, 0, "mounted hit row selects its losing track")
        compare(JSON.stringify(hit.selected), JSON.stringify([sounding]),
                "mounted hit row selects exactly the last sounding same-key note")
        compare(JSON.stringify([hit.undoIndex, hit.undoCount]),
                JSON.stringify([baseline.undoIndex, baseline.undoCount]),
                "mounted hit row preserves undo index and count")
        compare(hit.bytes, baseline.bytes, "mounted hit row preserves exact exported MIDI bytes")

        verify(bootstrap.stagePolyphonyMiss(otherTrack, sounding),
               "the unused-key case restores a different track and the selected sounding note")
        tryVerify(function() {
            return bootstrap.polyphonyRevealTrack() === otherTrack
        }, 3000, "the miss starts on the alternate track after the QtBridge turn")
        doubleClickEvent(1)
        tryVerify(function() {
            return bootstrap.polyphonyRevealTrack() === 0
        }, 3000, "the unused-key row dispatches to the roll selection consumer")
        waitForRendering(pane)
        const unused = JSON.parse(bootstrap.polyphonyRevealState())
        compare(JSON.stringify(unused.selected), JSON.stringify([sounding]),
                "mounted unused-key row retains the existing note without claiming another")
        compare(unused.track, 0, "mounted unused-key row still switches to its losing track")
        compare(JSON.stringify([unused.undoIndex, unused.undoCount]),
                JSON.stringify([baseline.undoIndex, baseline.undoCount]),
                "mounted unused-key row preserves undo index and count")
        compare(unused.bytes, baseline.bytes,
                "mounted unused-key row preserves exact exported MIDI bytes")

        verify(bootstrap.stagePolyphonyMiss(otherTrack, sounding),
               "the expired-note case again restores the note on an alternate track")
        tryVerify(function() {
            return bootstrap.polyphonyRevealTrack() === otherTrack
        }, 3000, "the expired-note miss starts after the QtBridge turn")
        doubleClickEvent(0)
        tryVerify(function() {
            return bootstrap.polyphonyRevealTrack() === 0
        }, 3000, "the expired-note row dispatches to the roll selection consumer")
        waitForRendering(pane)
        const expired = JSON.parse(bootstrap.polyphonyRevealState())
        compare(JSON.stringify(expired.selected), JSON.stringify([sounding]),
                "mounted expired same-key row never claims the earlier expired note")
        compare(JSON.stringify([expired.undoIndex, expired.undoCount]),
                JSON.stringify([baseline.undoIndex, baseline.undoCount]),
                "mounted expired-key row preserves undo index and count")
        compare(expired.bytes, baseline.bytes,
                "mounted expired-key row preserves exact exported MIDI bytes")
    }

    function collectChannelCells(item, cells) {
        if (item.objectName === "polyphonyChannelCell")
            cells.push(item)
        if (item.children.length > 0
                && item.children[0].objectName === "polyphonyChannelCell")
            verify(waitForPolish(item), "channel flow relayout settles before measuring resized cells")
        for (const child of item.children)
            collectChannelCells(child, cells)
    }

    function responsiveGeometry(pane) {
        const usage = findChild(pane, "polyphonyUsageSection")
        const overflow = findChild(pane, "polyphonyOverflowSection")
        const scroll = findChild(pane, "polyphonyScroll")
        const cells = []
        collectChannelCells(usage, cells)
        verify(waitForPolish(pane), "responsive sections settle after channel flow relayout")
        const u = usage.mapToItem(pane, 0, 0)
        const o = overflow.mapToItem(pane, 0, 0)
        const rectsFit = u.x >= 0 && u.y >= 0 && u.x + usage.width <= pane.width
            && o.x >= 0 && o.y >= 0 && o.x + overflow.width <= pane.width
            && u.y + usage.height <= scroll.contentHeight
            && o.y + overflow.height <= scroll.contentHeight
        var cellsFit = cells.length > 0
        for (const cell of cells) {
            const point = cell.mapToItem(scroll.contentItem, 0, 0)
            if (point.x < 0 || point.x + cell.width > scroll.width
                    || point.y < 0 || point.y + cell.height > scroll.contentHeight
                    || cell.mapToItem(usage, 0, 0).y + cell.height > usage.height)
                cellsFit = false
        }
        return {
            rectsFit: rectsFit,
            stacked: o.y >= u.y + usage.height,
            sideBySide: o.x >= u.x + usage.width,
            cellsFit: cellsFit
        }
    }

    function test_responsiveChannelGridAndSections() {
        const presenter = createShell()
        const session = presenter.session
        const fixture = probe.fixturePresenter()
        referencePane = referenceComponent.createObject(shell.contentItem, {
            presenter: fixture, colors: session.palette,
            typography: session.typographyFonts, layoutSpaces: session.layoutSpaces,
            baseFontPx: session.baseFontPx, width: 380, height: 760
        })
        verify(referencePane, "responsive geometry uses the production panel with rich events")
        verify(findChild(referencePane, "polyphonyUsageSection")
               && findChild(referencePane, "polyphonyOverflowSection")
               && findChild(referencePane, "polyphonyScroll"),
               "responsive production pane mounts usage overflow and scroll viewport")
        verify(waitForPolish(referencePane), "initial tall pane settles its complete geometry")
        var geometry = responsiveGeometry(referencePane)
        verify(geometry.rectsFit && geometry.stacked,
               "initial tall panel keeps complete usage and overflow rectangles stacked in scrollable content")
        verify(geometry.cellsFit, "initial tall panel contains every rendered channel cell")

        referencePane.width = 180
        referencePane.height = 980
        verify(waitForPolish(referencePane), "tall narrow pane settles its complete geometry")
        compare(referencePane.wideLayout, false, "tall narrow pane selects vertical layout")
        geometry = responsiveGeometry(referencePane)
        verify(geometry.rectsFit,
               "tall narrow panel keeps complete usage and overflow rectangles inside scrollable content")
        verify(geometry.stacked, "tall narrow overflow rectangle begins below the usage rectangle")
        verify(geometry.cellsFit, "tall narrow panel contains every rendered channel cell")

        referencePane.width = 900
        referencePane.height = 600
        verify(waitForPolish(referencePane), "wide pane settles its complete geometry")
        compare(referencePane.wideLayout, true, "wide pane selects horizontal layout")
        geometry = responsiveGeometry(referencePane)
        verify(geometry.rectsFit && geometry.sideBySide,
               "wide panel keeps complete usage and overflow rectangles separated in scrollable content")
        verify(geometry.cellsFit, "wide panel contains every rendered channel cell")

        referencePane.width = 380
        referencePane.height = 240
        verify(waitForPolish(referencePane), "short pane settles its complete geometry for the grid")
        compare(referencePane.wideLayout, false, "short pane selects vertical layout")
        geometry = responsiveGeometry(referencePane)
        verify(geometry.rectsFit && geometry.stacked,
               "short panel keeps complete usage and overflow rectangles stacked in scrollable content")
        verify(geometry.cellsFit, "short panel contains every rendered channel cell")
        const scroll = findChild(referencePane, "polyphonyScroll")
        verify(scroll.contentHeight > scroll.height,
               "short responsive panel exposes the clipped log via scrolling")

        referencePane.height = 980
        verify(waitForPolish(referencePane), "expanded pane settles its complete geometry for the grid")
        compare(referencePane.wideLayout, false, "expanded pane selects vertical layout")
        geometry = responsiveGeometry(referencePane)
        verify(geometry.rectsFit && geometry.stacked,
               "expanded panel keeps complete usage and overflow rectangles stacked in scrollable content")
        verify(geometry.cellsFit, "expanded panel contains every rendered channel cell")
        compare(Math.max(0, scroll.contentHeight - scroll.height), 0,
                "expanded responsive panel restores zero vertical scroll range")
    }

    function test_polyphonyLayoutScales() {
        const presenter = createShell()
        const session = presenter.session
        const em = session.baseFontPx
        const fixture = probe.fixturePresenter()
        fixture.setInvertChecked(true)
        referencePane = referenceComponent.createObject(shell.contentItem, {
            presenter: fixture, colors: session.palette,
            typography: session.typographyFonts, layoutSpaces: session.layoutSpaces,
            baseFontPx: em, width: Math.round(em * 48), height: Math.round(em * 70)
        })
        const pane = referencePane
        verify(pane && fixture.showingShadow,
               "font-scaled layout mounts the production panel with the shadow snapshot")
        verify(responsiveGeometry(pane).cellsFit, "font-scaled 48x70 em panel settles its channel cells")
        tryCompare(pane, "wideLayout", false, 3000, "font-scaled 48x70 em panel keeps the narrow layout")
        tryVerify(function() {
            return pane.overflowSectionRect.y >= pane.usageSectionRect.y + pane.usageSectionRect.height
        }, 3000, "font-scaled narrow panel stacks the overflow section below usage")
        tryVerify(function() { return pane.gridFullyVisible }, 3000,
                  "font-scaled narrow panel shows the complete channel grid")

        pane.width = Math.round(em * 75)
        pane.height = Math.round(em * 50)
        verify(responsiveGeometry(pane).cellsFit, "font-scaled 75x50 em panel settles its channel cells")
        tryCompare(pane, "wideLayout", true, 3000, "font-scaled 75x50 em panel activates the wide layout")
        tryVerify(function() {
            return pane.overflowSectionRect.x >= pane.usageSectionRect.x + pane.usageSectionRect.width
        }, 3000, "font-scaled wide panel places the overflow section right of usage")
        tryVerify(function() { return pane.gridFullyVisible }, 3000,
                  "font-scaled wide panel shows the complete channel grid")

        pane.width = Math.round(em * 32)
        pane.height = Math.round(em * 20)
        verify(responsiveGeometry(pane).cellsFit, "font-scaled 32x20 em panel settles its channel cells")
        tryCompare(pane, "wideLayout", false, 3000, "font-scaled 32x20 em panel falls back to the narrow layout")
        tryVerify(function() { return pane.gridFullyVisible }, 3000,
                  "font-scaled small panel shows the complete channel grid")
        tryVerify(function() { return pane.vScrollRange > 0 }, 3000,
                  "font-scaled small panel exposes a vertical scroll range")
        fixture.setInvertChecked(false)
    }

    function compareRegion(reference, name, target, tolerance) {
        var expected = reference.regions.filter(function(region) { return region.name === name })[0]
        verify(expected, "widget baseline contains " + name)
        verify(target, "production pane exposes " + name)
        var position = target.mapToItem(referencePane, 0, 0)
        verify(Math.abs(position.x - expected.x) <= tolerance
            && Math.abs(position.y - expected.y) <= tolerance,
            name + " preserves widget position within " + tolerance + " px: "
            + position.x + "," + position.y + " vs " + expected.x + "," + expected.y)
        verify(Math.abs(target.width - expected.w) <= tolerance
            && Math.abs(target.height - expected.h) <= tolerance,
            name + " preserves widget size within " + tolerance + " px: "
            + target.width + "×" + target.height + " vs " + expected.w + "×" + expected.h)
    }

    function test_visualProfiles() {
        var profile = probe.profileName
        verify(typeof profile === "string",
               "profileName must bridge as a String; check PolyphonyShellProbe registration")
        if (profile.length === 0)
            skip("profile captures run in dedicated DPR children")
        var px = profile.indexOf("font16") >= 0 ? 16 : 12
        var presenter = createShell()
        compare(presenter.session.baseFontPx, px,
                "profile child captures its base before mounting polyphony")
        var fixture = probe.fixturePresenter()
        referencePane = referenceComponent.createObject(shell.contentItem, {
            presenter: fixture, colors: presenter.session.palette,
            typography: presenter.session.typographyFonts,
            layoutSpaces: presenter.session.layoutSpaces,
            baseFontPx: presenter.session.baseFontPx, width: 380, height: 600
        })
        var pane = referencePane
        verify(pane, "the production polyphony pane mounts with the isolated fixture")
        var states = ["narrow-vanilla", "wide-vanilla",
                      "narrow-darkneutralhigh", "wide-darkneutralhigh"]
        for (var i = 0; i < states.length; ++i) {
            var state = states[i]
            var json = probe.baseline(profile, state)
            verify(typeof json === "string" && json.length > 0,
                   state + " fixture is missing for " + profile
                   + " under src/checks/fixtures/visual/macos-" + profile + "/polyphony/")
            bootstrap.preferences.setString("theme.mode", state.indexOf("darkneutralhigh") >= 0
                                            ? "dark-neutral-high" : "vanilla")
            bootstrap.preferences.setString("theme.grid-line-contrast", "50")
            presenter.restoreAppearance()
            var baseline = JSON.parse(json)
            testCase.width = Math.max(testCase.width, baseline.image.width + 16)
            testCase.height = Math.max(testCase.height, baseline.image.height + 16)
            pane.width = baseline.image.width
            pane.height = baseline.image.height
            verify(waitForPolish(pane), "pane geometry settles before capture")
            var usageGroups = findChild(pane, "polyphonyUsageSection").children[1].children
            for (var group = 0; group < usageGroups.length; ++group) {
                if (usageGroups[group].children.length > 1)
                    verify(waitForPolish(usageGroups[group].children[1]),
                           "channel flow relayout settles at the profile width")
            }
            compare(pane.em, presenter.session.baseFontPx,
                    "panel em follows the published base instead of body")
            compare(pane.Screen.devicePixelRatio, baseline.image.dpr,
                    "the profile child renders at the widget baseline DPR")
            compare(Math.round(pane.width), baseline.image.width, "the pane matches widget width")
            compare(Math.round(pane.height), baseline.image.height, "the pane matches widget height")
            compare(pane.wideLayout, state.indexOf("wide-") === 0,
                    "the widget's responsive breakpoint matches the frozen profile")
            verify(waitForPolish(pane), "fixture channel rows settle before geometry comparison")
            compareRegion(baseline, "poly.invert", findChild(pane, "polyphonyInvert"), px / 2)
            compareRegion(baseline, "poly.overflow-heading", findChild(pane, "polyphonyOverflowHeading"), px)
            compareRegion(baseline, "poly.overflow-table", findChild(pane, "polyphonyOverflowTable"), px * 2)
            compareRegion(baseline, "poly.overflow-row.0", findChild(pane, "polyphonyOverflowRow_0"), px)
            compareRegion(baseline, "poly.event-log", findChild(pane, "polyphonyEventLog"), px * 2)
            compareRegion(baseline, "poly.log-row.0", findChild(pane, "polyphonyEventRow_0"), px)
            compareRegion(baseline, "poly.usage-heading", findChild(pane, "polyphonyUsageHeading"), px)
            compareRegion(baseline, "poly.overflow-section", findChild(pane, "polyphonyOverflowSection"), px * 2)
            compareRegion(baseline, "poly.log-heading", findChild(pane, "polyphonyLogHeading"), px * 2)
            verify(waitForPolish(pane), "rich snapshot paints")
            var saved = false
            pane.grabToImage(function(result) {
                saved = result.saveToFile("file://" + probe.artifactPath(bootstrap.projectRoot,
                                                                         profile, state))
            })
            tryVerify(function() { return saved }, 5000,
                      state + " production pane captured against widget baseline")
        }
    }
}
