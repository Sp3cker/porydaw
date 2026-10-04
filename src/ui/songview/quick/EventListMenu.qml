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
        active: page.controller.menuOpen
        visible: page.controller.menuOpen
        sourceComponent: Component {
            Item {
                id: menuHost
                focus: true
                property string typeAhead: ""
                function matchingRow(prefix) {
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
                        page.controller.dismissMenu()
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
                                    page.hoverRow(menuPanel, row)
                                    break
                                }
                            }
                        }
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (menuPanel.highlightedRow >= 0)
                            page.activateRow(menuPanel, menuPanel.highlightedRow)
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
                            page.hoverRow(menuPanel, row)
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
                    enabled: page.controller.menuOpen
                    onPressed: page.controller.dismissMenu()
                }
                QuickMenuPanel {
                    id: menuPanel
                    anchors.fill: parent
                    host: page
                    rootLevel: true
                    menuModel: page.controller.menuItems
                    rowObjectNamePrefix: "eventListMenuRow_"
                    readonly property bool showsShortcuts: page.controller.menuShortcutText.length > 0
                    readonly property real shortcutWidth: controlFontMetrics.advanceWidth(
                                                              page.controller.menuShortcutText)
                    readonly property int separatorCount: page.controller.menuSeparatorCount
                    appearance: ({
                        background: page.buttonBackground,
                        outline: page.buttonOutline,
                        text: page.buttonText,
                        hoverBackground: page.buttonHoverBackground,
                        hoverText: page.buttonText,
                        pressedBackground: page.buttonPressedBackground,
                        pressedText: page.buttonPressedText,
                        disabledText: page.disabledText,
                        separator: page.buttonOutline,
                        font: page.controlFont
                    })
                    rowHeight: page.rowHeight
                    checkX: page.cellHorizontalPadding / 2
                    checkWidth: page.cellHorizontalPadding
                    textX: page.cellHorizontalPadding * 2
                    textRight: showsShortcuts ? menuWidth - shortcutWidth
                                                 - page.cellHorizontalPadding * 2
                                              : menuWidth - page.cellHorizontalPadding
                    shortcutRight: showsShortcuts ? menuWidth - page.cellHorizontalPadding : -1
                    menuWidth: Math.min(parent.width, Math.max(
                                            headerFontMetrics.advanceWidth(qsTr("Channel aftertouch")) * 2,
                                            showsShortcuts ? controlFontMetrics.advanceWidth(
                                                                 qsTr("Move Event Down (Same Tick)"))
                                                            + shortcutWidth
                                                            + page.cellHorizontalPadding * 4 : 0))
                    menuHeight: Math.min(parent.height, (rowCount - separatorCount) * rowHeight
                                         + separatorCount * separatorHeight + 2)
                    menuOrigin: MenuPlacement.clampOrigin(
                        Qt.point(page.controller.menuX, page.controller.menuY),
                        menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
}
