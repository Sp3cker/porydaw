pragma ComponentBehavior: Bound

import QtQuick
import QtQml.Models
import Porydaw.Ui
import PorydawApp as App

Item {
    id: menuHost
    final required property EditorSurface root
    final required property MouseArea rollInput
    final required property MouseArea rulerInput
    final required property TrackHeaderBand trackHeaders
    final required property FontMetrics bodyFontMetrics
    final property alias headerMenuLoader: headerMenuLoader
    final property alias gridMenuLoader: gridMenuLoader
    final property alias timeSigMenuLoader: timeSigMenuLoader
    final readonly property MenuAppearance menuAppearance: MenuAppearance {
        font: menuHost.root.bodyFont
    }
    property int rulerMenuKind
    Binding {
        when: menuHost.root.gridModel !== null
        restoreMode: Binding.RestoreNone
        menuHost.menuAppearance.background: menuHost.root.gridModel?.palette?.chromeBackground
        menuHost.menuAppearance.outline: menuHost.root.gridModel?.palette?.separator
        menuHost.menuAppearance.text: menuHost.root.gridModel?.palette?.primaryText
        menuHost.menuAppearance.hoverBackground: menuHost.root.gridModel?.palette?.hoverChipFill
        menuHost.menuAppearance.hoverText: menuHost.root.gridModel?.palette?.hoverChipText
        menuHost.menuAppearance.disabledText: menuHost.root.gridModel?.palette?.disabledText
    }
    Binding {
        target: menuHost
        property: "rulerMenuKind"
        value: menuHost.root.rulerMenu?.menuKind
        when: menuHost.root.rulerMenu !== null
        restoreMode: Binding.RestoreNone
    }
    component MenuEntry: QtObject {
        required property int index
        required property int menuKind
        required property string text
        final readonly property App.RulerMenuRow rulerRow: menuKind === 3 && menuHost.root.rulerMenu
            ? menuHost.root.rulerMenu.menuRow(index) : null
        readonly property bool separator: rulerRow ? rulerRow.separator : false
        readonly property string shortcutText: rulerRow ? rulerRow.shortcutText : ""
        readonly property real advance: menuHost.bodyFontMetrics.advanceWidth(text)
    }

    component MenuMeasure: Item {
        id: measure
        required property var items
        required property int menuKind
        readonly property real widestText: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i) as MenuEntry
                if (row && !row.separator)
                    width = Math.max(width, row.advance)
            }
            return Math.ceil(width)
        }
        readonly property real widestShortcut: {
            let width = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i) as MenuEntry
                if (row && !row.separator && row.shortcutText)
                    width = Math.max(width, menuHost.bodyFontMetrics.advanceWidth(row.shortcutText))
            }
            return Math.ceil(width)
        }
        readonly property int separatorCount: {
            let count = 0
            for (let i = 0; i < entries.count; ++i) {
                const row = entries.objectAt(i) as MenuEntry
                if (row && row.separator)
                    ++count
            }
            return count
        }
        Instantiator {
            id: entries
            model: measure.items
            delegate: MenuEntry { menuKind: measure.menuKind }
        }
    }

    function hoverRow(panel: QuickMenuPanel, row: int): void { panel.highlightedRow = row }
    // Single dismissal seam: only the closing surface still owning keyboard
    // focus may move it; a close landing while focus sits elsewhere moves nothing.
    function dismissalOwnsFocus(menuItem: Item): bool {
        return menuItem !== null && menuItem.activeFocus
    }
    // A late close finds focus on the itemless loader or up the parent chain;
    // neither owns a control, so both still route home.
    function dismissalFocusOrphaned(): bool {
        const window = menuHost.Window.window
        if (!window)
            return false
        const focused = window.activeFocusItem
        if (!focused || !focused.visible || !focused.enabled)
            return true
        if ((focused === gridMenuLoader || focused === headerMenuLoader
             || focused === timeSigMenuLoader) && !(focused as Loader).item)
            return true
        let host = menuHost
        while (host) {
            if (focused === host)
                return true
            host = host.parent
        }
        return false
    }
    function activateRow(panel: QuickMenuPanel, row: int): void {
        if (panel.rowObjectNamePrefix === "headerMenuRow_") {
            const item = menuHost.root.headersModel.menuItem(row)
            if (item && item.enabled)
                menuHost.root.headersModel.activateHeaderMenuAction(item.actionId)
        } else if (panel.rowObjectNamePrefix === "gridMenuRow_") {
            const item = menuHost.root.gridModel.gridMenuRow(row)
            if (item && item.enabled)
                menuHost.root.gridModel.activateGridMenuRow(item.actionId)
        } else if (panel.rowObjectNamePrefix === "rulerMenuRow_") {
            const item = menuHost.root.rulerMenu.menuRow(row)
            if (!item || !item.enabled || item.separator)
                return
            const targetTick = menuHost.root.rulerMenu.targetTick()
            const wasTimeMenu = menuHost.root.rulerMenu.menuKind === 2
            const openPrompt = menuHost.root.rulerMenu.activate(item.actionId)
            menuHost.root.timeSigHost.closeTimeSigMenu()
            if (openPrompt)
                menuHost.root.timeSigHost.openTimeSigPrompt(targetTick)
            else if (wasTimeMenu && !menuHost.root.rulerMenu.insertTimePromptOpen
                     && menuHost.dismissalOwnsFocus(timeSigMenuLoader.item as Item))
                menuHost.rollInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: menuHost.root.rulerMenu
        function onIsOpenChanged(): void {
            if (menuHost.root.rulerMenu.isOpen)
                return
            if (menuHost.root.timeSigHost && menuHost.root.timeSigHost.timeSigMenuOpen)
                menuHost.root.timeSigHost.closeTimeSigMenu()
            const target = menuHost.root.timeMenuFocus ? menuHost.rollInput : menuHost.rulerInput
            menuHost.root.timeMenuFocus = false
            if (!menuHost.root.applicationSession.timeSigPromptOpen
                && !menuHost.root.rulerMenu.insertTimePromptOpen
                && (menuHost.dismissalOwnsFocus(timeSigMenuLoader.item as Item) || menuHost.dismissalFocusOrphaned()))
                target.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Connections {
        target: menuHost.root.gridModel
        function onGridMenuKindChanged(): void {
            if (menuHost.root.gridModel.gridMenuKind === 0
                && !menuHost.root.applicationSession.timeSigPromptOpen
                && (menuHost.dismissalOwnsFocus(gridMenuLoader.item as Item) || menuHost.dismissalFocusOrphaned()))
                menuHost.rulerInput.forceActiveFocus(Qt.OtherFocusReason)
        }
    }
    Loader {
        id: headerMenuLoader
        anchors.fill: parent
        z: 10
        active: menuHost.root.headersModel !== null && menuHost.root.gridModel !== null
                && menuHost.root.headersModel.menuOpen
        Connections {
            target: menuHost.root.headersModel
            function onMenuOpenChanged(): void {
                if (!menuHost.root.headersModel.menuOpen && !menuHost.root.applicationSession.headerVoicePickerOpen
                    && menuHost.root.headersModel.renamingTrack < 0 && menuHost.trackHeaders.bandVisible
                    && (menuHost.dismissalOwnsFocus(headerMenuLoader.item as Item) || menuHost.dismissalFocusOrphaned()))
                    menuHost.trackHeaders.restoreHeaderFocus()
            }
        }
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    menuHost.root.headersModel.dismissHeaderMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: menuHost.root.headersModel.dismissHeaderMenu()
                }
                MenuMeasure {
                    id: headerMeasure
                    items: menuHost.root.headersModel?.menuItems ?? null
                    menuKind: 1
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: menuHost
                    menuModel: menuHost.root.headersModel?.menuItems ?? null
                    rootLevel: true
                    rowObjectNamePrefix: "headerMenuRow_"
                    appearance: menuHost.menuAppearance
                    rowHeight: Math.round(menuHost.bodyFontMetrics.height) + 2 * menuHost.root.menuVerticalPadding
                    textX: menuHost.root.menuHorizontalPadding
                    textRight: menuWidth - 1 - menuHost.root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + headerMeasure.widestText + menuHost.root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
                    menuOrigin: MenuPlacement.clampOrigin(
                        menuHost.root.headerMenuPosition, menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: gridMenuLoader
        anchors.fill: parent
        z: 10
        active: menuHost.root.gridModel !== null && menuHost.root.gridModel.gridMenuKind !== 0
        sourceComponent: Component {
            Item {
                focus: true
                function moveRow(delta: int): void {
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
                    menuHost.root.gridModel.dismissGridMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onPressed: menuHost.root.gridModel.dismissGridMenu()
                }
                MenuMeasure {
                    id: gridMeasure
                    items: menuHost.root.gridModel?.gridMenuRows ?? null
                    menuKind: 2
                }
                QuickMenuPanel {
                    id: gridPanel
                    anchors.fill: parent
                    host: menuHost
                    menuModel: menuHost.root.gridModel?.gridMenuRows ?? null
                    rootLevel: true
                    rowObjectNamePrefix: "gridMenuRow_"
                    appearance: menuHost.menuAppearance
                    rowHeight: Math.round(menuHost.bodyFontMetrics.height) + 2 * menuHost.root.menuVerticalPadding
                    checkX: menuHost.root.menuHorizontalPadding
                    checkWidth: Math.floor(rowHeight / 2)
                    textX: menuHost.root.menuHorizontalPadding + checkWidth + menuHost.root.menuGap
                    textRight: menuWidth - 1 - menuHost.root.menuHorizontalPadding
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + gridMeasure.widestText + menuHost.root.menuHorizontalPadding)
                    menuHeight: Math.min(parent.height, 2 + rowCount * rowHeight)
                    menuOrigin: MenuPlacement.clampOrigin(
                        menuHost.root.gridMenuPosition, menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }

    Loader {
        id: timeSigMenuLoader
        anchors.fill: parent
        z: 10
        active: menuHost.root.rulerMenu !== null && menuHost.root.gridModel !== null
                && menuHost.root.rulerMenu.isOpen
        sourceComponent: Component {
            Item {
                focus: true
                Keys.onEscapePressed: (event) => {
                    menuHost.root.timeSigHost.closeTimeSigMenu()
                    event.accepted = true
                }
                MouseArea {
                    anchors.fill: parent
                    onPressed: {
                        menuHost.root.timeSigHost.closeTimeSigMenu()
                    }
                }
                MenuMeasure {
                    id: rulerMeasure
                    items: menuHost.root.rulerMenu?.rows ?? null
                    menuKind: 3
                }
                QuickMenuPanel {
                    anchors.fill: parent
                    host: menuHost
                    menuModel: menuHost.root.rulerMenu?.rows ?? null
                    rootLevel: true
                    rowObjectNamePrefix: "rulerMenuRow_"
                    appearance: menuHost.menuAppearance
                    rowHeight: Math.round(menuHost.bodyFontMetrics.height) + 2 * menuHost.root.menuVerticalPadding
                    separatorHeight: 1
                    textX: menuHost.root.menuHorizontalPadding
                    textRight: rulerMeasure.widestShortcut > 0
                               ? menuWidth - rulerMeasure.widestShortcut
                                 - menuHost.root.menuHorizontalPadding * 2
                               : menuWidth - 1 - menuHost.root.menuHorizontalPadding
                    shortcutRight: rulerMeasure.widestShortcut > 0
                                   ? menuWidth - menuHost.root.menuHorizontalPadding : -1
                    menuWidth: Math.min(parent.width, 2 + textX
                                        + rulerMeasure.widestText + menuHost.root.menuHorizontalPadding
                                        + (rulerMeasure.widestShortcut > 0
                                           ? rulerMeasure.widestShortcut
                                             + menuHost.root.menuHorizontalPadding * 2 : 0))
                    menuHeight: Math.min(parent.height, 2
                                         + (rowCount - rulerMeasure.separatorCount) * rowHeight
                                         + rulerMeasure.separatorCount)
                    menuOrigin: MenuPlacement.clampOrigin(
                        menuHost.rulerMenuKind === 2 ? menuHost.root.timeSelectionMenuPosition
                                                   : menuHost.root.timeSigMenuPosition,
                        menuWidth, menuHeight, width, height)
                }
                Component.onCompleted: forceActiveFocus(Qt.PopupFocusReason)
            }
        }
    }
}
