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
    property var shellRouter: null
    readonly property bool showEvents: session.showsEvents
    signal contextMenuAt(real x, real y)

    Component.onDestruction: controller.pageReleased(session.tabId)

    Loader {
        anchors.fill: parent
        sourceComponent: Component {
            EditorSurface {
                applicationSession: root.session
                shellRouter: root.shellRouter
                onContextMenuAt: (x, y) => root.contextMenuAt(x, y)
            }
        }
    }
}
