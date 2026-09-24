import QtQuick

// The canvas owns one of these per active popup session. It provides the
// outside-press underlay for menus and modal forms, while the form
// container's shield keeps frame gaps and labels from dismissing the active
// form. Owner-governed surfaces supply their own shield and input policy.
Item {
    id: layer

    required property var session
    property bool formActive: false
    property bool surfaceActive: false
    property alias formContainer: formContent

    objectName: "quickPopupLayer"
    anchors.fill: parent
    z: 1000000

    MouseArea {
        id: underlay

        objectName: "quickPopupUnderlay"
        anchors.fill: parent
        enabled: !layer.surfaceActive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (mouse) => layer.session.outsidePressed(mouse.button,
                                                            Qt.point(mouse.x, mouse.y))
        onWheel: (wheel) => wheel.accepted = true

        // The underlay is a no-hint group: while it is the hover leaf it
        // claims empty so covered background hints cannot leak through.
        HoverHint {
            source: underlay
        }
    }

    Item {
        id: formContent

        objectName: "quickPopupFormContainer"
        visible: layer.formActive
        z: 1

        // Form roots are appended above this shield. Its geometry follows the
        // form panel, leaving every point outside the panel to the underlay.
        MouseArea {
            id: formShield

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            onWheel: (wheel) => wheel.accepted = true

            // The shield is its own no-hint group; form children publish
            // their real profiles and never compete with it.
            HoverHint {
                source: formShield
            }
        }
    }
}
