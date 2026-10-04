pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

FocusScope {
    id: pickerRoot
    objectName: "voicePicker"
    required final property var model
    final property Item pageItem: null
    final property App.MouseHints hintService: null
    final readonly property App.HeaderVoicePicker headerModel: model as App.HeaderVoicePicker
    final readonly property App.VoiceChangesPage voiceModel: model as App.VoiceChangesPage
    final property App.PromptStyle appearance: headerModel
        ? headerModel.promptStyle : voiceModel ? voiceModel.promptStyle : null
    final property string pickerTitle
    final property string pickerFilter
    final property int pickerIndex
    final property bool pickerHasMatch

    Binding {
        when: pickerRoot.headerModel !== null || pickerRoot.voiceModel !== null
        restoreMode: Binding.RestoreNone
        pickerRoot.pickerTitle: pickerRoot.headerModel ? pickerRoot.headerModel?.pickerTitle : pickerRoot.voiceModel?.pickerTitle
        pickerRoot.pickerFilter: pickerRoot.headerModel ? pickerRoot.headerModel?.pickerFilter : pickerRoot.voiceModel?.pickerFilter
        pickerRoot.pickerIndex: pickerRoot.headerModel ? pickerRoot.headerModel?.pickerIndex : pickerRoot.voiceModel?.pickerIndex
        pickerRoot.pickerHasMatch: pickerRoot.headerModel ? pickerRoot.headerModel?.pickerHasMatch : pickerRoot.voiceModel?.pickerHasMatch
        list.model: pickerRoot.headerModel ? pickerRoot.headerModel?.pickerRows : pickerRoot.voiceModel?.pickerRows
    }

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
    visible: showing
    enabled: showing
    onShowingChanged: {
        if (showing)
            Qt.callLater(prompt.activateInitialFocus)
        else {
            releasePickerAudition()
            closed()
        }
    }
    Component.onDestruction: releasePickerAudition()
    Keys.onShortcutOverride: event => {
        event.accepted = event.key !== Qt.Key_Space || search.activeFocus
    }
    MouseArea {
        objectName: "voicePickerUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: pickerRoot.cancelPicker()
    }

    PromptCard {
        id: prompt

        objectName: "voicePickerCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: pickerRoot.appearance
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

        Component.onCompleted: if (pickerRoot.showing) Qt.callLater(activateInitialFocus)

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
            id: title
            objectName: "voicePickerTitle"
            text: pickerRoot.pickerTitle
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"


            FontMetrics {
                id: titleMetrics
            }
            FontMetrics {
                id: searchMetrics
            }

            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"

                anchors.fill: parent
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
                id: emptyText
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                text: qsTr("No matching voices")
                visible: !pickerRoot.pickerHasMatch
                renderType: Text.NativeRendering
            }
        }

        Row {
            id: buttons

            PromptButton {
                id: acceptButton

                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: prompt.appearance
                text: qsTr("OK")
                enabled: pickerRoot.pickerHasMatch
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
                KeyNavigation.tab: search
                KeyNavigation.backtab: pickerRoot.pickerHasMatch ? acceptButton : list
                onActivated: prompt.cancelDisplayed()
            }
        }
    }

    Binding {
        when: pickerRoot.appearance !== null
        restoreMode: Binding.RestoreNone
        prompt.minimumWidth: pickerRoot.appearance?.minimumWidth
        title.color: pickerRoot.appearance?.text
        title.font: pickerRoot.appearance?.font
        searchFrame.implicitWidth: Math.max(
            pickerRoot.appearance?.minimumWidth - 2 * pickerRoot.appearance?.dialogPadding,
            Math.max(titleMetrics.advanceWidth(pickerRoot.pickerTitle), searchMetrics.advanceWidth(searchHint.text))
            + 2 * (pickerRoot.appearance?.horizontalPadding + pickerRoot.appearance?.borderWidth))
        searchFrame.implicitHeight: searchMetrics.height
            + 2 * (pickerRoot.appearance?.verticalPadding + pickerRoot.appearance?.borderWidth)
        searchFrame.color: pickerRoot.appearance?.background
        searchFrame.border.width: pickerRoot.appearance?.borderWidth
        searchFrame.border.color: search.activeFocus ? pickerRoot.appearance?.focus : pickerRoot.appearance?.outline
        searchFrame.radius: pickerRoot.appearance?.radius
        titleMetrics.font: pickerRoot.appearance?.font
        searchMetrics.font: pickerRoot.appearance?.font
        searchHint.anchors.leftMargin: pickerRoot.appearance?.horizontalPadding + pickerRoot.appearance?.borderWidth
        searchHint.color: pickerRoot.appearance?.placeholderText
        searchHint.font: pickerRoot.appearance?.font
        search.color: pickerRoot.appearance?.text
        search.font: pickerRoot.appearance?.font
        search.padding: pickerRoot.appearance?.borderWidth
        search.leftPadding: pickerRoot.appearance?.horizontalPadding + pickerRoot.appearance?.borderWidth
        search.topPadding: pickerRoot.appearance?.verticalPadding + pickerRoot.appearance?.borderWidth
        search.selectionColor: pickerRoot.appearance?.selection
        search.selectedTextColor: pickerRoot.appearance?.selectionText
        list.height: pickerRoot.appearance?.listHeight
        emptyText.color: pickerRoot.appearance?.text
        emptyText.font: pickerRoot.appearance?.font
        buttons.spacing: pickerRoot.appearance?.spacing
        acceptButton.minimumWidth: cancelButton.labelWidth + 2 * pickerRoot.appearance?.buttonPadding
        cancelButton.minimumWidth: acceptButton.labelWidth + 2 * pickerRoot.appearance?.buttonPadding
    }
}
