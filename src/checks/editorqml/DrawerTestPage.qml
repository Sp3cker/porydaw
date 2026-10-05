// Test-owned page for the production drawer hosting seam.
// Reports lifecycle and focus while sharing the tab's grid gutter.
import QtQuick
import PorydawApp as App

FocusScope {
    id: page

    objectName: "drawerTestPage"

    required property App.SongTabSession applicationSession

    // The page shares the roll's header and keyboard gutter.
    readonly property real plotOrigin: page.applicationSession.gridPresenter().trackHeaderWidth
                                       + page.applicationSession.gridPresenter().keyboardWidth

    // Observe hosted-item destruction separately from its retained Swift owner.
    signal pageDestroyed()

    // Observable focus: the container focuses this item's scope, never a
    // handler it re-declares for the page.
    readonly property bool pageFocused: page.activeFocus

    Rectangle {
        anchors.fill: parent
        color: "#20404040"
    }

    Component.onDestruction: page.pageDestroyed()
}
