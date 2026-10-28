pragma ComponentBehavior: Bound

import QtQuick

// Producers own the chip's unit-derived geometry and palette surface.
Rectangle {
    id: chip
    required property Item dragLayer
    property Item home
    final property string sliceName: ""
    Drag.active: chipDrag.drag.active
    Drag.hotSpot.x: chipDrag.mouseX
    Drag.hotSpot.y: chipDrag.mouseY
    Drag.source: chip
    Drag.supportedActions: Qt.CopyAction

    function restore(): void {
        parent = home
        x = 0
        y = 0
    }

    MouseArea {
        id: chipDrag
        anchors.fill: parent
        drag.target: chip
        onPressed: {
            chip.home = chip.parent
            const point = chip.mapToItem(chip.dragLayer, 0, 0)
            const x = point.x
            const y = point.y
            chip.parent = chip.dragLayer
            chip.x = x
            chip.y = y
        }
        onReleased: { chip.Drag.drop(); chip.restore() }
        onCanceled: chip.restore()
    }
}
