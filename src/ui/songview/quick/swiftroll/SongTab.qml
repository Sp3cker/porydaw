pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui
import PorydawApp

// Each page acknowledges destruction so the controller keeps its workspace
// alive until every tab holding it has gone.
FocusScope {
    id: root

    final required property SongTabSession session
    final required property SongTabsController controller
    final property ShellPresenter shellRouter: null
    readonly property bool showEvents: root.session.showsEvents
    final readonly property EditorSurface surface: pageLoader.item as EditorSurface
    signal contextMenuAt(real x, real y)

    Component.onDestruction: {
        pageLoader.active = false
        root.controller.pageReleased(root.session.tabId)
    }

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
