import QtQuick

// The canvas owns one of these per active popup session. It provides the only
// outside-press underlay for menus and forms, while the form container's
// shield keeps frame gaps and labels from dismissing the active form.
Item {
    id: layer

    required property var session
    property bool formActive: false
    property alias formContainer: formContent

    objectName: "quickPopupLayer"
    anchors.fill: parent
    z: 1000000

    MouseArea {
        id: underlay

        objectName: "quickPopupUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        onPressed: (mouse) => layer.session.outsidePressed(mouse.button,
                                                            Qt.point(mouse.x, mouse.y))
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
