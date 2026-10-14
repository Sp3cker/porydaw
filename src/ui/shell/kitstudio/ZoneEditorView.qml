pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import Porydaw.Icons
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
        function onSelectedSliceChanged(): void {
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
        if (view.edgeZone >= 0)
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
        const visibleWidth = keyboardScroll.width
        if (!keyboardScroll || visibleWidth <= 0)
            return
        const left = view.xOf(Math.max(0, first))
        const right = view.endXOf(Math.min(127, last))
        if (left >= keyboardScroll.contentX && right <= keyboardScroll.contentX + visibleWidth)
            return
        keyboardScroll.contentX = Math.max(0, Math.min(keyboardScroll.contentWidth - visibleWidth, (left + right - visibleWidth) / 2))
    }

    component ZoomButton: ToolButton {
        id: zoomButton
        required property IconSpec glyph
        contentItem: Item {
            implicitWidth: zoomIcon.width
            implicitHeight: zoomIcon.height
            AppIcon {
                id: zoomIcon
                anchors.centerIn: parent
                width: Math.round(view.unit)
                height: width
                icon: zoomButton.glyph
                color: zoomButton.enabled ? view.colors.windowText : view.colors.disabledText
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        Label { text: qsTr("Keyboard"); font.bold: true; color: view.colors.windowText }
        Button { text: qsTr("■ Stop"); onClicked: view.workflow.stopAudition() }
        Item { Layout.fillWidth: true }
        ZoomButton { glyph: Icons.zoomOut; Accessible.name: qsTr("Zoom keyboard out"); onClicked: view.keyboardZoom = Math.max(0.5, view.keyboardZoom / 1.25) }
        ZoomButton { glyph: Icons.zoomIn; Accessible.name: qsTr("Zoom keyboard in"); onClicked: view.keyboardZoom = Math.min(4, view.keyboardZoom * 1.25) }
    }
    Flickable {
        id: keyboardScroll
        objectName: "splitStudioKeyboardScroll"
        Layout.fillWidth: true
        Layout.preferredHeight: keyboardBoard.height
        contentWidth: view.whitesBefore(128) * view.whiteWidth
        contentHeight: keyboardBoard.height
        flickableDirection: Flickable.HorizontalFlick
        clip: true
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
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
                        color: view.colors.keyboardNatural
                        border.color: view.colors.keyboardSeparator
                        border.width: Math.max(1, Math.round(view.unit / 13))
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
                        color: view.colors.keyboardBlack
                        border.color: view.colors.keyboardSeparator
                        border.width: Math.max(1, Math.round(view.unit / 13))
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
                    id: zoneWhites
                    required property int startKey
                    required property int endKey
                    required property bool selected
                    z: 2
                    Repeater {
                        model: zoneWhites.endKey - zoneWhites.startKey + 1
                        Rectangle {
                            required property int index
                            readonly property int key: zoneWhites.startKey + index
                            visible: !view.isBlack(key)
                            x: view.xOf(key)
                            y: 0
                            width: view.whiteWidth
                            height: view.keysHeight
                            color: view.colors.keyboardActiveKey
                            border.color: zoneWhites.selected ? view.colors.selectionEdge : view.colors.keyboardSeparator
                            border.width: zoneWhites.selected ? Math.max(2, Math.round(view.unit / 6)) : Math.max(1, Math.round(view.unit / 13))
                        }
                    }
                }
            }
            Repeater {
                model: view.editor.zoneRows
                Item {
                    id: zoneBlacks
                    required property int startKey
                    required property int endKey
                    required property bool selected
                    z: 3
                    Repeater {
                        model: zoneBlacks.endKey - zoneBlacks.startKey + 1
                        Rectangle {
                            id: blackFill
                            required property int index
                            readonly property int key: zoneBlacks.startKey + index
                            visible: view.isBlack(key)
                            x: view.xOf(key)
                            y: 0
                            width: view.blackWidth
                            height: view.blackHeight
                            color: view.colors.keyboardBlack
                            border.color: zoneBlacks.selected ? view.colors.selectionEdge : view.colors.keyboardSeparator
                            border.width: zoneBlacks.selected ? Math.max(2, Math.round(view.unit / 6)) : Math.max(1, Math.round(view.unit / 13))
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: blackFill.border.width
                                color: view.colors.keyboardActiveKey
                                opacity: 0.55
                            }
                        }
                    }
                }
            }
            Repeater {
                model: view.editor.zoneRows
                Item {
                    id: zoneBadges
                    required property int startKey
                    required property int endKey
                    required property int sliceBadge
                    z: 4
                    Repeater {
                        model: zoneBadges.endKey - zoneBadges.startKey + 1
                        Rectangle {
                            required property int index
                            readonly property int key: zoneBadges.startKey + index
                            readonly property bool black: view.isBlack(key)
                            visible: zoneBadges.sliceBadge > 0
                            width: (black ? 1.0 : 1.35) * view.unit
                            height: (black ? 1.0 : 1.35) * view.unit
                            radius: width / 2
                            color: view.colors.keyboardBlack
                            x: view.xOf(key) + ((black ? view.blackWidth : view.whiteWidth) - width) / 2
                            y: (black ? view.blackHeight : view.keysHeight) - height - view.unit * 0.5
                            Label {
                                anchors.centerIn: parent
                                text: zoneBadges.sliceBadge
                                font: view.captionFont
                                color: view.colors.keyboardNatural
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
                    z: 5
                    visible: edge.selected && view.editor.mode === 1
                    Rectangle {
                        x: view.xOf(edge.startKey) - width / 2
                        y: 0
                        width: view.unit / 3
                        height: view.keysHeight
                        color: view.colors.selectionEdge
                        MouseArea {
                            x: -view.unit / 3
                            width: parent.width + 2 * view.unit / 3
                            height: parent.height
                            cursorShape: Qt.SizeHorCursor
                            Accessible.name: qsTr("Resize zone start")
                            onPressed: view.pressEdge(edge.index, true)
                            onPositionChanged: function(mouse) {
                                if (pressed)
                                    view.dragEdge(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                            }
                            onReleased: view.releaseEdge()
                            onCanceled: view.releaseEdge()
                        }
                    }
                    Rectangle {
                        x: view.endXOf(edge.endKey) - width / 2
                        y: 0
                        width: view.unit / 3
                        height: view.keysHeight
                        color: view.colors.selectionEdge
                        MouseArea {
                            x: -view.unit / 3
                            width: parent.width + 2 * view.unit / 3
                            height: parent.height
                            cursorShape: Qt.SizeHorCursor
                            Accessible.name: qsTr("Resize zone end")
                            onPressed: view.pressEdge(edge.index, false)
                            onPositionChanged: function(mouse) {
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
                onDropped: drop => {
                    const event = drop as DragEvent
                    if (!event)
                        return
                    const key = view.keyAt(event.x)
                    if (event.hasUrls && event.urls.length > 0) {
                        view.workflow.dropLibrarySample("%1".arg(event.urls[0]), key)
                        for (let i = 1; i < event.urls.length; ++i)
                            view.workflow.loadSource("%1".arg(event.urls[i]))
                        event.acceptProposedAction()
                        return
                    }
                    const chip = event.source as KitDragSource
                    if (!chip || chip.sliceName.length === 0)
                        return
                    view.editor.dropSample(chip.sliceName, key)
                    event.acceptProposedAction()
                }
            }
        }
    }
    Item { Layout.fillHeight: true }
}
