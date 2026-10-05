pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

PromptOverlay {
    id: pickerRoot
    objectName: "voicePicker"
    required final property QtObject model
    final property Item pageItem: null
    final property App.MouseHints hintService: null
    final readonly property App.HeaderVoicePicker headerModel: model as App.HeaderVoicePicker
    final readonly property App.VoiceChangesPage voiceModel: model as App.VoiceChangesPage
    final readonly property App.PromptStyle appearance: headerModel
        ? headerModel.promptStyle : voiceModel.promptStyle
    final readonly property string pickerTitle: headerModel ? headerModel.pickerTitle : voiceModel.pickerTitle
    final readonly property string pickerFilter: headerModel ? headerModel.pickerFilter : voiceModel.pickerFilter
    final readonly property int pickerIndex: headerModel ? headerModel.pickerIndex : voiceModel.pickerIndex
    final readonly property bool pickerHasMatch: headerModel ? headerModel.pickerHasMatch : voiceModel.pickerHasMatch

    function releasePickerAudition(): void {
        if (headerModel) headerModel.releasePickerAudition()
        else if (voiceModel) voiceModel.releasePickerAudition()
    }
    function acceptPicker(): void {
        if (headerModel) headerModel.acceptPicker()
        else if (voiceModel) voiceModel.acceptPicker()
    }
    function cancelPicker(): void {
        if (headerModel) headerModel.cancelPicker()
        else if (voiceModel) voiceModel.cancelPicker()
    }
    function setPickerFilter(text: string): void {
        if (headerModel) headerModel.setPickerFilter(text)
        else if (voiceModel) voiceModel.setPickerFilter(text)
    }
    function currentPickerIndex(): int {
        return headerModel ? headerModel.pickerIndex : voiceModel ? voiceModel.pickerIndex : -1
    }
    function selectPickerRow(index: int): void {
        if (headerModel) headerModel.selectPickerRow(index)
        else if (voiceModel) voiceModel.selectPickerRow(index)
    }
    function pressAndHoldPickerRow(index: int): void {
        if (headerModel) headerModel.pressAndHoldPickerRow(index)
        else if (voiceModel) voiceModel.pressAndHoldPickerRow(index)
    }
    property bool showing: false
    signal closed()
    anchors.fill: parent
    overlayOpen: showing
    cardItem: prompt
    underlayObjectName: "voicePickerUnderlay"
    onInitialFocusRequested: prompt.activateInitialFocus()
    onOverlayClosed: {
        releasePickerAudition()
        closed()
    }
    onDismissRequested: cancelPicker()
    Component.onDestruction: releasePickerAudition()
    Keys.onShortcutOverride: event => {
        event.accepted = event.key !== Qt.Key_Space || search.activeFocus
    }

    PromptCard {
        id: prompt

        objectName: "voicePickerCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: pickerRoot.appearance
        minimumWidth: pickerRoot.appearance.minimumWidth
        property bool viewReady: false
        MouseArea {
            parent: prompt
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        function acceptDisplayed(): void {
            pickerRoot.acceptPicker()
        }
        function cancelDisplayed(): void {
            pickerRoot.cancelPicker()
        }
        function activateInitialFocus(): void {
            search.forceActiveFocus(Qt.PopupFocusReason)
            if (pickerRoot.pickerIndex >= 0) {
                list.currentIndex = pickerRoot.pickerIndex
                list.positionViewAtIndex(pickerRoot.pickerIndex, ListView.Center)
            }
            viewReady = true
        }

        // TextInput and ListView edit first; declined keys stop inside the popup.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                cancelDisplayed()
            event.accepted = true
        }
        Keys.onReleased: (event) => event.accepted = true

        Accessible.role: Accessible.Client
        Accessible.name: pickerRoot.pickerTitle

        Text {
            objectName: "voicePickerTitle"
            text: pickerRoot.pickerTitle
            color: pickerRoot.appearance.text
            font: pickerRoot.appearance.font
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"
            implicitWidth: Math.max(
                pickerRoot.appearance.minimumWidth - 2 * pickerRoot.appearance.dialogPadding,
                Math.max(titleMetrics.advanceWidth(pickerRoot.pickerTitle), searchMetrics.advanceWidth(searchHint.text))
                + 2 * (pickerRoot.appearance.horizontalPadding + pickerRoot.appearance.borderWidth))
            implicitHeight: searchMetrics.height
                + 2 * (pickerRoot.appearance.verticalPadding + pickerRoot.appearance.borderWidth)
            color: pickerRoot.appearance.background
            border.width: pickerRoot.appearance.borderWidth
            border.color: search.activeFocus ? pickerRoot.appearance.focus : pickerRoot.appearance.outline
            radius: pickerRoot.appearance.radius

            FontMetrics {
                id: titleMetrics
                font: pickerRoot.appearance.font
            }
            FontMetrics {
                id: searchMetrics
                font: pickerRoot.appearance.font
            }

            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"

                anchors.fill: parent
                anchors.leftMargin: pickerRoot.appearance.horizontalPadding + pickerRoot.appearance.borderWidth
                color: pickerRoot.appearance.placeholderText
                font: pickerRoot.appearance.font
                anchors.rightMargin: anchors.leftMargin
                verticalAlignment: Text.AlignVCenter
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                renderType: Text.NativeRendering
            }

            TextInput {
                id: search

                objectName: "voicePickerSearch"
                HoverHint {
                    source: search
                    hintService: pickerRoot.hintService
                    scopeAllowed: pickerRoot.showing
                    cursorShape: Qt.IBeamCursor
                    // Modern TextInput's own Shift-click marking; no availability
                    // check. Session scope is enforced inside HoverHint.
                    profile: HintProfiles.TextSelection
                }
                anchors.fill: parent
                clip: true
                color: pickerRoot.appearance.text
                font: pickerRoot.appearance.font
                padding: pickerRoot.appearance.borderWidth
                leftPadding: pickerRoot.appearance.horizontalPadding + pickerRoot.appearance.borderWidth
                topPadding: pickerRoot.appearance.verticalPadding + pickerRoot.appearance.borderWidth
                selectionColor: pickerRoot.appearance.selection
                selectedTextColor: pickerRoot.appearance.selectionText
                rightPadding: leftPadding
                bottomPadding: topPadding
                renderType: TextInput.NativeRendering
                activeFocusOnTab: true
                selectByMouse: true
                text: pickerRoot.pickerFilter
                Accessible.role: Accessible.EditableText
                Accessible.name: searchHint.text
                Accessible.description: pickerRoot.pickerTitle
                Accessible.editable: true
                KeyNavigation.tab: list
                KeyNavigation.backtab: cancelButton

                onTextChanged: pickerRoot.setPickerFilter(text)
                Keys.onReturnPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    if (pickerRoot.pickerHasMatch)
                        list.forceActiveFocus(Qt.TabFocusReason)
                    event.accepted = true
                }
            }
        }

        ListView {
            id: list

            objectName: "voicePickerList"
            width: searchFrame.implicitWidth
            height: pickerRoot.appearance.listHeight
            model: pickerRoot.headerModel ? pickerRoot.headerModel.pickerRows : pickerRoot.voiceModel.pickerRows
            clip: true
            focus: false
            activeFocusOnTab: true
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Voices")
            Accessible.description: qsTr("Click and hold to audition (middle C).")
            KeyNavigation.tab: pickerRoot.pickerHasMatch ? acceptButton : cancelButton
            KeyNavigation.backtab: search

            Connections {
                target: pickerRoot.model
                function onPickerIndexChanged(): void {
                    list.currentIndex = pickerRoot.currentPickerIndex()
                }
                function onPickerFilterChanged(): void {
                    if (list.currentIndex >= 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Center)
                }
            }

            onCurrentIndexChanged: {
                if (prompt.viewReady && currentIndex !== pickerRoot.currentPickerIndex())
                    pickerRoot.selectPickerRow(currentIndex)
            }

            Keys.onReturnPressed: (event) => {
                prompt.acceptDisplayed()
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                prompt.acceptDisplayed()
                event.accepted = true
            }
            Keys.onEscapePressed: (event) => {
                prompt.cancelDisplayed()
                event.accepted = true
            }

            highlight: Rectangle {
                color: prompt.appearance.pressedBackground
                radius: prompt.appearance.radius
            }

            delegate: Item {
                id: row

                required property int index
                required property int program
                required property string label

                objectName: "voicePickerRow_" + program
                width: list.width
                height: rowText.implicitHeight + 2 * prompt.appearance.verticalPadding
                Accessible.role: Accessible.ListItem
                Accessible.name: label
                Accessible.selected: ListView.isCurrentItem
                Accessible.onPressAction: pickerRoot.selectPickerRow(row.index)

                Text {
                    id: rowText

                    anchors.left: parent.left
                    anchors.leftMargin: prompt.appearance.horizontalPadding
                    anchors.right: parent.right
                    anchors.rightMargin: prompt.appearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem ? prompt.appearance.pressedText : prompt.appearance.text
                    font: prompt.appearance.font
                    text: row.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: {
                        list.currentIndex = row.index
                        pickerRoot.pressAndHoldPickerRow(row.index)
                    }
                    onReleased: pickerRoot.releasePickerAudition()
                    onCanceled: pickerRoot.releasePickerAudition()
                    onClicked: list.forceActiveFocus(Qt.MouseFocusReason)
                    onDoubleClicked: prompt.acceptDisplayed()
                }
            }

            Text {
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                text: qsTr("No matching voices")
                color: pickerRoot.appearance.text
                font: pickerRoot.appearance.font
                visible: !pickerRoot.pickerHasMatch
                renderType: Text.NativeRendering
            }
        }

        Row {
            spacing: pickerRoot.appearance.spacing

            PromptButton {
                id: acceptButton

                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: prompt.appearance
                text: qsTr("OK")
                enabled: pickerRoot.pickerHasMatch
                minimumWidth: cancelButton.labelWidth + 2 * pickerRoot.appearance.buttonPadding
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: list
                onActivated: prompt.acceptDisplayed()
            }

            PromptButton {
                id: cancelButton

                objectName: "voicePickerCancel"
                claimsShortcuts: false
                appearance: prompt.appearance
                text: qsTr("Cancel")
                minimumWidth: acceptButton.labelWidth + 2 * pickerRoot.appearance.buttonPadding
                KeyNavigation.tab: search
                KeyNavigation.backtab: pickerRoot.pickerHasMatch ? acceptButton : list
                onActivated: prompt.cancelDisplayed()
            }
        }
    }
}
