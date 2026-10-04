// Captured command policy stays in Swift; original shared rows render the menu.
import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp as App

pragma ComponentBehavior: Bound

FocusScope {
    id: menuRoot
    objectName: "voiceChangeMenu"
    required property App.VoiceChangesPage model
    property VoiceChangesPage pageItem: null
    property bool showing: false
    property int currentRow: 0
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing
    readonly property real baseFontPx: menuRoot.model ? menuRoot.model.baseFontPx : 13
    property font bodyFont
    Binding on bodyFont {
        when: menuRoot.pageItem !== null && menuRoot.pageItem.applicationSession !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.pageItem?.applicationSession?.timeSigHost.typographyFonts.body
    }
    readonly property App.GridPalette menuColors: menuRoot.pageItem ? menuRoot.pageItem.gridPalette : null
    readonly property point anchor: {
        const localX = menuRoot.model ? menuRoot.model.menuX : 0
        const localY = menuRoot.model ? menuRoot.model.menuY : 0
        if (menuRoot.pageItem !== null && menuRoot.parent !== null) {
            const mapped = menuRoot.pageItem.mapToItem(menuRoot.parent, localX, localY)
            return Qt.point(mapped.x, mapped.y)
        }
        return Qt.point(localX, localY)
    }
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

    MenuAppearance {
        id: menuAppearance
        font: menuRoot.bodyFont
    }
    Binding {
        target: menuAppearance
        property: "background"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.menuBackground
    }
    Binding {
        target: menuAppearance
        property: "outline"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.outline
    }
    Binding {
        target: menuAppearance
        property: "text"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.windowText
    }
    Binding {
        target: menuAppearance
        property: "hoverBackground"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.menuHoverBackground
    }
    Binding {
        target: menuAppearance
        property: "hoverText"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.windowText
    }
    Binding {
        target: menuAppearance
        property: "pressedBackground"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.menuHoverBackground
    }
    Binding {
        target: menuAppearance
        property: "pressedText"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.windowText
    }
    Binding {
        target: menuAppearance
        property: "disabledText"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.disabledText
    }
    Binding {
        target: menuAppearance
        property: "separator"
        when: menuRoot.menuColors !== null
        restoreMode: Binding.RestoreNone
        value: menuRoot.menuColors?.separator
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
        menuModel: menuRoot.model ? menuRoot.model.menuRows : null
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
        appearance: menuAppearance
    }
}
