pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true

    required property App.ApplicationSession applicationSession
    // The selected tab's grid, published for the mounted-surface consumers:
    // null with zero tabs; harness retries.
    readonly property App.PianoGrid gridModel: root.applicationSession.songTabs.selectedPage ? root.applicationSession.songTabs.selectedPage.grid : null

    SongTabs {
        id: songTabs
        anchors.fill: parent
        controller: root.applicationSession.songTabs
    }
}
