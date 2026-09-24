import QtQuick
import ".." as Original

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
    property bool showEvents: false
    signal contextMenuAt(real x, real y)

    // The presenter mirrors page visibility: the event Loader destroys its
    // item on hide without a visible transition, so the page alone cannot
    // publish the false edge the shell key router reads.
    onShowEventsChanged: {
        const presenter = root.session.eventListPresenter()
        if (presenter)
            presenter.setVisible(root.showEvents)
    }
    readonly property var eventPageItem: eventPage.item

    Component.onDestruction: controller.pageReleased(session.tabId)

    Loader {
        anchors.fill: parent
        active: !root.showEvents
        sourceComponent: Component {
            EditorSurface {
                applicationSession: root.session
                applicationFont: root.applicationFont
                shellRouter: root.shellRouter
                onContextMenuAt: (x, y) => root.contextMenuAt(x, y)
            }
        }
    }

    Loader {
        id: eventPage
        anchors.fill: parent
        active: root.showEvents
        sourceComponent: Component {
            Original.EventListPage {
                objectName: "eventListPage"
                presenter: root.session.eventListPresenter()
            }
        }
    }
}
