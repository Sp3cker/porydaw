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
    readonly property real hairline: Math.max(1, Math.round(unit / 13))
    readonly property real edgeWidth: Math.max(2, Math.round(unit / 6))
    spacing: paneSpacing
    property int dragZone: -1
    property int dragPressKey: 0
    property int moveStart: -1
    property int glissKey: -1
    property int edgeZone: -1
    property bool edgeStart: true
    property int edgeKey: 0
    property bool dropping: false
    property bool dropUnloadable: false
    // The key range the held gesture would produce; previewFirst < 0 hides it.
    property int previewFirst: -1
    property int previewLast: -1
    property bool previewInvalid: false

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
    function keyAt(x: real, y: real): int {
        for (let n = 0; n < 128; ++n) {
            if (y < view.blackHeight && isBlack(n) && x >= xOf(n) && x < xOf(n) + view.blackWidth)
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
    function clearPreview(): void {
        view.previewFirst = -1
        view.previewLast = -1
        view.previewInvalid = false
    }
    function pressKey(key: int): void {
        view.dragZone = view.editor.zoneIndexAtKey(key)
        view.dragPressKey = key
        view.moveStart = view.dragZone >= 0 ? view.editor.zoneStartKey(view.dragZone) : -1
        view.glissKey = key
        view.editor.playKey(key)
    }
    function dragKey(x: real, y: real): void {
        if (view.dragZone < 0) {
            const key = view.keyAt(x, y)
            if (key !== view.glissKey) {
                view.glissKey = key
                view.workflow.stopAudition()
                view.editor.playKey(key)
            }
            return
        }
        if (view.dragZone >= view.editor.zoneCount())
            return
        const target = view.editor.movedZoneStart(view.dragZone,
                                                  view.editor.zoneStartKey(view.dragZone) + view.keyAt(x, y) - view.dragPressKey)
        if (target === view.moveStart)
            return
        view.moveStart = target
        const offset = view.moveStart - view.editor.zoneStartKey(view.dragZone)
        view.previewInvalid = offset !== 0 && !view.editor.zoneMoveFits(view.dragZone, view.moveStart)
        view.previewLast = offset !== 0 ? view.editor.zoneEndKey(view.dragZone) + offset : -1
        view.previewFirst = offset !== 0 ? view.moveStart : -1
    }
    function releaseKey(commit: bool): void {
        view.workflow.stopAudition()
        if (commit && view.dragZone >= 0 && view.dragZone < view.editor.zoneCount()) {
            view.editor.selectZone(view.dragZone)
            if (view.moveStart !== view.editor.zoneStartKey(view.dragZone) && !view.previewInvalid)
                view.editor.moveZone(view.dragZone, view.moveStart)
        }
        view.dragZone = -1
        view.dragPressKey = 0
        view.moveStart = -1
        view.glissKey = -1
        view.clearPreview()
    }
    function pressEdge(zone: int, start: bool): void {
        view.edgeZone = zone
        view.edgeStart = start
        view.edgeKey = start ? view.editor.zoneStartKey(zone) : view.editor.zoneEndKey(zone)
        view.previewFirst = view.editor.zoneStartKey(zone)
        view.previewLast = view.editor.zoneEndKey(zone)
        view.previewInvalid = false
    }
    // The key whose start (or end) boundary lies nearest x, so a press on an edge never shifts it.
    function edgeKeyAt(x: real, start: bool): int {
        let best = 0
        let distance = Infinity
        for (let n = 0; n < 128; ++n) {
            const delta = Math.abs((start ? view.xOf(n) : view.endXOf(n)) - x)
            if (delta < distance) {
                best = n
                distance = delta
            }
        }
        return best
    }
    function dragEdge(x: real): void {
        if (view.edgeZone < 0)
            return
        const key = view.editor.zoneEdgeKey(view.edgeZone, view.edgeStart, view.edgeKeyAt(x, view.edgeStart))
        if (key === view.edgeKey)
            return
        view.edgeKey = key
        if (view.edgeStart)
            view.previewFirst = key
        else
            view.previewLast = key
    }
    function releaseEdge(commit: bool): void {
        if (commit && view.edgeZone >= 0
                && view.edgeKey !== (view.edgeStart ? view.editor.zoneStartKey(view.edgeZone) : view.editor.zoneEndKey(view.edgeZone)))
            view.editor.dragZoneEdge(view.edgeZone, view.edgeStart, view.edgeKey)
        view.edgeZone = -1
        view.edgeStart = true
        view.edgeKey = 0
        view.clearPreview()
    }
    function updateDrop(x: real, y: real): void {
        if (!view.dropping)
            return
        const key = view.keyAt(x, y)
        const end = view.editor.dropRangeEnd(key)
        view.previewFirst = key
        view.previewLast = end < 0 ? key : end
        view.previewInvalid = view.dropUnloadable || end < 0
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

    RowLayout {
        Layout.fillWidth: true
        spacing: view.paneSpacing
        Label { text: qsTr("Keyboard"); font.bold: true; color: view.colors.windowText }
        Button { text: qsTr("■ Stop"); onClicked: view.workflow.stopAudition() }
        Item { Layout.fillWidth: true }
        IconToolButton { glyph: Icons.zoomOut; colors: view.colors; unit: view.unit; Accessible.name: qsTr("Zoom keyboard out"); onClicked: view.keyboardZoom = Math.max(0.5, view.keyboardZoom / 1.25) }
        IconToolButton { glyph: Icons.zoomIn; colors: view.colors; unit: view.unit; Accessible.name: qsTr("Zoom keyboard in"); onClicked: view.keyboardZoom = Math.min(4, view.keyboardZoom * 1.25) }
    }
    Flickable {
        id: keyboardScroll
        acceptedButtons: Qt.NoButton
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
                Rectangle {
                    id: keyCell
                    required property int index
                    readonly property bool black: view.isBlack(index)
                    readonly property int zone: view.editor.slicesRevision >= 0 ? view.editor.zoneIndexAtKey(index) : -1
                    readonly property int badge: view.editor.slicesRevision >= 0 && zone >= 0 ? view.editor.zoneBadge(zone) : 0
                    readonly property bool selected: zone >= 0 && zone === view.editor.selectedZone
                    z: black ? 1 : 0
                    x: view.xOf(index)
                    width: black ? view.blackWidth : view.whiteWidth
                    height: black ? view.blackHeight : view.keysHeight
                    color: black ? view.colors.keyboardBlack : zone >= 0 ? view.colors.keyboardActiveKey : view.colors.keyboardNatural
                    border.color: selected ? view.colors.selectionEdge : view.colors.keyboardSeparator
                    border.width: selected ? view.edgeWidth : view.hairline
                    Rectangle {
                        visible: keyCell.black && keyCell.zone >= 0
                        anchors.fill: parent
                        anchors.margins: keyCell.border.width
                        color: view.colors.keyboardActiveKey
                        opacity: 0.55
                    }
                    Rectangle {
                        visible: keyCell.badge > 0
                        width: (keyCell.black ? 1.0 : 1.35) * view.unit
                        height: width
                        radius: width / 2
                        x: (keyCell.width - width) / 2
                        y: keyCell.height - height - view.unit * 0.5
                        color: view.colors.keyboardBlack
                        Label {
                            anchors.centerIn: parent
                            text: keyCell.badge
                            font: view.captionFont
                            color: view.colors.keyboardNatural
                        }
                    }
                    Label {
                        visible: !keyCell.black && keyCell.index % 12 === 0
                        y: view.keysHeight
                        width: parent.width
                        height: view.labelHeight
                        text: view.workflow.keyName(keyCell.index)
                        font: view.captionFont
                        color: view.colors.windowText
                    }
                    MouseArea {
                        anchors.fill: parent
                        preventStealing: true
                        onPressed: view.pressKey(keyCell.index)
                        onPositionChanged: mouse => {
                            const point = mapToItem(keyboardBoard, mouse.x, mouse.y)
                            if (pressed)
                                view.dragKey(point.x, point.y)
                        }
                        onReleased: view.releaseKey(true)
                        onCanceled: view.releaseKey(false)
                    }
                }
            }
            Repeater {
                model: 2
                Rectangle {
                    id: edge
                    required property int index
                    readonly property bool start: index === 0
                    z: 5
                    visible: view.editor.selectedZone >= 0 && view.editor.mode === 1
                    // An edge drag moves its handle with the previewed range.
                    x: (start ? view.xOf(view.edgeZone >= 0 ? view.previewFirst : view.editor.selectedZoneFirstKey)
                              : view.endXOf(view.edgeZone >= 0 ? view.previewLast : view.editor.selectedZoneLastKey)) - width / 2
                    width: view.unit / 3
                    height: view.keysHeight
                    color: view.colors.selectionEdge
                    MouseArea {
                        preventStealing: true
                        x: -view.unit / 3
                        width: parent.width + 2 * view.unit / 3
                        height: parent.height
                        cursorShape: Qt.SizeHorCursor
                        Accessible.name: edge.start ? qsTr("Resize zone start") : qsTr("Resize zone end")
                        onPressed: view.pressEdge(view.editor.selectedZone, edge.start)
                        onPositionChanged: mouse => {
                            if (pressed)
                                view.dragEdge(mapToItem(keyboardBoard, mouse.x, mouse.y).x)
                        }
                        onReleased: view.releaseEdge(true)
                        onCanceled: view.releaseEdge(false)
                    }
                }
            }
            Rectangle {
                id: keyPreview
                objectName: "splitStudioKeyPreview"
                readonly property bool single: view.previewFirst === view.previewLast
                readonly property bool black: single && view.isBlack(view.previewFirst)
                z: 6
                visible: view.previewFirst >= 0
                x: view.xOf(view.previewFirst)
                width: keyPreview.black ? view.blackWidth : view.endXOf(view.previewLast) - view.xOf(view.previewFirst)
                height: keyPreview.black ? view.blackHeight : view.keysHeight
                color: "transparent"
                border.color: view.previewInvalid ? view.colors.errorText : view.colors.selectionEdge
                border.width: view.edgeWidth
                Rectangle {
                    visible: !view.previewInvalid
                    x: keyPreview.single ? (keyPreview.width - width) / 2 : view.unit * 0.4
                    y: (keyPreview.black ? 0 : view.blackHeight) + view.unit * 0.4
                    width: previewKeyName.implicitWidth + view.unit * 0.6
                    height: view.unit * 1.35
                    radius: height / 2
                    color: view.colors.keyboardBlack
                    Label {
                        id: previewKeyName
                        anchors.centerIn: parent
                        text: view.previewFirst < 0 ? ""
                            : keyPreview.single ? view.workflow.keyName(view.previewFirst)
                            : qsTr("%1–%2").arg(view.workflow.keyName(view.previewFirst)).arg(view.workflow.keyName(view.previewLast))
                        font: view.captionFont
                        color: view.colors.keyboardNatural
                    }
                }
            }
            DropArea {
                anchors.fill: parent
                onEntered: drag => {
                    const chip = drag.source as KitDragSource
                    view.dropping = drag.hasUrls || chip !== null
                    view.dropUnloadable = drag.hasUrls && !view.workflow.areLoadableSources(drag.getDataAsString("text/uri-list"))
                    view.updateDrop(drag.x, drag.y)
                }
                onPositionChanged: drag => view.updateDrop(drag.x, drag.y)
                onExited: {
                    view.dropping = false
                    view.clearPreview()
                }
                onDropped: drop => {
                    const invalid = !view.dropping || view.previewInvalid
                    view.dropping = false
                    view.clearPreview()
                    const event = drop as DragEvent
                    if (!event || invalid)
                        return
                    const key = view.keyAt(event.x, event.y)
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
