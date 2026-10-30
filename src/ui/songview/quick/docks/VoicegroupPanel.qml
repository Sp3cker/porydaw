pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import QtQuick.Templates as T
import QtQuick.Controls.Fusion as Fusion
import QtQuick.Controls.Fusion.impl as FusionImpl
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp

ColumnLayout {
    id: panel
    objectName: "voicegroupPanel"
    required property ApplicationSession applicationSession
    required property VoiceListController controller
    readonly property GridPalette colors: applicationSession.palette
    readonly property real baseFontPx: applicationSession.baseFontPx
    readonly property int rowHeight: Math.round(baseFontPx * 1.33)
    readonly property int headerHeight: Math.round(baseFontPx * 1.83)
    readonly property int typeWidth: Math.round(baseFontPx * 3.75)
    readonly property int adsrWidth: Math.round(baseFontPx * 8.33)
    // Indexed by VoiceListGlyph; the reverse sample reuses the sample glyph rotated.
    readonly property list<IconSpec> typeIcons: [Icons.sample, Icons.sample, Icons.square1, Icons.square2,
                                                Icons.wave, Icons.noise, Icons.keysplit, Icons.drumkit]
    readonly property IconSpec emptyIcon: IconSpec { glyph: ""; fit: 1 }
    property int contextSlot: -1
    spacing: 0
    enabled: panel.controller.editingEnabled

    function isSongAssignmentFocus(focusedItem: Item): bool {
        let item = focusedItem
        while (item && item !== panel) {
            if (item === selector || item === newVoicegroup)
                return true
            item = item.parent
        }
        return false
    }

    Menu {
        id: rowMenu
        objectName: "voicegroupRowMenu"
        MenuItem {
            objectName: "voicegroupEditInStudio"
            text: qsTr("Edit in Studio")
            onTriggered: panel.controller.requestEditKit(panel.contextSlot)
        }
    }

    ComboBox {
        objectName: "retainedVoicegroupCombo"
        Layout.fillWidth: true
        visible: !panel.controller.hasSongContext && panel.controller.isBound
        model: panel.controller.retainedGroupNames
        currentIndex: panel.controller.retainedGroupIndex
        Accessible.name: qsTr("Retained voicegroup")
        onActivated: panel.controller.selectRetainedVoicegroup(currentIndex)
    }

    RowLayout {
        id: assignmentRow
        Layout.fillWidth: true
        Layout.preferredHeight: panel.baseFontPx * 2.17
        Layout.leftMargin: Math.round(panel.baseFontPx * 0.33)
        Layout.rightMargin: Math.round(panel.baseFontPx * 0.33)
        spacing: Math.round(panel.baseFontPx * 0.16)
        Label {
            objectName: "voicegroupPanelTitle"
            text: panel.controller.panelTitle
            Layout.maximumWidth: panel.width * 0.6
            elide: Text.ElideMiddle
            color: panel.colors.primaryText
        }
        Fusion.TextField {
            id: selector
            objectName: "voicegroupSelector"
            Layout.fillWidth: true
            Layout.preferredHeight: panel.baseFontPx * 1.83
            enabled: panel.controller.selectorEnabled
            text: panel.controller.selectorText
            selectByMouse: true
            rightPadding: dropdownButton.width + leftPadding
            Accessible.name: qsTr("Voicegroup")
            background: FusionImpl.ButtonPanel {
                id: selectorBackground
                readonly property int edge: Math.max(1, Math.round(panel.baseFontPx * 0.08))
                control: dropdownButton
                visible: true
                highlighted: selector.activeFocus
                Rectangle {
                    x: selectorBackground.edge
                    y: selectorBackground.edge
                    width: selector.width - dropdownButton.width - x
                    height: selector.height - 2 * y
                    radius: panel.baseFontPx * 0.16
                    color: selector.palette.base
                    Rectangle {
                        anchors.right: parent.right
                        width: selectorBackground.edge
                        height: parent.height
                        color: selectorBackground.border.color
                    }
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: selectorBackground.edge
                        color: Fusion.Fusion.topShadow
                    }
                }
            }

            function commitSelection(name: string): void {
                panel.controller.selectorText = name
                panel.controller.commitVoicegroupSelection()
                choicesPopup.close()
            }
            onTextEdited: {
                choicesList.currentIndex = panel.controller.filterVoicegroupChoices(text)
                choicesPopup.open()
                choicesList.positionViewAtBeginning()
            }
            onAccepted: {
                const choice = choicesList.currentItem as T.MenuItem
                commitSelection(choicesPopup.visible && choice ? choice.text : text)
            }
            onActiveFocusChanged: {
                if (!activeFocus)
                    choicesPopup.close()
            }
            onEnabledChanged: {
                if (!enabled)
                    choicesPopup.close()
            }
            Keys.onEscapePressed: event => {
                if (choicesPopup.visible) {
                    choicesPopup.close()
                    event.accepted = true
                } else {
                    event.accepted = false
                }
            }
            Keys.onDownPressed: {
                choicesPopup.open()
                choicesList.incrementCurrentIndex()
                choicesList.positionViewAtIndex(choicesList.currentIndex, ListView.Contain)
            }
            Keys.onUpPressed: {
                choicesPopup.open()
                choicesList.decrementCurrentIndex()
                choicesList.positionViewAtIndex(choicesList.currentIndex, ListView.Contain)
            }
            Connections {
                target: panel.controller
                function onSelectorTextChanged(): void {
                    choicesPopup.close()
                    selector.text = panel.controller.selectorText
                }
            }
            ToolButton {
                id: dropdownButton
                objectName: "voicegroupDropdownButton"
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: selector.height
                focusPolicy: Qt.NoFocus
                Accessible.name: qsTr("Show voicegroups")
                down: pressed || choicesPopup.visible
                padding: 0
                background: null
                contentItem: Item {
                    AppIcon {
                        anchors.centerIn: parent
                        width: Math.round(selector.font.pixelSize * 1.5)
                        height: selector.font.pixelSize
                        icon: Icons.comboArrow
                        color: selector.palette.text
                    }
                }
                onClicked: {
                    if (choicesPopup.visible) {
                        choicesPopup.close()
                    } else {
                        choicesList.currentIndex = panel.controller.filterVoicegroupChoices("")
                        choicesPopup.open()
                        choicesList.positionViewAtIndex(choicesList.currentIndex, ListView.Contain)
                        selector.forceActiveFocus()
                        selector.selectAll()
                    }
                }
            }
            Fusion.Popup {
                id: choicesPopup
                objectName: "voicegroupChoicesPopup"
                popupType: T.Popup.Item
                y: selector.height
                width: selector.width
                height: Math.min(Math.max(choicesList.contentHeight, selector.height) + topPadding + bottomPadding,
                                 Math.max(0, panel.height - assignmentRow.y - selector.y
                                          - selector.height - bottomMargin))
                margins: Math.round(panel.baseFontPx * 0.5)
                padding: Math.round(panel.baseFontPx * 0.08)
                focus: false
                modal: false
                closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent
                onClosed: {
                    panel.controller.filterVoicegroupChoices("")
                    selector.text = panel.controller.selectorText
                    choicesList.currentIndex = -1
                }
                contentItem: ListView {
                    id: choicesList
                    objectName: "voicegroupChoicesList"
                    clip: true
                    acceptedButtons: Qt.NoButton
                    model: panel.controller.argChoices
                    currentIndex: -1
                    delegate: MenuItem {
                        required property string name
                        required property int index
                        width: choicesList.width
                        text: name
                        focusPolicy: Qt.NoFocus
                        highlighted: choicesList.currentIndex === index
                        onHoveredChanged: {
                            if (hovered)
                                choicesList.currentIndex = index
                        }
                        onClicked: selector.commitSelection(text)
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    Label {
                        anchors.centerIn: parent
                        visible: choicesList.count === 0
                        text: qsTr("No matching voicegroups")
                        color: selector.palette.windowText
                    }
                }
            }
            ToolTip.text: qsTr("The song's voicegroup (-G). Changing it is undoable.")
            ToolTip.visible: hovered
        }
        ToolButton {
            id: newVoicegroup
            objectName: "vgNewVoicegroupButton"
            enabled: panel.controller.selectorEnabled
            Layout.preferredWidth: panel.baseFontPx * 2.08
            Layout.preferredHeight: panel.baseFontPx * 1.83
            Layout.minimumHeight: 0
            contentItem: Item {
                AppIcon {
                    anchors.centerIn: parent
                    width: Math.round(panel.baseFontPx)
                    height: width
                    icon: Icons.plus
                    color: newVoicegroup.palette.buttonText
                }
            }
            Accessible.name: qsTr("New voicegroup")
            ToolTip.text: qsTr("New voicegroup")
            ToolTip.visible: hovered
            onClicked: panel.controller.requestNewVoicegroup()
        }
    }

    Rectangle {
        id: tree
        objectName: "voicegroupTree"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: panel.rowHeight * 3
        color: panel.colors.windowBackground
        border.width: 1
        border.color: panel.colors.outline

        Rectangle {
            id: treeHeader
            objectName: "voicegroupTreeHeader"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            anchors.rightMargin: Math.round(panel.baseFontPx * 0.58)
            height: panel.headerHeight
            color: panel.colors.chromeBackground
            RowLayout {
                anchors.fill: parent
                spacing: 0
                Label {
                    text: qsTr("Voice")
                    objectName: "voicegroupVoiceHeader"
                    Layout.fillWidth: true
                    Layout.leftMargin: panel.applicationSession.layoutSpaces.one
                    color: panel.colors.primaryText
                }
                Label {
                    text: qsTr("Type")
                    objectName: "voicegroupTypeHeader"
                    Layout.preferredWidth: panel.typeWidth
                    color: panel.colors.primaryText
                }
                Label {
                    text: qsTr("ADSR")
                    objectName: "voicegroupAdsrHeader"
                    Layout.preferredWidth: panel.adsrWidth
                    color: panel.colors.primaryText
                }
            }
        }
        Rectangle {
            anchors.left: treeHeader.left
            anchors.right: treeHeader.right
            anchors.top: treeHeader.bottom
            height: 1
            color: panel.colors.outline
        }
        ListView {
            id: voiceList
            acceptedButtons: Qt.NoButton
            objectName: "voicegroupRows"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: treeHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 1
            anchors.rightMargin: 1
            anchors.bottomMargin: 1
            clip: true
            model: panel.controller.rows
            boundsBehavior: Flickable.StopAtBounds
            // -1 stops the unused highlight animating ~470 ms of frames after each bank load.
            currentIndex: -1
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            delegate: Rectangle {
                id: row
                required property int slot
                required property string title
                required property string typeName
                required property string adsr
                required property int typeIconKey
                required property bool altChip
                required property bool used
                objectName: "voicegroupRow_" + slot
                width: voiceList.width - Math.round(panel.baseFontPx * 0.67)
                height: panel.rowHeight
                activeFocusOnTab: true
                Keys.onPressed: function(event: KeyEvent) {
                    if ((event.key === Qt.Key_Menu
                         || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier)))
                            && panel.controller.slotIsKit(row.slot)) {
                        panel.contextSlot = row.slot
                        rowMenu.popup(row, row.width / 2, row.height / 2)
                        event.accepted = true
                    }
                }
                color: panel.controller.currentSlot === slot ? panel.colors.selectionRing
                       : used ? Qt.tint(panel.colors.windowBackground, "#22b4e4ee")
                              : panel.colors.windowBackground
                RowLayout {
                    anchors.fill: parent
                    spacing: 0
                    Label {
                        text: row.title
                        objectName: "voicegroupTitle_" + row.slot
                        Layout.fillWidth: true
                        Layout.leftMargin: panel.applicationSession.layoutSpaces.one
                        color: panel.controller.currentSlot === row.slot ? panel.colors.selectionText
                                                                       : panel.colors.primaryText
                        elide: Text.ElideRight
                    }
                    Item {
                        objectName: "voicegroupTypeIcon_" + row.slot
                        Layout.preferredWidth: panel.typeWidth
                        Layout.fillHeight: true
                        Accessible.role: Accessible.StaticText
                        Accessible.name: row.typeName
                        HoverHandler { id: iconHover }
                        Rectangle {
                            anchors.centerIn: parent
                            width: panel.baseFontPx * 1.25
                            height: width
                            radius: height * 0.25
                            color: Qt.tint(panel.colors.windowBackground, "#59666666")
                            visible: row.altChip
                        }
                        AppIcon {
                            anchors.centerIn: parent
                            width: panel.baseFontPx * 1.25
                            height: width
                            icon: row.typeIconKey < 0 ? panel.emptyIcon
                                  : panel.typeIcons[Math.floor(row.typeIconKey / 2)]
                            rotation: Math.floor(row.typeIconKey / 2) === 1 ? 180 : 0
                            color: row.altChip ? panel.colors.windowBackground
                                   : panel.controller.currentSlot === row.slot
                                     ? panel.colors.selectionText : panel.colors.primaryText
                        }
                        ToolTip.text: row.typeName
                        ToolTip.visible: iconHover.hovered && row.typeName.length > 0
                    }
                    Label {
                        objectName: "voicegroupAdsr_" + row.slot
                        Layout.preferredWidth: panel.adsrWidth
                        text: row.adsr
                        color: panel.controller.currentSlot === row.slot ? panel.colors.selectionText
                                                                       : panel.colors.primaryText
                        elide: Text.ElideRight
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: function(mouse: MouseEvent) {
                        row.forceActiveFocus()
                        if (mouse.button === Qt.LeftButton) {
                            panel.controller.selectSlot(row.slot)
                            panel.controller.pressVoice(row.slot)
                        }
                    }
                    onClicked: function(mouse: MouseEvent) {
                        if (mouse.button === Qt.RightButton && panel.controller.slotIsKit(row.slot)) {
                            panel.contextSlot = row.slot
                            rowMenu.popup(row, mouse.x, mouse.y)
                        }
                    }
                    onReleased: function(mouse: MouseEvent) {
                        if (mouse.button === Qt.LeftButton)
                            panel.controller.releaseVoice()
                    }
                    onCanceled: panel.controller.releaseVoice()
                }
            }
        }
        Connections {
            target: panel.controller
            function onRevealRequestChanged(): void {
                voiceList.positionViewAtIndex(panel.controller.revealSlotId, ListView.Contain)
            }
        }
    }

    Flickable {
        id: editorScroll
        acceptedButtons: Qt.NoButton
        objectName: "voiceEditorScrollView"
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        Layout.preferredHeight: voiceEditor.Layout.preferredHeight
        Layout.maximumHeight: voiceEditor.Layout.preferredHeight
        Layout.leftMargin: Math.round(panel.baseFontPx * 0.33)
        Layout.rightMargin: Math.round(panel.baseFontPx * 0.25)
        Layout.topMargin: Math.round(panel.baseFontPx * 0.33)
        contentWidth: width
        contentHeight: voiceEditor.Layout.preferredHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        VoiceEditor {
            id: voiceEditor
            objectName: "voicegroupEditorSurface"
            width: editorScroll.width
            height: editorScroll.contentHeight
            controller: panel.controller
            colors: panel.colors
            applicationSession: panel.applicationSession
        }
    }

    Loader {
        id: newVoicegroupDialog
        objectName: "voicegroupNewDialogLoader"
        height: 0
        active: panel.controller.newVoicegroupPrompt
        sourceComponent: VoicegroupNewDialog {
            controller: panel.controller
            baseFontPx: panel.baseFontPx
            layoutSpaces: panel.applicationSession.layoutSpaces
        }
        onLoaded: {
            if (status === Loader.Ready)
                (newVoicegroupDialog.item as VoicegroupNewDialog).open()
        }
    }
}
