pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp
import Porydaw.Ui

Loader {
    id: menuLoader

    required property Item page
    required property EventListPresenter controller
    required property FontMetrics headerFontMetrics
    required property FontMetrics controlFontMetrics
        z: 10
        active: menuLoader.page.controller.menuOpen
        visible: menuLoader.page.controller.menuOpen
        sourceComponent: Component {
            Item {
                id: menuHost
                focus: true
                property string typeAhead: ""
                function matchingRow(prefix: string): int {
                    const count = menuPanel.rowCount
                    for (let offset = 1; offset <= count; ++offset) {
                        const index = (menuPanel.highlightedRow + offset + count) % count
                        const row = menuPanel.rowItem(index)
                        if (row && row.active
                            && row.itemData.text.toLowerCase().startsWith(prefix.toLowerCase()))
                            return index
                    }
                    return -1
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        menuLoader.page.controller.dismissMenu()
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                        const count = menuPanel.rowCount
                        if (count > 0) {
                            const direction = event.key === Qt.Key_Down ? 1 : -1
                            const start = menuPanel.highlightedRow >= 0
                                    ? menuPanel.highlightedRow : (direction > 0 ? -1 : 0)
                            for (let offset = 1; offset <= count; ++offset) {
                                const row = (start + direction * offset + count * 2) % count
                                const item = menuPanel.rowItem(row)
                                if (item && item.active) {
                                    menuLoader.page.hoverRow(menuPanel, row)
                                    break
                                }
                            }
                        }
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (menuPanel.highlightedRow >= 0)
                            menuLoader.page.activateRow(menuPanel, menuPanel.highlightedRow)
                    } else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier
                                                     | Qt.MetaModifier))
                               && event.text.length === 1 && event.text >= " ") {
                        menuHost.typeAhead += event.text
                        let row = menuHost.matchingRow(menuHost.typeAhead)
                        if (row < 0 && menuHost.typeAhead.length > 1) {
                            menuHost.typeAhead = event.text
                            row = menuHost.matchingRow(menuHost.typeAhead)
                        }
                        if (row >= 0)
                            menuLoader.page.hoverRow(menuPanel, row)
                        typeAheadReset.restart()
                    } else {
                        event.accepted = false
                        return
                    }
                    event.accepted = true
                }
                Timer {
                    id: typeAheadReset
                    interval: 1000
                    onTriggered: menuHost.typeAhead = ""
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    enabled: menuLoader.page.controller.menuOpen
                    onPressed: menuLoader.page.controller.dismissMenu()
                }
                QuickMenuPanel {
                    id: menuPanel
                    anchors.fill: parent
                    host: menuLoader.page
                    rootLevel: true
                    menuModel: menuLoader.page.controller.menuItems
                    rowObjectNamePrefix: "eventListMenuRow_"
                    readonly property bool showsShortcuts: menuLoader.page.controller.menuShortcutText.length > 0
                    readonly property real shortcutWidth: menuLoader.controlFontMetrics.advanceWidth(
                                                              menuLoader.page.controller.menuShortcutText)
                    readonly property int separatorCount: menuLoader.page.controller.menuSeparatorCount
                    appearance: ({
                        background: menuLoader.page.buttonBackground,
                        outline: menuLoader.page.buttonOutline,
                        text: menuLoader.page.buttonText,
                        hoverBackground: menuLoader.page.buttonHoverBackground,
                        hoverText: menuLoader.page.buttonText,
                        pressedBackground: menuLoader.page.buttonPressedBackground,
                        pressedText: menuLoader.page.buttonPressedText,
                        disabledText: menuLoader.page.disabledText,
                        separator: menuLoader.page.buttonOutline,
                        font: menuLoader.page.controlFont
                    })
                    rowHeight: menuLoader.page.rowHeight
                    checkX: menuLoader.page.cellHorizontalPadding / 2
                    checkWidth: menuLoader.page.cellHorizontalPadding
                    textX: menuLoader.page.cellHorizontalPadding * 2
                    textRight: showsShortcuts ? menuWidth - shortcutWidth
                                                 - menuLoader.page.cellHorizontalPadding * 2
                                              : menuWidth - menuLoader.page.cellHorizontalPadding
                    shortcutRight: showsShortcuts ? menuWidth - menuLoader.page.cellHorizontalPadding : -1
                    menuWidth: Math.min(parent.width, Math.max(
                                            menuLoader.headerFontMetrics.advanceWidth(qsTr("Channel aftertouch")) * 2,
                                            showsShortcuts ? menuLoader.controlFontMetrics.advanceWidth(
                                                                 qsTr("Move Event Down (Same Tick)"))
                                                            + shortcutWidth
                                                            + menuLoader.page.cellHorizontalPadding * 4 : 0))
                    menuHeight: Math.min(parent.height, (rowCount - separatorCount) * rowHeight
                                         + separatorCount * separatorHeight + 2)
                    menuOrigin: MenuPlacement.clampOrigin(
                        Qt.point(menuLoader.page.controller.menuX, menuLoader.page.controller.menuY),
                        menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
}
