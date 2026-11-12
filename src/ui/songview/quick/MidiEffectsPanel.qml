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

    // Supporting ink; only on window and input surfaces.
    component Note: Caption {
        color: root.model.colors.secondaryText
    }

    component Heading: Caption {
        font.bold: true
        Accessible.role: Accessible.Heading
    }


    // Structural divider spanning the whole card, padding included.
    component Divider: Item {
        Layout.fillWidth: true
        implicitHeight: card.appearance.borderWidth
        Rectangle {
            x: -card.appearance.dialogPadding
            width: card.width
            height: parent.height
            color: root.model.colors.outline
        }
    }

    // Position cue for a clipped view, drawn by a sibling so it never scrolls away.
    // It sits against the view's right edge, centred in `gutter` when one is given.
    component ScrollMark: Rectangle {
        required property Item view
        required property real heightRatio
        required property real yPosition
        property real gutter: 0
        visible: heightRatio < 1
        width: root.unit / 4
        radius: width / 2
        x: view.x + view.width - Math.max(width, (gutter + width) / 2)
        y: view.y + Math.max(0, yPosition) * view.height
        height: Math.min(heightRatio, 1) * view.height
        color: root.model.colors.scrollbarHandle
    }

    component Action: PromptAction {
        id: action
        // Label padding on each side; the shared chrome supplies buttonPadding of it.
        property real sidePadding: card.gap
        appearance: root.model.promptStyle
        Layout.preferredWidth: action.implicitWidth
            + 2 * Math.max(0, action.sidePadding - action.appearance.buttonPadding)
        Layout.preferredHeight: Math.max(action.implicitHeight, card.controlHeight)
        onActiveFocusChanged: if (activeFocus) {
            contentView.reveal(action, action.mapToItem(contentView.contentItem, 0, 0).y, action.height)
        }
    }

    // One exclusive choice. Space stays with transport, as for PromptAction.
    component Segment: Rectangle {
        id: segment
        required property string text
        property bool selected: false
        readonly property bool pressed: segmentTap.pressed
        signal activated()
        implicitWidth: segmentLabel.implicitWidth + 2 * card.fieldPadding
        implicitHeight: Math.max(segmentLabel.implicitHeight + 2 * card.appearance.buttonPadding, card.controlHeight)
        radius: card.appearance.radius
        color: pressed ? card.appearance.pressedBackground
            : selected ? card.appearance.selection : card.appearance.buttonBackground
        border.width: card.appearance.borderWidth
        border.color: activeFocus ? card.appearance.focus : card.appearance.outline
        activeFocusOnTab: enabled
        Accessible.role: Accessible.RadioButton
        Accessible.name: text
        Accessible.checkable: true
        Accessible.checked: selected
        Accessible.focusable: enabled
        Accessible.onPressAction: activate()

        function activate(): void {
            if (enabled)
                activated()
        }

        onActiveFocusChanged: if (activeFocus)
            contentView.reveal(segment, segment.mapToItem(contentView.contentItem, 0, 0).y, segment.height)
        Keys.onReturnPressed: event => { activate(); event.accepted = true }
        Keys.onEnterPressed: event => { activate(); event.accepted = true }
        Keys.onShortcutOverride: event => event.accepted =
            event.key === Qt.Key_Return || event.key === Qt.Key_Enter

        Text {
            id: segmentLabel
            anchors.centerIn: parent
            text: segment.text
            font: card.appearance.font
            color: !segment.enabled ? card.appearance.disabledText
                : segment.pressed ? card.appearance.pressedText
                : segment.selected ? card.appearance.selectionText : card.appearance.buttonText
            renderType: Text.NativeRendering
            textFormat: Text.PlainText
            Accessible.ignored: true
        }

        TapHandler {
            id: segmentTap
            onTapped: {
                segment.forceActiveFocus(Qt.MouseFocusReason)
                segment.activate()
            }
        }
    }

    component Setting: RowLayout {
        id: setting
        required property string title
        required property list<string> labels
        required property int value
        readonly property real titleWidth: settingTitle.implicitWidth
        property real titleColumn: titleWidth
        signal selected(value: int)
        Layout.fillWidth: true
        spacing: card.gap

        Caption {
            id: settingTitle
            Layout.preferredWidth: setting.titleColumn
            Layout.alignment: Qt.AlignVCenter
            text: setting.title
            enabled: setting.enabled
            color: enabled ? root.model.colors.windowText : root.model.colors.disabledText
            Accessible.ignored: true
        }
        Flow {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: card.tight
            Accessible.role: Accessible.Grouping
            Accessible.name: setting.title
            Repeater {
                model: setting.labels
                delegate: Segment {
                    required property int index
                    required property string modelData
                    text: modelData
                    selected: setting.value === index
                    onActivated: setting.selected(index)
                }
            }
        }
    }

    TextMetrics {
        id: selectionMark
        font: root.model.bodyFont
        text: "✓"
    }

    FontMetrics {
        id: metrics
        font: root.model.promptStyle.font
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
        // Rhythm from the rendered prompt font, shared with the voice picker family.
        readonly property real line: Math.ceil(metrics.height)
        readonly property real gap: Math.round(line / 2)
        readonly property real tight: Math.max(appearance.spacing, Math.round(gap / 2))
        // Sections sit inside the card's own padding; together they make one gap.
        readonly property real inset: Math.max(0, gap - appearance.dialogPadding)
        readonly property real fieldPadding: Math.max(appearance.horizontalPadding, gap)
        readonly property real fieldVerticalPadding: Math.max(appearance.verticalPadding, Math.round(line / 4))
        readonly property real controlHeight: line + gap
        readonly property real footerWidth: Math.max(removeButton.implicitWidth, reloadButton.implicitWidth,
            closeButton.implicitWidth) + 2 * Math.max(0, line - appearance.buttonPadding)
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
            width: Math.max(0, Math.min(root.unit * 48,
                root.width - 4 * card.appearance.dialogPadding))
            height: Math.max(0, Math.min(implicitHeight,
                root.height - 4 * card.appearance.dialogPadding))
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: card.inset
                Layout.rightMargin: card.inset
                Layout.topMargin: card.inset
                Layout.bottomMargin: card.gap
                spacing: card.gap
                Heading {
                    Layout.alignment: Qt.AlignBaseline
                    text: qsTr("MIDI Effects")
                }
                Caption {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: root.model.trackLabel
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                }
            }

            Divider {}

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                Layout.preferredHeight: contentView.contentHeight

                Flickable {
                    id: contentView
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: body.implicitHeight + 2 * card.gap
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
                        x: card.inset
                        y: card.gap
                        width: Math.max(0, contentView.width - 2 * card.inset)
                        spacing: card.tight

                        // Scrolls with the content so long messages wrap in full without crowding the dialog.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.bottomMargin: card.tight
                            visible: root.model.status.length > 0
                            implicitHeight: statusText.implicitHeight + 2 * card.fieldVerticalPadding
                            color: root.model.colors.alternateBackground
                            border.width: card.appearance.borderWidth
                            border.color: root.model.colors.outline
                            radius: card.appearance.radius

                            Caption {
                                id: statusText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: card.fieldPadding
                                anchors.rightMargin: card.fieldPadding
                                text: root.model.status
                                wrapMode: Text.Wrap
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.model.hasEffect
                            spacing: card.tight
                            Heading {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: root.model.effectName
                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }
                            Note {
                                objectName: "midiEffectsLiveState"
                                Layout.leftMargin: card.tight
                                text: root.model.isLoading ? qsTr("Loading…")
                                    : root.model.isLive ? qsTr("Live on") : qsTr("Live off")
                                elide: Text.ElideRight
                            }
                            Action {
                                id: changePlugin
                                objectName: "midiEffectsChange"
                                text: qsTr("Change Plug-in…")
                                visible: !root.model.browsingPlugins
                                enabled: !root.model.isLoading
                                onActivated: {
                                    root.model.showPluginChooser()
                                    rescan.forceActiveFocus(Qt.PopupFocusReason)
                                }
                            }
                            Action {
                                id: openEditor
                                objectName: "midiEffectsOpenEditor"
                                text: qsTr("Open Editor")
                                visible: root.model.hasEffect && !root.model.browsingPlugins
                                enabled: root.model.hasEffect && root.model.canOpenEditor
                                    && !root.model.isLoading && !root.model.canReload
                                onActivated: root.model.openEditor()
                            }
                        }


                        ColumnLayout {
                            id: settings
                            readonly property real titleColumn:
                                Math.max(inputSetting.titleWidth, pacingSetting.titleWidth, prerollSetting.titleWidth)
                            Layout.fillWidth: true
                            Layout.topMargin: card.tight
                            visible: root.model.hasEffect && !root.model.browsingPlugins
                            spacing: card.tight
                            Setting {
                                id: inputSetting
                                objectName: "midiEffectsInput"
                                titleColumn: settings.titleColumn
                                title: qsTr("Input")
                                labels: [qsTr("None"), qsTr("Track notes")]
                                value: root.model.inputMode
                                enabled: root.model.hasEffect && !root.model.isLoading
                                onSelected: value => root.model.setInputMode(value)
                            }
                            Heading {
                                Layout.topMargin: card.gap
                                text: qsTr("Render settings")
                            }
                            Setting {
                                id: pacingSetting
                                objectName: "midiEffectsPacing"
                                titleColumn: settings.titleColumn
                                title: qsTr("Pacing")
                                labels: [qsTr("Offline"), qsTr("Realtime")]
                                value: root.model.pacing
                                enabled: root.model.hasEffect && !root.model.isLoading
                                onSelected: value => root.model.setPacing(value)
                            }
                            Setting {
                                id: prerollSetting
                                objectName: "midiEffectsPreroll"
                                titleColumn: settings.titleColumn
                                title: qsTr("Pre-roll")
                                labels: [qsTr("0 bars"), qsTr("1 bar"), qsTr("2 bars")]
                                value: root.model.prerollBars
                                enabled: root.model.hasEffect && !root.model.isLoading
                                onSelected: value => root.model.setPrerollBars(value)
                            }
                            Note {
                                Layout.fillWidth: true
                                Layout.topMargin: card.tight
                                visible: text.length > 0
                                text: root.model.diagnostics.length > 0
                                    ? qsTr("Last output: %1").arg(root.model.diagnostics) : ""
                                wrapMode: Text.Wrap
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: root.model.browsingPlugins
                            spacing: card.tight
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: card.tight
                                Heading { text: qsTr("Plug-ins") }
                                Note {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: card.tight
                                    text: root.model.isScanning ? qsTr("Scanning…") : ""
                                    elide: Text.ElideRight
                                }
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
                                    text: qsTr("Add Folder…")
                                    enabled: !root.model.isScanning && !root.model.isLoading
                                    onActivated: folderPicker.open()
                                }
                            }

                            Rectangle {
                                id: library
                                readonly property real inset: card.appearance.borderWidth + Math.round(card.tight / 2)
                                Layout.fillWidth: true
                                Layout.preferredHeight: 2 * inset
                                    + Math.min(Math.max(plugins.contentHeight, card.line * 3), card.line * 12)
                                color: root.model.colors.inputBackground
                                border.width: card.appearance.borderWidth
                                border.color: plugins.activeFocus ? card.appearance.focus : root.model.colors.outline
                                radius: card.appearance.radius

                                ListView {
                                    id: plugins
                                    objectName: "midiEffectsPluginList"
                                    anchors.fill: parent
                                    anchors.margins: library.inset
                                    model: root.model.plugins
                                    clip: true
                                    spacing: card.appearance.borderWidth
                                    boundsBehavior: Flickable.StopAtBounds
                                    Accessible.role: Accessible.List
                                    Accessible.name: qsTr("Plug-ins")
                                    delegate: Rectangle {
                                        id: plugin
                                        required property int index
                                        required property string name
                                        required property string vendor
                                        required property string detail
                                        readonly property bool selected: root.model.candidatePlugin === index
                                        readonly property bool hovered: enabled && !selected && pointer.hovered
                                        readonly property color ink: selected ? card.appearance.selectionText
                                            : enabled ? root.model.colors.windowText : root.model.colors.disabledText
                                        readonly property color supportInk: selected ? card.appearance.selectionText
                                            : !enabled ? root.model.colors.disabledText
                                            : hovered ? root.model.colors.windowText : root.model.colors.secondaryText
                                        width: plugins.width
                                        implicitHeight: pluginContents.implicitHeight + 2 * card.fieldVerticalPadding
                                        color: selected ? card.appearance.selection
                                            : hovered ? root.model.colors.buttonHoverBackground
                                            : root.model.colors.inputBackground
                                        border.width: activeFocus ? card.appearance.borderWidth : 0
                                        border.color: card.appearance.focus
                                        radius: card.appearance.radius
                                        activeFocusOnTab: enabled
                                        enabled: !root.model.isLoading && !root.model.isScanning
                                        Accessible.role: Accessible.Button
                                        Accessible.name: plugin.name
                                        Accessible.description: plugin.selected
                                            ? qsTr("Selected. %1").arg(supportLine.text) : supportLine.text
                                        Accessible.onPressAction: activate()

                                        function activate(): void {
                                            if (enabled)
                                                root.model.choosePlugin(index)
                                        }
                                        onActiveFocusChanged: if (activeFocus) {
                                            plugins.positionViewAtIndex(index, ListView.Contain)
                                            contentView.reveal(plugin, plugin.mapToItem(contentView.contentItem, 0, 0).y, plugin.height)
                                        }
                                        Keys.onReturnPressed: event => { activate(); event.accepted = true }
                                        Keys.onEnterPressed: event => { activate(); event.accepted = true }
                                        HoverHandler { id: pointer }
                                        TapHandler { onTapped: plugin.activate() }

                                        RowLayout {
                                            id: pluginContents
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: card.tight
                                            anchors.rightMargin: card.fieldPadding
                                            spacing: card.tight

                                            Caption {
                                                Layout.alignment: Qt.AlignTop
                                                Layout.preferredWidth: selectionMark.advanceWidth
                                                text: root.model.selectedPlugin === plugin.index ? selectionMark.text : ""
                                                color: plugin.ink
                                                Accessible.ignored: true
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Caption {
                                                    Layout.fillWidth: true
                                                    text: plugin.name
                                                    color: plugin.ink
                                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                }
                                                Caption {
                                                    id: supportLine
                                                    Layout.fillWidth: true
                                                    visible: text.length > 0
                                                    text: plugin.vendor.length > 0 && plugin.detail.length > 0
                                                        ? qsTr("%1 · %2").arg(plugin.vendor).arg(plugin.detail)
                                                        : plugin.vendor + plugin.detail
                                                    color: plugin.supportInk
                                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                }
                                            }
                                        }
                                    }
                                }

                                Note {
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, parent.width - 2 * card.fieldPadding)
                                    visible: plugins.count === 0
                                    text: root.model.isScanning ? qsTr("Scanning plug-in folders…") : qsTr("No plug-ins listed.")
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                }

                                ScrollMark {
                                    view: plugins
                                    heightRatio: plugins.visibleArea.heightRatio
                                    yPosition: plugins.visibleArea.yPosition
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: card.tight
                                visible: root.model.folders.length > 0
                                spacing: card.tight
                                Note { text: qsTr("Plug-in folders") }
                                Repeater {
                                    model: root.model.folders
                                    delegate: RowLayout {
                                        id: folderRow
                                        required property int index
                                        required property string modelData
                                        Layout.fillWidth: true
                                        spacing: card.gap
                                        Caption {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            text: folderRow.modelData
                                            wrapMode: Text.WrapAnywhere
                                        }
                                        Action {
                                            Layout.alignment: Qt.AlignTop
                                            text: qsTr("Remove")
                                            Accessible.description: qsTr("Remove folder %1").arg(folderRow.modelData)
                                            enabled: !root.model.isScanning && !root.model.isLoading
                                            onActivated: root.model.removeFolder(folderRow.index)
                                        }
                                    }
                                }
                            }
                        }


                    }
                }

                ScrollMark {
                    view: contentView
                    heightRatio: contentView.visibleArea.heightRatio
                    yPosition: contentView.visibleArea.yPosition
                    gutter: card.inset
                }
            }

            Divider {}

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: card.inset
                Layout.rightMargin: card.inset
                Layout.topMargin: card.gap
                Layout.bottomMargin: card.inset
                spacing: card.tight
                Action {
                    id: removeButton
                    objectName: "midiEffectsRemove"
                    Layout.preferredWidth: card.footerWidth
                    text: qsTr("Remove Effect")
                    visible: root.model.hasEffect && !root.model.browsingPlugins
                    enabled: root.model.hasEffect && !root.model.isLoading
                    onActivated: root.model.removeEffect()
                }
                Item { Layout.fillWidth: true }
                Action {
                    objectName: "midiEffectsCancelChoice"
                    text: qsTr("Back")
                    visible: root.model.browsingPlugins && root.model.hasEffect
                    onActivated: {
                        root.model.cancelPluginChooser()
                        closeButton.forceActiveFocus(Qt.PopupFocusReason)
                    }
                }
                Action {
                    objectName: "midiEffectsApply"
                    text: root.model.hasEffect ? qsTr("Replace Plug-in") : qsTr("Add Plug-in")
                    visible: root.model.browsingPlugins
                    enabled: root.model.candidatePlugin >= 0
                        && root.model.candidatePlugin !== root.model.selectedPlugin
                        && !root.model.isScanning && !root.model.isLoading
                    onActivated: {
                        root.model.applyPlugin()
                        closeButton.forceActiveFocus(Qt.PopupFocusReason)
                    }
                }
                // Fixed beside Close so recovery stays reachable however long the status grows.
                Action {
                    id: reloadButton
                    objectName: "midiEffectsReload"
                    Layout.preferredWidth: card.footerWidth
                    text: qsTr("Reload Plug-in")
                    visible: root.model.canReload
                    enabled: !root.model.isLoading
                    onActivated: root.model.reloadPlugin()
                }
                Action {
                    id: closeButton
                    objectName: "midiEffectsClose"
                    Layout.preferredWidth: card.footerWidth
                    text: qsTr("Close")
                    onActivated: root.model.close()
                    KeyNavigation.tab: root.model.browsingPlugins ? rescan : changePlugin
                }
            }
        }
    }
}
