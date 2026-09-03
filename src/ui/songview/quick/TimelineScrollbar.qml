import QtQuick

Item {
    id: scrollbar

    required property real scrollY
    required property real contentHeight
    required property real viewportHeight
    required property real maximumScrollY
    required property real minimumThumbHeight
    required property color handleColor
    required property color handleHoverColor
    property bool externalVisible: true
    property bool visibleWhenNotScrollable: false
    property string thumbObjectName: ""
    property string accessibleName: qsTr("Timeline")
    property real lineStep: Math.max(1, safeViewportHeight / 10)

    readonly property real safeViewportHeight: Math.max(0, viewportHeight)
    readonly property real safeContentHeight: Math.max(safeViewportHeight, contentHeight)
    readonly property bool scrollable: maximumScrollY > 0 && safeViewportHeight > 0
                                    && safeContentHeight > 0
    readonly property real thumbHeight: {
        if (safeViewportHeight <= 0 || height <= 0)
            return 0
        if (!scrollable)
            return visibleWhenNotScrollable ? height : 0
        return Math.min(Math.max(0, height), Math.max(minimumThumbHeight,
                                                        safeViewportHeight / safeContentHeight
                                                        * safeViewportHeight))
    }
    readonly property real thumbTravel: Math.max(0, height - thumbHeight)
    readonly property real thumbY: maximumScrollY === 0 ? 0
                                                          : scrollY / maximumScrollY * thumbTravel
    property real dragStartThumbY: 0

    signal scrollYRequested(real value)
    signal pageRequested(real localY)
    signal wheelRequested(real pixelX, real pixelY, real angleX, real angleY, bool inverted)

    function requestScroll(value) {
        if (!scrollable)
            return
        scrollYRequested(Math.min(maximumScrollY, Math.max(0, value)))
    }

    function requestLine(direction) {
        requestScroll(scrollY + direction * Math.max(1, lineStep))
    }

    function requestPage(direction) {
        requestScroll(scrollY + direction * safeViewportHeight)
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Up:
            requestLine(-1)
            break
        case Qt.Key_Down:
            requestLine(1)
            break
        case Qt.Key_PageUp:
            requestPage(-1)
            break
        case Qt.Key_PageDown:
            requestPage(1)
            break
        case Qt.Key_Home:
            requestScroll(0)
            break
        case Qt.Key_End:
            requestScroll(maximumScrollY)
            break
        default:
            return
        }
        event.accepted = true
    }

    visible: externalVisible && (visibleWhenNotScrollable || scrollable)
    activeFocusOnTab: scrollable
    Keys.onPressed: (event) => scrollbar.handleKey(event)

    Accessible.role: Accessible.ScrollBar
    Accessible.name: scrollbar.accessibleName
    Accessible.description: qsTr("Use arrow or page keys to scroll")
    Accessible.focusable: scrollbar.scrollable
    Accessible.onIncreaseAction: scrollbar.requestLine(1)
    Accessible.onDecreaseAction: scrollbar.requestLine(-1)
    Accessible.onScrollUpAction: scrollbar.requestPage(-1)
    Accessible.onScrollDownAction: scrollbar.requestPage(1)
    Accessible.onPreviousPageAction: scrollbar.requestPage(-1)
    Accessible.onNextPageAction: scrollbar.requestPage(1)

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds

        onTapped: (eventPoint) => {
            if (!scrollbar.scrollable)
                return
            const y = eventPoint.position.y
            if (y >= scrollbar.thumbY && y < scrollbar.thumbY + scrollbar.thumbHeight)
                return
            scrollbar.pageRequested(y)
        }
    }

    WheelHandler {
        onWheel: (event) => scrollbar.wheelRequested(event.pixelDelta.x, event.pixelDelta.y,
                                                      event.angleDelta.x, event.angleDelta.y,
                                                      event.inverted)
    }

    Rectangle {
        id: thumb

        objectName: scrollbar.thumbObjectName
        y: scrollbar.thumbY
        width: parent.width
        height: scrollbar.thumbHeight
        visible: (scrollbar.scrollable || scrollbar.visibleWhenNotScrollable)
                 && width > 0 && height > 0
        color: thumbHover.hovered ? scrollbar.handleHoverColor : scrollbar.handleColor

        HoverHandler {
            id: thumbHover
        }

        DragHandler {
            yAxis.enabled: true
            xAxis.enabled: false

            onActiveChanged: {
                if (active)
                    scrollbar.dragStartThumbY = scrollbar.thumbY
            }
            onTranslationChanged: {
                if (scrollbar.thumbTravel <= 0)
                    return
                const y = Math.min(scrollbar.thumbTravel,
                                   Math.max(0, scrollbar.dragStartThumbY + translation.y))
                scrollbar.scrollYRequested(y / scrollbar.thumbTravel * scrollbar.maximumScrollY)
            }
        }
    }
}
