import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

ShellLaneSupport {
    id: testCase
    name: "ShellVoicegroup"
    when: windowShown
    width: 420
    height: 680
    visible: true
    property alias bootstrap: voiceBootstrap
    property alias fileProbe: voiceFileProbe
    readonly property ApplicationSession app: voiceShell.session
    property alias shellPresenter: voiceShell
    property alias panel: voicePanel
    property alias fullShellComponent: shellWindowComponent

    ShellQmlBootstrap { id: voiceBootstrap }
    TabsDrawerProbe { id: voiceFileProbe }
    ShellPresenter { id: voiceShell }
    property int saveStarts: 0
    property int saveFinishes: 0
    Connections {
        target: app
        function onSaveInProgressChanged() {
            if (app.saveInProgress)
                ++testCase.saveStarts
            else
                ++testCase.saveFinishes
        }
    }
    property var fullShell: null
    property int shellSaveStarts: 0
    property int shellSaveFinishes: 0
    Connections {
        target: fullShell ? fullShell.shellPresenter.session : null
        function onSaveInProgressChanged() {
            if (fullShell.shellPresenter.session.saveInProgress)
                ++testCase.shellSaveStarts
            else
                ++testCase.shellSaveFinishes
        }
    }
    Component {
        id: shellWindowComponent
        ShellWindow {
            width: testCase.width * 2.5
            height: testCase.height
            visible: true
        }
    }
    Pane {
        anchors.fill: parent
        padding: 0
        font: app.typographyFonts.body
        contentItem: VoicegroupPanel {
            id: voicePanel
            applicationSession: app
            controller: app.voiceListController()
        }
    }

    function compareRole(item, role, name) {
        verify(!!item, name + " is mounted for " + role)
        const expected = app.typographyFonts[role]
        compare(item.font.family, expected.family, name + " uses " + role + " family")
        compare(item.font.pixelSize, expected.pixelSize, name + " uses " + role + " pixelSize")
        compare(item.font.weight, expected.weight, name + " uses " + role + " weight")
    }

    laneBootstrap: bootstrap

    function createFullShell() {
        bootstrap.preferences.setString("lastProjectDir", "")
        fullShell = fullShellComponent.createObject(null)
        verify(fullShell !== null, "the production full-shell fixture creates")
        fullShell.requestActivate()
        tryCompare(fullShell, "active", true)
        waitForFullShellScene()
        return fullShell
    }

    function waitForFullShellScene() {
        verify(waitForNative(function() {
            return fullShell.visible && fullShell.sceneLoader !== null
                && fullShell.sceneLoader.status === Loader.Ready
                && fullShell.contentItem.width > 0 && fullShell.contentItem.height > 0
        }, 10000), "the full shell mounts its workspace before fixture input")
        verify(waitForPolish(fullShell), "the full-shell layout finishes its pending polish")
        verify(NativeWait.waitForSubmittedFrame(bootstrap, function(ms) { wait(ms) }, fullShell, 5000),
               "the exposed full shell submits the requested frame before fixture input")
    }

    function initTestCase() {
        compare(panel.baseFontPx, app.baseFontPx,
                "voicegroup pane derives its base before a song opens")
        compareRole(findChild(panel, "vgArgCombo"), "body", "voicegroup selector before song open")
        compare(findChild(panel, "voicegroupTreeHeader").height,
                Math.round(app.baseFontPx * 1.83),
                "voicegroup header follows the session base before song open")
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000),
               "fixture song opens: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        app.gridPresenter().configureViewport(420, 680, 12, 1)
        tryCompare(app.voiceListController(), "isBound", true)
        waitForRendering(panel)
    }

    function region(reference, name) {
        return reference.regions.find(function(entry) { return entry.name === name })
    }

    function directChildGeometry() {
        const editor = findChild(panel, "voicegroupEditorSurface")
        let parts = ["panel h=" + panel.height + " implicit=" + panel.implicitHeight
                     + " font=" + panel.baseFontPx + " slot=" + panel.controller.currentSlot
                     + " editor.macro=" + editor.draft.macro
                     + " fresh.macro=" + panel.controller.editorModel().macro
                     + " editor.preferred=" + editor.Layout.preferredHeight
                     + " editor.rows=" + editor.visibleRows]
        for (let i = 0; i < panel.children.length; i++) {
            const child = panel.children[i]
            parts.push(i + ":" + (child.objectName || "unnamed")
                       + " y=" + child.y + " h=" + child.height
                       + " implicit=" + child.implicitHeight
                       + " visible=" + child.visible)
        }
        for (let i = 0; i < editor.children.length; i++) {
            const child = editor.children[i]
            parts.push("editor." + i + ":" + (child.objectName || "unnamed")
                       + " y=" + child.y + " h=" + child.height
                       + " implicit=" + child.implicitHeight
                       + " visible=" + child.visible)
        }
        return parts.join("; ")
    }

    function checkRegion(reference, name, item, tolerance) {
        const expected = region(reference, name)
        verify(expected !== undefined, "widget reference has " + name)
        verify(item !== null, "mounted panel has " + name)
        const scale = panel.baseFontPx / reference.environment.fontPx
        const origin = item.mapToItem(panel, 0, 0)
        const expectedX = expected.x * scale
        const expectedWidth = panel.width - expectedX
                              - (reference.image.width - expected.x - expected.w) * scale
        const expectedY = name.startsWith("editor.")
                          ? panel.height - (reference.image.height - expected.y) * scale
                          : expected.y * scale
        const expectedHeight = name === "tree"
                               ? panel.height - expectedY
                                 - (reference.image.height - expected.y - expected.h) * scale
                               : expected.h * scale
        verify(Math.abs(origin.x - expectedX) <= tolerance
               && Math.abs(origin.y - expectedY) <= tolerance
               && Math.abs(item.width - expectedWidth) <= tolerance
               && Math.abs(item.height - expectedHeight) <= tolerance,
               name + " measured " + origin.x + "," + origin.y + " "
               + item.width + "x" + item.height + " vs rebased widget "
               + expectedX + "," + expectedY + " "
               + expectedWidth + "x" + expectedHeight
               + (name === "tree" ? "; " + directChildGeometry() : ""))
    }

    function capture(variant) {
        const reference = JSON.parse(bootstrap.voicegroupReferenceJson(variant))
        compare(reference.image.width, panel.width)
        compare(reference.image.height, panel.height)
        const editor = findChild(panel, "voicegroupEditorSurface")
        tryCompare(editor, "visibleRows", variant === "editor-square1" ? 4
                   : variant === "editor-readonly" ? 1 : 3, 1000,
                   "editor form recomputes for selected bank slot")
        waitForRendering(panel)
        checkRegion(reference, "selector", findChild(panel, "vgArgCombo"), 4)
        checkRegion(reference, "tree", findChild(panel, "voicegroupTree"), 5)
        checkRegion(reference, "tree.header", findChild(panel, "voicegroupTreeHeader"), 5)
        checkRegion(reference, "tree.row.000", findChild(panel, "voicegroupRow_0"), 5)
        if (variant === "editor-readonly") {
            checkRegion(reference, "editor.notice",
                        findChild(panel, "voicegroupEditorNotice"), 5)
        } else {
            checkRegion(reference, "editor.type", findChild(panel, "vgTypeCombo"), 5)
            if (variant === "editor-square1") {
                checkRegion(reference, "editor.sweep", findChild(panel, "vgSweepSpin"), 5)
            } else {
                checkRegion(reference, "editor.sample.button",
                            findChild(panel, "vgSamplePickerButton"), 5)
            }
        }
        let saved = false
        const destination = bootstrap.projectRoot + "/voicegroupbrowser-"
                            + (variant.length ? variant : "vanilla") + ".png"
        verify(panel.grabToImage(function(image) {
            saved = image.saveToFile(destination)
        }), "rendered the production VoicegroupPanel")
        tryVerify(function() { return saved }, 5000,
                  "saved " + variant + " voicegroup reference PNG at " + destination)
    }

    function cleanup() {
        if (!fullShell)
            return
        fullShell.close()
        if (fullShell.shellPresenter.session.songTabs.pendingCloseId >= 0)
            fullShell.shellPresenter.session.songTabs.confirmDiscard()
        fullShell.destroy()
        fullShell = null
        wait(0)
    }
}
