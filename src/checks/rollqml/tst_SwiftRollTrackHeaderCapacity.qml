import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui

RollLaneSupport {
    id: testCase
    name: "SwiftRollTrackHeaderCapacity"
    when: windowShown
    width: 960
    height: 640
    visible: true

    verifySurface: true
    surfaceMessage: ""

    function item(name) {
        var result = null
        tryVerify(function() {
            result = findChild(surface(), name)
            return result !== null
        }, 1000, "mounted item " + name + " exists")
        return result
    }
    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("se_fanfare_1trk"))
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), session.lastSaveError)
        verify(session.songOpen, session.lastSaveError)
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        testCase.overlay = overlayComponent.createObject(testCase, {
            "width": testCase.width, "height": testCase.height
        })
        verify(testCase.overlay !== null)
        verify(waitForNative(function() {
            var mounted = findChild(testCase.overlay, "swiftRollOverlay")
            return mounted !== null && mounted.visible && mounted.width > 0
        }, 5000))
    }
    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing())
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval())
        }
    }
    function test_capacityMenuDisablesDuplicate() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        compare(rows.count, 1, "the capacity song mounts its only playable track")
        verify(!rows.itemAt(0).isAddTrack,
               "the capacity song shows no add row")
        var input = item("timelineTrackHeadersInput")
        var first = rows.itemAt(0)
        tryVerify(function() {
            return h.viewportHeight > 0 && first.titleRect.width > 0
                   && first.titleRect.height > 0
        }, 5000, "the capacity header has a measured title hit target")
        mouseClick(input, first.titleRect.x + first.titleRect.width / 2,
                   first.titleRect.y + first.titleRect.height / 2, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        var panel = item("quickMenuPanelRoot")
        compare(panel.rowCount, 5, "the capacity menu retains the fork's five actions")
        var duplicate = item("headerMenuRow_4")
        compare(duplicate.enabled, false, "duplicate at capacity stays disabled")
        mouseClick(duplicate, duplicate.width / 2, duplicate.height / 2)
        compare(h.menuOpen, true,
                "clicking the disabled duplicate neither dispatches nor dismisses")
        compare(rows.count, 1, "clicking the disabled duplicate writes nothing")
        keyClick(Qt.Key_Escape)
        tryCompare(h, "menuOpen", false, 5000,
                   "escape dismisses the capacity menu")
        mouseClick(input, first.titleRect.x + first.titleRect.width / 2,
                   first.titleRect.y + first.titleRect.height / 2, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        var frame = item("quickMenuFrame")
        var origin = frame.mapToItem(null, 0, 0)
        var point = input.mapToItem(null, input.width - 1, input.height - 1)
        verify(point.x < origin.x || point.x >= origin.x + frame.width
               || point.y < origin.y || point.y >= origin.y + frame.height)
        mouseClick(input, input.width - 1, input.height - 1)
        tryCompare(h, "menuOpen", false, 5000,
                   "outside press dismisses the capacity menu")
        compare(rows.count, 1, "outside dismissal leaves the capacity song untouched")
    }
}
