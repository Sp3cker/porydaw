import QtQuick

// The canvas owns one of these per active popup session. It provides the
// outside-press underlay for menus and modal forms, while the form
// container's shield keeps frame gaps and labels from dismissing the active
// form. Owner-governed surfaces supply their own shield and input policy.
// The underlay covers only the session's visible page rect (published by the
// session from its page root), so anything outside the page — a shared tab
// strip, a sibling page slot — stays interactive while a popup is open.
Item {
    id: layer

    required property var session
    property bool formActive: false
    property bool surfaceActive: false
    property rect pageRect: Qt.rect(0, 0, 0, 0)
    property alias formContainer: formContent
    property alias underlay: underlay

    objectName: "quickPopupLayer"
    anchors.fill: parent
    z: 1000000

    MouseArea {
        id: underlay

        objectName: "quickPopupUnderlay"
        x: layer.pageRect.x
        y: layer.pageRect.y
        width: layer.pageRect.width
        height: layer.pageRect.height
        enabled: !layer.surfaceActive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (mouse) => layer.session.outsidePressed(
                       mouse.button, underlay.mapToItem(null, mouse.x, mouse.y))
        onWheel: (wheel) => wheel.accepted = true
    }

    Item {
        id: formContent

        objectName: "quickPopupFormContainer"
        visible: layer.formActive
        z: 1

        // Form roots are appended above this shield. Its geometry follows the
        // form panel, leaving every point outside the panel to the underlay.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            onWheel: (wheel) => wheel.accepted = true
        }
    }
}
