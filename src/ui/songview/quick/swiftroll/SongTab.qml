pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

// Each page acknowledges destruction so the controller keeps its workspace
// alive until every tab holding it has gone.
FocusScope {
    id: root

    required property QtObject session
    required property QtObject controller
    property var shellRouter: null
    readonly property bool showEvents: root.session.showsEvents
    readonly property var surface: pageLoader.item
    signal contextMenuAt(real x, real y)

    Component.onDestruction: root.controller.pageReleased(root.session.tabId)

    Loader {
        id: pageLoader
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
