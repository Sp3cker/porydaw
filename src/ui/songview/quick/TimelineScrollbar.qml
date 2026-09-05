import QtQuick

// Shared scrollbar for timeline Quick surfaces, in either orientation. The
// owning model stays authoritative: the control reports requested values and
// renders thumb geometry from its inputs, never touching model state itself.
Item {
    id: scrollbar

    property int orientation: Qt.Vertical
    property real minimum: 0
    property real maximum: 0
    property real value: 0
    property real pageStep: 0
    property real singleStep: 1
    property real minimumThumbLength: 0
    required property color handleColor
    required property color handleHoverColor
    property bool externalVisible: true
    property bool visibleWhenNotScrollable: false
    property string thumbObjectName: ""
    property string accessibleName: qsTr("Timeline")

    readonly property real span: Math.max(0, Math.max(minimum, maximum) - minimum)
    readonly property bool scrollable: span > 0
    onSpanChanged: scrollbar.rebaseDrag()
    readonly property real trackLength: orientation === Qt.Vertical ? height : width
    readonly property real thumbLength: {
        if (!(trackLength > 0))
            return 0
        if (!scrollable)
            return visibleWhenNotScrollable ? trackLength : 0
        const fraction = pageStep > 0 ? Math.min(1, pageStep / (span + pageStep)) : 0
        return Math.min(trackLength, Math.max(minimumThumbLength, fraction * trackLength))
    }
    readonly property real thumbTravel: Math.max(0, trackLength - thumbLength)
    onThumbTravelChanged: scrollbar.rebaseDrag()
    readonly property real thumbPos: !scrollable || thumbTravel <= 0
                                     ? 0
                                     : (Math.min(Math.max(minimum, maximum),
                                                 Math.max(minimum, value)) - minimum)
                                       / span * thumbTravel
    property real dragStartValue: 0
    property real dragBaseTranslation: 0

    signal valueRequested(real value)
    signal wheelRequested(real pixelX, real pixelY, real angleX, real angleY, bool inverted)

    function clampedValue(requested) {
        return Math.max(minimum, Math.min(maximum, requested))
    }

    function requestScroll(requested) {
        if (!scrollable)
            return
        valueRequested(clampedValue(requested))
    }

    function rebaseDrag() {
        if (!thumbDrag || !thumbDrag.active)
            return
        dragStartValue = clampedValue(value)
        dragBaseTranslation = scrollbar.orientation === Qt.Vertical ? thumbDrag.translation.y
                                                                    : thumbDrag.translation.x
    }

    function requestLine(direction) {
        requestScroll(value + direction * Math.max(0, singleStep))
    }

    function requestPage(direction) {
        requestScroll(value + direction * Math.max(0, pageStep))
    }

    function handleKey(event) {
        const vertical = orientation === Qt.Vertical
        if (event.key === (vertical ? Qt.Key_Up : Qt.Key_Left)) {
            requestLine(-1)
        } else if (event.key === (vertical ? Qt.Key_Down : Qt.Key_Right)) {
            requestLine(1)
        } else if (event.key === Qt.Key_PageUp) {
            requestPage(-1)
        } else if (event.key === Qt.Key_PageDown) {
            requestPage(1)
        } else if (event.key === Qt.Key_Home) {
            requestScroll(minimum)
        } else if (event.key === Qt.Key_End) {
            requestScroll(maximum)
        } else {
            return
        }
        event.accepted = true
    }

    visible: externalVisible && (visibleWhenNotScrollable || scrollable)
    // Qt cannot revoke tab eligibility while this item still owns active focus.
    activeFocusOnTab: scrollable || activeFocus
    Keys.onPressed: (event) => scrollbar.handleKey(event)

    Accessible.role: Accessible.ScrollBar
    Accessible.name: scrollbar.accessibleName
    Accessible.description: qsTr("Use arrow or page keys to scroll")
    Accessible.focusable: scrollbar.activeFocusOnTab
    Accessible.onIncreaseAction: scrollbar.requestLine(1)
    Accessible.onDecreaseAction: scrollbar.requestLine(-1)
    Accessible.onScrollUpAction: scrollbar.requestPage(-1)
    Accessible.onScrollDownAction: scrollbar.requestPage(1)
    Accessible.onScrollLeftAction: scrollbar.requestPage(-1)
    Accessible.onScrollRightAction: scrollbar.requestPage(1)
    Accessible.onPreviousPageAction: scrollbar.requestPage(-1)
    Accessible.onNextPageAction: scrollbar.requestPage(1)

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds

        onTapped: (eventPoint) => {
            if (!scrollbar.scrollable)
                return
            const position = scrollbar.orientation === Qt.Vertical
                             ? eventPoint.position.y : eventPoint.position.x
            if (position >= scrollbar.thumbPos
                    && position < scrollbar.thumbPos + scrollbar.thumbLength)
                return
            scrollbar.requestPage(position < scrollbar.thumbPos ? -1 : 1)
        }
    }

    // Both handlers can receive diagonal or ongoing gestures. Dispatch from
    // exactly one: the horizontal handler owns events with an X component.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.pixelDelta.x === 0 && event.angleDelta.x === 0)
                scrollbar.wheelRequested(event.pixelDelta.x, event.pixelDelta.y,
                                         event.angleDelta.x, event.angleDelta.y, event.inverted)
        }
    }

    WheelHandler {
        orientation: Qt.Horizontal
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            if (event.pixelDelta.x !== 0 || event.angleDelta.x !== 0)
                scrollbar.wheelRequested(event.pixelDelta.x, event.pixelDelta.y,
                                         event.angleDelta.x, event.angleDelta.y, event.inverted)
        }
    }

    Rectangle {
        id: thumb

        objectName: scrollbar.thumbObjectName
        x: scrollbar.orientation === Qt.Vertical ? 0 : scrollbar.thumbPos
        y: scrollbar.orientation === Qt.Vertical ? scrollbar.thumbPos : 0
        width: scrollbar.orientation === Qt.Vertical ? parent.width : scrollbar.thumbLength
        height: scrollbar.orientation === Qt.Vertical ? scrollbar.thumbLength : parent.height
        visible: (scrollbar.scrollable || scrollbar.visibleWhenNotScrollable)
                 && width > 0 && height > 0
        color: thumbHover.hovered ? scrollbar.handleHoverColor : scrollbar.handleColor

        HoverHandler {
            id: thumbHover
        }

        // target stays null: the model is authoritative, so dragging only maps
        // gesture translation onto a requested value and the thumb position is
        // a pure binding of value and geometry. A mid-gesture span or travel
        // change rebases the gesture (onSpanChanged/onThumbTravelChanged), so
        // deltas after the change map through the fresh geometry instead of
        // reinterpreting the accumulated translation at a stale scale.
        DragHandler {
            id: thumbDrag

            xAxis.enabled: scrollbar.orientation === Qt.Horizontal
            yAxis.enabled: scrollbar.orientation === Qt.Vertical
            target: null
            enabled: scrollbar.scrollable && scrollbar.thumbTravel > 0

            onActiveChanged: {
                if (active) {
                    scrollbar.dragStartValue = scrollbar.clampedValue(scrollbar.value)
                    scrollbar.dragBaseTranslation = 0
                }
            }
            onTranslationChanged: {
                if (!active || scrollbar.thumbTravel <= 0)
                    return
                const axisTranslation = (scrollbar.orientation === Qt.Vertical
                                         ? translation.y : translation.x)
                                        - scrollbar.dragBaseTranslation
                scrollbar.requestScroll(scrollbar.dragStartValue
                                        + axisTranslation / scrollbar.thumbTravel
                                          * scrollbar.span)
            }
        }
    }
}
