import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "TextContrastAudit.js" as Audit
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

// Measure every rendered shell text item against its actual drawn surface
// in all shipped themes; disabled text keeps the WCAG exemption.
ShellLaneSupport {
    id: testCase
    name: "TextContrast"
    when: windowShown
    width: 1280
    height: 800
    visible: true

    readonly property var settings: bootstrap.preferences
    property var failures: []
    property var seenFailures: []
    property int measured: 0

    ShellQmlBootstrap { id: bootstrap }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { typographyCaptureFont: Qt.font({ pixelSize: 12 }); width: 1280; height: 800; visible: true } }

    readonly property var themes: [
        { mode: "vanilla", window: "#C9C1BB" },
        { mode: "dark-neutral-high", window: "#373737" },
        { mode: "immaterial", window: "#2E3138" },
    ]

    function initTestCase() {
        settings.setString("lastProjectDir", "")
    }

    laneBootstrap: bootstrap

    closeGateMessage: "closing reaches the dirty gate or completes"
    closeReadyMessage: "the scene is released"

    function openShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const chrome = findChild(shell, "shellContentLoader")
        verify(waitForNative(function() {
            return chrome && chrome.status === Loader.Ready && chrome.item !== null
        }, 10000), "persistent chrome mounts before window contrast audits")
    }

    function applyTheme(theme) {
        settings.setString("theme.mode", theme.mode)
        settings.setInt("theme.grid-line-contrast", 50)
        shell.shellPresenter.restoreAppearance()
        const palette = shell.shellPresenter.session.palette
        verify(waitForNative(function() {
            return Qt.colorEqual(palette.windowBackground, theme.window)
        }, 3000), theme.mode + " is applied")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "the shell submits the applied theme before contrast capture")
    }

    function grab(root) {
        return grabImage(root)
    }

    // Record each distinct theme/item/text/ink/surface once and log it
    // because QTest truncates long failure messages.
    function record(context, result) {
        measured += result.measured
        for (const failure of result.failures) {
            const key = [context.split(" ")[0], failure.where, failure.text,
                         failure.fg, failure.bg].join("|")
            if (seenFailures.indexOf(key) >= 0)
                continue
            seenFailures.push(key)
            const line = Audit.format(context, failure)
            console.warn("contrast: " + line)
            failures.push(line)
        }
    }

    function auditWindow(context) {
        const result = Audit.audit(shell.contentItem, grab,
                                   [].concat(Array.from(shell.data), [shell.menuBar]))
        record(context, result)
        return result.popups
    }

    function popupItem(popup) {
        return popup.background ? popup.background.parent : popup.contentItem.parent
    }

    // Opens every popup the window owns — menus, combo lists, prompts — one
    // at a time and audits only its own surface.
    function auditPopups(context, popups) {
        const done = []
        const queue = popups.slice()
        while (queue.length > 0) {
            const popup = queue.shift()
            if (done.indexOf(popup) >= 0)
                continue
            done.push(popup)
            // A disabled owner (combo, button) cannot open its popup.
            if (popup.parent && popup.parent.enabled === false)
                continue
            popup.open()
            if (!waitForNative(function() { return popup.opened }, 1000)) {
                popup.close()
                continue
            }
            const surface = popupItem(popup)
            if (surface) {
                const result = Audit.audit(surface, grab)
                record(context + " popup " + (popup.objectName || Audit.describe(surface)),
                       result)
                for (const nested of result.popups)
                    queue.push(nested)
            }
            popup.close()
            waitForNative(function() { return !popup.visible }, 1000)
        }
    }

    function auditVoicegroupSearch(context) {
        const field = findChild(shell, "voicegroupSelector")
        const popup = findChild(field, "voicegroupChoicesPopup")
        const list = findChild(field, "voicegroupChoicesList")
        shell.requestActivate()
        tryCompare(shell, "active", true)
        waitForRendering(field)
        field.forceActiveFocus()
        tryCompare(field, "activeFocus", true)
        field.selectAll()
        for (const character of "no_matching_voicegroup")
            keyClick(character)
        tryCompare(list, "count", 0)
        tryCompare(popup, "opened", true)
        record(context + " empty voicegroup search", Audit.audit(popupItem(popup), grab))
        popup.close()
        tryCompare(popup, "visible", false)
    }

    function auditSettings(context) {
        findChild(shell, "shellSettingsLoader").active = true
        const dialog = findChild(shell, "shellSettingsDialog")
        verify(dialog !== null, "settings window exists")
        shell.shellPresenter.activate("edit.engine_settings")
        tryCompare(dialog, "visible", true, 3000)
        for (let tab = 0; tab < 3; ++tab) {
            if (tab === 1 && !findChild(dialog, "settingsSongTab").enabled)
                continue
            dialog.selectedTab = tab
            const result = Audit.audit(dialog.contentItem, grab)
            record(context + " settings tab " + tab, result)
            auditPopups(context + " settings tab " + tab, result.popups)
        }
        dialog.close()
        tryCompare(dialog, "visible", false, 3000)
    }

    function auditWavExport(context) {
        const presenter = shell.shellPresenter
        const model = presenter.session.wavExportPresenter()
        model.open()
        let dialog = null
        verify(waitForNative(function() {
            dialog = findChild(shell, "shellWavExportDialog")
            return dialog !== null && dialog.visible
        }, 3000), "requesting WAV export presents its actual options window")
        tryCompare(dialog, "visible", true, 3000)
        record(context + " WAV options", Audit.audit(dialog.contentItem, grab))
        model.rejectOptions()
        model.open()
        tryCompare(dialog, "visible", true, 3000)
        model.setLoopCount(99)
        const picker = findChild(shell, "shellWavExportFileDialog")
        picker.selectedFile = "file://" + bootstrap.projectRoot + "/sound/contrast.wav"
        model.acceptOptions()
        verify(waitForNative(function() { return picker.visible }, 5000),
               "contrast audit save picker opens with its destination")
        picker.accept()
        let progress = null
        verify(waitForNative(function() {
            progress = findChild(shell, "shellWavExportProgress")
            return progress !== null && progress.visible
        }, 3000), "accepting WAV export presents its actual progress window")
        tryCompare(progress, "visible", true, 3000)
        record(context + " WAV progress", Audit.audit(progress.contentItem, grab))
        model.cancelRender()
        verify(waitForNative(function() { return !model.active }, 30000),
               "contrast audit export cancels")
    }
    function auditImportWizard(context) {
        const picker = findChild(shell, "shellImportMidiPicker")
        const dialog = findChild(shell, "midiImportWizard")
        verify(picker !== null && dialog !== null, "import wizard and picker are mounted")
        picker.selectedFile = "file://" + bootstrap.projectRoot + "/test_midis/external_import.mid"
        shell.shellPresenter.activate("file.import_midi")
        verify(waitForNative(function() { return picker.visible }, 5000), "import picker opens")
        picker.accept()
        verify(waitForNative(function() { return dialog.visible }, 30000), "import wizard opens")
        const toggle = findChild(dialog, "importControllerToggle")
        if (toggle.visible)
            mouseClick(toggle)
        for (let page = 0; page < 3; ++page) {
            const result = Audit.audit(dialog.contentItem, grab)
            record(context + " import page " + page, result)
            auditPopups(context + " import page " + page, result.popups)
            if (page < 2)
                mouseClick(findChild(dialog, "importWizardNext"))
        }
        mouseClick(findChild(dialog, "importWizardCancel"))
        verify(waitForNative(function() { return !dialog.visible }, 5000), "import wizard closes")
    }

    function auditNewSongWizard(context) {
        const dialog = findChild(shell, "newSongWizard")
        verify(dialog !== null, "new song wizard is mounted")
        shell.shellPresenter.activate("file.new_song")
        verify(waitForNative(function() { return dialog.visible }, 30000), "new song wizard opens")
        const identity = Audit.audit(dialog.contentItem, grab)
        record(context + " new song identity", identity)
        auditPopups(context + " new song identity", identity.popups)
        const name = findChild(dialog, "importSongName")
        name.insert(0, "mus_contrast_audit")
        verify(waitForNative(function() {
            return findChild(dialog, "newSongWizardNext").enabled
        }, 3000), "valid name enables Sound navigation")
        mouseClick(findChild(dialog, "newSongWizardNext"))
        verify(waitForNative(function() {
            return findChild(dialog, "newSongWizardTitle").text === "Sound settings"
        }, 3000), "Sound page opens")
        const sound = Audit.audit(dialog.contentItem, grab)
        record(context + " new song sound", sound)
        auditPopups(context + " new song sound", sound.popups)
        mouseClick(findChild(dialog, "newSongWizardCancel"))
        verify(waitForNative(function() { return !dialog.visible }, 5000), "new song wizard closes")
    }
    function auditSampleStudio(context) {
        shell.shellPresenter.activate("tools.import_sample")
        verify(waitForNative(function() {
            const picker = findChild(shell, "shellImportSamplePicker")
            return picker && picker.visible
        }, 5000), "studio-owned sample picker opens")
        const picker = findChild(shell, "shellImportSamplePicker")
        picker.reject()
        tryCompare(picker, "visible", false, 5000)
        picker.currentFolder = shell.shellPresenter.session.sampleStudio().pickerFolder
        picker.selectedFile = "file://" + bootstrap.projectRoot + "/samplesources/hires_tone.wav"
        mouseClick(findChild(shell, "sampleLibraryOpen"))
        tryCompare(picker, "visible", true, 5000)
        picker.accept()
        verify(waitForNative(function() {
            const opened = findChild(shell, "sampleStudioDialog")
            return opened && opened.visible && shell.shellPresenter.session.sampleStudio().editor().hasSource
        }, 15000), "sample editor decodes and displays the chosen source")
        const dialog = findChild(shell, "sampleStudioDialog")
        const result = Audit.audit(dialog.contentItem, grab)
        record(context + " sample editor", result)
        auditPopups(context + " sample editor", result.popups)
        const sources = bootstrap.projectRoot + "/samplesources"
        verify(disk.copyFile(sources + "/hires_tone.wav", sources + "/contrast_row.wav"),
               "second real WAV creates an unselected file row")
        verify(disk.makeDirectory(sources + "/contrast_child"), "nested row is available")
        mouseClick(findChild(dialog, "sampleLibraryAdd"))
        const folderPicker = findChild(dialog, "sampleLibraryFolderPicker")
        verify(waitForNative(function() { return folderPicker && folderPicker.visible }, 5000),
               "library folder chooser opens")
        folderPicker.selectedFolder = "file://" + sources
        folderPicker.accept()
        const folders = findChild(dialog, "sampleLibraryFolders")
        const files = findChild(dialog, "sampleLibraryFiles")
        verify(waitForNative(function() {
            return folders && folders.count === 2 && files && files.count === 2
                && folders.itemAtIndex(0) && folders.itemAtIndex(1)
                && files.itemAtIndex(0) && files.itemAtIndex(1)
        }, 5000), "both folder and file delegate rows are painted")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, dialog, 5000),
               "populated pane submits its rows before audit")
        record(context + " library folder and file rows",
               Audit.audit(dialog.contentItem, grab, [
                   folders.itemAtIndex(0), folders.itemAtIndex(1),
                   files.itemAtIndex(0), files.itemAtIndex(1)
               ]))
        const first = files.itemAtIndex(0)
        mouseClick(first)
        verify(waitForNative(function() {
            return files.itemAtIndex(0).selected
        }, 10000), "selected file highlights its row")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, dialog, 5000),
               "selected row submits before audit")
        record(context + " library selection",
               Audit.audit(dialog.contentItem, grab, [
                   folders.itemAtIndex(0), folders.itemAtIndex(1),
                   files.itemAtIndex(0), files.itemAtIndex(1)
               ]))
        const advanced = findChild(dialog, "sampleStudioAdvanced")
        if (advanced) {
            mouseClick(advanced)
            record(context + " sample advanced", Audit.audit(dialog.contentItem, grab))
        }
        dialog.close()
        verify(waitForNative(function() { return !dialog.visible }, 5000), "editor closes")
        const workflow = shell.shellPresenter.session.sampleStudio()
        const sf2Path = bootstrap.projectRoot + "/samplesources/zones.sf2"
        workflow.requestImport(-1)
        verify(waitForNative(function() {
            const opened = findChild(shell, "sampleStudioDialog")
            const chooser = findChild(shell, "shellImportSamplePicker")
            return opened && opened.visible && chooser && chooser.visible
        }, 15000), "SoundFont audit opens a new studio and its native chooser")
        const sf2Picker = findChild(shell, "shellImportSamplePicker")
        sf2Picker.reject()
        tryCompare(sf2Picker, "visible", false, 5000)
        sf2Picker.currentFolder = shell.shellPresenter.session.sampleStudio().pickerFolder
        sf2Picker.selectedFile = "file://" + sf2Path
        mouseClick(findChild(shell, "sampleLibraryOpen"))
        tryCompare(sf2Picker, "visible", true, 5000)
        compare(sf2Picker.selectedFile.toString(), "file://" + sf2Path)
        sf2Picker.accept()
        tryCompare(sf2Picker, "visible", false, 5000)
        verify(waitForNative(function() {
            const opened = findChild(shell, "sf2ZonePickerDialog")
            return opened && opened.visible
        }, 15000), "SoundFont zone picker opens")
        const zones = findChild(shell, "sf2ZonePickerDialog")
        record(context + " SoundFont zones", Audit.audit(zones.contentItem, grab))
        zones.close()
        verify(waitForNative(function() { return !zones.visible }, 5000), "zone picker closes")
        const reopenedStudio = findChild(shell, "sampleStudioDialog")
        reopenedStudio.close()
        verify(waitForNative(function() { return !reopenedStudio.visible }, 5000),
               "blank SoundFont audit editor closes")
    }

    function auditClippedKeyboardLabel(context) {
        const tabs = shell.shellPresenter.session.songTabs
        const page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        const surface = page ? findChild(page, "swiftRollOverlay") : null
        verify(surface !== null, "the loaded roll is mounted")
        const gutter = findChild(surface, "timelineQuickRollGutter")
        verify(gutter !== null, "the keyboard gutter is mounted")
        const keys = findChild(surface, "timelineRendererKeyboard")
        verify(keys !== null && keys.parent.clip
               && keys.width === keys.parent.width && keys.height === keys.parent.height,
               "keyboard text paints inside the clipped keyboard viewport")
        const grid = surface.gridModel
        verify(grid.rowHeight > 0 && keys.height > 0, "the keyboard has a viewport")
        const natural = grid.palette.keyboardNatural
        const naturalRgb = [natural.r * 255, natural.g * 255, natural.b * 255]
        for (const edge of ["top", "bottom"]) {
            const rowOffset = edge === "top" ? 0.2 : 0.8
            const scroll = (127 - 72 + rowOffset) * grid.rowHeight
                - (edge === "bottom" ? keys.height : 0)
            grid.setCameraVScroll(scroll)
            let rowTop = 0
            tryVerify(function() {
                rowTop = (127 - 72) * grid.rowHeight - grid.cameraScrollY
                return (edge === "top" ? rowTop < 0 : rowTop + grid.rowHeight > keys.height)
                    && rowTop < keys.height && rowTop + grid.rowHeight > 0
            }, 3000, "C5 straddles the scrolled keyboard's " + edge + " edge")
            waitForRendering(keys)
            const image = RollNoteFaces.grab(testCase, gutter)
            const dpr = image.width / gutter.width
            const y0 = Math.max(0, Math.ceil(rowTop * dpr) + 1)
            const y1 = Math.min(image.height, Math.floor((rowTop + grid.rowHeight) * dpr) - 1)
            let naturalPixels = 0
            let ink = null
            let inkRatio = 0
            for (let y = y0; y < y1; ++y) {
                for (let x = 0; x < image.width; ++x) {
                    const c = image.pixel(x, y)
                    const rgb = [c.r * 255, c.g * 255, c.b * 255]
                    const ratio = Audit.contrast(rgb, naturalRgb)
                    if (ratio < 1.05)
                        ++naturalPixels
                    else if (ratio > inkRatio) {
                        inkRatio = ratio
                        ink = rgb
                    }
                }
            }
            verify(y1 > y0 && naturalPixels > 0,
                   "the " + edge + "-clipped C5 glyph box remains visible")
            verify(y0 >= 0 && y1 <= image.height,
                   "the " + edge + "-clipped C5 ink stays on its painted key")
            verify(ink !== null, "the " + edge + "-clipped C5 ink is painted")
            verify(naturalPixels > (y1 - y0),
                   "the " + edge + "-clipped C5 glyph sits on the actual natural key")
            verify(inkRatio >= 4.5,
                   "the " + edge + "-clipped C5 ink meets WCAG AA on its painted key")
            auditWindow(context + " " + edge + "-clipped keyboard")
        }
    }

    function auditNoteAutomation(context) {
        const presenter = shell.shellPresenter
        const tabs = presenter.session.songTabs
        const page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        const surface = findChild(page, "swiftRollOverlay")
        const roll = findChild(surface, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        presenter.activate("roll.select_all")
        presenter.activate("roll.pitch_bend")
        tryVerify(function() { return findChild(surface, "pitchBendPopup") !== null },
                  5000, "note automation opens for its contrast audit")
        const popup = findChild(surface, "pitchBendPopup")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "all three graph lanes submit before contrast capture")
        record(context + " note automation", Audit.audit(popup, grab))
        const editor = popup.bridge
        editor.cancelAndClose()
        tryCompare(editor, "isOpen", false)
    }

    function auditArpeggiator(context) {
        const surface = selectedSurface()
        const model = surface.arpeggiatorModel
        model.open(surface.gridModel.trackIndex)
        tryCompare(model, "isOpen", true)
        tryVerify(function() { return findChild(surface, "arpeggiatorPanel") !== null }, 5000)
        const panel = findChild(surface, "arpeggiatorPanel")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "arpeggiator controls submit before contrast capture")
        const result = Audit.audit(panel, grab)
        record(context + " arpeggiator", result)
        auditPopups(context + " arpeggiator", result.popups)
        model.close()
        tryCompare(model, "isOpen", false)
    }

    function auditUndoHistory(context) {
        const presenter = shell.shellPresenter
        const history = presenter.session.undoHistory
        presenter.activate("view.undo_history")
        const dock = findChild(shell, "shellUndoHistoryDock")
        const list = findChild(shell, "undoHistoryList")
        verify(dock !== null && list !== null, "undo history dock mounts")
        tryCompare(dock, "visible", true)
        verify(waitForNative(function() {
            return history.canJump && list.count === 1
        }, 5000), "the opened song has its base history row")

        presenter.activate("roll.select_all")
        presenter.activate("roll.transpose_up")
        verify(waitForNative(function() {
            return history.canJump && list.count === 2
        }, 5000), "transpose adds an applied history row")
        presenter.activate("roll.delete")
        verify(waitForNative(function() {
            return history.canJump && list.count === 3
        }, 5000), "delete adds another history row")
        presenter.activate("edit.undo")
        verify(waitForNative(function() {
            return history.canJump && history.currentRow === 1
                && list.itemAtIndex(0) !== null && list.itemAtIndex(1) !== null
        }, 5000), "history displays both applied and undone rows")

        const undone = list.itemAtIndex(0)
        const applied = list.itemAtIndex(1)
        compare(undone.step.applied, false)
        compare(applied.step.applied, true)
        const undoneLabel = findChild(undone, "undoHistoryLabel")
        const appliedLabel = findChild(applied, "undoHistoryLabel")
        verify(undoneLabel !== null && appliedLabel !== null, "history labels exist")
        compare(undoneLabel.enabled, true)
        compare(appliedLabel.enabled, true)
        compare(undoneLabel.color, presenter.session.palette.secondaryText)
        compare(appliedLabel.color, presenter.session.palette.windowText)
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "the shell submits both history text states before contrast capture")
        const image = grab(shell.contentItem)
        verify(Audit.measure(undoneLabel, image, shell.contentItem) !== null,
               "the undone label is measured, not disabled-exempt")
        verify(Audit.measure(appliedLabel, image, shell.contentItem) !== null,
               "the applied label is measured")
        // ListView delegates are not in the window's QObject data tree.
        record(context + " undo history", Audit.audit(shell.contentItem, grab,
               [dock, undone, applied, list.itemAtIndex(2)]))

        history.activate(2)
        verify(waitForNative(function() {
            return history.canJump && history.currentRow === 2
        }, 5000), "the history audit restores the opened song")
        presenter.activate("view.undo_history")
        tryCompare(dock, "visible", false)
    }

    function report(label) {
        verify(measured > 0, label + ": text items were measured")
        verify(failures.length === 0, label + ": " + failures.length
               + " text items below the WCAG AA floor (of " + measured + " measured):\n"
               + failures.join("\n"))
    }

    function resetTally() {
        failures = []
        seenFailures = []
        measured = 0
    }

    // One row per shipped theme; the runner gives each row its own process.
    function themeRows() {
        return themes.map(function(theme) { return { tag: theme.mode, theme: theme } })
    }

    function test_emptyShellText_data() { return themeRows() }

    function test_emptyShellText(data) {
        resetTally()
        openShell()
        applyTheme(data.theme)
        auditPopups(data.tag + " empty", auditWindow(data.tag + " empty"))
        auditSettings(data.tag + " empty")
        report(data.tag + " empty shell")
    }

    function auditSplitStudio(context) {
        const session = shell.shellPresenter.session
        session.kitStudio().requestOpen()
        verify(waitForNative(function() {
            const studio = child("splitStudioWindow")
            return studio !== null && studio.visible
        }, 10000), "Split Studio opening state mounts")
        const studio = child("splitStudioWindow")
        const result = Audit.audit(studio.contentItem, grab)
        verify(result.measured > 0, context + ": Split Studio text items were measured")
        record(context + " split studio", result)
        studio.close()
        tryCompare(session.kitStudio(), "windowOpen", false, 5000)
    }

    function test_songShellText_data() { return themeRows() }

    function test_songShellText(data) {
        resetTally()
        openShell()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        verify(waitForNative(function() {
            const scene = shell.sceneLoader
            if (scene === null || scene.status !== Loader.Ready)
                return false
            const page = findChild(scene.item, "songTab_" + session.songTabs.selectedId)
            const surface = page ? findChild(page, "swiftRollOverlay") : null
            return surface !== null && surface.visible
        }, 10000), "the selected song page mounts before body contrast audits")
        applyTheme(data.theme)
        const presenter = shell.shellPresenter
        const mode = data.tag
        if (mode === "vanilla" || mode === "dark-neutral-high")
            auditSplitStudio(mode)
        session.voiceListController().selectSlot(0)
        auditPopups(mode + " song", auditWindow(mode + " song"))
        auditVoicegroupSearch(mode)
        auditClippedKeyboardLabel(mode)
        auditNoteAutomation(mode)
        auditArpeggiator(mode)

        presenter.activate("view.polyphony_debugger")
        tryVerify(function() {
            const dock = findChild(shell, "shellPolyphonyDock")
            return dock !== null && dock.visible
        }, 3000, "polyphony dock opens")
        auditWindow(mode + " polyphony")
        presenter.activate("view.polyphony_debugger")

        auditUndoHistory(mode)

        presenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        auditPopups(mode + " events", auditWindow(mode + " events"))
        presenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", false, 3000)

        auditSettings(mode + " song")
        auditWavExport(mode + " song")
        auditImportWizard(mode + " song")
        auditNewSongWizard(mode + " song")
        auditSampleStudio(mode + " song")
        report(mode + " song shell")
    }
}
