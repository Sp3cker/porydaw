// Original VoicePickerPrompt structure, bound to the Swift-owned picker.
import QtQuick
import Porydaw.Ui
import PorydawApp as App

pragma ComponentBehavior: Bound

FocusScope {
    id: pickerRoot
    objectName: "voicePicker"
    required property App.VoiceChangesPage model
    property VoiceChangesPage pageItem: null
    property App.MouseHints hintService: null
    property bool showing: false
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing

    readonly property real baseFontPx: pickerRoot.model ? pickerRoot.model.baseFontPx : 13
    readonly property App.PromptStyle pickerAppearance: pickerRoot.model
                                                       ? pickerRoot.model.promptStyle : null

    function focusSearch(): void {
        if (!pickerRoot.showing)
            return
        search.forceActiveFocus(Qt.PopupFocusReason)
        pickerRoot.revealMatch()
    }
    function revealMatch(): void {
        list.currentIndex = pickerRoot.model ? pickerRoot.model.pickerIndex : -1
        if (list.currentIndex >= 0)
            list.positionViewAtIndex(list.currentIndex, ListView.Center)
    }
    onShowingChanged: {
        if (showing)
            Qt.callLater(focusSearch)
        else {
            if (model)
                model.releasePickerAudition()
            closed()
        }
    }
    Component.onDestruction: {
        if (model)
            model.releasePickerAudition()
    }
    Keys.onShortcutOverride: event => {
        event.accepted = event.key !== Qt.Key_Space || search.activeFocus
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            pickerRoot.model.cancelPicker()
        event.accepted = true
    }
    Keys.onReleased: event => event.accepted = true

    MouseArea {
        objectName: "voicePickerUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: pickerRoot.model.cancelPicker()
    }

    PromptCard {
        id: card
        objectName: "voicePickerCard"
        anchors.centerIn: parent
        appearance: pickerRoot.pickerAppearance
        width: implicitWidth
        height: implicitHeight
        Accessible.role: Accessible.Client
        Accessible.name: pickerRoot.model ? pickerRoot.model.pickerTitle : ""
        MouseArea {
            parent: card
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        Text {
            objectName: "voicePickerTitle"
            text: pickerRoot.model ? pickerRoot.model.pickerTitle : ""
            color: pickerRoot.pickerAppearance.text
            font: pickerRoot.pickerAppearance.font
            renderType: Text.NativeRendering
        }
        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"
            width: Math.max(1, Math.min(pickerRoot.baseFontPx * 30,
                                       pickerRoot.width - 4 * pickerRoot.pickerAppearance.dialogPadding))
            height: searchMetrics.height + 2 * (pickerRoot.pickerAppearance.verticalPadding + pickerRoot.pickerAppearance.borderWidth)
            color: pickerRoot.pickerAppearance.background
            border.width: pickerRoot.pickerAppearance.borderWidth
            border.color: search.activeFocus ? pickerRoot.pickerAppearance.focus : pickerRoot.pickerAppearance.outline
            radius: pickerRoot.pickerAppearance.radius
            FontMetrics { id: searchMetrics; font: pickerRoot.pickerAppearance.font }
            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"
                anchors.fill: parent
                anchors.leftMargin: pickerRoot.pickerAppearance.horizontalPadding + pickerRoot.pickerAppearance.borderWidth
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                color: pickerRoot.pickerAppearance.placeholderText
                font: pickerRoot.pickerAppearance.font
                renderType: Text.NativeRendering
            }
            TextInput {
                id: search
                objectName: "voicePickerSearch"
                anchors.fill: parent
                clip: true
                color: pickerRoot.pickerAppearance.text
                font: pickerRoot.pickerAppearance.font
                padding: pickerRoot.pickerAppearance.borderWidth
                leftPadding: pickerRoot.pickerAppearance.horizontalPadding + pickerRoot.pickerAppearance.borderWidth
                rightPadding: leftPadding
                topPadding: pickerRoot.pickerAppearance.verticalPadding + pickerRoot.pickerAppearance.borderWidth
                bottomPadding: topPadding
                selectionColor: pickerRoot.pickerAppearance.selection
                selectedTextColor: pickerRoot.pickerAppearance.selectionText
                renderType: TextInput.NativeRendering
                activeFocusOnTab: true
                selectByMouse: true
                text: pickerRoot.model ? pickerRoot.model.pickerFilter : ""
                onTextChanged: {
                    if (pickerRoot.model)
                        pickerRoot.model.setPickerFilter(text)
                }
                KeyNavigation.tab: list
                KeyNavigation.backtab: cancelButton
                Keys.onReturnPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
                Keys.onEnterPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
                Keys.onDownPressed: event => {
                    if (pickerRoot.model.pickerHasMatch)
                        list.forceActiveFocus(Qt.TabFocusReason)
                    event.accepted = true
                }
                HoverHint {
                    source: search
                    cursorShape: Qt.IBeamCursor
                    profile: HintProfiles.TextSelection
                    hintService: pickerRoot.hintService
                    scopeAllowed: pickerRoot.showing
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: searchHint.text
                Accessible.editable: true
            }
        }
        ListView {
            id: list
            objectName: "voicePickerList"
            width: searchFrame.width
            height: Math.max(pickerRoot.baseFontPx * 2, Math.min(pickerRoot.baseFontPx * 11,
                pickerRoot.height - searchFrame.height - searchMetrics.height * 4 - 6 * pickerRoot.pickerAppearance.dialogPadding))
            clip: true
            activeFocusOnTab: true
            model: pickerRoot.model ? pickerRoot.model.pickerRows : null
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0
            keyNavigationEnabled: false
            currentIndex: pickerRoot.model ? pickerRoot.model.pickerIndex : -1
            KeyNavigation.tab: acceptButton.enabled ? acceptButton : cancelButton
            KeyNavigation.backtab: search
            Connections {
                target: pickerRoot.model
                function onPickerIndexChanged(): void { pickerRoot.revealMatch() }
                function onPickerFilterChanged(): void { Qt.callLater(pickerRoot.revealMatch) }
            }
            Keys.onUpPressed: event => { pickerRoot.model.movePickerSelection(-1); event.accepted = true }
            Keys.onDownPressed: event => { pickerRoot.model.movePickerSelection(1); event.accepted = true }
            Keys.onReturnPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
            Keys.onEnterPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
            highlight: Rectangle { color: pickerRoot.pickerAppearance.pressedBackground; radius: pickerRoot.pickerAppearance.radius }
            delegate: Item {
                id: row
                required property int index
                required property int program
                required property string label
                objectName: "voicePickerRow_" + row.program
                width: list.width
                height: rowText.implicitHeight + 2 * pickerRoot.pickerAppearance.verticalPadding
                Text {
                    id: rowText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: pickerRoot.pickerAppearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem ? pickerRoot.pickerAppearance.pressedText : pickerRoot.pickerAppearance.text
                    font: pickerRoot.pickerAppearance.font
                    text: row.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: pickerRoot.model.pressAndHoldPickerRow(row.index)
                    onReleased: pickerRoot.model.releasePickerAudition()
                    onCanceled: pickerRoot.model.releasePickerAudition()
                    onClicked: list.forceActiveFocus(Qt.MouseFocusReason)
                    onDoubleClicked: pickerRoot.model.acceptPicker()
                }
                Accessible.role: Accessible.ListItem
                Accessible.name: row.label
                Accessible.selected: ListView.isCurrentItem
                Accessible.onPressAction: pickerRoot.model.selectPickerRow(row.index)
            }
            Text {
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                color: pickerRoot.pickerAppearance.text
                font: pickerRoot.pickerAppearance.font
                text: qsTr("No matching voices")
                visible: pickerRoot.model ? !pickerRoot.model.pickerHasMatch : true
                renderType: Text.NativeRendering
            }
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Voices")
            Accessible.description: pickerRoot.model && pickerRoot.model.auditionAvailable
                ? qsTr("Click and hold to audition (middle C).") : ""
        }
        Row {
            spacing: pickerRoot.pickerAppearance.spacing
            PromptButton {
                id: acceptButton
                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: pickerRoot.pickerAppearance
                text: qsTr("OK")
                enabled: pickerRoot.model ? pickerRoot.model.pickerHasMatch : false
                minimumWidth: cancelButton.labelWidth + 2 * pickerRoot.pickerAppearance.buttonPadding
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: list
                onActivated: pickerRoot.model.acceptPicker()
            }
            PromptButton {
                id: cancelButton
                objectName: "voicePickerCancel"
                claimsShortcuts: false
                appearance: pickerRoot.pickerAppearance
                text: qsTr("Cancel")
                minimumWidth: acceptButton.labelWidth + 2 * pickerRoot.pickerAppearance.buttonPadding
                KeyNavigation.tab: search
                KeyNavigation.backtab: acceptButton.enabled ? acceptButton : list
                onActivated: pickerRoot.model.cancelPicker()
            }
        }
    }
}
