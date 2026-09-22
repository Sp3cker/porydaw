import QtQuick

// The mounted roll surface: the song tab strip over one page per open song.
// The window installs the production session as the `appSession` context
// property before it loads this document (RewriteWindow::attachGridScene), and
// every mounted-surface consumer reads the selected page's grid from the view
// root.
Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true

    readonly property QtObject applicationSession: appSession
    // The selected tab's grid, published for the mounted-surface consumers:
    // null with zero tabs; harness retries.
    readonly property var gridModel: root.applicationSession.songTabs.selectedPage ? root.applicationSession.songTabs.selectedPage.grid : null

    SongTabs {
        id: songTabs
        anchors.fill: parent
        controller: root.applicationSession.songTabs
    }
}
