import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "ShellTabs"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    property var settings: null

    ShellQmlBootstrap { id: bootstrap }
    TabsDrawerProbe { id: fileProbe }

    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "genuine QtCore.Settings is available")
    }

    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            var settled = false
            for (var step = 0; step < 12 && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                        || shell.shellPresenter.session.songTabs.pendingCloseBankTitle.length > 0
                }, 5000)
                if (!gate)
                    break
                if (shell.shellPresenter.closeReady) {
                    settled = true
                    break
                }
                shell.shellPresenter.session.songTabs.confirmDiscard()
                wait(50)
            }
            verify(shell.shellPresenter.closeReady,
                   "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function seedDrawerPrefs() {
        settings.setValue("editorDrawer/velocityVisible", true)
        settings.setValue("editorDrawer/velocityHeight", 173)
        settings.setValue("editorDrawer/automationVisible", true)
        settings.setValue("editorDrawer/automationHeight", 200)
        settings.setValue("editorDrawer/voiceChangesVisible", true)
        settings.setValue("editorDrawer/voiceChangesHeight", 200)
        settings.setValue("editorDrawer/activePage", "velocity")
        settings.sync()
    }

    function openShell(labels) {
        // Every explicit-open test starts without a stale startup recipe.
        settings.setValue("lastProjectDir", "")
        settings.sync()
        seedDrawerPrefs()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        var toolbar = findChild(shell, "transportToolbar")
        verify(toolbar !== null && toolbar.height > 0, "mounted transport has a measured height")
        shell.height += toolbar.height
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, labels[0])
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the first song loads" + openDiagnostics(session))
        var ids = []
        tryCompare(session.songTabs, "tabCount", 1)
        ids.push(session.songTabs.selectedId)
        waitForPage(ids[0])
        for (var i = 1; i < labels.length; ++i) {
            session.openSong(labels[i])
            var expected = i + 1
            verify(waitForNative(function() {
                return session.songTabs.tabCount === expected
                    || session.lastSaveError.length > 0
            }, 30000), labels[i] + " appends a tab" + openDiagnostics(session))
            ids.push(session.songTabs.selectedId)
            waitForPage(ids[i])
        }
        return ids
    }

    function waitForPage(tabId) {
        var session = shell.shellPresenter.session
        verify(waitForNative(function() {
            var grid = testCase.gridOf(tabId)
            return grid !== null && grid.renderedNoteCount > 0
        }, 30000), "tab " + tabId + " publishes its rendered grid"
            + openDiagnostics(session))
        waitForRendering(tabsRoot())
    }

    function tabs() { return shell.shellPresenter.session.songTabs }
    function session() { return shell.shellPresenter.session }
    function tabsRoot() { return shell.sceneLoader.item }
    function strip() { return findChild(tabsRoot(), "songTabStrip") }
    function pages() { return findChild(tabsRoot(), "songTabPages") }
    function selectButton(tabId) { return findChild(tabsRoot(), "songTabSelect_" + tabId) }
    function closeButton(tabId) { return findChild(tabsRoot(), "songTabClose_" + tabId) }
    function scrollLeft() { return findChild(tabsRoot(), "songTabScrollLeft") }
    function scrollRight() { return findChild(tabsRoot(), "songTabScrollRight") }
    function pageOf(tabId) { return findChild(pages(), "songTab_" + tabId) }
    function surfaceOf(tabId) {
        var page = pageOf(tabId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function gridOf(tabId) {
        var surface = surfaceOf(tabId)
        return surface ? surface.gridModel : null
    }
    function summaryOf(tabId) { return gridOf(tabId).noteSummary }
    function dialogButton(name) {
        var button = findChild(shell, name)
        if (button)
            return button
        var matches = collectAll(name)
        return matches.length > 0 ? matches[0] : null
    }
    function awaitGateButtons() {
        return waitForNative(function() {
            var save = dialogButton("songTabSave")
            var discard = dialogButton("songTabDiscard")
            var cancel = dialogButton("songTabCancel")
            return save !== null && discard !== null && cancel !== null
                && save.visible && discard.visible && cancel.visible
        }, 5000)
    }
    function collectByPrefix(item, prefix, found) {
        var collected = found || []
        if (!item)
            return collected
        if (String(item.objectName).indexOf(prefix) === 0)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByPrefix(item.children[i], prefix, collected)
        return collected
    }

    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByName(item.children[i], name, collected)
        return collected
    }

    function tabOrderIds() {
        var buttons = testCase.collectByPrefix(tabsRoot(), "songTabSelect_", [])
        buttons.sort(function(a, b) { return a.x - b.x })
        return buttons.map(function(item) {
            return parseInt(String(item.objectName).slice("songTabSelect_".length), 10)
        })
    }

    function tabButtonVisible(tabId) {
        var button = selectButton(tabId)
        var stripItem = strip()
        if (!button || !stripItem || !button.visible)
            return false
        var visibleWidth = stripItem.width
        var left = scrollLeft()
        if (left && left.visible)
            visibleWidth = stripItem.width - left.parent.width
        var buttonLeft = button.x
        var buttonRight = button.x + button.width
        var viewportX = stripViewport().contentX
        return buttonLeft >= viewportX - 0.5
            && buttonRight <= viewportX + visibleWidth + 0.5
    }

    function stripViewport() {
        var stripItem = strip()
        for (var i = 0; i < stripItem.children.length; ++i) {
            var child = stripItem.children[i]
            if (child.contentX !== undefined && child.contentWidth !== undefined)
                return child
        }
        return null
    }

    function revealTab(tabId) {
        var button = selectButton(tabId)
        verify(button, "tab " + tabId + " has a strip button")
        var stripItem = strip()
        var center = stripItem.width / 2
        for (var attempt = 0; attempt < 64 && !tabButtonVisible(tabId); ++attempt) {
            var origin = button.mapToItem(stripItem, button.width / 2, button.height / 2)
            var pointsLeft = origin.x < center
            var control = pointsLeft ? scrollLeft() : scrollRight()
            verify(control && control.visible,
                   "the strip exposes a scroll control toward tab " + tabId)
            verify(control.enabled, "the scroll control is enabled before tab "
                   + tabId + " is revealed")
            mouseClick(control, control.width / 2, control.height / 2)
            wait(50)
        }
        verify(tabButtonVisible(tabId),
               "the strip's scroll controls revealed tab " + tabId)
    }

    function clickSelectTab(tabId) {
        revealTab(tabId)
        var button = selectButton(tabId)
        mouseClick(button, button.width / 3, button.height / 2)
        verify(waitForNative(function() {
            var page = pageOf(tabId)
            return tabs().selectedId === tabId && page !== null && page.visible
        }, 5000), "clicking tab " + tabId + " selects its page")
    }

    function pointFor(tabId, tick, pitch) {
        var grid = gridOf(tabId)
        var surface = surfaceOf(tabId)
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var x = tick * pixelsPerTick - grid.cameraScrollX
        var y = (127.0 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        return fills.mapToItem(findChild(surface, "swiftRollInput"), x, y)
    }

    function drawNote(tabId) {
        var grid = gridOf(tabId)
        var input = findChild(surfaceOf(tabId), "swiftRollInput")
        var plot = findChild(surfaceOf(tabId), "timelineQuickRollPlot")
        var before = JSON.parse(summaryOf(tabId))
        var snap = grid.snapTicks
        verify(snap > 0, "tab " + tabId + " publishes its snap resolution")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var firstTick = Math.ceil(((grid.cameraScrollX + 24.0) / pixelsPerTick) / snap) * snap
        var lastTick = Math.floor(((grid.cameraScrollX + plot.width - 24.0) / pixelsPerTick) / snap) * snap
        var firstRow = Math.max(0, Math.min(127, Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2))
        var lastRow = Math.max(0, Math.min(127, Math.floor((grid.cameraScrollY + plot.height) / grid.rowHeight) - 2))
        var tick = -1
        var pitch = -1
        for (var row = firstRow; row <= lastRow && tick < 0; ++row) {
            var candidatePitch = 127 - row
            for (var candidate = Math.max(0, firstTick);
                 candidate + 2 * snap <= lastTick && tick < 0; candidate += snap) {
                var end = candidate + 2 * snap
                var occupied = before.some(function(note) {
                    return note.pitch === candidatePitch
                        && note.tick < end + snap
                        && note.tick + note.duration > candidate - snap
                })
                if (!occupied) {
                    tick = candidate
                    pitch = candidatePitch
                }
            }
        }
        verify(tick >= 0, "tab " + tabId + " has a visible empty lane to draw in")
        var inset = Math.max(1, snap / 4)
        var start = pointFor(tabId, tick + inset, pitch)
        var finish = pointFor(tabId, tick + 2 * snap - inset, pitch)
        mouseMove(input, start.x, start.y)
        mousePress(input, start.x, start.y, Qt.LeftButton)
        mouseMove(input, finish.x, finish.y, 20, Qt.LeftButton)
        mouseRelease(input, finish.x, finish.y, Qt.LeftButton)
        var drawn = null
        verify(waitForNative(function() {
            var after = JSON.parse(summaryOf(tabId))
            return after.length === before.length + 1
        }, 5000), "a real pointer drag added one note to tab " + tabId)
        var after = JSON.parse(summaryOf(tabId))
        for (var i = 0; i < after.length; ++i) {
            if (!before.some(function(note) { return note.id === after[i].id }))
                drawn = after[i]
        }
        verify(drawn, "the drawn note has a new document identity")
        return drawn
    }


    function regionOf(image, anchor, control) {
        var origin = control.mapToItem(anchor, 0, 0)
        var anchorWin = anchor.mapToItem(null, 0, 0)
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.max(0, Math.round((origin.x + anchorWin.x) * scaleX)),
                 y0: Math.max(0, Math.round((origin.y + anchorWin.y) * scaleY)),
                 x1: Math.min(image.width - 1,
                              Math.round((origin.x + anchorWin.x + control.width) * scaleX) - 1),
                 y1: Math.min(image.height - 1,
                              Math.round((origin.y + anchorWin.y + control.height) * scaleY) - 1) }
    }

    function collectAll(prefix) {
        var collected = []
        var roots = [shell.contentItem]
        for (var i = 0; i < shell.data.length; ++i)
            roots.push(shell.data[i])
        for (var r = 0; r < roots.length; ++r)
            testCase.collectByPrefix(roots[r], prefix, collected)
        return collected
    }
    function channelsOf(color) {
        var value = parseInt(String(color).slice(-6), 16)
        return [(value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff]
    }

    function pixelDistance(image, x, y, target) {
        return Math.max(Math.abs(image.red(x, y) - target[0]),
                        Math.abs(image.green(x, y) - target[1]),
                        Math.abs(image.blue(x, y) - target[2]))
    }

    function changedPixels(before, after, region, limit) {
        var changed = 0
        var cap = limit || 1000000
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (imagePixelDiffers(before, after, x, y)) {
                    if (++changed > cap)
                        return changed
                }
            }
        }
        return changed
    }

    function imagePixelDiffers(before, after, x, y) {
        return before.red(x, y) !== after.red(x, y)
            || before.green(x, y) !== after.green(x, y)
            || before.blue(x, y) !== after.blue(x, y)
    }

    function matchingColorCount(image, region, target, tolerance) {
        var count = 0
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (pixelDistance(image, x, y, target) <= tolerance)
                    ++count
            }
        }
        return count
    }
    function grabRegionStable(item, region) {
        var previous = grabImage(item)
        for (var i = 0; i < 20; ++i) {
            wait(100)
            var next = grabImage(item)
            if (changedPixels(previous, next, region, 0) === 0)
                return next
            previous = next
        }
        return previous
    }

    function grabUntilDifferent(item, reference, region) {
        var frame = grabImage(item)
        for (var i = 0; i < 30 && changedPixels(reference, frame, region, 16) <= 16; ++i) {
            wait(100)
            frame = grabImage(item)
        }
        return frame
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

        var tabMetrics = { 14: { strip: 22, tab: 28 }, 15: { strip: 23, tab: 28 },
                           18: { strip: 27, tab: 28 } }
        var metrics = tabMetrics[button.font.pixelSize]
        verify(metrics !== undefined,
               "the tab label font resolves to a captured production scale")
        compare(button.font.weight, Font.DemiBold, "the tab caption keeps DemiBold weight")
        compare(Math.round(stripItem.height), metrics.strip,
                "the strip keeps its production height")
        compare(Math.round(button.height), metrics.tab,
                "the tab body keeps its production height")
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
        compare(JSON.stringify(JSON.parse(selectedGrid.noteSummary)),
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
        compare(JSON.stringify(JSON.parse(firstSurface.gridModel.noteSummary)),
                JSON.stringify(JSON.parse(summaryOf(firstId))),
                "the open tab keeps its grid")
        compare(JSON.stringify(JSON.parse(secondSurface.gridModel.noteSummary)),
                JSON.stringify(JSON.parse(summaryOf(secondId))),
                "the appended tab publishes its own grid")
    }

    function test_eSwitchPreservesState() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        clickSelectTab(firstId)

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

    function test_gBackgroundClosePreservesActive() {
        var ids = openShell(["mus_route101", "mus_littleroot_test", "mus_route102"])
        var firstId = ids[0]
        var secondId = ids[1]
        var thirdId = ids[2]
        clickSelectTab(secondId)
        var activeSummary = summaryOf(secondId)
        var activePage = pageOf(secondId)
        var activeRow = tabOrderIds().indexOf(secondId)
        verify(activeRow >= 0, "the active tab has a strip row")

        var close = closeButton(thirdId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 5000),
               "closing the background tab removes its row")
        compare(tabs().pendingCloseId, -1, "a clean close asks nothing")
        compare(tabOrderIds().indexOf(thirdId), -1, "the closed tab left the strip")
        verify(waitForNative(function() { return pageOf(thirdId) === null }, 5000),
               "the closed tab's page is destroyed")
        compare(tabs().selectedId, secondId, "the background close keeps the selection")
        compare(tabOrderIds().indexOf(secondId), activeRow,
                "the background close keeps the active row")
        verify(pageOf(secondId) === activePage, "the background close keeps the active page")
        compare(summaryOf(secondId), activeSummary, "the active document is untouched")
        verify(pageOf(secondId).visible, "the active page stays presented")
        verify(pageOf(firstId) !== null, "the background close kept the first tab")
    }

    function test_gSelectedCleanCloseRetargetsSurvivor() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var survivorId = ids[0]
        var closingId = ids[1]
        compare(tabs().selectedId, closingId, "the second tab is selected")
        var close = closeButton(closingId)
        verify(close && close.visible, "the selected tab has a close control")
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(tabs(), "tabCount", 1, 5000)
        tryCompare(tabs(), "selectedId", survivorId, 5000)
        verify(waitForNative(function() { return pageOf(closingId) === null }, 5000),
               "the closed tab left the strip and its page is destroyed")
        verify(waitForNative(function() {
            var survivorSurface = surfaceOf(survivorId)
            return survivorSurface && survivorSurface.visible
        }, 5000), "the survivor page is presented")
        var survivorSurface = surfaceOf(survivorId)
        verify(survivorSurface, "the survivor surface resolves after presentation")
        var headers = findChild(survivorSurface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the survivor track headers are mounted")
        var track = headers.itemAt(survivorSurface.gridModel.trackIndex)
        verify(track && !track.isAddTrack, "the survivor has a selected track")
        compare(track.soloChecked, false, "the survivor starts with Solo off")
        var roll = findChild(survivorSurface, "swiftRollInput")
        verify(roll && roll.visible, "the survivor roll can receive the shortcut")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        tryCompare(track, "soloChecked", true, 3000)
    }

    function test_hFinalCloseEmptyAndReopen() {
        var ids = openShell(["mus_route101"])
        var onlyId = ids[0]
        compare(tabs().tabCount, 1)
        verify(JSON.parse(summaryOf(onlyId)).length > 0, "the staged song publishes notes")
        var sceneRoot = tabsRoot()
        var pagesProbe = regionOf(grabImage(tabsRoot()), tabsRoot(), pages())
        var filledFrame = grabRegionStable(tabsRoot(), pagesProbe)
        var close = closeButton(onlyId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "closing the final tab empties the strip")
        compare(tabs().pendingCloseId, -1, "a clean close asks nothing")
        compare(tabs().selectedId, -1, "no tab stays selected")
        compare(tabs().selectedIndex, -1, "no row stays selected")
        compare(session().songOpen, false, "the empty strip reports no open song")
        verify(waitForNative(function() { return pageOf(onlyId) === null }, 5000),
               "the closed tab's page is destroyed")
        compare(collectByPrefix(tabsRoot(), "songTab_", []).length, 0,
                "the empty strip publishes no grid")
        verify(tabsRoot() === sceneRoot, "the empty strip keeps its mounted scene")

        verify(strip().visible, "the empty strip stays presented")
        verify(pages().visible, "the empty page stack stays presented")
        verify(shell.sceneLoader.item !== null, "the mounted scene survives")
        var pagesRegion = regionOf(filledFrame, tabsRoot(), pages())
        var emptyFrame = grabUntilDifferent(tabsRoot(), filledFrame, pagesRegion)
        verify(emptyFrame.width > 0, "the empty workspace composited into an image")
        verify(changedPixels(filledFrame, emptyFrame, pagesRegion, 5000) > 5000,
               "the closed tab's rendering left the page stack")
        var background = channelsOf(session().palette.windowBackground)
        var ink = channelsOf(session().palette.windowText)
        var pagePixels = (pagesRegion.x1 - pagesRegion.x0 + 1)
            * (pagesRegion.y1 - pagesRegion.y0 + 1)
        var backgroundPixels = matchingColorCount(emptyFrame, pagesRegion, background, 2)
        verify(backgroundPixels > pagePixels * 0.95,
               "the empty workspace is background ink apart from its label")
        var leakedPixels = 0
        for (var px = pagesRegion.x0; px <= pagesRegion.x1; ++px) {
            for (var py = pagesRegion.y0; py <= pagesRegion.y1; ++py) {
                if (pixelDistance(emptyFrame, px, py, background) > 2
                        && pixelDistance(emptyFrame, px, py, ink) > 120)
                    ++leakedPixels
            }
        }
        compare(leakedPixels, 0, "no leaked rendering survives outside the label ink")

        session().openSong("mus_route102")
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 30000),
               "the empty strip opens again")
        verify(shell.visible, "the window stays exposed with an empty strip")
        var reopenedId = tabs().selectedId
        verify(reopenedId >= 0 && reopenedId !== onlyId,
               "the reopened tab is a new identity")
        waitForPage(reopenedId)
        verify(pageOf(reopenedId).visible, "the reopened page is presented")
        verify(selectButton(reopenedId) !== null, "the reopened song has a strip tab")
        verify(tabsRoot() === sceneRoot, "the reopened tab renders in the same view")
        waitForRendering(tabsRoot())
        var reopenedFrame = grabImage(tabsRoot())
        var reopenedRegion = regionOf(reopenedFrame, tabsRoot(), pages())
        verify(matchingColorCount(reopenedFrame, reopenedRegion, background, 2)
               < (reopenedRegion.x1 - reopenedRegion.x0 + 1)
               * (reopenedRegion.y1 - reopenedRegion.y0 + 1),
               "the reopened tab paints inside the page stack")
        verify(JSON.parse(summaryOf(reopenedId)).length > 0,
               "the reopened tab publishes its notes")
    }

    function test_iReopenExistingFocusesTab() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var firstId = ids[0]
        var secondId = ids[1]
        clickSelectTab(secondId)
        var firstRow = tabOrderIds().indexOf(firstId)
        verify(firstRow >= 0, "the first tab has a strip row")
        var firstSummary = summaryOf(firstId)
        var firstPage = pageOf(firstId)

        session().openSong("mus_route101")
        verify(waitForNative(function() { return tabs().selectedId === firstId }, 30000),
               "re-opening focuses the open tab")
        compare(tabs().tabCount, 2, "focusing adds no second tab")
        compare(tabOrderIds().indexOf(firstId), firstRow, "focusing moves no row")
        compare(tabs().selectedIndex, firstRow, "the focused row is selected")

        verify(pageOf(firstId) === firstPage, "focusing an open tab keeps its page")
        compare(summaryOf(firstId), firstSummary, "focusing an open tab keeps its document")
        verify(waitForNative(function() {
            return pageOf(firstId).visible && pageOf(firstId).enabled
        }, 5000), "the focused page is presented")
        verify(!pageOf(secondId).visible, "the sibling page is hidden")
        verify(selectButton(firstId).checked, "the focused tab is the checked tab")
    }

    function test_jDirtyCancelDiscardSave() {
        var ids = openShell(["mus_route101", "mus_route102"])
        var dirtyId = ids[0]
        var otherId = ids[1]
        clickSelectTab(dirtyId)

        var dirtyPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var otherPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route102")
        var dirtyBefore = fileProbe.fileFingerprint(dirtyPath)
        var otherBefore = fileProbe.fileFingerprint(otherPath)
        verify(dirtyBefore.length > 0, "the staged dirty song is readable")
        verify(otherBefore.length > 0, "the staged other song is readable")

        drawNote(dirtyId)
        verify(session().documentDirty, "the drawn note dirtied the tab")
        verify(session().canUndo, "the drawn note armed the tab's history")
        var dirtySummary = summaryOf(dirtyId)
        verify(waitForNative(function() {
            return String(selectButton(dirtyId).text).slice(-1) === "*"
        }, 5000), "a dirty tab's caption is marked")

        var dirtyPage = pageOf(dirtyId)
        var dirtyClose = closeButton(dirtyId)
        mouseClick(dirtyClose, dirtyClose.width / 2, dirtyClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === dirtyId },
                             5000), "the dirty close raises the gate")
        verify(waitForNative(function() { return !strip().enabled }, 5000),
               "the strip is gated while the dialog asks")
        verify(awaitGateButtons(), "the close gate offers Save, Discard and Cancel")
        var saveButton = dialogButton("songTabSave")
        var discardButton = dialogButton("songTabDiscard")
        var cancelButton = dialogButton("songTabCancel")
        var otherButton = selectButton(otherId)
        mouseClick(otherButton, otherButton.width / 3, otherButton.height / 2)
        wait(100)
        compare(tabs().selectedId, dirtyId, "the modal gate keeps the dirty selection")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId < 0 }, 5000),
               "Cancel lowers the gate")
        compare(tabs().tabCount, 2, "Cancel keeps the tab")
        compare(summaryOf(dirtyId), dirtySummary, "Cancel keeps the unsaved work")
        verify(pageOf(dirtyId) === dirtyPage, "Cancel keeps the tab's page")
        verify(session().documentDirty, "Cancel keeps the tab's unsaved work flagged")
        compare(fileProbe.fileFingerprint(dirtyPath), dirtyBefore,
                "Cancel wrote no song bytes")
        verify(waitForNative(function() { return strip().enabled }, 5000),
               "Cancel hands the strip back")
        dirtyClose = closeButton(dirtyId)
        mouseClick(dirtyClose, dirtyClose.width / 2, dirtyClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === dirtyId },
                             5000), "the dirty close raises the gate again")
        verify(awaitGateButtons(), "the gate offers its answers again")
        discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 5000),
               "Discard closes the tab")
        compare(tabs().pendingCloseId, -1, "Discard lowers the gate")
        verify(waitForNative(function() { return pageOf(dirtyId) === null }, 5000),
               "the discarded tab's page is destroyed")
        compare(tabs().selectedId, otherId, "Discard selects the surviving tab")
        compare(fileProbe.fileFingerprint(dirtyPath), dirtyBefore,
                "Discard wrote no song bytes")

        clickSelectTab(otherId)
        var saved = drawNote(otherId)
        verify(session().documentDirty, "the drawn note dirtied the tab")
        var otherClose = closeButton(otherId)
        mouseClick(otherClose, otherClose.width / 2, otherClose.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === otherId },
                             5000), "the dirty close raises the gate for Save")
        verify(awaitGateButtons(), "the gate offers its answers for Save")
        saveButton = dialogButton("songTabSave")
        mouseClick(saveButton, saveButton.width / 2, saveButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 30000),
               "Save closed the tab")
        compare(tabs().pendingCloseId, -1, "Save lowered the gate")
        compare(session().saveInProgress, false, "the gate waited for the save")
        compare(session().lastSaveError, "", "the save reported no error")
        var otherAfter = fileProbe.fileFingerprint(otherPath)
        verify(otherAfter.length > 0 && otherAfter !== otherBefore,
               "Save wrote the song to disk")

        session().openSong("mus_route102")
        var reopenedId = -1
        verify(waitForNative(function() {
            if (tabs().tabCount !== 1)
                return false
            reopenedId = tabs().selectedId
            var grid = gridOf(reopenedId)
            return grid !== null && grid.renderedNoteCount > 0
        }, 30000), "the saved song reopens")
        waitForRendering(tabsRoot())
        var persisted = JSON.parse(summaryOf(reopenedId)).some(function(note) {
            return note.tick === saved.tick && note.pitch === saved.pitch
                && note.duration === saved.duration
        })
        verify(persisted, "the saved song carries the note the user drew")
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

        var automation = pageOf(ids[0]).session.automationPage()
        verify(automation.openParameterMenu(0, 0, 0), "volume's real range menu opens")
        verify(automation.consumeMenuAction(16), "the 0–64 range is a cosmetic lane change")
        verify(!session().documentDirty, "changing an editor lane preference does not dirty MIDI")

        shell.close()
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the clean host close releases its tab pages")
        settings.sync()
        compare(settings.value("lastSongLabel"), "mus_route101",
                "final-close walk retains the previously selected tab")
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
        fuzzyCompare(gridOf(restored[1]).cameraScrollY, freshScrollY, 0.01,
                     "reopened tab starts with a fresh camera, not a saved camera")
    }

    function bankPath() { return bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc" }
    function closeGateLabel() {
        var dialog = findChild(tabsRoot(), "songTabCloseDialog")
        if (!dialog || dialog.contentChildren.length === 0)
            return ""
        return String(dialog.contentChildren[0].text)
    }

    function dirtyOpenBank() {
        var controller = session().voiceListController()
        verify(waitForNative(function() {
            return controller.isBound && controller.bankLoadName === "fixture_rich"
        }, 15000), "the open song binds its voicegroup bank")
        verify(fileProbe.fileFingerprint(bankPath()).length > 0,
               "the staged bank source is readable")
        controller.selectSlot(4)
        var draft = controller.editorModel()
        var initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release !== initial
        }, 15000), "the voice editor release edit dirties the bank")
        return controller
    }

    function orphanDirtyBank() {
        var onlyId = openShell(["mus_route101"])[0]
        var controller = dirtyOpenBank()
        var bankBefore = fileProbe.fileFingerprint(bankPath())
        var close = closeButton(onlyId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === onlyId }, 5000),
               "the bank-dirty tab close raises the tab gate")
        verify(awaitGateButtons(), "the tab gate offers Save, Discard and Cancel")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "Discard closes the last tab")
        compare(tabs().pendingCloseId, -1, "Discard lowers the tab gate")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore, "Discard wrote no bank bytes")
        return { controller: controller, bankBefore: bankBefore }
    }

    function verifyBankGate(cause) {
        compare(tabs().pendingCloseBankTitle, "fixture_rich", cause + " names the dirty bank")
        compare(tabs().pendingCloseId, -1, cause + " asks about no tab")
        verify(awaitGateButtons(), cause + " offers Save, Discard and Cancel")
        verify(closeGateLabel().indexOf("fixture_rich") >= 0,
               cause + " dialog names the bank: " + closeGateLabel())
        verify(waitForNative(function() { return !strip().enabled }, 5000),
               cause + " gates the strip while the dialog asks")
    }

    function test_lOrphanDirtyBankGatesProjectSwitch() {
        var orphan = orphanDirtyBank()
        var controller = orphan.controller
        var revisionBefore = controller.catalogRevision
        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || controller.catalogRevision !== revisionBefore
                || session().lastSaveError.length > 0
        }, 30000), "the switch either asks about the orphan bank or completes"
            + openDiagnostics(session()))
        compare(controller.catalogRevision, revisionBefore,
                "the switch waits for an answer about the orphaned dirty bank")
        verifyBankGate("the project switch")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "raising the bank gate wrote no bank bytes")

        var cancelButton = dialogButton("songTabCancel")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000),
               "Cancel lowers the bank gate")
        compare(controller.catalogRevision, revisionBefore, "Cancel aborts the switch")
        verify(session().projectOpen, "Cancel keeps the project open")
        verify(waitForNative(function() { return strip().enabled }, 5000),
               "Cancel hands the strip back")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Cancel wrote no bank bytes")

        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || controller.catalogRevision !== revisionBefore
        }, 30000), "the next switch asks again" + openDiagnostics(session()))
        compare(controller.catalogRevision, revisionBefore,
                "Cancel kept the orphaned bank dirty for the next switch")
        verifyBankGate("the repeated project switch")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() {
            return controller.catalogRevision !== revisionBefore
        }, 30000), "Discard lets the switch complete" + openDiagnostics(session()))
        compare(tabs().pendingCloseBankTitle, "", "Discard lowers the bank gate")
        compare(session().lastSaveError, "", "the switch reported no error")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Discard wrote no bank bytes")
    }

    function test_mOrphanDirtyBankGatesWindowClose() {
        var orphan = orphanDirtyBank()
        shell.close()
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the window close asks about the orphan bank or completes")
        verify(!shell.shellPresenter.closeReady, "the window close waits for an answer")
        verifyBankGate("the window close")

        var cancelled = 0
        var countCancel = function() { cancelled++ }
        session().closeCancelled.connect(countCancel)
        var cancelButton = dialogButton("songTabCancel")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return cancelled === 1 }, 5000),
               "Cancel reports the refused close to the window")
        session().closeCancelled.disconnect(countCancel)
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000),
               "Cancel lowers the bank gate")
        verify(shell.shellPresenter.sceneActive && !shell.shellPresenter.closeReady,
               "Cancel leaves the window open")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Cancel wrote no bank bytes")

        shell.close()
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the next window close asks again")
        verifyBankGate("the repeated window close")
        tabs().confirmSave()
        verify(session().saveInProgress, "the bank Save is in flight")
        tabs().confirmDiscard()
        tabs().cancelClose()
        compare(tabs().pendingCloseBankTitle, "fixture_rich",
                "Discard and Cancel are refused while the bank Save is in flight")
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the saved bank lets the window close complete")
        compare(tabs().pendingCloseBankTitle, "", "Save lowers the bank gate")
        compare(session().saveInProgress, false, "the close waited for the bank Save")
        compare(session().lastSaveError, "", "the bank Save reported no error")
        var bankAfter = fileProbe.fileFingerprint(bankPath())
        verify(bankAfter.length > 0 && bankAfter !== orphan.bankBefore,
               "Save wrote the orphaned bank to disk")
    }

    function test_nDirtyTabThenOrphanBankWalk() {
        var onlyId = openShell(["mus_route101"])[0]
        dirtyOpenBank()
        drawNote(onlyId)
        var songPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var songBefore = fileProbe.fileFingerprint(songPath)
        var bankBefore = fileProbe.fileFingerprint(bankPath())

        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseId === onlyId }, 5000),
               "the window close asks about the dirty tab first")
        compare(tabs().pendingCloseBankTitle, "", "the tab question names no bank")
        verify(awaitGateButtons(), "the tab gate offers its answers")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the walk moves on from the discarded tab")
        compare(tabs().tabCount, 0, "Discard closed the tab")
        verify(!shell.shellPresenter.closeReady, "the orphaned bank is asked about by name")
        verifyBankGate("the bank stage")

        discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the answered bank is not asked about again")
        compare(tabs().pendingCloseBankTitle, "", "Discard lowers the bank gate")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore, "Discard wrote no bank bytes")
        compare(fileProbe.fileFingerprint(songPath), songBefore, "Discard wrote no song bytes")
    }

    function holdBandOn(tabId) {
        var surface = surfaceOf(tabId)
        var input = findChild(surface, "swiftRollInput")
        verify(input && input.visible, "tab " + tabId + " mounts its roll input")
        var notes = JSON.parse(summaryOf(tabId))
        for (var n = 0; n < notes.length; ++n) {
            if (notes[n].ghost || notes[n].selected)
                continue
            var face = findChild(surface, "gridNote_" + notes[n].id)
            if (!face || face.width <= 0 || face.height <= 0)
                continue
            var topLeft = face.mapToItem(input, 0, 0)
            var bottomRight = face.mapToItem(input, face.width, face.height)
            var sx = topLeft.x - 3
            var sy = topLeft.y - 3
            var ex = bottomRight.x + 3
            var ey = bottomRight.y + 3
            if (sx < 1 || sy < 1 || ex > input.width - 1 || ey > input.height - 1)
                continue
            var targetId = notes[n].id
            mouseMove(input, sx, sy)
            mousePress(input, sx, sy, Qt.RightButton)
            mouseMove(input, ex, ey, -1, Qt.RightButton)
            verify(waitForNative(function() {
                return JSON.parse(summaryOf(tabId)).some(function(note) {
                    return note.id === targetId && note.selected
                })
            }, 5000), "the held band on tab " + tabId + " previews its selection")
            return input.mapToItem(shell.contentItem, ex, ey)
        }
        fail("tab " + tabId + " has a fully visible note a band can enclose")
    }

    function watchPageRemoval(tabId, grid, before) {
        var stack = pages()
        var repeater = null
        for (var i = 0; i < stack.children.length && !repeater; ++i) {
            if (stack.children[i].itemRemoved !== undefined)
                repeater = stack.children[i]
        }
        verify(repeater !== null, "the page stack exposes its page repeater")
        var watch = { seen: false, reason: -1, restored: false, closeReady: true,
                      repeater: repeater }
        watch.handler = function(index, item) {
            if (watch.seen || !item || item.objectName !== "songTab_" + tabId)
                return
            watch.seen = true
            watch.reason = grid.lastCancelReason
            watch.restored = grid.noteSummary === before
            watch.closeReady = shell.shellPresenter.closeReady
        }
        repeater.itemRemoved.connect(watch.handler)
        return watch
    }

    function test_oMidGestureCloseCancelsHeldBand() {
        var ids = openShell(["mus_route101", "mus_littleroot_test"])
        var survivorId = ids[0]
        var closingId = ids[1]
        compare(tabs().selectedId, closingId, "the gesture tab is selected")
        var closingPath = fileProbe.songPath(bootstrap.projectRoot, "mus_littleroot_test")
        var closingBytes = fileProbe.fileFingerprint(closingPath)
        var survivorSummary = summaryOf(survivorId)
        var grid = gridOf(closingId)
        var before = grid.noteSummary
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-hidden cancel reason")
        var release = holdBandOn(closingId)
        verify(!JSON.parse(summaryOf(survivorId)).some(function(note) { return note.selected }),
               "the survivor starts without a selection")
        var watch = watchPageRemoval(closingId, grid, before)
        tabs().requestClose(closingId)
        verify(waitForNative(function() { return watch.seen }, 5000),
               "the mid-gesture close retires the closed page")
        watch.repeater.itemRemoved.disconnect(watch.handler)
        compare(watch.reason, 2, "the mid-gesture close cancels the band as hidden before page retirement")
        verify(watch.restored, "the mid-gesture close restores the pre-band notes before page retirement")
        compare(tabs().pendingCloseId, -1, "the cancelled band left nothing to save")
        compare(tabs().tabCount, 1, "the mid-gesture close removes the tab")
        mouseRelease(shell.contentItem, release.x, release.y, Qt.RightButton)
        verify(waitForNative(function() {
            var survivor = pageOf(survivorId)
            return pageOf(closingId) === null && tabs().selectedId === survivorId
                && survivor !== null && survivor.visible
        }, 5000), "the survivor is presented after the closed page retires")
        compare(fileProbe.fileFingerprint(closingPath), closingBytes,
                "the mid-gesture close wrote no song bytes")
        compare(summaryOf(survivorId), survivorSummary, "the survivor's notes are untouched")
        verify(!session().canUndo, "the survivor inherits no history")

        var input = findChild(surfaceOf(survivorId), "swiftRollInput")
        var notes = JSON.parse(summaryOf(survivorId))
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            if (notes[n].ghost)
                continue
            var center = pointFor(survivorId, notes[n].tick + notes[n].duration / 2,
                                  notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the survivor has a note a click can reach")
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(summaryOf(survivorId)).filter(function(note) {
                return note.selected
            }).length === 1
        }, 5000), "the survivor roll takes a fresh click after the mid-gesture close")

        var survivorPage = pageOf(survivorId)
        session().openSong("mus_littleroot_test")
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 30000),
               "reopening the closed song appends its replacement tab")
        var reopenedId = tabs().selectedId
        verify(reopenedId !== closingId && reopenedId !== survivorId,
               "the reopened song is selected under a new identity")
        compare(pageOf(survivorId), survivorPage, "the reopen retains the survivor tab")
        waitForPage(reopenedId)
    }

    function test_pCloseWalkCancelsHeldBand() {
        var onlyId = openShell(["mus_route101"])[0]
        var songPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var songBytes = fileProbe.fileFingerprint(songPath)
        var grid = gridOf(onlyId)
        var before = grid.noteSummary
        grid.inputCancelled(1)
        compare(grid.lastCancelReason, 1, "an idle ungrab primes a non-hidden cancel reason")
        var release = holdBandOn(onlyId)
        var watch = watchPageRemoval(onlyId, grid, before)
        shell.close()
        verify(waitForNative(function() { return watch.seen }, 30000),
               "the window close walk retires the held band's page")
        mouseRelease(shell.contentItem, release.x, release.y, Qt.RightButton)
        compare(watch.reason, 2, "the close walk cancels the held band as hidden before page retirement")
        verify(watch.restored, "the close walk restores the pre-band notes before page retirement")
        verify(!watch.closeReady, "the close walk cancels the band before the detach acknowledgment")
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the close walk reaches scene detach after cancelling the band")
        compare(fileProbe.fileFingerprint(songPath), songBytes,
                "the cancelled close walk wrote no song bytes")
    }
}
