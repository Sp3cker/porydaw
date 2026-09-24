import QtQuick
import QtQuick.Controls.Basic
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

    Button {
        id: pageToggle
        objectName: "songTabEventListToggle"
        anchors.top: parent.top
        anchors.right: parent.right
        z: 11
        text: root.showEvents ? qsTr("Piano Roll") : qsTr("Event List")
        font: root.applicationFont
        padding: Math.round(root.applicationFont.pixelSize * 0.5)
        onClicked: {
            root.showEvents = !root.showEvents
            if (root.showEvents && root.visible)
                Qt.callLater(function() {
                    if (eventPage.item)
                        eventPage.item.forceActiveFocus(Qt.OtherFocusReason)
                })
        }
        Accessible.name: root.showEvents ? qsTr("Show piano roll") : qsTr("Show event list")
    }
}
