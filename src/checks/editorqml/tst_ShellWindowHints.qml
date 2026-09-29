import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_pMouseHintTargetClaims() {
        openTwoSongShell()
        var surface = selectedSurface()
        var hints = shell.shellPresenter.mouseHints
        var caption = findChild(shell, "shellMouseHintText")
        var plot = findChild(surface, "swiftRollInput")
        var gutter = findChild(surface, "timelineQuickRollGutter")
        var headers = findChild(surface, "timelineTrackHeadersInput")
        var rows = findChild(surface, "timelineTrackHeaderRows")
        verify(rows.count >= 1, "the mounted header model seeds at least one track row")
        verify(caption && plot && gutter && headers && rows && rows.count > 0)
        tryCompare(surface, "hintWindowActive", true)
        mouseMove(plot, plot.width / 2, plot.height / 2)
        tryVerify(function() { return hints.text.length > 0 && caption.text === hints.text }, 3000)
        var plotHint = hints.text
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return hints.text.length > 0 && hints.text !== plotHint
                               && caption.text === hints.text }, 3000)
        var gutterHint = hints.text
        var row = rows.itemAt(0)
        verify(row && !row.isAddTrack && row.titleRect.width > 0)
        var titleX = row.titleRect.x + row.titleRect.width / 2
        var titleY = row.titleRect.y + row.titleRect.height / 2
        mouseMove(headers, titleX, titleY)
        tryVerify(function() { return hints.text.length > 0 && hints.text !== plotHint
                               && caption.text === hints.text }, 3000)
        var rowHint = hints.text
        verify(gutterHint !== plotHint && rowHint !== gutterHint,
               "each hover target publishes its own non-empty profile")
        var mute = surface.headersModel.muteButtonRect
        mouseMove(headers, mute.x + mute.width / 2, mute.y + mute.height / 2)
        tryVerify(function() { return hints.text === "" && caption.text === "" }, 3000)
        var muteEmpty = hints.text === ""
        mouseMove(headers, titleX, titleY)
        tryVerify(function() { return hints.text === rowHint && caption.text === rowHint },
                  3000, "returning to the row body restores the row text")
        var scrollbar = findChild(surface, "timelineRollScrollBar")
        verify(scrollbar && scrollbar.visible)
        mouseMove(scrollbar, scrollbar.width / 2, scrollbar.height / 2)
        tryVerify(function() { return muteEmpty && hints.text === "" && caption.text === "" },
                  3000, "a no-hint control claims empty instead of leaking")
    }

    function test_qMouseHintMenuAndPopupScope() {
        openTwoSongShell()
        var surface = selectedSurface()
        var hints = shell.shellPresenter.mouseHints
        var headerModel = surface.headersModel
        var headers = findChild(surface, "timelineTrackHeadersInput")
        var rows = findChild(surface, "timelineTrackHeaderRows")
        var row = rows.itemAt(0)
        var titleX = row.titleRect.x + row.titleRect.width / 2
        var titleY = row.titleRect.y + row.titleRect.height / 2
        tryCompare(surface, "hintWindowActive", true)
        mouseMove(headers, titleX, titleY)
        tryVerify(function() { return hints.text.length > 0 }, 3000)
        verify(rows.count > 1 && rows.itemAt(1) && !rows.itemAt(1).isAddTrack,
               "the mounted header model seeds a second track row for the menu journey")
        var nextRow = rows.itemAt(1)
        var nextX = nextRow.titleRect.x + nextRow.titleRect.width / 2
        var nextY = headerModel.rowHeight + nextRow.titleRect.y + nextRow.titleRect.height / 2
        var firstTrack = row.track
        mouseDoubleClickSequence(headers, titleX, titleY, Qt.LeftButton)
        tryCompare(headerModel, "renamingTrack", firstTrack, 3000,
                   "double-clicking the first row title starts renaming that track")
        mouseClick(headers, nextX, nextY, Qt.RightButton)
        tryCompare(headerModel, "menuOpen", true)
        tryCompare(hints, "text", "")
        tryCompare(headerModel, "renamingTrack", -1, 3000,
                   "opening the second-row menu ends the in-progress rename")
        var headerPanel = null
        tryVerify(function() {
            headerPanel = findChild(surface, "quickMenuPanelRoot")
            return headerPanel && headerPanel.rowObjectNamePrefix === "headerMenuRow_"
                   && headerPanel.rowItem(2) !== null
        }, 3000)
        var renameRow = headerPanel.rowItem(2)
        compare(renameRow.itemData.actionId, 3)
        mouseClick(renameRow, renameRow.width / 2, renameRow.height / 2)
        tryCompare(headerModel, "menuOpen", false)
        tryCompare(headerModel, "renamingTrack", nextRow.track, 3000,
                   "choosing Rename targets the menu track")
        var rename = findChild(surface, "timelineTrackHeaderRename")
        tryVerify(function() { return rename && rename.visible }, 3000)
        // Visibility can still describe the previous row until queued bindings and the scene settle.
        tryCompare(rename.parent, "rowIndex", 1, 3000)
        verify(waitForRendering(rename, 3000))
        mouseMove(rename, rename.width / 2, rename.height / 2)
        tryVerify(function() { return hints.text.length > 0 }, 3000)
        var renameHint = hints.text
        headerModel.finishRename(false, true)
        tryCompare(headerModel, "renamingTrack", -1, 3000,
                   "finishRename ends the rename")
        mouseMove(headers, titleX, titleY)
        tryVerify(function() { return hints.text.length > 0 && hints.text !== renameHint },
                  3000, "an open menu keeps the rename hint and dismiss restores the editor hint")

        var gutter = findChild(surface, "timelineQuickRollGutter")
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return hints.text.length > 0 }, 3000)
        var coveredHint = hints.text
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler && ruler.width > 0 && ruler.height > 0)
        mouseClick(ruler, ruler.width * 0.28, ruler.height * 0.75, Qt.RightButton)
        var menu = surface.rulerMenu
        tryCompare(menu, "isOpen", true)
        var panel = null
        tryVerify(function() {
            panel = findChild(surface, "quickMenuPanelRoot")
            return panel && panel.rowObjectNamePrefix === "rulerMenuRow_"
                   && panel.rowItem(0) !== null
        }, 3000)
        var insertRow = panel.rowItem(0)
        compare(insertRow.itemData.actionId, 1)
        mouseClick(insertRow, insertRow.width / 2, insertRow.height / 2)
        tryCompare(menu, "insertTimePromptOpen", true)
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryCompare(hints, "text", "")
        menu.cancelInsertTimePrompt()
        tryCompare(menu, "insertTimePromptOpen", false)
        tryVerify(function() { return hints.text === coveredHint }, 3000,
                  "dismissing a popup restores the covered target hint")
    }

    function test_rMouseHintStatusPresentation() {
        openTwoSongShell()
        var surface = selectedSurface()
        var hints = shell.shellPresenter.mouseHints
        var caption = findChild(shell, "shellMouseHintText")
        var status = findChild(shell, "shellStatusText")
        var meter = findChild(shell, "shellPolyMeter")
        var plot = findChild(surface, "swiftRollInput")
        verify(caption && status && meter && plot)
        tryCompare(surface, "hintWindowActive", true)
        mouseMove(plot, plot.width / 2, plot.height / 2)
        tryVerify(function() { return hints.text.length > 0 && caption.text === hints.text },
                  3000, "the footer caption mirrors the current hint text")
        tryCompare(hints, "text", "⇧ Right-drag: select time · ⌘ Wheel: zoom key height · ⇧ Wheel: scroll horizontally", 3000)
        var plotHint = hints.text
        verify(caption.text === plotHint,
               "the footer caption holds the full plot hint string")
        function hintCentered() {
            var center = caption.mapToItem(shell.footer, caption.width / 2, 0).x
            return caption.horizontalAlignment === Text.AlignHCenter
                   && Math.abs(center - shell.footer.width / 2) <= shell.chromeBaseFontPx / 2
        }
        var height = shell.footer.height
        var originalStatus = shell.shellPresenter.statusText
        shell.shellPresenter.statusText = "Operational message"
        tryCompare(status, "text", "Operational message")
        verify(caption.text === plotHint,
               "the operational message leaves the full hint caption intact")
        var stable = caption.text === hints.text && hintCentered()
                     && shell.footer.height === height
        var meterPresenter = shell.shellPresenter.session.transportBarPresenter()
        meterPresenter.polyMeterVisible = false
        tryCompare(meter, "visible", false)
        stable = stable && caption.text === hints.text && hintCentered()
                 && shell.footer.height === height
        meterPresenter.polyMeterVisible = true
        tryCompare(meter, "visible", true)
        verify(hints.text === plotHint,
               "showing the meter keeps the pre-meter hint profile")
        var gutter = findChild(surface, "timelineQuickRollGutter")
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return hints.text.length > 0 && hints.text !== plotHint }, 3000)
        tryCompare(hints, "text", "⌘ Wheel: zoom key height · ⇧ Wheel: scroll horizontally", 3000)
        var gutterHint = hints.text
        tryVerify(function() { return caption.text === gutterHint }, 3000,
                  "the footer caption holds the full hint after the profile changes")
        verify(shell.footer.height === height,
               "changing the hint profile keeps the metered footer height")
        stable = stable && caption.text === hints.text && hintCentered()
                 && shell.footer.height === height
        meterPresenter.polyMeterVisible = false
        tryCompare(meter, "visible", false)
        verify(stable && caption.text === hints.text && status.text === "Operational message"
               && hintCentered() && shell.footer.height === height,
               "transient status and meter changes keep the hint center")
        shell.shellPresenter.statusText = originalStatus
        var originalWidth = shell.width
        try {
            var fullHintWidth = footerCaptionMetrics.advanceWidth(plotHint)
            var statusSpace = status.width + shell.chromeSpacing.two * 2
            var targetWidth = Math.max(shell.minimumWidth,
                                       originalWidth - plot.width + shell.chromeBaseFontPx * 2,
                                       fullHintWidth / 2 + statusSpace * 2)
            shell.width = targetWidth
            verify(waitForPolish(shell))
            verify(plot.visible && plot.width > 0 && plot.height > 0)
            mouseMove(plot, plot.width / 2, plot.height / 2)
            tryCompare(hints, "text", plotHint)
            tryVerify(function() {
                return caption.width < fullHintWidth
            }, 3000, "the actual caption allocation must be narrower than the full hint"
                     + " (window=" + shell.width + ", minimum=" + shell.minimumWidth
                     + ", caption=" + caption.width + ", hint=" + fullHintWidth + ")")
            tryVerify(function() {
                return caption.truncated && caption.text === plotHint && hintCentered()
            }, 3000, "elided hints retain the status center")
        } finally {
            shell.width = originalWidth
        }
    }

    function test_sEnlargedFontClausesRetired() {
        openTwoSongShell()
        var surface = selectedSurface()
        var hints = shell.shellPresenter.mouseHints
        var caption = findChild(shell, "shellMouseHintText")
        var meter = findChild(shell, "shellPolyMeter")
        var plot = findChild(surface, "swiftRollInput")
        var gutter = findChild(surface, "timelineQuickRollGutter")
        verify(caption && meter && plot && gutter)
        tryCompare(surface, "hintWindowActive", true)
        function hintCentered() {
            var center = caption.mapToItem(shell.footer, caption.width / 2, 0).x
            return caption.horizontalAlignment === Text.AlignHCenter
                   && Math.abs(center - shell.footer.width / 2) <= shell.chromeBaseFontPx / 2
        }
        mouseMove(plot, plot.width / 2, plot.height / 2)
        tryVerify(function() { return hints.text.length > 0 }, 3000)
        var plotHint = hints.text
        verify(!("currentSource" in hints) && hints.text === plotHint,
               "the plot hover publishes text only; the native hint-source token has no mounted channel")
        tryVerify(function() { return caption.text === plotHint }, 3000,
                  "the enlarged-font caption clause retires; the full-text identity executes at the production font")
        var meterPresenter = shell.shellPresenter.session.transportBarPresenter()
        meterPresenter.polyMeterVisible = true
        tryCompare(meter, "visible", true)
        var meteredHeight = shell.footer.height
        var meterX = meter.x
        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryVerify(function() { return hints.text.length > 0 && hints.text !== plotHint }, 3000)
        verify(shell.footer.height === meteredHeight,
               "the enlarged-font bar-height clause retires; the metered height executes at the production font")
        verify(meter.x === meterX,
               "the enlarged-font meter-offset clause retires; the meter offset executes at the production font")
        verify(hintCentered(),
               "the enlarged-font centering clause retires; the metered center executes at the production font")
        meterPresenter.polyMeterVisible = false
        tryCompare(meter, "visible", false)
        verify(hintCentered(),
               "the enlarged-font hide-meter clause retires; the unmetered center executes at the production font")
    }
}
