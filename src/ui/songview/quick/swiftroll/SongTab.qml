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
    readonly property bool showEvents: session.showsEvents
    signal contextMenuAt(real x, real y)

    // The presenter mirrors page visibility: the event Loader destroys its
    // item on hide without a visible transition, so the page alone cannot
    // publish the false edge the shell key router reads.
    onShowEventsChanged: {
        const presenter = root.session.eventListPresenter()
        if (presenter)
            presenter.setVisible(root.showEvents)
        if (root.showEvents && root.visible && eventPage.item)
            Qt.callLater(function() {
                if (eventPage.item)
                    eventPage.item.forceActiveFocus(Qt.OtherFocusReason)
            })
    }

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
            EventListPage {
                objectName: "eventListPage"
                presenter: root.session.eventListPresenter()
            }
        }
    }
}
