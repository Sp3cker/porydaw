pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion

// Fusion's ScrollView; content scrolls by wheel, touchpad or scroll bar, never by mouse drag.
Fusion.ScrollView {
    id: control

    // `data`, not the default `contentData`: a child there would create the Flickable early.
    data: Binding {
        target: control.contentItem
        property: "acceptedButtons"
        value: Qt.NoButton
    }
}
