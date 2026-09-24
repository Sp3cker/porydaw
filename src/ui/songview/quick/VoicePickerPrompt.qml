pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

FocusScope {
    id: pickerRoot
    objectName: "voicePicker"
    required property var model
    required property var promptPalette
    property var pageItem: null
    property var hintService: null
    property bool showing: false
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing
    onShowingChanged: {
        if (showing)
            Qt.callLater(prompt.activateInitialFocus)
        else {
            model.releasePickerAudition()
            closed()
        }
    }
    Component.onDestruction: model.releasePickerAudition()
    Keys.onShortcutOverride: event => {
        event.accepted = event.key !== Qt.Key_Space || search.activeFocus
    }
    MouseArea {
        objectName: "voicePickerUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: pickerRoot.model.cancelPicker()
    }

    PromptCard {
        id: prompt

        objectName: "voicePickerCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: Object.assign({}, pickerRoot.model.promptAppearance, {
            font: Qt.font(pickerRoot.model.promptFont),
            background: pickerRoot.promptPalette?.windowBackground ?? "transparent",
            outline: pickerRoot.promptPalette?.outline ?? "transparent",
            text: pickerRoot.promptPalette?.windowText ?? "transparent",
            focus: pickerRoot.promptPalette?.focusOutline ?? "transparent",
            buttonBackground: pickerRoot.promptPalette?.buttonBackground ?? "transparent",
            buttonText: pickerRoot.promptPalette?.buttonText ?? "transparent",
            pressedBackground: pickerRoot.promptPalette?.buttonPressedBackground ?? "transparent",
            pressedText: pickerRoot.promptPalette?.buttonPressedText ?? "transparent",
            // Search-hint ink: placeholderText is the legible hint ink on the
            // window surface; outline is a line color and fails as text.
            placeholderText: pickerRoot.promptPalette?.placeholderText ?? "transparent",
            disabledText: pickerRoot.promptPalette?.disabledText ?? "transparent",
            selection: pickerRoot.promptPalette?.tabSelectedBackground ?? "transparent",
            selectionText: pickerRoot.promptPalette?.selectionText ?? "transparent"
        })
        minimumWidth: prompt.appearance.minimumWidth
        property bool viewReady: false
        MouseArea {
            parent: prompt
            anchors.fill: parent
            z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        }

        function acceptDisplayed() {
            pickerRoot.model.acceptPicker()
        }
        function cancelDisplayed() {
            pickerRoot.model.cancelPicker()
        }
        function activateInitialFocus() {
            search.forceActiveFocus(Qt.PopupFocusReason)
            if (pickerRoot.model.pickerIndex >= 0) {
                list.currentIndex = pickerRoot.model.pickerIndex
                list.positionViewAtIndex(pickerRoot.model.pickerIndex, ListView.Center)
            }
            viewReady = true
        }

        Component.onCompleted: if (pickerRoot.showing) Qt.callLater(activateInitialFocus)

        // No declined key may escape the shared popup session into timeline
        // routing. TextInput and ListView receive their own editing/navigation
        // keys before this terminal sink.
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                cancelDisplayed()
            event.accepted = true
        }
        Keys.onReleased: (event) => event.accepted = true

        Accessible.role: Accessible.Client
        Accessible.name: pickerRoot.model.pickerTitle

        Text {
            objectName: "voicePickerTitle"
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: pickerRoot.model.pickerTitle
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: searchFrame
            objectName: "voicePickerSearchFrame"

            implicitWidth: Math.max(
                               prompt.appearance.minimumWidth - 2 * prompt.appearance.dialogPadding,
                               Math.max(titleMetrics.advanceWidth(pickerRoot.model.pickerTitle),
                                        searchMetrics.advanceWidth(searchHint.text))
                               + 2 * (prompt.appearance.horizontalPadding + prompt.appearance.borderWidth))
            implicitHeight: searchMetrics.height
                            + 2 * (prompt.appearance.verticalPadding + prompt.appearance.borderWidth)
            color: prompt.appearance.background
            border.width: prompt.appearance.borderWidth
            border.color: search.activeFocus ? prompt.appearance.focus : prompt.appearance.outline
            radius: prompt.appearance.radius

            FontMetrics {
                id: titleMetrics
                font: prompt.appearance.font
            }
            FontMetrics {
                id: searchMetrics
                font: prompt.appearance.font
            }

            Text {
                id: searchHint
                objectName: "voicePickerSearchHint"

                anchors.fill: parent
                anchors.leftMargin: prompt.appearance.horizontalPadding + prompt.appearance.borderWidth
                anchors.rightMargin: anchors.leftMargin
                verticalAlignment: Text.AlignVCenter
                color: prompt.appearance.placeholderText
                font: prompt.appearance.font
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
                color: prompt.appearance.text
                font: prompt.appearance.font
                padding: prompt.appearance.borderWidth
                leftPadding: prompt.appearance.horizontalPadding + prompt.appearance.borderWidth
                rightPadding: leftPadding
                topPadding: prompt.appearance.verticalPadding + prompt.appearance.borderWidth
                bottomPadding: topPadding
                selectionColor: prompt.appearance.selection ?? prompt.appearance.focus
                selectedTextColor: prompt.appearance.selectionText ?? prompt.appearance.text
                renderType: TextInput.NativeRendering
                activeFocusOnTab: true
                selectByMouse: true
                text: pickerRoot.model.pickerFilter
                Accessible.role: Accessible.EditableText
                Accessible.name: searchHint.text
                Accessible.description: pickerRoot.model.pickerTitle
                Accessible.editable: true
                KeyNavigation.tab: list
                KeyNavigation.backtab: cancelButton

                onTextChanged: pickerRoot.model.setPickerFilter(text)
                Keys.onReturnPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    if (pickerRoot.model.pickerHasMatch)
                        list.forceActiveFocus(Qt.TabFocusReason)
                    event.accepted = true
                }
            }
        }

        ListView {
            id: list

            objectName: "voicePickerList"
            width: searchFrame.implicitWidth
            height: prompt.appearance.listHeight
            clip: true
            focus: false
            activeFocusOnTab: true
            model: pickerRoot.model.pickerRows
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Voices")
            Accessible.description: qsTr("Click and hold to audition (middle C).")
            KeyNavigation.tab: pickerRoot.model.pickerHasMatch ? acceptButton : cancelButton
            KeyNavigation.backtab: search

            Connections {
                target: pickerRoot.model
                function onPickerIndexChanged() {
                    list.currentIndex = pickerRoot.model.pickerIndex
                }
                function onPickerFilterChanged() {
                    if (list.currentIndex >= 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Center)
                }
            }

            onCurrentIndexChanged: {
                if (prompt.viewReady && currentIndex !== pickerRoot.model.pickerIndex)
                    pickerRoot.model.selectPickerRow(currentIndex)
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
                required property var model
                readonly property int program: model.program
                readonly property string label: model.label

                objectName: "voicePickerRow_" + program
                width: list.width
                height: rowText.implicitHeight + 2 * prompt.appearance.verticalPadding
                Accessible.role: Accessible.ListItem
                Accessible.name: label
                Accessible.selected: ListView.isCurrentItem
                Accessible.onPressAction: pickerRoot.model.selectPickerRow(row.index)

                Text {
                    id: rowText

                    anchors.left: parent.left
                    anchors.leftMargin: prompt.appearance.horizontalPadding
                    anchors.right: parent.right
                    anchors.rightMargin: prompt.appearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem ? prompt.appearance.pressedText : prompt.appearance.text
                    font: prompt.appearance.font
                    text: label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: {
                        list.currentIndex = row.index
                        pickerRoot.model.pressAndHoldPickerRow(row.index)
                    }
                    onReleased: pickerRoot.model.releasePickerAudition()
                    onCanceled: pickerRoot.model.releasePickerAudition()
                    onClicked: list.forceActiveFocus(Qt.MouseFocusReason)
                    onDoubleClicked: prompt.acceptDisplayed()
                }
            }

            Text {
                objectName: "voicePickerEmptyText"
                anchors.centerIn: parent
                color: prompt.appearance.text
                font: prompt.appearance.font
                text: qsTr("No matching voices")
                visible: !pickerRoot.model.pickerHasMatch
                renderType: Text.NativeRendering
            }
        }

        Row {
            spacing: prompt.appearance.spacing

            PromptButton {
                id: acceptButton

                objectName: "voicePickerAccept"
                claimsShortcuts: false
                appearance: prompt.appearance
                text: qsTr("OK")
                enabled: pickerRoot.model.pickerHasMatch
                minimumWidth: cancelButton.labelWidth + 2 * prompt.appearance.buttonPadding
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
                minimumWidth: acceptButton.labelWidth + 2 * prompt.appearance.buttonPadding
                KeyNavigation.tab: search
                KeyNavigation.backtab: pickerRoot.model.pickerHasMatch ? acceptButton : list
                onActivated: prompt.cancelDisplayed()
            }
        }
    }
}
