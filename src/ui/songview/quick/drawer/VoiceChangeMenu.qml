// Captured command policy stays in Swift; original shared rows render the menu.
import QtQuick
import QtQuick.Controls
import ".." as Shared

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
    readonly property font bodyFont: ApplicationWindow.window
        ? ApplicationWindow.window.font : Application.font
    readonly property var menuColors: menuRoot.pageItem ? menuRoot.pageItem.gridPalette : null
    readonly property point anchor: pageItem && parent
        ? pageItem.mapToItem(parent, model ? model.menuX : 0, model ? model.menuY : 0)
        : Qt.point(model ? model.menuX : 0, model ? model.menuY : 0)
    onShowingChanged: {
        if (showing) {
            currentRow = 0
            forceActiveFocus(Qt.PopupFocusReason)
        } else {
            closed()
        }
    }
    function hoverRow(panel, index) { currentRow = index }
    function activateRow(panel, index) { return model.activateMenuRow(index) }
    function moveRow(delta) {
        currentRow = Math.min(Math.max(currentRow + delta, 0), Math.max(0, panel.rowCount - 1))
    }
    Keys.onUpPressed: event => { moveRow(-1); event.accepted = true }
    Keys.onDownPressed: event => { moveRow(1); event.accepted = true }
    Keys.onReturnPressed: event => { activateRow(panel, currentRow); event.accepted = true }
    Keys.onEnterPressed: event => { activateRow(panel, currentRow); event.accepted = true }
    Keys.onEscapePressed: event => { model.dismissVoiceMenu(); event.accepted = true }
    Keys.onShortcutOverride: event => event.accepted = true
    Keys.onPressed: event => event.accepted = true
    Keys.onReleased: event => event.accepted = true

    MouseArea {
        objectName: "voiceMenuUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: menuRoot.model.dismissVoiceMenu()
    }
    Shared.QuickMenuPanel {
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
        x: Math.min(Math.max(menuRoot.anchor.x, 0), Math.max(0, menuRoot.width - width))
        y: Math.min(Math.max(menuRoot.anchor.y, 0), Math.max(0, menuRoot.height - height))
        textX: Math.round(menuRoot.baseFontPx / 2)
        textRight: menuWidth - textX
        highlightedRow: menuRoot.currentRow
        appearance: menuRoot.menuColors ? ({
            background: menuRoot.menuColors.menuBackground, outline: menuRoot.menuColors.outline,
            text: menuRoot.menuColors.windowText, hoverBackground: menuRoot.menuColors.menuHoverBackground,
            hoverText: menuRoot.menuColors.windowText, disabledText: menuRoot.menuColors.disabledText,
            separator: menuRoot.menuColors.separator, font: menuRoot.bodyFont
        }) : null
    }
}
