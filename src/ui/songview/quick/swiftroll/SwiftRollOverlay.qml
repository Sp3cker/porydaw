import QtQuick

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
