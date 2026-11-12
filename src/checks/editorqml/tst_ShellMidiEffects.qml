import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck
import Porydaw.Ui
import "NativeWait.js" as NativeWait

ShellClipboardSupport {
    id: testCase
    name: "ShellMidiEffects"

    function init() {
        verify(bootstrap.resetPreferences())
    }

    function openFromTrackHeader(track) {
        const app = openRoute101()
        shell.width = 960
        shell.height = 640
        if (track === undefined)
            track = 0
        const view = selectedSurface()
        verify(!!view, "Object exists")
        view.gridModel.setTrack(0)
        tryCompare(view.gridModel, "trackIndex", 0)
        const rows = findChild(view, "timelineTrackHeaderRows")
        verify(!!rows, "Object exists")
        tryVerify(function() { return rows.count > track })
        const row = rows.itemAt(track)
        verify(!!row, "Object exists")
        const button = findChild(row, "timelineHeaderEffectsButton_" + row.track)
        verify(!!button, "Object exists")
        tryCompare(button, "visible", true)
        mouseClick(button, button.width / 2, button.height / 2)
        tryCompare(view.gridModel, "trackIndex", row.track)
        tryCompare(view.applicationSession, "headerVoicePickerOpen", false)
        const model = view.midiEffectsModel
        verify(!!model, "Object exists")
        tryCompare(model, "isOpen", true)
        tryVerify(function() { return findChild(view, "midiEffectsPanel") !== null })
        const panel = findChild(view, "midiEffectsPanel")
        verify(!!panel, "Object exists")
        const close = findChild(panel, "midiEffectsClose")
        verify(!!close, "Object exists")
        tryCompare(close, "activeFocus", true)
        return { app: app, view: view, rows: rows, row: row, button: button,
                 track: row.track, model: model, panel: panel }
    }

    function pluginRow(list, index) {
        list.positionViewAtIndex(index, ListView.Contain)
        list.forceLayout()
        tryVerify(function() { return list.itemAtIndex(index) !== null })
        const row = list.itemAtIndex(index)
        verify(!!row, "Object exists")
        return row
    }

    function verifyCardFits(panel) {
        const card = panel.cardItem
        verify(!!card, "Object exists")
        tryVerify(function() {
            const at = card.mapToItem(panel, 0, 0)
            return card.width > 0 && card.height > 0 && at.x >= 0 && at.y >= 0
                && at.x + card.width <= panel.width + 1
                && at.y + card.height <= panel.height + 1
        })
    }

    function midiEffectsDiagnostics(model, list) {
        const names = []
        for (let index = 0; index < list.count; ++index) {
            const row = list.itemAtIndex(index)
            names.push(row ? row.name : "<uninstantiated row " + index + ">")
        }
        return JSON.stringify({
            status: model.status, diagnostics: model.diagnostics,
            isScanning: model.isScanning, isLoading: model.isLoading,
            selectedPlugin: model.selectedPlugin, count: list.count, plugins: names
        })
    }

    function test_effectButtonKeyboardKeepsSpaceForTransport() {
        const p = openFromTrackHeader()
        p.model.close()
        tryCompare(p.model, "isOpen", false)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") === null }, 3000,
                  "setup unmounts before focusing the header button")
        p.button.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(p.button, "activeFocus", true)
        const transport = p.app.transportBarPresenter()
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 3)
        tryCompare(p.model, "isOpen", false)
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 2)
        tryCompare(p.model, "isOpen", false)
        shell.shellPresenter.activate("transport.stop")
        tryCompare(transport, "state", 1)

        const keys = [Qt.Key_Return, Qt.Key_Enter]
        for (const key of keys) {
            p.button.forceActiveFocus(Qt.TabFocusReason)
            tryCompare(p.button, "activeFocus", true)
            keyClick(key)
            tryCompare(p.model, "isOpen", true)
            tryCompare(p.view.gridModel, "trackIndex", p.track)
            tryVerify(function() { return findChild(p.view, "midiEffectsPanel") !== null })
            const close = findChild(p.view, "midiEffectsClose")
            verify(!!close, "Object exists")
            mouseClick(close, close.width / 2, close.height / 2)
            tryCompare(p.model, "isOpen", false)
            tryVerify(function() { return findChild(p.view, "midiEffectsPanel") === null }, 3000,
                      "setup unmounts before the next header activation")
        }
    }

    function test_effectButtonCancelsWithoutReordering() {
        const p = openFromTrackHeader()
        p.model.close()
        tryCompare(p.model, "isOpen", false)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") === null }, 3000,
                  "setup unmounts before pointer input reaches the header")
        const header = findChild(p.view, "timelineTrackHeadersInput")
        verify(!!header, "Object exists")
        const target = p.rows.itemAt(1)
        verify(!!target, "Object exists")
        const outside = target.mapToItem(header, target.effectRect.x + target.effectRect.width / 2,
                                        target.effectRect.y + target.effectRect.height / 2)
        const start = p.button.mapToItem(header, p.button.width / 2, p.button.height / 2)
        const revision = p.view.gridModel.appliedRevisionText
        mousePress(header, start.x, start.y, Qt.LeftButton)
        tryCompare(p.row, "effectPressed", true)
        mouseMove(header, outside.x, outside.y, 20, Qt.LeftButton)
        tryCompare(p.view.headersModel, "reorderIndicatorVisible", false)
        mouseRelease(header, outside.x, outside.y, Qt.LeftButton)
        tryCompare(p.row, "effectPressed", false)
        tryCompare(p.model, "isOpen", false)
        tryCompare(p.view.applicationSession, "headerVoicePickerOpen", false)
        tryCompare(p.view.gridModel, "appliedRevisionText", revision)

        mousePress(header, start.x, start.y, Qt.LeftButton)
        tryCompare(p.row, "effectPressed", true)
        p.view.headersModel.inputCancelled(1)
        mouseRelease(header, start.x, start.y, Qt.LeftButton)
        tryCompare(p.row, "effectPressed", false)
        tryCompare(p.model, "isOpen", false)
        tryCompare(p.view.headersModel, "reorderIndicatorVisible", false)
        tryCompare(p.view.gridModel, "appliedRevisionText", revision)
        mouseClick(p.button, p.button.width / 2, p.button.height / 2)
        tryCompare(p.model, "isOpen", true)
    }

    function test_fixtureSelectionCrashReloadAndRemove() {
        const p = openFromTrackHeader(1)
        verify(bootstrap.vstFixtureFolder.length > 0)
        p.model.addFolder(bootstrap.vstFixtureFolder)
        let list = findChild(p.panel, "midiEffectsPluginList")
        verify(!!list, "Object exists")
        verify(waitForNative(function() {
            if (p.model.isScanning)
                return false
            const names = []
            for (let index = 0; index < list.count; ++index) {
                list.positionViewAtIndex(index, ListView.Contain)
                list.forceLayout()
                const row = list.itemAtIndex(index)
                if (!row)
                    return false
                names.push(row.name)
            }
            return ["TestGen", "TestGenAudio", "TestGenRealtimeOnly"].every(function(name) {
                return names.indexOf(name) >= 0
            })
        }, 30000), "MIDI producer scan settles: " + midiEffectsDiagnostics(p.model, list))
        const names = []
        let generator = -1
        for (let index = 0; index < list.count; ++index) {
            const row = pluginRow(list, index)
            names.push(row.name)
            if (row.name === "TestGen") {
                generator = index
            }
        }
        verify(names.indexOf("TestGen") >= 0)
        verify(names.indexOf("TestGenAudio") >= 0)
        verify(names.indexOf("TestGenRealtimeOnly") >= 0)
        compare(names.indexOf("porydawtestcrash"), -1)
        compare(names.indexOf("porydawtesthang"), -1)
        compare(names.indexOf("TestAudioOnly"), -1)
        verify(generator >= 0)
        verify(waitForNative(function() { return !p.model.isLoading }, 30000),
               "MIDI effect setup settles: " + midiEffectsDiagnostics(p.model, list))
        const generatorRow = pluginRow(list, generator)
        tryCompare(generatorRow, "enabled", true, 30000)
        const beforeAdd = p.app.undoHistory.currentRow
        mouseClick(generatorRow, generatorRow.width / 2, generatorRow.height / 2)
        tryCompare(p.model, "candidatePlugin", generator)
        compare(p.model.hasEffect, false)
        compare(p.app.undoHistory.currentRow, beforeAdd)
        const apply = findChild(p.panel, "midiEffectsApply")
        tryCompare(apply, "enabled", true)
        mouseClick(apply, apply.width / 2, apply.height / 2)
        verify(waitForNative(function() {
            return p.model.hasEffect && !p.model.isLoading && p.model.canOpenEditor
                && p.model.selectedPlugin === generator
        }, 30000), "Selected MIDI producer loads: " + midiEffectsDiagnostics(p.model, list))
        tryCompare(p.model, "hasEffect", true, 30000)
        tryCompare(p.model, "isLoading", false, 30000)
        tryCompare(p.model, "selectedPlugin", generator)
        tryCompare(p.row, "effectName", "TestGen")
        tryCompare(p.rows.itemAt(0), "effectName", "")
        tryCompare(p.row, "effectStopped", false)
        const badge = findChild(p.row, "timelineHeaderEffect_" + p.track)
        verify(!!badge, "Object exists")
        tryCompare(badge, "text", "TestGen")
        tryCompare(badge, "visible", true)
        const caption = findChild(p.row, "timelineHeaderEffectCaption_" + p.track)
        verify(!!caption, "Object exists")
        verifyCardFits(p.panel)

        const originalHistory = p.app.undoHistory.currentRow
        p.model.showPluginChooser()
        tryCompare(p.model, "browsingPlugins", true)
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "the chooser layout is submitted before clicking a candidate")
        const replacement = names.indexOf("TestGenAudio")
        verify(replacement >= 0)
        const replacementRow = pluginRow(list, replacement)
        mouseClick(replacementRow, replacementRow.width / 2, replacementRow.height / 2)
        tryCompare(p.model, "candidatePlugin", replacement)
        compare(p.model.effectName, "TestGen")
        compare(p.row.effectName, "TestGen")
        compare(p.app.undoHistory.currentRow, originalHistory)
        const back = findChild(p.panel, "midiEffectsCancelChoice")
        mouseClick(back, back.width / 2, back.height / 2)
        tryCompare(p.model, "browsingPlugins", false)
        compare(p.model.candidatePlugin, -1)
        compare(p.model.effectName, "TestGen")
        compare(p.app.undoHistory.currentRow, originalHistory)

        p.model.showPluginChooser()
        p.model.choosePlugin(replacement)
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, shell, 5000),
               "the replacement action is submitted before clicking Apply")
        mouseClick(apply, apply.width / 2, apply.height / 2)
        tryCompare(p.model, "effectName", "TestGenAudio")
        verify(waitForNative(function() { return !p.model.isLoading && p.model.canOpenEditor }, 30000),
               "replacement finishes loading through the native main-actor pump")
        tryCompare(p.row, "effectName", "TestGenAudio")
        p.model.showPluginChooser()
        p.model.choosePlugin(generator)
        p.model.applyPlugin()
        tryCompare(p.model, "effectName", "TestGen")
        verify(waitForNative(function() { return !p.model.isLoading && p.model.canOpenEditor }, 30000),
               "restoring the original plug-in finishes loading")
        tryCompare(p.model, "isLive", true, 30000)
        tryCompare(p.model, "browsingPlugins", false)

        let editor = findChild(p.panel, "midiEffectsOpenEditor")
        verify(!!editor, "Object exists")
        tryCompare(editor, "enabled", true)
        const close = findChild(p.panel, "midiEffectsClose")
        verify(!!close, "Object exists")
        close.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(close, "activeFocus", true)
        const transport = p.app.transportBarPresenter()
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 3)
        tryCompare(p.model, "isOpen", true)
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 2)
        tryCompare(p.model, "isOpen", true)
        tryCompare(p.model, "hasEffect", true)
        shell.shellPresenter.activate("transport.stop")
        tryCompare(transport, "state", 1)

        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(p.model, "isOpen", false)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") === null })
        const live = findChild(p.row, "timelineHeaderLive_" + p.track)
        verify(!!live, "the track has an independent Live toggle")
        tryCompare(live, "visible", true)
        tryCompare(live, "enabled", true)
        const liveHistory = p.app.undoHistory.currentRow
        const liveTrack = p.view.gridModel.trackIndex
        mouseClick(live, live.width / 2, live.height / 2)
        verify(waitForNative(function() { return !p.row.liveArmed && live.enabled }, 10000),
               "header Live disarms the existing effect")
        compare(p.model.isOpen, false)
        compare(p.view.gridModel.trackIndex, liveTrack)
        compare(p.app.undoHistory.currentRow, liveHistory)
        live.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(live, "activeFocus", true)
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() { return p.row.liveArmed && live.enabled }, 10000),
               "Return on header Live rearms the same effect")
        compare(p.model.isOpen, false)
        compare(p.app.undoHistory.currentRow, liveHistory)
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 3)
        compare(p.row.liveArmed, true)
        compare(p.model.isOpen, false)
        keyClick(Qt.Key_Space)
        tryCompare(transport, "state", 2)
        shell.shellPresenter.activate("transport.stop")
        tryCompare(transport, "state", 1)
        compare(p.app.undoHistory.currentRow, liveHistory)
        mouseClick(p.button, p.button.width / 2, p.button.height / 2)
        tryCompare(p.model, "isOpen", true)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") !== null })
        p.panel = findChild(p.view, "midiEffectsPanel")
        list = findChild(p.panel, "midiEffectsPluginList")
        editor = findChild(p.panel, "midiEffectsOpenEditor")
        verify(waitForNative(function() { return editor.enabled && !p.model.isLoading }, 10000),
               "rack reopening settles through the native main-actor pump")

        const undoRow = p.app.undoHistory.currentRow
        verify(bootstrap.injectPluginFault(p.track, 1))
        verify(waitForNative(function() {
            return p.model.status === "TestGen stopped working." && p.model.canReload
        }, 30000), "MIDI producer crash is published: " + midiEffectsDiagnostics(p.model, list))
        tryCompare(p.model, "status", "TestGen stopped working.", 30000)
        tryCompare(p.app.undoHistory, "currentRow", undoRow)
        tryCompare(p.model, "canReload", true, 30000)
        tryCompare(p.row, "effectStopped", true)
        tryCompare(caption, "text", "Stopped")
        tryCompare(caption, "visible", true)
        tryCompare(editor, "enabled", false)
        tryCompare(shell, "visible", true)
        const reload = findChild(p.panel, "midiEffectsReload")
        verify(!!reload, "Object exists")
        tryCompare(reload, "visible", true)
        tryCompare(reload, "enabled", true)
        reload.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(reload, "activeFocus", true)
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return !p.model.canReload && !p.model.isLoading && p.model.canOpenEditor
                && p.model.status === ""
        }, 30000), "MIDI producer reload settles: " + midiEffectsDiagnostics(p.model, list))
        tryCompare(p.model, "canReload", false, 30000)
        tryCompare(p.model, "isLoading", false, 30000)
        tryCompare(p.model, "status", "", 30000)
        tryCompare(reload, "visible", false)
        tryCompare(editor, "enabled", true)
        tryCompare(p.row, "effectName", "TestGen")
        tryCompare(p.row, "effectStopped", false)
        tryCompare(badge, "text", "TestGen")
        tryCompare(badge, "visible", true)
        verifyCardFits(p.panel)

        const remove = findChild(p.panel, "midiEffectsRemove")
        verify(!!remove, "Object exists")
        tryCompare(remove, "enabled", true, 30000)
        mouseClick(remove, remove.width / 2, remove.height / 2)
        tryCompare(p.model, "hasEffect", false, 30000)
        tryCompare(p.model, "isOpen", false)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") === null }, 3000,
                  "Remove unmounts setup before clicking the persistent header button")
        tryCompare(p.row, "effectName", "")
        tryCompare(p.button, "visible", true)
        mouseClick(p.button, p.button.width / 2, p.button.height / 2)
        tryCompare(p.model, "isOpen", true)
        tryCompare(p.model, "hasEffect", false)
        tryCompare(p.view.gridModel, "trackIndex", p.track)
        tryVerify(function() { return findChild(p.view, "midiEffectsPanel") !== null })
    }
}
