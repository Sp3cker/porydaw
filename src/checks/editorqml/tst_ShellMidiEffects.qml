import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck
import Porydaw.Ui

ShellClipboardSupport {
    id: testCase
    name: "ShellMidiEffects"

    function init() {
        verify(bootstrap.resetPreferences())
    }

    function openFromTrackHeader() {
        const app = openRoute101()
        shell.width = 960
        shell.height = 640
        const view = selectedSurface()
        verify(!!view, "Object exists")
        view.gridModel.setTrack(0)
        const rows = findChild(view, "timelineTrackHeaderRows")
        verify(!!rows, "Object exists")
        tryVerify(function() { return rows.count > 0 })
        const row = rows.itemAt(0)
        verify(!!row, "Object exists")
        const header = view.trackHeaders
        verify(!!header, "Object exists")
        mouseClick(header, row.titleRect.x + row.titleRect.width / 2,
                   row.titleRect.y + row.titleRect.height / 2 - view.headersModel.scrollY,
                   Qt.RightButton)
        tryCompare(view.headersModel, "menuOpen", true)
        tryVerify(function() { return findChild(view, "headerMenuRow_7") !== null })
        const menu = findChild(view, "headerMenuRow_7")
        verify(!!menu, "Object exists")
        tryCompare(menu, "enabled", true)
        mouseClick(menu, menu.width / 2, menu.height / 2)
        const model = view.midiEffectsModel
        verify(!!model, "Object exists")
        tryCompare(model, "isOpen", true)
        tryVerify(function() { return findChild(view, "midiEffectsPanel") !== null })
        const panel = findChild(view, "midiEffectsPanel")
        verify(!!panel, "Object exists")
        const close = findChild(panel, "midiEffectsClose")
        verify(!!close, "Object exists")
        tryCompare(close, "activeFocus", true)
        return { app: app, view: view, rows: rows, model: model, panel: panel }
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

    function test_fixtureSelectionCrashReloadAndRemove() {
        const p = openFromTrackHeader()
        verify(bootstrap.vstFixtureFolder.length > 0)
        p.model.addFolder(bootstrap.vstFixtureFolder)
        const list = findChild(p.panel, "midiEffectsPluginList")
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
                compare(row.blocked, false)
            }
        }
        verify(names.indexOf("TestGen") >= 0)
        verify(names.indexOf("TestGenAudio") >= 0)
        verify(names.indexOf("TestGenRealtimeOnly") >= 0)
        compare(names.indexOf("TestAudioOnly"), -1)
        verify(generator >= 0)
        verify(waitForNative(function() { return !p.model.isLoading }, 30000),
               "MIDI effect setup settles: " + midiEffectsDiagnostics(p.model, list))
        const generatorRow = pluginRow(list, generator)
        tryCompare(generatorRow, "enabled", true, 30000)
        mouseClick(generatorRow, generatorRow.width / 2, generatorRow.height / 2)
        verify(waitForNative(function() {
            return p.model.hasEffect && !p.model.isLoading && p.model.canOpenEditor
                && p.model.selectedPlugin === generator
        }, 30000), "Selected MIDI producer loads: " + midiEffectsDiagnostics(p.model, list))
        tryCompare(p.model, "hasEffect", true, 30000)
        tryCompare(p.model, "isLoading", false, 30000)
        tryCompare(p.model, "selectedPlugin", generator)
        tryVerify(function() { return p.rows.itemAt(0).effectName === "TestGen" })
        tryVerify(function() { return !p.rows.itemAt(0).effectStopped })
        const badge = findChild(p.view, "timelineHeaderEffect_0")
        verify(!!badge, "Object exists")
        tryCompare(badge, "text", "TestGen")
        tryCompare(badge, "visible", true)
        const caption = findChild(p.view, "timelineHeaderEffectCaption_0")
        verify(!!caption, "Object exists")
        tryCompare(caption, "visible", false)
        verifyCardFits(p.panel)

        const editor = findChild(p.panel, "midiEffectsOpenEditor")
        verify(!!editor, "Object exists")
        tryCompare(editor, "enabled", true)
        compare(p.model.isEditorOpen, false)
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

        const undoRow = p.app.undoHistory.currentRow
        verify(bootstrap.injectPluginFault(0, 1))
        verify(waitForNative(function() {
            return p.model.status === "TestGen stopped working." && p.model.canReload
        }, 30000), "MIDI producer crash is published: " + midiEffectsDiagnostics(p.model, list))
        tryCompare(p.model, "status", "TestGen stopped working.", 30000)
        tryCompare(p.app.undoHistory, "currentRow", undoRow)
        tryCompare(p.model, "canReload", true, 30000)
        tryVerify(function() { return p.rows.itemAt(0).effectStopped })
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
        tryVerify(function() {
            const row = p.rows.itemAt(0)
            return row.effectName === "TestGen" && !row.effectStopped
        })
        tryCompare(caption, "visible", false)
        tryCompare(badge, "text", "TestGen")
        tryCompare(badge, "visible", true)
        verifyCardFits(p.panel)

        const remove = findChild(p.panel, "midiEffectsRemove")
        verify(!!remove, "Object exists")
        tryCompare(remove, "enabled", true, 30000)
        mouseClick(remove, remove.width / 2, remove.height / 2)
        tryCompare(p.model, "hasEffect", false, 30000)
        tryCompare(p.model, "isOpen", false)
        tryVerify(function() { return p.rows.itemAt(0).effectName === "" })
        tryCompare(badge, "visible", false)
    }
}
