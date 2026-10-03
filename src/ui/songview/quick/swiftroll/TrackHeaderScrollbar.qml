pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

Item {
    id: trackHeaderScrollBar

    required property var headersModel
    required property bool bandVisible
    required property color scrollbarHandle
    required property color scrollbarHandleHover
    required property real rowAreaWidth

    signal wheelDelivered(var event)

    objectName: "timelineTrackHeaderScrollBar"
    x: rowAreaWidth
    width: Math.max(0, headersModel.scrollbarWidth)
    height: parent.height
    z: 4
    visible: bandVisible && scrollable
    activeFocusOnTab: scrollable || activeFocus

    readonly property real span: Math.max(0, headersModel.maximumScrollY)
    readonly property bool scrollable: span > 0
    readonly property real thumbLength: {
        if (!(height > 0) || !scrollable)
            return 0
        const pageStep = headersModel.viewportHeight
        const fraction = pageStep > 0 ? Math.min(1, pageStep / (span + pageStep)) : 0
        return Math.min(height, Math.max(headersModel.scrollbarMinimumThumbHeight,
                                        fraction * height))
    }
    readonly property real thumbTravel: Math.max(0, height - thumbLength)
    readonly property real thumbPos: !scrollable || thumbTravel <= 0
                                     ? 0
                                     : Math.min(span, Math.max(0, headersModel.scrollY))
                                       / span * thumbTravel
    property real dragStartValue: 0
    property real dragStartPosition: 0
    property real dragLastPosition: 0
    property bool dragThresholdReached: false

    onSpanChanged: rebaseDrag()
    onThumbTravelChanged: rebaseDrag()

    function requestScroll(value) {
        if (scrollable)
            headersModel.scrollY = Math.max(0, Math.min(span, value))
    }

    function requestLine(direction) {
        requestScroll(headersModel.scrollY
                      + direction * Math.max(0, headersModel.rowHeight))
    }

    function requestPage(direction) {
        requestScroll(headersModel.scrollY
                      + direction * Math.max(0, headersModel.viewportHeight))
    }

    function rebaseDrag() {
        if (!thumbMouse || !thumbMouse.pressed || !dragThresholdReached)
            return
        dragStartValue = Math.max(0, Math.min(span, headersModel.scrollY))
        dragStartPosition = dragLastPosition
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Up)
            requestLine(-1)
        else if (event.key === Qt.Key_Down)
            requestLine(1)
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
            // Cross-axis arrows stay consumed, as in TimelineScrollbar.
        } else if (event.key === Qt.Key_PageUp)
            requestPage(-1)
        else if (event.key === Qt.Key_PageDown)
            requestPage(1)
        else if (event.key === Qt.Key_Home)
            requestScroll(0)
        else if (event.key === Qt.Key_End)
            requestScroll(span)
        else
            return
        event.accepted = true
    }

    Accessible.role: Accessible.ScrollBar
    Accessible.name: qsTr("Track headers")
    Accessible.description: qsTr("Use arrow or page keys to scroll")
    Accessible.focusable: activeFocusOnTab
    Accessible.onIncreaseAction: requestLine(1)
    Accessible.onDecreaseAction: requestLine(-1)
    Accessible.onScrollUpAction: requestPage(-1)
    Accessible.onScrollDownAction: requestPage(1)
    Accessible.onScrollLeftAction: requestPage(-1)
    Accessible.onScrollRightAction: requestPage(1)
    Accessible.onPreviousPageAction: requestPage(-1)
    Accessible.onNextPageAction: requestPage(1)

    MouseArea {
        anchors.fill: parent
        enabled: trackHeaderScrollBar.scrollable

        onClicked: (mouse) => {
            if (mouse.y >= trackHeaderScrollBar.thumbPos
                    && mouse.y < trackHeaderScrollBar.thumbPos
                                 + trackHeaderScrollBar.thumbLength)
                return
            trackHeaderScrollBar.requestPage(mouse.y < trackHeaderScrollBar.thumbPos ? -1 : 1)
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.pixelDelta.x === 0 && event.angleDelta.x === 0)
                trackHeaderScrollBar.wheelDelivered(event)
        }
    }

    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.pixelDelta.x !== 0 || event.angleDelta.x !== 0)
                trackHeaderScrollBar.wheelDelivered(event)
        }
    }

    Rectangle {
        objectName: "timelineTrackHeaderScrollThumb"
        y: trackHeaderScrollBar.thumbPos
        width: parent.width
        height: trackHeaderScrollBar.thumbLength
        visible: trackHeaderScrollBar.scrollable && width > 0 && height > 0
        color: thumbHover.hovered ? trackHeaderScrollBar.scrollbarHandleHover
                                  : trackHeaderScrollBar.scrollbarHandle

        HoverHandler {
            id: thumbHover
        }
    }

    MouseArea {
        id: thumbMouse

        anchors.fill: parent
        enabled: trackHeaderScrollBar.scrollable && trackHeaderScrollBar.thumbTravel > 0
        hoverEnabled: false
        z: 1

        onPressed: (mouse) => {
            if (mouse.y < trackHeaderScrollBar.thumbPos
                    || mouse.y >= trackHeaderScrollBar.thumbPos
                                  + trackHeaderScrollBar.thumbLength) {
                mouse.accepted = false
                return
            }
            trackHeaderScrollBar.dragStartValue = Math.max(0,
                Math.min(trackHeaderScrollBar.span, trackHeaderScrollBar.headersModel.scrollY))
            trackHeaderScrollBar.dragStartPosition = mouse.y
            trackHeaderScrollBar.dragLastPosition = mouse.y
            trackHeaderScrollBar.dragThresholdReached = false
        }
        onPositionChanged: (mouse) => {
            if (!pressed)
                return
            trackHeaderScrollBar.dragLastPosition = mouse.y
            if (!trackHeaderScrollBar.dragThresholdReached) {
                if (Math.abs(mouse.y - trackHeaderScrollBar.dragStartPosition)
                        < Qt.styleHints.startDragDistance)
                    return
                trackHeaderScrollBar.dragThresholdReached = true
            }
            if (trackHeaderScrollBar.thumbTravel <= 0)
                return
            trackHeaderScrollBar.requestScroll(trackHeaderScrollBar.dragStartValue
                + (mouse.y - trackHeaderScrollBar.dragStartPosition)
                  / trackHeaderScrollBar.thumbTravel * trackHeaderScrollBar.span)
        }
    }

}
