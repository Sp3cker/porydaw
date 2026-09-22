import QtQuick

// One song tab's page: the surface of the workspace the tab owns. A page is
// destroyed when its tab closes or the strip reorders, and the controller keeps
// the bound workspace alive until every page holding it is gone, so the page
// acknowledges its own destruction.
Item {
    id: root

    required property QtObject session
    required property QtObject controller

    Component.onDestruction: controller.pageReleased(session.tabId)

    EditorSurface {
        anchors.fill: parent
        applicationSession: root.session
    }
}
