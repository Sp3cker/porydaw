// Original VoicePickerPrompt structure, bound to the Swift-owned picker.
import QtQuick
import Porydaw.Ui

pragma ComponentBehavior: Bound

FocusScope {
    id: pickerRoot
    objectName: "voicePicker"
    required property var model
    property var pageItem: null
    property var hintService: null
    property bool showing: false
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing

    readonly property real baseFontPx: model ? model.baseFontPx : 13
    readonly property var pickerColors: pickerRoot.pageItem ? pickerRoot.pageItem.gridPalette : null
    QtObject {
        id: pickerAppearance
        readonly property color background: pickerRoot.pickerColors ? pickerRoot.pickerColors.windowBackground : "transparent"
        readonly property color outline: pickerRoot.pickerColors ? pickerRoot.pickerColors.outline : "transparent"
        readonly property color text: pickerRoot.pickerColors ? pickerRoot.pickerColors.windowText : "transparent"
        readonly property color focus: pickerRoot.pickerColors ? pickerRoot.pickerColors.focusOutline : "transparent"
        readonly property color pressedBackground: pickerRoot.pickerColors ? pickerRoot.pickerColors.buttonPressedBackground : "transparent"
        readonly property color pressedText: pickerRoot.pickerColors ? pickerRoot.pickerColors.buttonPressedText : "transparent"
        readonly property color buttonBackground: pickerRoot.pickerColors ? pickerRoot.pickerColors.buttonBackground : "transparent"
        readonly property color buttonText: pickerRoot.pickerColors ? pickerRoot.pickerColors.buttonText : "transparent"
        readonly property color placeholder: pickerRoot.pickerColors ? pickerRoot.pickerColors.placeholderText : "transparent"
        readonly property color selection: pickerRoot.pickerColors ? pickerRoot.pickerColors.tabSelectedBackground : "transparent"
        readonly property color selectionText: pickerRoot.pickerColors ? pickerRoot.pickerColors.selectionText : "transparent"
        readonly property real borderWidth: 1
        readonly property real radius: Math.max(1, pickerRoot.baseFontPx / 4)
        readonly property real dialogPadding: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real spacing: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real horizontalPadding: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real verticalPadding: Math.round(pickerRoot.baseFontPx / 4)
        readonly property real buttonPadding: Math.round(pickerRoot.baseFontPx / 3)
        property font resolvedFont
        resolvedFont.pixelSize: Math.round(pickerRoot.baseFontPx)
        resolvedFont.family: "Atkinson Hyperlegible Next"
        readonly property font font: pickerAppearance.resolvedFont
    }

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
        appearance: pickerAppearance
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
            color: pickerAppearance.text
            font: pickerAppearance.font
            renderType: Text.NativeRendering
        }
        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"
            width: Math.max(1, Math.min(pickerRoot.baseFontPx * 30,
                                       pickerRoot.width - 4 * pickerAppearance.dialogPadding))
            height: searchMetrics.height + 2 * (pickerAppearance.verticalPadding + pickerAppearance.borderWidth)
            color: pickerAppearance.background
            border.width: pickerAppearance.borderWidth
            border.color: search.activeFocus ? pickerAppearance.focus : pickerAppearance.outline
            radius: pickerAppearance.radius
            FontMetrics { id: searchMetrics; font: pickerAppearance.font }
            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"
                anchors.fill: parent
                anchors.leftMargin: pickerAppearance.horizontalPadding + pickerAppearance.borderWidth
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                color: pickerAppearance.placeholder
                font: pickerAppearance.font
                renderType: Text.NativeRendering
            }
            TextInput {
                id: search
                objectName: "voicePickerSearch"
                anchors.fill: parent
                clip: true
                color: pickerAppearance.text
                font: pickerAppearance.font
                padding: pickerAppearance.borderWidth
                leftPadding: pickerAppearance.horizontalPadding + pickerAppearance.borderWidth
                rightPadding: leftPadding
                topPadding: pickerAppearance.verticalPadding + pickerAppearance.borderWidth
                bottomPadding: topPadding
                selectionColor: pickerAppearance.selection
                selectedTextColor: pickerAppearance.selectionText
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
                pickerRoot.height - searchFrame.height - searchMetrics.height * 4 - 6 * pickerAppearance.dialogPadding))
            clip: true
            activeFocusOnTab: true
            model: pickerRoot.model ? pickerRoot.model.pickerRows : []
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
            highlight: Rectangle { color: pickerAppearance.pressedBackground; radius: pickerAppearance.radius }
            delegate: Item {
                id: row
                required property int index
                required property int program
                required property string label
                objectName: "voicePickerRow_" + row.program
                width: list.width
                height: rowText.implicitHeight + 2 * pickerAppearance.verticalPadding
                Text {
                    id: rowText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: pickerAppearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem ? pickerAppearance.pressedText : pickerAppearance.text
                    font: pickerAppearance.font
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
                color: pickerAppearance.text
                font: pickerAppearance.font
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
            spacing: pickerAppearance.spacing
            PromptButton {
                id: acceptButton
                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: pickerAppearance
                text: qsTr("OK")
                enabled: pickerRoot.model ? pickerRoot.model.pickerHasMatch : false
                minimumWidth: cancelButton.labelWidth + 2 * pickerAppearance.buttonPadding
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: list
                onActivated: pickerRoot.model.acceptPicker()
            }
            PromptButton {
                id: cancelButton
                objectName: "voicePickerCancel"
                claimsShortcuts: false
                appearance: pickerAppearance
                text: qsTr("Cancel")
                minimumWidth: acceptButton.labelWidth + 2 * pickerAppearance.buttonPadding
                KeyNavigation.tab: search
                KeyNavigation.backtab: acceptButton.enabled ? acceptButton : list
                onActivated: pickerRoot.model.cancelPicker()
            }
        }
    }
}
