import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "TextContrastAudit.js" as Audit

TestCase {
    id: testCase
    name: "ShellPolyphony"
    when: windowShown
    width: 960
    height: 760
    visible: true
    property var shell: null
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

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function createShell() {
        shell = (probe.profileName.length > 0 ? profileShellComponent : shellComponent).createObject(null)
        verify(shell, "the production shell mounts")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        return shell.shellPresenter
    }

    function cleanup() {
        if (referencePane) {
            referencePane.destroy()
            referencePane = null
        }
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close gate completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
                   "the shell retires its editor scene")
        }
        bootstrap.children.length = 0
        shell.destroy()
        shell = null
        wait(0)
    }


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
        const cell = findChild(pane, "polyphonyChannelCell")
        verify(cell !== null, "mounted channel group has a rendered cell")
        compare(cell.width, Math.round(session.baseFontPx * 46 / 12),
                "channel cell width follows fontPx(46/12)")
        const label = cell.children[0]
        compare(label.font.family, caption.family, "channel cell label uses caption family")
        compare(label.font.pixelSize, caption.pixelSize, "channel cell label uses caption size")
        compare(label.font.weight, caption.weight, "channel cell label keeps caption weight")
    }

    function test_viewActionAndEventNavigation() {
        var presenter = createShell()
        var session = presenter.session
        var poly = session.polyphony
        verify(!presenter.polyphonyVisible && !dock().visible,
               "the debugger starts hidden")
        compare(presenter.actionLabel("view.polyphony_debugger"), "Polyphony Debugger")
        verify(presenter.actionEnabled("view.polyphony_debugger"),
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
        var flashSaved = false
        verify(referencePane.grabToImage(function(result) {
            flashSaved = result.saveToFile("file://" + probe.artifactPath(bootstrap.projectRoot,
                                                                          "flash", ""))
        }), "flashing pane capture starts")
        tryVerify(function() { return flashSaved }, 5000,
                  "the polyphony-flash.png artifact captures the painted flash")
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
