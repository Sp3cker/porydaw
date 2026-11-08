pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp as App

PromptOverlay {
    id: root
    objectName: "midiEffectsPanel"
    required property App.MidiEffectsPresenter model
    required focusOrigin
    readonly property real unit: model.baseFontPx
    overlayOpen: model.isOpen
    cardItem: card
    underlayObjectName: "midiEffectsUnderlay"
    dismissOnlyOutsideCard: true
    consumeDismissPress: true
    preventUnderlayStealing: true
    z: 100
    onInitialFocusRequested: closeButton.forceActiveFocus(Qt.PopupFocusReason)
    onOverlayClosed: restoreFocusIfOwned()
    onDismissRequested: model.close()

    component Caption: Text {
        font: root.model.bodyFont
        color: root.model.colors.windowText
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    component Action: PromptAction {
        id: action
        appearance: root.model.promptStyle
        onActiveFocusChanged: if (activeFocus)
            contentView.reveal(action, action.mapToItem(contentView.contentItem, 0, 0).y, action.height)
    }

    component Setting: RowLayout {
        id: setting
        required property string title
        required property list<string> labels
        required property int value
        signal selected(value: int)
        spacing: root.model.promptStyle.spacing
        Caption { text: setting.title; enabled: setting.enabled }
        Repeater {
            model: setting.labels
            delegate: Action {
                required property int index
                required property string modelData
                text: setting.value === index ? qsTr("✓ %1").arg(modelData) : modelData
                Accessible.description: setting.value === index ? qsTr("Selected") : ""
                onActivated: setting.selected(index)
            }
        }
    }

    FolderDialog {
        id: folderPicker
        objectName: "midiEffectsFolderPicker"
        title: qsTr("Add VST3 Plug-in Folder")
        parentWindow: root.Window.window
        onAccepted: root.model.addFolder(folderPicker.selectedFolder)
    }

    PromptCard {
        id: card
        anchors.centerIn: parent
        appearance: root.model.promptStyle
        width: implicitWidth
        height: implicitHeight
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("MIDI Effects")
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.model.close()
            event.accepted = event.key !== Qt.Key_Space
                && event.key !== Qt.Key_Tab && event.key !== Qt.Key_Backtab
        }
        Keys.onReleased: event => event.accepted = event.key !== Qt.Key_Space

        ColumnLayout {
            width: Math.max(0, Math.min(root.unit * 58,
                root.width - 4 * card.appearance.dialogPadding))
            height: Math.max(0, Math.min(implicitHeight,
                root.height - 4 * card.appearance.dialogPadding))
            spacing: card.appearance.spacing

            RowLayout {
                Layout.fillWidth: true
                Caption { text: qsTr("MIDI Effects"); font.bold: true }
                Caption {
                    Layout.fillWidth: true
                    text: root.model.trackLabel
                    elide: Text.ElideRight
                }
                Action {
                    text: qsTr("Close")
                    onActivated: root.model.close()
                }
            }

            Flickable {
                id: contentView
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: body.implicitHeight
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                function reveal(item: Item, top: real, itemHeight: real): void {
                    let ancestor = item.parent
                    while (ancestor && ancestor !== contentItem)
                        ancestor = ancestor.parent
                    if (!ancestor)
                        return
                    const bottom = top + itemHeight
                    if (top < contentY)
                        contentY = top
                    else if (bottom > contentY + height)
                        contentY = bottom - height
                    contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
                }

                ColumnLayout {
                    id: body
                    width: contentView.width
                    spacing: card.appearance.spacing

                    RowLayout {
                        Layout.fillWidth: true
                        Action {
                            id: rescan
                            objectName: "midiEffectsRescan"
                            text: qsTr("Rescan")
                            enabled: !root.model.isScanning && !root.model.isLoading
                            onActivated: root.model.rescan()
                        }
                        Action {
                            objectName: "midiEffectsCancelScan"
                            text: qsTr("Cancel Scan")
                            visible: root.model.isScanning
                            onActivated: root.model.cancelScan()
                        }
                        Action {
                            objectName: "midiEffectsAddFolder"
                            text: qsTr("Add Folder")
                            enabled: !root.model.isScanning && !root.model.isLoading
                            onActivated: folderPicker.open()
                        }
                    }

                    Repeater {
                        model: root.model.folders
                        delegate: RowLayout {
                            id: folderRow
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            Caption {
                                Layout.fillWidth: true
                                text: folderRow.modelData
                                wrapMode: Text.WrapAnywhere
                            }
                            Action {
                                text: qsTr("Remove Folder")
                                enabled: !root.model.isScanning && !root.model.isLoading
                                onActivated: root.model.removeFolder(folderRow.index)
                            }
                        }
                    }

                    ListView {
                        id: plugins
                        objectName: "midiEffectsPluginList"
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.unit * 12
                        model: root.model.plugins
                        clip: true
                        spacing: card.appearance.spacing
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            id: plugin
                            required property int index
                            required property string name
                            required property string vendor
                            required property string detail
                            required property bool blocked
                            readonly property bool selected: root.model.selectedPlugin === index
                            width: plugins.width
                            implicitHeight: pluginContents.implicitHeight + 2 * card.appearance.buttonPadding
                            color: selected ? root.model.colors.buttonPressedBackground : root.model.colors.windowBackground
                            border.width: card.appearance.borderWidth
                            border.color: activeFocus ? card.appearance.focus : root.model.colors.outline
                            radius: card.appearance.radius
                            activeFocusOnTab: enabled
                            enabled: !root.model.isLoading && !root.model.isScanning
                            Accessible.role: Accessible.Button
                            Accessible.name: plugin.name
                            Accessible.description: plugin.blocked ? qsTr("Skipped: %1").arg(plugin.detail) : plugin.detail
                            Accessible.onPressAction: activate()
                            function activate(): void {
                                if (enabled && !plugin.blocked)
                                    root.model.selectPlugin(index)
                            }
                            onActiveFocusChanged: if (activeFocus) {
                                plugins.positionViewAtIndex(index, ListView.Contain)
                                contentView.reveal(plugin, plugin.mapToItem(contentView.contentItem, 0, 0).y, plugin.height)
                            }
                            Keys.onReturnPressed: event => { activate(); event.accepted = true }
                            Keys.onEnterPressed: event => { activate(); event.accepted = true }
                            TapHandler { onTapped: plugin.activate() }

                            RowLayout {
                                id: pluginContents
                                anchors.fill: parent
                                anchors.margins: card.appearance.buttonPadding
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Caption {
                                        Layout.fillWidth: true
                                        text: plugin.blocked ? qsTr("Skipped: %1").arg(plugin.name) : plugin.name
                                        color: plugin.selected ? root.model.colors.buttonPressedText : root.model.colors.windowText
                                        wrapMode: Text.Wrap
                                    }
                                    Caption {
                                        Layout.fillWidth: true
                                        text: plugin.vendor
                                        color: plugin.selected ? root.model.colors.buttonPressedText : root.model.colors.windowText
                                        visible: text.length > 0
                                        wrapMode: Text.Wrap
                                    }
                                    Caption {
                                        Layout.fillWidth: true
                                        text: plugin.detail
                                        color: plugin.selected ? root.model.colors.buttonPressedText : root.model.colors.windowText
                                        visible: text.length > 0
                                        wrapMode: Text.Wrap
                                    }
                                }
                                Action {
                                    text: qsTr("Retry")
                                    visible: plugin.blocked
                                    onActivated: root.model.retryBlocked(plugin.index)
                                }
                            }
                        }
                    }
                    Caption {
                        Layout.fillWidth: true
                        visible: plugins.count === 0
                        text: qsTr("No MIDI-producing VST3 plugins found. Add a folder or Rescan.")
                        wrapMode: Text.Wrap
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: card.appearance.spacing
                        Action {
                            objectName: "midiEffectsOpenEditor"
                            text: qsTr("Open Editor")
                            enabled: root.model.hasEffect && root.model.canOpenEditor
                                && !root.model.isLoading && !root.model.canReload
                            onActivated: root.model.openEditor()
                        }
                        Setting {
                            objectName: "midiEffectsInput"
                            title: qsTr("Input")
                            labels: [qsTr("None"), qsTr("Track notes")]
                            value: root.model.inputMode
                            enabled: root.model.hasEffect && !root.model.isLoading
                            onSelected: value => root.model.setInputMode(value)
                        }
                        Setting {
                            objectName: "midiEffectsPacing"
                            title: qsTr("Pacing")
                            labels: [qsTr("Offline"), qsTr("Realtime")]
                            value: root.model.pacing
                            enabled: root.model.hasEffect && !root.model.isLoading
                            onSelected: value => root.model.setPacing(value)
                        }
                        Setting {
                            objectName: "midiEffectsPreroll"
                            title: qsTr("Pre-roll")
                            labels: [qsTr("0 bars"), qsTr("1 bar"), qsTr("2 bars")]
                            value: root.model.prerollBars
                            enabled: root.model.hasEffect && !root.model.isLoading
                            onSelected: value => root.model.setPrerollBars(value)
                        }
                    }
                    Caption {
                        Layout.fillWidth: true
                        text: root.model.status
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                    }
                    Caption {
                        Layout.fillWidth: true
                        text: root.model.diagnostics
                        visible: text.length > 0
                        wrapMode: Text.Wrap
                    }
                    Action {
                        objectName: "midiEffectsReload"
                        text: qsTr("Reload Plug-in")
                        visible: root.model.canReload
                        enabled: !root.model.isLoading
                        onActivated: root.model.reloadPlugin()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Action {
                    objectName: "midiEffectsRemove"
                    text: qsTr("Remove")
                    enabled: root.model.hasEffect && !root.model.isLoading
                    onActivated: root.model.removeEffect()
                }
                Item { Layout.fillWidth: true }
                Action {
                    id: closeButton
                    objectName: "midiEffectsClose"
                    text: qsTr("Close")
                    onActivated: root.model.close()
                    KeyNavigation.tab: rescan
                }
            }
        }
    }
}
