pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

ColumnLayout {
    id: view
    objectName: "splitStudioZoneEditor"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property font captionFont
    property real keyboardZoom: 1
    readonly property real whiteWidth: 2.25 * unit * keyboardZoom
    readonly property real blackWidth: 1.35 * unit * keyboardZoom
    readonly property real keysHeight: 8 * unit
    readonly property real blackHeight: 5 * unit
    readonly property real labelHeight: 1.75 * unit
    spacing: paneSpacing
    property int dragZone: -1
    property int dragPressKey: 0
    property int dragDelta: 0
    property int edgeZone: -1
    property bool edgeStart: true
    property int edgeKey: 0

    function isBlack(key: int): bool {
        return [1, 3, 6, 8, 10].indexOf(key % 12) !== -1
    }
    function whitesBefore(key: int): int {
        let count = 0
        for (let n = 0; n < key; ++n)
            if (!isBlack(n))
                ++count
        return count
    }
    function xOf(key: int): real {
        const before = whitesBefore(key)
        return isBlack(key) ? before * view.whiteWidth - view.blackWidth / 2 : before * view.whiteWidth
    }
    function endXOf(key: int): real {
        return xOf(key) + (isBlack(key) ? view.blackWidth : view.whiteWidth)
    }
    function keyAt(x: real): int {
        for (let n = 0; n < 128; ++n) {
            if (isBlack(n) && x >= xOf(n) && x < xOf(n) + view.blackWidth)
                return n
        }
        for (let n = 0; n < 128; ++n) {
            if (!isBlack(n) && x >= xOf(n) && x < xOf(n) + view.whiteWidth)
                return n
        }
        return x < 0 ? 0 : 127
    }
    Connections {
        target: view.editor
        function onSelectedZoneChanged(): void {
            if (view.editor.selectedZone >= 0)
                view.revealKeys(view.editor.selectedZoneFirstKey, view.editor.selectedZoneLastKey)
        }
    }
    function pressKey(key: int): void {
        view.dragZone = view.editor.zoneIndexAtKey(key)
        view.dragPressKey = key
        view.dragDelta = 0
        view.editor.playKey(key)
    }
    function dragKey(x: real): void {
        if (view.dragZone < 0 || view.dragZone >= view.editor.zoneCount())
            return
        const width = view.editor.zoneEndKey(view.dragZone) - view.editor.zoneStartKey(view.dragZone)
        const start = Math.max(0, Math.min(127 - width, view.editor.zoneStartKey(view.dragZone) + (view.keyAt(x) - view.dragPressKey)))
        view.dragDelta = start - view.editor.zoneStartKey(view.dragZone)
    }
    function releaseKey(): void {
        view.workflow.stopAudition()
        if (view.dragZone >= 0 && view.dragZone < view.editor.zoneCount()) {
            view.editor.selectZone(view.dragZone)
            if (view.dragDelta !== 0)
                view.editor.moveZone(view.dragZone, view.editor.zoneStartKey(view.dragZone) + view.dragDelta)
        }
        view.dragZone = -1
        view.dragPressKey = 0
        view.dragDelta = 0
    }
    function pressEdge(zone: int, start: bool): void {
        view.edgeZone = zone
        view.edgeStart = start
        view.edgeKey = start ? view.editor.zoneStartKey(zone) : view.editor.zoneEndKey(zone)
    }
    function dragEdge(x: real): void {
        if (view.edgeZone < 0)
            return
        view.edgeKey = view.keyAt(x)
    }
    function releaseEdge(): void {
        if (view.edgeZone >= 0)
            view.editor.dragZoneEdge(view.edgeZone, view.edgeStart, view.edgeKey)
        view.edgeZone = -1
        view.edgeStart = true
        view.edgeKey = 0
    }
    function revealKeys(first: int, last: int): void {
        const flick = keyboardScroll.contentItem as Flickable
        const visibleWidth = keyboardScroll.width
        if (!flick || visibleWidth <= 0)
            return
        const left = view.xOf(Math.max(0, first))
        const right = view.endXOf(Math.min(127, last))
        if (left >= flick.contentX && right <= flick.contentX + visibleWidth)
            return
        flick.contentX = Math.max(0, Math.min(keyboardScroll.contentWidth - visibleWidth, (left + right - visibleWidth) / 2))
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        Label { text: qsTr("Keyboard"); color: view.colors.windowText }
        Button { text: qsTr("■ Stop"); onClicked: view.workflow.stopAudition() }
        Item { Layout.fillWidth: true }
        Button { Layout.preferredWidth: 2.5 * view.unit; text: "−"; Accessible.name: qsTr("Zoom keyboard out"); onClicked: view.keyboardZoom = Math.max(0.5, view.keyboardZoom / 1.25) }
        Button { Layout.preferredWidth: 2.5 * view.unit; text: "+"; Accessible.name: qsTr("Zoom keyboard in"); onClicked: view.keyboardZoom = Math.min(4, view.keyboardZoom * 1.25) }
    }
    ScrollView {
        id: keyboardScroll
        objectName: "splitStudioKeyboardScroll"
        Layout.fillWidth: true
        Layout.preferredHeight: keyboardBoard.height + keyboardScroll.ScrollBar.horizontal.height
        contentWidth: view.whitesBefore(128) * view.whiteWidth
        contentHeight: keyboardBoard.height
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOn
        ScrollBar.vertical.policy: ScrollBar.AlwaysOff
        onWidthChanged: if (width > 0 && !revealed) { revealed = true; view.revealKeys(36, 72) }
        property bool revealed: false
        Item {
            id: keyboardBoard
            width: view.whitesBefore(128) * view.whiteWidth
            height: view.keysHeight + view.labelHeight
            Repeater {
                model: 128
                Item {
                    id: whiteCell
                    required property int index
                    visible: !view.isBlack(index)
                    x: view.xOf(index)
                    y: 0
                    width: view.whiteWidth
                    height: view.keysHeight
                    Rectangle {
                        anchors.fill: parent
                        color: view.colors.windowBackground
                        border.color: view.colors.windowText
                        border.width: view.unit / 13
                    }
                    Label {
                        visible: whiteCell.index % 12 === 0
                        y: view.keysHeight
                        width: parent.width
                        height: view.labelHeight
                        text: view.workflow.keyName(whiteCell.index)
                        font: view.captionFont
                        color: view.colors.windowText
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: view.pressKey(whiteCell.index)
                        onPositionChanged: mouse => {
                            if (pressed)
                                view.dragKey(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                        }
                        onReleased: view.releaseKey()
                        onCanceled: view.releaseKey()
                    }
                }
            }
            Repeater {
                model: 128
                Item {
                    id: blackCell
                    required property int index
                    visible: view.isBlack(index)
                    x: view.xOf(index)
                    y: 0
                    width: view.blackWidth
                    height: view.blackHeight
                    z: 1
                    Rectangle {
                        anchors.fill: parent
                        color: view.colors.chromeBackground
                        border.color: view.colors.windowText
                        border.width: view.unit / 13
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: view.pressKey(blackCell.index)
                        onPositionChanged: mouse => {
                            if (pressed)
                                view.dragKey(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                        }
                        onReleased: view.releaseKey()
                        onCanceled: view.releaseKey()
                    }
                }
            }
            Repeater {
                model: view.editor.zoneRows
                Item {
                    id: zoneFill
                    required property int startKey
                    required property int endKey
                    required property int sliceBadge
                    required property bool selected
                    z: 2
                    Repeater {
                        model: zoneFill.endKey - zoneFill.startKey + 1
                        Rectangle {
                            required property int index
                            readonly property int key: zoneFill.startKey + index
                            readonly property bool black: view.isBlack(key)
                            x: view.xOf(key)
                            y: 0
                            width: black ? view.blackWidth : view.whiteWidth
                            height: black ? view.blackHeight : view.keysHeight
                            color: view.colors.tabSelectedBackground
                            border.color: view.colors.windowText
                            border.width: zoneFill.selected ? view.unit / 6 : view.unit / 13
                            Rectangle {
                                visible: zoneFill.sliceBadge > 0
                                width: 1.5 * view.unit
                                height: 1.5 * view.unit
                                radius: 0.75 * view.unit
                                color: view.colors.windowText
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: view.paneSpacing
                                Label {
                                    anchors.centerIn: parent
                                    text: zoneFill.sliceBadge
                                    font: view.captionFont
                                    color: view.colors.windowBackground
                                }
                            }
                        }
                    }
                }
            }
            Repeater {
                model: view.editor.zoneRows
                Item {
                    id: edge
                    required property int index
                    required property int startKey
                    required property int endKey
                    required property bool selected
                    visible: edge.selected
                    Rectangle {
                        z: 3
                        x: view.xOf(edge.startKey) - view.unit / 3
                        y: 0
                        width: 2 * view.unit / 3
                        height: 2 * view.unit
                        color: view.colors.windowText
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            Accessible.name: qsTr("Resize zone start")
                            onPressed: view.pressEdge(edge.index, true)
                            onPositionChanged: mouse => {
                                if (pressed)
                                    view.dragEdge(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                            }
                            onReleased: view.releaseEdge()
                            onCanceled: view.releaseEdge()
                        }
                    }
                    Rectangle {
                        z: 3
                        x: view.endXOf(edge.endKey) - view.unit / 3
                        y: 0
                        width: 2 * view.unit / 3
                        height: 2 * view.unit
                        color: view.colors.windowText
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeHorCursor
                            Accessible.name: qsTr("Resize zone end")
                            onPressed: view.pressEdge(edge.index, false)
                            onPositionChanged: mouse => {
                                if (pressed)
                                    view.dragEdge(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                            }
                            onReleased: view.releaseEdge()
                            onCanceled: view.releaseEdge()
                        }
                    }
                }
            }
            DropArea {
                anchors.fill: parent
                keys: ["porydaw-sample", "porydaw-library"]
                onDropped: drop => {
                    const event = drop as DragEvent
                    if (!event)
                        return
                    const key = view.keyAt(event.x)
                    const source = event.source as KitDragSource
                    if (!source)
                        return
                    if (source.sliceName.length > 0)
                        view.editor.dropSample(source.sliceName, key)
                    else if (source.libraryPath.length > 0)
                        view.workflow.dropLibrarySample(source.libraryPath, key)
                    else
                        return
                    event.acceptProposedAction()
                }
            }
        }
    }
    Item { Layout.fillHeight: true }
}
