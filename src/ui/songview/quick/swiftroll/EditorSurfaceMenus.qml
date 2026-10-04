import QtQuick
import QtQml.Models
import Porydaw.Ui

Item {
    id: menuHost
    required property Item root
    required property Item rollInput
    required property Item rulerInput
    required property Item trackHeaders
    required property var bodyFontMetrics
    property alias headerMenuLoader: headerMenuLoader
    property alias gridMenuLoader: gridMenuLoader
    property alias timeSigMenuLoader: timeSigMenuLoader
    component MenuMeasure: Item {
        required property var items
        readonly property real widestText: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && !row.separator)
                    width = Math.max(width, row.advance)
            }
            return Math.ceil(width)
        }
        readonly property real widestShortcut: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && !row.separator && row.shortcutText)
                    width = Math.max(width, menuHost.bodyFontMetrics.advanceWidth(row.shortcutText))
            }
            return Math.ceil(width)
        }
        readonly property int separatorCount: {
            let count = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i)
                if (row && row.separator)
                    ++count
            }
            return count
        }
        Instantiator {
            id: entries
            model: items
            delegate: QtObject {
                required property var model
                readonly property var itemData: model.modelData ?? model
                readonly property bool separator: itemData.separator ?? false
                readonly property string shortcutText: itemData.shortcutText ?? ""
                readonly property real advance: menuHost.bodyFontMetrics.advanceWidth(itemData.text ?? "")
            }
        }
    }

    function hoverRow(panel, row) { panel.highlightedRow = row }
    // Single dismissal seam: only the closing surface still owning keyboard
    // focus may move it; a close landing while focus sits elsewhere moves nothing.
    function dismissalOwnsFocus(menuItem) {
        return !!(menuItem && menuItem.activeFocus)
    }
    // A late close finds focus on the itemless loader or up the parent chain;
    // neither owns a control, so both still route home.
    function dismissalFocusOrphaned() {
        const window = menuHost.Window.window
        if (!window)
            return false
        const focused = window.activeFocusItem
        if (!focused || !focused.visible || !focused.enabled)
            return true
        if ((focused === gridMenuLoader || focused === headerMenuLoader
             || focused === timeSigMenuLoader) && !focused.item)
            return true
        let host = menuHost
        while (host) {
            if (focused === host)
                return true
            host = host.parent
        }
        return false
    }
    function activateRow(panel, row) {
        const item = panel.rowItem(row)
        if (!item || !item.active)
            return
        const actionId = item.itemData.actionId
        if (panel.rowObjectNamePrefix === "headerMenuRow_") {
            root.headersModel.activateHeaderMenuAction(actionId)
        } else if (panel.rowObjectNamePrefix === "gridMenuRow_") {
            root.gridModel.activateGridMenuRow(actionId)
        } else if (panel.rowObjectNamePrefix === "rulerMenuRow_") {
            const targetTick = root.rulerMenu.targetTick()
            const wasTimeMenu = root.rulerMenu.menuKind === 2
            const openPrompt = root.rulerMenu.activate(actionId)
            root.timeSigHost.closeTimeSigMenu()
            if (openPrompt)
                root.timeSigHost.openTimeSigPrompt(targetTick)
            else if (wasTimeMenu && !root.rulerMenu.insertTimePromptOpen
                     && dismissalOwnsFocus(timeSigMenuLoader.item))
                rollInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: root.rulerMenu
        function onIsOpenChanged() {
            if (root.rulerMenu.isOpen)
                return
            if (root.timeSigHost && root.timeSigHost.timeSigMenuOpen)
                root.timeSigHost.closeTimeSigMenu()
            const target = root.timeMenuFocus ? rollInput : rulerInput
            root.timeMenuFocus = false
            if (!root.applicationSession.timeSigPromptOpen
                && !root.rulerMenu.insertTimePromptOpen
                && (dismissalOwnsFocus(timeSigMenuLoader.item) || dismissalFocusOrphaned()))
                target.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: root.gridModel
        function onGridMenuKindChanged() {
            if (root.gridModel.gridMenuKind === 0
                && !root.applicationSession.timeSigPromptOpen
                && (dismissalOwnsFocus(gridMenuLoader.item) || dismissalFocusOrphaned()))
                rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Loader {
        id: headerMenuLoader
        anchors.fill: parent
        z: 10
        active: root.headersModel.menuOpen
        Connections {
            target: root.headersModel
            function onMenuOpenChanged() {
                if (!root.headersModel.menuOpen && !root.applicationSession.headerVoicePickerOpen
                    && root.headersModel.renamingTrack < 0 && trackHeaders.bandVisible
                    && (dismissalOwnsFocus(headerMenuLoader.item) || dismissalFocusOrphaned()))
                    trackHeaders.restoreHeaderFocus()
            }
        }
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    root.headersModel.dismissHeaderMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.headersModel.dismissHeaderMenu()
                }
                MenuMeasure {
                    id: headerMeasure
                    items: root.headersModel.menuItems
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: menuHost
                    menuModel: root.headersModel.menuItems
                    rootLevel: true
                    rowObjectNamePrefix: "headerMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    textX: root.menuHorizontalPadding
                    textRight: menuWidth - 1 - root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + headerMeasure.widestText + root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
                    menuOrigin: MenuPlacement.clampOrigin(
                        root.headerMenuPosition, menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: gridMenuLoader
        anchors.fill: parent
        z: 10
        active: root.gridModel.gridMenuKind !== 0
        sourceComponent: Component {
            Item {
                focus: true
                function moveRow(delta) {
                    gridPanel.highlightedRow = Math.min(Math.max(gridPanel.highlightedRow + delta, 0),
                                                        Math.max(0, gridPanel.rowCount - 1))
                }
                Keys.onUpPressed: event => { moveRow(-1); event.accepted = true }
                Keys.onDownPressed: event => { moveRow(1); event.accepted = true }
                Keys.onReturnPressed: event => {
                    menuHost.activateRow(gridPanel, gridPanel.highlightedRow)
                    event.accepted = true
                }
                Keys.onEnterPressed: event => {
                    menuHost.activateRow(gridPanel, gridPanel.highlightedRow)
                    event.accepted = true
                }
                Keys.onShortcutOverride: event => event.accepted = true
                Keys.onPressed: event => event.accepted = true
                Keys.onReleased: event => event.accepted = true
                Keys.onEscapePressed: (event) => {
                    root.gridModel.dismissGridMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: root.gridModel.dismissGridMenu()
                }
                MenuMeasure {
                    id: gridMeasure
                    items: root.gridModel.gridMenuRows
                }
                QuickMenuPanel {
                    id: gridPanel
                    anchors.fill: parent
                    host: menuHost
                    menuModel: root.gridModel.gridMenuRows
                    rootLevel: true
                    rowObjectNamePrefix: "gridMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    checkX: root.menuHorizontalPadding
                    checkWidth: Math.floor(rowHeight / 2)
                    textX: root.menuHorizontalPadding + checkWidth + root.menuGap
                    textRight: menuWidth - 1 - root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + gridMeasure.widestText + root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
                    menuOrigin: MenuPlacement.clampOrigin(
                        root.gridMenuPosition, menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: timeSigMenuLoader
        anchors.fill: parent
        z: 10
        active: root.rulerMenu.isOpen
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    root.timeSigHost.closeTimeSigMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        root.timeSigHost.closeTimeSigMenu()
                    }
                }
                MenuMeasure {
                    id: rulerMeasure
                    items: root.rulerMenu.rows
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: menuHost
                    menuModel: root.rulerMenu.rows
                    rootLevel: true
                    rowObjectNamePrefix: "rulerMenuRow_"
                    appearance: ({
                        background: root.gridModel.palette.chromeBackground,
                        outline: root.gridModel.palette.separator,
                        text: root.gridModel.palette.primaryText,
                        hoverBackground: root.gridModel.palette.hoverChipFill,
                        hoverText: root.gridModel.palette.hoverChipText,
                        disabledText: root.gridModel.palette.disabledText,
                        font: root.bodyFont
                    })
                    rowHeight: Math.round(bodyFontMetrics.height) + 2 * root.menuVerticalPadding
                    separatorHeight: 1
                    textX: root.menuHorizontalPadding
                    textRight: rulerMeasure.widestShortcut > 0
                               ? menuWidth - rulerMeasure.widestShortcut
                                 - root.menuHorizontalPadding * 2
                               : menuWidth - 1 - root.menuHorizontalPadding
                    shortcutRight: rulerMeasure.widestShortcut > 0
                                   ? menuWidth - root.menuHorizontalPadding : -1
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + rulerMeasure.widestText + root.menuHorizontalPadding
                                        + (rulerMeasure.widestShortcut > 0
                                           ? rulerMeasure.widestShortcut
                                             + root.menuHorizontalPadding * 2 : 0))
                    menuHeight: Math.min(parent.height, 2
                                         + (rowCount - rulerMeasure.separatorCount) * rowHeight
                                         + rulerMeasure.separatorCount)
                    menuOrigin: MenuPlacement.clampOrigin(
                        root.rulerMenu.menuKind === 2 ? root.timeSelectionMenuPosition
                                                      : root.timeSigMenuPosition,
                        menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }
}
