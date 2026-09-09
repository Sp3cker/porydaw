// The workspace song shell: the persistent Quick page slot under the open-song
// tab strip. WorkspaceQuickHost attaches one session canvas per open song
// beneath songPageContainer and shows only the selected page; this file owns
// no session state — it is the fixed geometry the host projects pages into.
import QtQuick
import Porydaw.Ui

Item {
    id: root

    SongTabStrip {
        id: strip

        objectName: "songTabStrip"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: workspaceChrome.stripHeight
    }

    Item {
        id: pageSlot

        objectName: "songPageContainer"
        anchors.top: strip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
}
