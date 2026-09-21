// Original VoicePickerPrompt structure, bound to the Swift-owned picker.
import QtQuick
import ".." as Shared

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
    QtObject {
        id: pickerAppearance
        readonly property color background: "#E9E4E0"
        readonly property color outline: "#8C857F"
        readonly property color text: "#302C29"
        readonly property color focus: "#0084DB"
        readonly property color pressedBackground: "#D5CEC8"
        readonly property color pressedText: "#302C29"
        readonly property color buttonBackground: "#BDB5AF"
        readonly property color buttonText: "#302C29"
        readonly property real borderWidth: 1
        readonly property real radius: Math.max(1, pickerRoot.baseFontPx / 4)
        readonly property real dialogPadding: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real spacing: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real horizontalPadding: Math.round(pickerRoot.baseFontPx / 2)
        readonly property real verticalPadding: Math.round(pickerRoot.baseFontPx / 4)
        readonly property real buttonPadding: Math.round(pickerRoot.baseFontPx / 3)
        readonly property font font: Qt.font({
            pixelSize: Math.round(pickerRoot.baseFontPx),
            family: "Atkinson Hyperlegible Next"
        })
    }

    function focusSearch() {
        if (!showing)
            return
        search.forceActiveFocus(Qt.PopupFocusReason)
        revealMatch()
    }
    function revealMatch() {
        list.currentIndex = model ? model.pickerIndex : -1
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

    Shared.PromptCard {
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
            color: card.appearance.text
            font: card.appearance.font
            renderType: Text.NativeRendering
        }
        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"
            width: Math.max(1, Math.min(pickerRoot.baseFontPx * 30,
                                       pickerRoot.width - 4 * card.appearance.dialogPadding))
            height: searchMetrics.height + 2 * (card.appearance.verticalPadding + card.appearance.borderWidth)
            color: card.appearance.background
            border.width: card.appearance.borderWidth
            border.color: search.activeFocus ? card.appearance.focus : card.appearance.outline
            radius: card.appearance.radius
            FontMetrics { id: searchMetrics; font: card.appearance.font }
            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"
                anchors.fill: parent
                anchors.leftMargin: card.appearance.horizontalPadding + card.appearance.borderWidth
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                color: card.appearance.outline
                font: card.appearance.font
                renderType: Text.NativeRendering
            }
            TextInput {
                id: search
                objectName: "voicePickerSearch"
                anchors.fill: parent
                clip: true
                color: card.appearance.text
                font: card.appearance.font
                padding: card.appearance.borderWidth
                leftPadding: card.appearance.horizontalPadding + card.appearance.borderWidth
                rightPadding: leftPadding
                topPadding: card.appearance.verticalPadding + card.appearance.borderWidth
                bottomPadding: topPadding
                selectionColor: card.appearance.focus
                selectedTextColor: card.appearance.text
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
                Shared.HoverHint {
                    source: search
                    cursorShape: Qt.IBeamCursor
                    profile: Shared.HintProfiles.TextSelection
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
                pickerRoot.height - searchFrame.height - searchMetrics.height * 4 - 6 * card.appearance.dialogPadding))
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
                function onPickerIndexChanged() { pickerRoot.revealMatch() }
                function onPickerFilterChanged() { Qt.callLater(pickerRoot.revealMatch) }
            }
            Keys.onUpPressed: event => { pickerRoot.model.movePickerSelection(-1); event.accepted = true }
            Keys.onDownPressed: event => { pickerRoot.model.movePickerSelection(1); event.accepted = true }
            Keys.onReturnPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
            Keys.onEnterPressed: event => { pickerRoot.model.acceptPicker(); event.accepted = true }
            highlight: Rectangle { color: card.appearance.pressedBackground; radius: card.appearance.radius }
            delegate: Item {
                id: row
                required property int index
                required property var model
                objectName: "voicePickerRow_" + model.program
                width: list.width
                height: rowText.implicitHeight + 2 * card.appearance.verticalPadding
                Text {
                    id: rowText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: card.appearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem ? card.appearance.pressedText : card.appearance.text
                    font: card.appearance.font
                    text: row.model.label
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
                Accessible.name: model.label
                Accessible.selected: ListView.isCurrentItem
                Accessible.onPressAction: pickerRoot.model.selectPickerRow(row.index)
            }
            Text {
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                color: card.appearance.text
                font: card.appearance.font
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
            spacing: card.appearance.spacing
            Shared.PromptButton {
                id: acceptButton
                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: pickerAppearance
                text: qsTr("OK")
                enabled: pickerRoot.model ? pickerRoot.model.pickerHasMatch : false
                minimumWidth: cancelButton.labelWidth + 2 * appearance.buttonPadding
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: list
                onActivated: pickerRoot.model.acceptPicker()
            }
            Shared.PromptButton {
                id: cancelButton
                objectName: "voicePickerCancel"
                claimsShortcuts: false
                appearance: pickerAppearance
                text: qsTr("Cancel")
                minimumWidth: acceptButton.labelWidth + 2 * appearance.buttonPadding
                KeyNavigation.tab: search
                KeyNavigation.backtab: acceptButton.enabled ? acceptButton : list
                onActivated: pickerRoot.model.cancelPicker()
            }
        }
    }
}
