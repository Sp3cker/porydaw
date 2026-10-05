import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: lane

    property alias bootstrap: bootstrapObject
    property alias session: sessionObject
    property alias overlayComponent: overlayFactory
    property var overlay: null
    property bool verifySurface: false
    property string surfaceMessage: "the production EditorSurface is mounted"
    property bool includeStagedLabels: false
    property bool reserveRulerHeight: false
    signal overlayMounted(var item, var mounted, var drawer)

    RollQmlBootstrap {
        id: bootstrapObject
        ApplicationSession { id: sessionObject }
    }

    Component {
        id: overlayFactory
        SwiftRollOverlay { applicationSession: lane.session }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(lane.bootstrap, function(ms) { lane.wait(ms) }, predicate, timeoutMs)
    }

    // Mount polling needs a nullable lookup; settled suites retain their checks.
    function surface(checked) {
        var mounted = lane.overlay ? lane.findChild(lane.overlay, "swiftRollOverlay") : null
        if (checked === undefined ? lane.verifySurface : checked)
            lane.verify(mounted !== null, lane.surfaceMessage)
        return mounted
    }

    function stagedLabels() {
        var labels = []
        var songs = lane.session.songDockController().songListPresenter()
        var count = songs.rowCount
        for (var i = 0; i < count && i < 8; ++i)
            labels.push(songs.songLabel(i))
        return count > 8 ? labels.join(",") + ",…" : labels.join(",")
    }

    function openDiagnostics() {
        var details = ["projectRoot=" + lane.bootstrap.projectRoot,
                       "label=mus_route101",
                       "projectOpen=" + lane.session.projectOpen,
                       "songOpen=" + lane.session.songOpen]
        if (lane.includeStagedLabels)
            details.push("stagedLabels=[" + lane.stagedLabels() + "]")
        if (lane.session.lastSaveError.length > 0)
            details.push("lastSaveError=" + lane.session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

    function mountOverlay() {
        var item = lane.overlayComponent.createObject(lane, {
            "width": lane.width,
            "height": lane.height
        })
        lane.verify(item, "the production overlay came up")
        lane.overlay = item
        var mounted = null
        lane.verify(lane.waitForNative(function() {
            mounted = lane.surface(false)
            return mounted !== null
        }, 5000), "the selected tab's production EditorSurface mounted")
        if (lane.reserveRulerHeight)
            item.height += mounted.gridModel.rulerHeight
        var drawer = lane.findChild(mounted, "editorDrawer")
        lane.verify(drawer, "the production drawer is mounted")
        lane.session.configurePersistence()
        lane.verify(lane.waitForNative(function() {
            return mounted.visible && mounted.width > 0 && mounted.height > 0
        }, 5000), "the mounted surface is drawn")
        lane.overlayMounted(item, mounted, drawer)
    }

    function grid() {
        var g = lane.surface().gridModel
        lane.verify(g !== null, "the grid presenter is published")
        return g
    }

    function rollInput() {
        var input = lane.findChild(lane.surface(), "swiftRollInput")
        lane.verify(input !== null, "the roll input MouseArea exists")
        return input
    }
}
