import QtQuick

Item {
    id: prompt

    required property var bridge

    objectName: "voicePickerPrompt"
    implicitWidth: Math.max(content.implicitWidth + 2 * bridge.voicePickerAppearance.dialogPadding,
                            bridge.voicePickerAppearance.minimumWidth)
    implicitHeight: content.implicitHeight + 2 * bridge.voicePickerAppearance.dialogPadding
    focus: true
    property bool viewReady: false

    function acceptDisplayed() {
        bridge.accept()
    }
    function cancelDisplayed() {
        bridge.cancel()
    }
    function activateInitialFocus() {
        search.forceActiveFocus(Qt.PopupFocusReason)
        if (bridge.currentRow >= 0) {
            list.currentIndex = bridge.currentRow
            list.positionViewAtIndex(bridge.currentRow, ListView.Center)
        }
        viewReady = true
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

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
    Accessible.name: bridge.voicePickerTitle

    Rectangle {
        anchors.fill: parent
        color: bridge.voicePickerAppearance.background
        border.width: bridge.voicePickerAppearance.borderWidth
        border.color: bridge.voicePickerAppearance.outline
        radius: bridge.voicePickerAppearance.radius
    }

    Column {
        id: content

        x: bridge.voicePickerAppearance.dialogPadding
        y: bridge.voicePickerAppearance.dialogPadding
        spacing: bridge.voicePickerAppearance.spacing

        Text {
            color: bridge.voicePickerAppearance.text
            font: bridge.voicePickerAppearance.font
            text: bridge.voicePickerTitle
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: searchFrame

            implicitWidth: Math.max(
                               bridge.voicePickerAppearance.minimumWidth
                               - 2 * bridge.voicePickerAppearance.dialogPadding,
                               Math.max(titleMetrics.advanceWidth(bridge.voicePickerTitle),
                                        searchMetrics.advanceWidth(searchHint.text))
                               + 2 * (bridge.voicePickerAppearance.horizontalPadding
                                      + bridge.voicePickerAppearance.borderWidth))
            implicitHeight: searchMetrics.height
                            + 2 * (bridge.voicePickerAppearance.verticalPadding
                                   + bridge.voicePickerAppearance.borderWidth)
            color: bridge.voicePickerAppearance.background
            border.width: bridge.voicePickerAppearance.borderWidth
            border.color: search.activeFocus ? bridge.voicePickerAppearance.focus
                                             : bridge.voicePickerAppearance.outline
            radius: bridge.voicePickerAppearance.radius

            FontMetrics {
                id: titleMetrics
                font: bridge.voicePickerAppearance.font
            }
            FontMetrics {
                id: searchMetrics
                font: bridge.voicePickerAppearance.font
            }

            Text {
                id: searchHint

                anchors.fill: parent
                anchors.leftMargin: bridge.voicePickerAppearance.horizontalPadding
                                    + bridge.voicePickerAppearance.borderWidth
                anchors.rightMargin: anchors.leftMargin
                verticalAlignment: Text.AlignVCenter
                color: bridge.voicePickerAppearance.outline
                font: bridge.voicePickerAppearance.font
                text: qsTr("Search voices...")
                visible: search.text.length === 0
                renderType: Text.NativeRendering
            }

            TextInput {
                id: search

                objectName: "voicePickerSearch"
                anchors.fill: parent
                clip: true
                color: bridge.voicePickerAppearance.text
                font: bridge.voicePickerAppearance.font
                padding: bridge.voicePickerAppearance.borderWidth
                leftPadding: bridge.voicePickerAppearance.horizontalPadding
                             + bridge.voicePickerAppearance.borderWidth
                rightPadding: leftPadding
                topPadding: bridge.voicePickerAppearance.verticalPadding
                            + bridge.voicePickerAppearance.borderWidth
                bottomPadding: topPadding
                selectionColor: bridge.voicePickerAppearance.focus
                selectedTextColor: bridge.voicePickerAppearance.text
                renderType: TextInput.NativeRendering
                activeFocusOnTab: true
                Accessible.role: Accessible.EditableText
                Accessible.name: searchHint.text
                Accessible.description: bridge.voicePickerTitle
                Accessible.editable: true
                KeyNavigation.tab: list
                KeyNavigation.backtab: cancelButton

                onTextChanged: bridge.filter = text
                Keys.onReturnPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    prompt.acceptDisplayed()
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    if (bridge.hasMatch)
                        list.forceActiveFocus(Qt.TabFocusReason)
                    event.accepted = true
                }
            }
        }

        ListView {
            id: list

            objectName: "voicePickerList"
            width: searchFrame.implicitWidth
            height: bridge.voicePickerAppearance.listHeight
            clip: true
            focus: false
            activeFocusOnTab: true
            model: bridge.voicePickerModel
            boundsBehavior: Flickable.StopAtBounds
            highlightFollowsCurrentItem: true
            highlightMoveDuration: 0
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Voices")
            Accessible.description: qsTr("Click and hold to audition (middle C).")
            KeyNavigation.tab: bridge.hasMatch ? acceptButton : cancelButton
            KeyNavigation.backtab: search

            Connections {
                target: bridge
                function onCurrentRowChanged() {
                    list.currentIndex = bridge.currentRow
                }
                function onFilterChanged() {
                    if (list.currentIndex >= 0)
                        list.positionViewAtIndex(list.currentIndex, ListView.Center)
                }
            }

            onCurrentIndexChanged: {
                if (prompt.viewReady && currentIndex !== bridge.currentRow)
                    bridge.selectRow(currentIndex)
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
                color: bridge.voicePickerAppearance.pressedBackground
                radius: bridge.voicePickerAppearance.radius
            }

            delegate: Item {
                id: row

                required property int index
                required property int program
                required property string label

                objectName: "voicePickerRow_" + program
                width: list.width
                height: rowText.implicitHeight
                        + 2 * bridge.voicePickerAppearance.verticalPadding
                Accessible.role: Accessible.ListItem
                Accessible.name: label
                Accessible.selected: ListView.isCurrentItem

                Text {
                    id: rowText

                    anchors.left: parent.left
                    anchors.leftMargin: bridge.voicePickerAppearance.horizontalPadding
                    anchors.right: parent.right
                    anchors.rightMargin: bridge.voicePickerAppearance.horizontalPadding
                    anchors.verticalCenter: parent.verticalCenter
                    color: row.ListView.isCurrentItem
                           ? bridge.voicePickerAppearance.pressedText
                           : bridge.voicePickerAppearance.text
                    font: bridge.voicePickerAppearance.font
                    text: label
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: {
                        list.currentIndex = row.index
                        bridge.pressAndHold(row.program)
                    }
                    onReleased: bridge.releaseHeld()
                    onCanceled: bridge.releaseHeld()
                    onClicked: list.forceActiveFocus(Qt.MouseFocusReason)
                    onDoubleClicked: prompt.acceptDisplayed()
                }
            }

            Text {
                anchors.centerIn: parent
                color: bridge.voicePickerAppearance.text
                font: bridge.voicePickerAppearance.font
                text: qsTr("No matching voices")
                visible: !bridge.hasMatch
                renderType: Text.NativeRendering
            }
        }

        Row {
            spacing: bridge.voicePickerAppearance.spacing

            Rectangle {
                id: acceptButton

                objectName: "voicePickerAccept"
                activeFocusOnTab: enabled
                enabled: bridge.hasMatch
                width: Math.max(acceptText.implicitWidth, cancelText.implicitWidth)
                       + 2 * bridge.voicePickerAppearance.buttonPadding
                height: acceptText.implicitHeight
                        + 2 * bridge.voicePickerAppearance.buttonPadding
                color: acceptTap.pressed ? bridge.voicePickerAppearance.pressedBackground
                                         : bridge.voicePickerAppearance.buttonBackground
                border.width: bridge.voicePickerAppearance.borderWidth
                border.color: activeFocus ? bridge.voicePickerAppearance.focus
                                          : bridge.voicePickerAppearance.outline
                radius: bridge.voicePickerAppearance.radius
                opacity: enabled ? 1 : 0.5
                Accessible.role: Accessible.Button
                Accessible.name: acceptText.text
                Accessible.focusable: enabled
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: list
                Accessible.onPressAction: acceptButton.activate()

                function activate() {
                    if (enabled)
                        prompt.acceptDisplayed()
                }

                Text {
                    id: acceptText

                    anchors.centerIn: parent
                    color: bridge.voicePickerAppearance.buttonText
                    font: bridge.voicePickerAppearance.font
                    text: qsTr("OK")
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: (event) => {
                    acceptButton.activate()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    acceptButton.activate()
                    event.accepted = true
                }
                Keys.onSpacePressed: (event) => {
                    acceptButton.activate()
                    event.accepted = true
                }

                TapHandler {
                    id: acceptTap
                    onTapped: acceptButton.activate()
                }
            }

            Rectangle {
                id: cancelButton

                objectName: "voicePickerCancel"
                activeFocusOnTab: true
                width: Math.max(acceptText.implicitWidth, cancelText.implicitWidth)
                       + 2 * bridge.voicePickerAppearance.buttonPadding
                height: cancelText.implicitHeight
                        + 2 * bridge.voicePickerAppearance.buttonPadding
                color: cancelTap.pressed ? bridge.voicePickerAppearance.pressedBackground
                                         : bridge.voicePickerAppearance.buttonBackground
                border.width: bridge.voicePickerAppearance.borderWidth
                border.color: activeFocus ? bridge.voicePickerAppearance.focus
                                          : bridge.voicePickerAppearance.outline
                radius: bridge.voicePickerAppearance.radius
                Accessible.role: Accessible.Button
                Accessible.name: cancelText.text
                Accessible.focusable: true
                Accessible.onPressAction: cancelButton.activate()
                KeyNavigation.tab: search
                KeyNavigation.backtab: bridge.hasMatch ? acceptButton : list

                function activate() {
                    prompt.cancelDisplayed()
                }

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    color: bridge.voicePickerAppearance.buttonText
                    font: bridge.voicePickerAppearance.font
                    text: qsTr("Cancel")
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: (event) => {
                    cancelButton.activate()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    cancelButton.activate()
                    event.accepted = true
                }
                Keys.onSpacePressed: (event) => {
                    cancelButton.activate()
                    event.accepted = true
                }

                TapHandler {
                    id: cancelTap
                    onTapped: cancelButton.activate()
                }
            }
        }
    }
}
