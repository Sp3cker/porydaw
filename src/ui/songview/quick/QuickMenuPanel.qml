pragma ComponentBehavior: Bound
// Shared typed menu renderer. The Swift-owned menu supplies rows and the
// QML host delivers hover and activation; each level paints only its frame.
// The drawer-wide modal layer owns outside presses and keyboard navigation.
import QtQuick
import Porydaw.Ui

Item {
    id: panel

    required property var host
    required property var menuModel

    property var appearance: null
    property bool rootLevel: false
    property int rowHeight: 0
    property int separatorHeight: 1
    property int checkX: -1
    property int checkWidth: 0
    property int textX: 0
    property int textRight: 0
    property int shortcutRight: -1
    property int arrowRight: -1
    property int arrowWidth: 0
    property int menuWidth: 0
    property int menuHeight: 0
    property point menuOrigin: Qt.point(0, 0)
    property int highlightedRow: -1
    property int pressedRow: -1
    property string rowObjectNamePrefix: ""
    readonly property int rowCount: list.count

    objectName: rootLevel ? "quickMenuPanelRoot" : "quickMenuPanelSubmenu"

    onHighlightedRowChanged: {
        if (highlightedRow >= 0)
            list.positionViewAtIndex(highlightedRow, ListView.Contain)
    }

    readonly property color backgroundColor: appearance?.background ?? "transparent"
    readonly property color outlineColor: appearance?.outline ?? "transparent"
    readonly property color textColor: appearance?.text ?? "transparent"
    readonly property color hoverBackgroundColor: appearance?.hoverBackground ?? "transparent"
    readonly property color hoverTextColor: appearance?.hoverText ?? textColor
    readonly property color pressedBackgroundColor:
        appearance?.pressedBackground ?? hoverBackgroundColor
    readonly property color pressedTextColor: appearance?.pressedText ?? hoverTextColor
    readonly property color disabledTextColor: appearance?.disabledText ?? textColor
    readonly property color separatorColor: appearance?.separator ?? "transparent"
    readonly property font menuFont: appearance?.font ?? Application.font

    // Current model-index lookup intentionally excludes ListView's pooled
    // delegates, which can outlive a model reset for reuse.
    function rowItem(row) {
        return list.itemAtIndex(row)
    }

    // Scene-space rect of a realized row; the host anchors submenu frames on it.
    function rowSceneRect(row) {
        const rowItem = list.itemAtIndex(row)
        if (!rowItem)
            return Qt.rect(0, 0, 0, 0)
        const scene = rowItem.mapToItem(null, 0, 0)
        return Qt.rect(scene.x, scene.y, rowItem.width, rowItem.height)
    }


    Rectangle {
        objectName: "quickMenuFrame"
        id: frame

        x: panel.menuOrigin.x
        y: panel.menuOrigin.y
        width: panel.menuWidth
        height: panel.menuHeight
        color: panel.backgroundColor
        border.color: panel.outlineColor
        border.width: 1

        // Absorb presses and hover across the whole frame — the border ring,
        // any area below the list content, and inactive rows (their disabled
        // delegate lets events fall through) — so they never reach the
        // underlay beneath the frame.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: frame.border.width
            model: panel.menuModel
            interactive: contentHeight > height
            keyNavigationEnabled: false
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row
                required property int index
                required property var model
                // Array-backed Swift ruler rows arrive as modelData; the
                // existing typed QAbstractItemModel exposes its roles directly.
                readonly property var itemData: model.modelData ?? model
                objectName: panel.rowObjectNamePrefix.length > 0
                            ? panel.rowObjectNamePrefix + (itemData.actionId ?? itemData.itemId) : ""
                readonly property bool separator: itemData.separator ?? false
                readonly property bool available: itemData.enabled ?? true

                // Canonical Qt state: Item.enabled drives accessibility, so
                // a disabled row must be a disabled item, not a styling
                // convention.
                enabled: row.active
                width: ListView.view.width
                height: row.separator ? panel.separatorHeight : panel.rowHeight

                readonly property bool active: !row.separator && row.available
                readonly property color rowTextColor: {
                    if (!row.available && !row.separator)
                        return panel.disabledTextColor
                    if (panel.pressedRow === index)
                        return panel.pressedTextColor
                    if (panel.highlightedRow === index)
                        return panel.hoverTextColor
                    return panel.textColor
                }

                Rectangle {
                    anchors.fill: parent
                    visible: row.active
                    color: panel.pressedRow === row.index ? panel.pressedBackgroundColor
                          : panel.highlightedRow === row.index ? panel.hoverBackgroundColor
                          : "transparent"
                }

                Rectangle {
                    visible: row.separator
                    width: parent.width
                    height: row.separator ? panel.separatorHeight : 0
                    y: (parent.height - height) / 2
                    color: panel.separatorColor
                }

                // Check mark drawn from two rotated strokes so it never
                // depends on a glyph being present in the theme font.
                Item {
                    id: tick

                    visible: (row.itemData.checkable ?? false) && (row.itemData.checked ?? false)
                             && !row.separator
                    x: panel.checkX
                    y: (row.height - width) / 2
                    width: panel.checkWidth
                    height: width

                    readonly property real stroke: Math.max(2, width / 5)

                    Rectangle {
                        width: tick.width * 0.65
                        height: tick.stroke
                        color: row.rowTextColor
                        rotation: -45
                        x: tick.width * 0.55 - width / 2
                        y: tick.height * 0.45 - height / 2
                    }

                    Rectangle {
                        width: tick.width * 0.30
                        height: tick.stroke
                        color: row.rowTextColor
                        rotation: 45
                        x: tick.width * 0.215 - width / 2
                        y: tick.height * 0.575 - height / 2
                    }
                }

                Text {
                    x: panel.textX
                    width: Math.max(0, panel.textRight - panel.textX)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    color: row.rowTextColor
                    font: panel.menuFont
                    text: row.itemData.text
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    visible: panel.shortcutRight >= 0
                    x: panel.textRight
                    width: Math.max(0, panel.shortcutRight - panel.textRight)
                    height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    // Same state ink as the label: alpha-dimmed text cannot
                    // hold contrast on hover/pressed fills.
                    color: row.rowTextColor
                    font: panel.menuFont
                    text: row.itemData.shortcutText ?? ""
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                // Submenu arrow: the visible right half of a rotated square.
                Item {
                    id: arrow

                    visible: (row.itemData.hasSubmenu ?? false) && !row.separator
                    x: panel.arrowRight - width
                    y: (row.height - height) / 2
                    width: panel.arrowWidth
                    height: width * 2
                    clip: true

                    Rectangle {
                        width: arrow.height * 0.7
                        height: width
                        color: row.rowTextColor
                        rotation: 45
                        x: -width / 2
                        y: arrow.height / 2 - height / 2
                    }
                }

                HoverHandler {
                    enabled: row.active
                    cursorShape: Qt.ArrowCursor
                    onHoveredChanged: {
                        if (hovered)
                            panel.host.hoverRow(panel, row.index)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: (mouse) => {
                        mouse.accepted = true
                        if (!row.active)
                            return
                        panel.pressedRow = row.index
                    }
                    onReleased: (mouse) => {
                        const releasedHere = panel.pressedRow === row.index
                                             && mouse.x >= 0 && mouse.x < width
                                             && mouse.y >= 0 && mouse.y < height
                        panel.pressedRow = -1
                        if (releasedHere)
                            panel.host.activateRow(panel, row.index)
                    }
                    onCanceled: panel.pressedRow = -1
                }

                Accessible.role: row.separator ? Accessible.Separator : Accessible.MenuItem
                Accessible.name: row.itemData.text
                Accessible.onPressAction: {
                    if (row.active)
                        panel.host.activateRow(panel, row.index)
                }
            }
        }

        Accessible.role: Accessible.PopupMenu
        Accessible.name: panel.rootLevel ? qsTr("Menu") : qsTr("Submenu")
    }
}
