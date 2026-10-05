pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: overlay
    required property bool overlayOpen
    required property Item cardItem
    required property string underlayObjectName
    property Item focusOrigin: null
    property bool dismissOnlyOutsideCard: false
    property bool consumeDismissPress: false
    property bool preventUnderlayStealing: false
    property bool focusOnCompletion: true
    property bool consumingOutsidePress: false
    signal initialFocusRequested()
    signal dismissRequested()
    signal overlayClosed()
    visible: overlayOpen || consumingOutsidePress
    enabled: visible

    function finishOutsidePress(): void {
        consumingOutsidePress = false
    }
    function restoreFocusIfOwned(): void {
        const active = overlay.Window.window ? overlay.Window.window.activeFocusItem : null
        let focus = active
        while (focus && focus !== overlay)
            focus = focus.parent
        if (!active || focus === overlay)
            focusOrigin.forceActiveFocus(Qt.OtherFocusReason)
    }
    onOverlayOpenChanged: {
        if (overlayOpen)
            Qt.callLater(overlay.initialFocusRequested)
        else
            overlayClosed()
    }
    Component.onCompleted: if (overlayOpen && focusOnCompletion) Qt.callLater(overlay.initialFocusRequested)

    MouseArea {
        objectName: overlay.underlayObjectName
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        preventStealing: overlay.preventUnderlayStealing
        onPressed: mouse => {
            mouse.accepted = true
            if (!overlay.dismissOnlyOutsideCard
                    || mouse.x < overlay.cardItem.x || mouse.x >= overlay.cardItem.x + overlay.cardItem.width
                    || mouse.y < overlay.cardItem.y || mouse.y >= overlay.cardItem.y + overlay.cardItem.height) {
                if (overlay.consumeDismissPress)
                    overlay.consumingOutsidePress = true
                overlay.dismissRequested()
            }
        }
        onReleased: if (overlay.consumeDismissPress) Qt.callLater(overlay.finishOutsidePress)
        onCanceled: if (overlay.consumeDismissPress) Qt.callLater(overlay.finishOutsidePress)
    }
}
