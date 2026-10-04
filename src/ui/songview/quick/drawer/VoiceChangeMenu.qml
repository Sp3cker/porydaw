// Captured command policy stays in Swift; original shared rows render the menu.
import QtQuick
import PorydawStyle
import Porydaw.Ui

pragma ComponentBehavior: Bound

FocusScope {
    id: menuRoot
    objectName: "voiceChangeMenu"
    required property var model
    property var pageItem: null
    property bool showing: false
    property int currentRow: 0
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing
    readonly property real baseFontPx: model ? model.baseFontPx : 13
    readonly property font bodyFont: menuRoot.pageItem
        ? Qt.font((menuRoot.pageItem.applicationSession.timeSigHost
                   || menuRoot.pageItem.applicationSession).typographyFonts.body) : menuRoot.neutralFont
    readonly property var menuColors: menuRoot.pageItem ? menuRoot.pageItem.gridPalette : null
    property font neutralFont
    readonly property point anchor: pageItem && parent
        ? pageItem.mapToItem(parent, model ? model.menuX : 0, model ? model.menuY : 0)
        : Qt.point(model ? model.menuX : 0, model ? model.menuY : 0)
    // Focus only once enabled: a disabled item's focus request parks active
    // focus on the window root until the enabled binding catches up.
    onEnabledChanged: {
        if (enabled) {
            currentRow = 0
            forceActiveFocus(Qt.PopupFocusReason)
        }
    }
    onShowingChanged: if (!showing) closed()
    function hoverRow(panel: Item, index: int): void { menuRoot.currentRow = index }
    function activateRow(panel: Item, index: int): bool { return menuRoot.model.activateMenuRow(index) }
    function moveRow(delta: int): void {
        menuRoot.currentRow = Math.min(Math.max(menuRoot.currentRow + delta, 0), Math.max(0, panel.rowCount - 1))
    }
    Keys.onUpPressed: event => { moveRow(-1); event.accepted = true }
    Keys.onDownPressed: event => { moveRow(1); event.accepted = true }
    Keys.onReturnPressed: event => { activateRow(panel, currentRow); event.accepted = true }
    Keys.onEnterPressed: event => { activateRow(panel, currentRow); event.accepted = true }
    Keys.onEscapePressed: event => { model.dismissVoiceMenu(); event.accepted = true }
    Keys.onShortcutOverride: event => event.accepted = true
    Keys.onPressed: event => event.accepted = true
    Keys.onReleased: event => event.accepted = true

    QtObject {
        id: menuAppearance
        readonly property color background: menuRoot.menuColors ? menuRoot.menuColors.menuBackground : "transparent"
        readonly property color outline: menuRoot.menuColors ? menuRoot.menuColors.outline : "transparent"
        readonly property color text: menuRoot.menuColors ? menuRoot.menuColors.windowText : "transparent"
        readonly property color hoverBackground: menuRoot.menuColors ? menuRoot.menuColors.menuHoverBackground : "transparent"
        readonly property color hoverText: menuRoot.menuColors ? menuRoot.menuColors.windowText : "transparent"
        readonly property color disabledText: menuRoot.menuColors ? menuRoot.menuColors.disabledText : "transparent"
        readonly property color separator: menuRoot.menuColors ? menuRoot.menuColors.separator : "transparent"
        readonly property font font: menuRoot.bodyFont
    }

    MouseArea {
        objectName: "voiceMenuUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: menuRoot.model.dismissVoiceMenu()
    }
    QuickMenuPanel {
        id: panel
        objectName: "voiceMenuPanel"
        rowObjectNamePrefix: "voiceMenuRow_"
        host: menuRoot
        menuModel: menuRoot.model ? menuRoot.model.menuRows : []
        rootLevel: true
        rowHeight: Math.round(menuRoot.baseFontPx * 1.6)
        menuWidth: Math.min(Math.round(menuRoot.baseFontPx * 14), menuRoot.width)
        menuHeight: Math.min(rowCount * rowHeight + 2, menuRoot.height)
        width: menuWidth
        height: menuHeight
        readonly property point origin: MenuPlacement.clampOrigin(
            menuRoot.anchor, width, height, menuRoot.width, menuRoot.height)
        x: origin.x
        y: origin.y
        textX: Math.round(menuRoot.baseFontPx / 2)
        textRight: menuWidth - textX
        highlightedRow: menuRoot.currentRow
        appearance: menuRoot.menuColors ? menuAppearance : null
    }
}
