pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import QtQuick.Templates as T

// Fusion's Menu whose action rows are this style's MenuItem; its list scrolls
// by wheel, touchpad or scroll bar, never by mouse drag.
Fusion.Menu {
    id: control

    delegate: MenuItem {}

    contentItem: ListView {
        implicitHeight: contentHeight
        model: control.contentModel
        interactive: Window.window
                     ? contentHeight + control.topPadding + control.bottomPadding > control.height
                     : false
        acceptedButtons: Qt.NoButton
        clip: true
        currentIndex: control.currentIndex

        T.ScrollIndicator.vertical: Fusion.ScrollIndicator {}
    }
}
