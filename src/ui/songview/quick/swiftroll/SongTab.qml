import QtQuick
import Porydaw.Ui

// One song tab's page: the surface of the workspace the tab owns. A page is
// destroyed when its tab closes, and the controller keeps the bound workspace
// alive until every page holding it is gone, so the page acknowledges its own
// destruction.
FocusScope {
    id: root

    required property QtObject session
    required property QtObject controller
    property font applicationFont: Application.font
    property var shellRouter: null
    signal contextMenuAt(real x, real y)

    Component.onDestruction: controller.pageReleased(session.tabId)

    EditorSurface {
        anchors.fill: parent
        applicationSession: root.session
        applicationFont: root.applicationFont
        shellRouter: root.shellRouter
        onContextMenuAt: (x, y) => root.contextMenuAt(x, y)
    }
}
