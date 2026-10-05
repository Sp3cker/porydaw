import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui

RollLaneSupport {
    id: testCaseRoot
    readonly property var testCase: testCaseRoot
    property alias standaloneComponent: standaloneFixture
    name: "TimelineScrollbar"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property real originalAutomationHeight: 0

    Component {
        id: standaloneFixture
        Item {
            x: 40
            y: 40
            width: 240
            height: 20
            property real modelMinimum: -80
            property real modelMaximum: 80
            property real modelValue: -80
            property real modelPage: 20
            property alias control: standalone
            TimelineScrollbar {
                id: standalone
                width: parent.width
                height: parent.height
                orientation: Qt.Horizontal
                minimum: parent.modelMinimum
                maximum: parent.modelMaximum
                value: parent.modelValue
                pageStep: parent.modelPage
                minimumThumbLength: 24
                handleColor: "#777777"
                handleHoverColor: "#aaaaaa"
                onValueRequested: value => parent.modelValue = value
            }
        }
    }

    function grid() { return surface().gridModel }
    function bar(vertical) {
        return findChild(surface(), vertical ? "timelineRollScrollBar"
                                             : "timelineHorizontalScrollBar")
    }
    function cameraValue(vertical) { return vertical ? grid().cameraScrollY : grid().cameraScrollX }
    function cameraMaximum(vertical) {
        return vertical ? grid().cameraMaxVScroll : grid().cameraMaxHScroll
    }
    function midpoint(bar, position) {
        return bar.orientation === Qt.Vertical
                ? { x: bar.width / 2, y: position }
                : { x: position, y: bar.height / 2 }
    }
    function closeTo(actual, expected) { return Math.abs(actual - expected) < 0.01 }
    function thumbWithinTrack(control, vertical) {
        var thumb = findChild(surface(), vertical ? "timelineRollScrollThumb"
                                                  : "timelineHorizontalScrollThumb")
        return thumb && thumb.visible && (vertical ? thumb.y : thumb.x) >= -0.01
            && (vertical ? thumb.y + thumb.height : thumb.x + thumb.width)
               <= control.trackLength + 0.01
            && closeTo(vertical ? thumb.x : thumb.y, 0)
            && closeTo(vertical ? thumb.width : thumb.height,
                       vertical ? control.width : control.height)
    }

    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"), "the staged song starts opening")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the song opened: " + session.lastSaveError)
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        overlay = overlayComponent.createObject(testCase, {
            "width": testCase.width, "height": testCase.height
        })
        verify(overlay, "production composition loaded")
        verify(waitForNative(function() { return surface() !== null }, 5000),
               "the mounted editor loaded")
        session.configurePersistence()
        verify(waitForNative(function() {
            return bar(false) && bar(true) && bar(false).visible && bar(true).visible
                && bar(false).thumbTravel > 0 && bar(true).thumbTravel > 0
        }, 5000), "both rendered scroll tracks have a thumb and travel")
        originalAutomationHeight = surface().drawerPresenter.automationSection.bodyHeight
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(), "document remains presented during teardown")
        var old = overlay
        overlay = null
        if (old) {
            old.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(), "scene removal acknowledged")
        }
    }

    function init() {
        bootstrap.cancelInput()
        overlay.width = testCase.width
        overlay.height = testCase.height
        if (session.showsEvents)
            session.songTabs.setSelectedTabEventsVisible(false)
        grid().setScaleFold(false)
        grid().setCameraHScroll(100)
        grid().setCameraVScroll(Math.min(150, grid().cameraMaxVScroll))
        wait(0)
    }

    function cleanup() {
        surface().drawerPresenter.setSectionBodyHeight(0, originalAutomationHeight)
        if (session.showsEvents)
            session.songTabs.setSelectedTabEventsVisible(false)
        grid().setScaleFold(false)
        wait(0)
    }

}
