import QtQuick

PromptCard {
    id: prompt

    required property var bridge

    objectName: "voicePickerPrompt"
    appearance: bridge.voicePickerAppearance
    minimumWidth: bridge.voicePickerAppearance.minimumWidth
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

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.voicePickerTitle
        renderType: Text.NativeRendering
    }

    Rectangle {
        id: searchFrame

        implicitWidth: Math.max(
                           appearance.minimumWidth - 2 * appearance.dialogPadding,
                           Math.max(titleMetrics.advanceWidth(bridge.voicePickerTitle),
                                    searchMetrics.advanceWidth(searchHint.text))
                           + 2 * (appearance.horizontalPadding + appearance.borderWidth))
        implicitHeight: searchMetrics.height
                        + 2 * (appearance.verticalPadding + appearance.borderWidth)
        color: appearance.background
        border.width: appearance.borderWidth
        border.color: search.activeFocus ? appearance.focus : appearance.outline
        radius: appearance.radius

        FontMetrics {
            id: titleMetrics
            font: appearance.font
        }
        FontMetrics {
            id: searchMetrics
            font: appearance.font
        }

        Text {
            id: searchHint

            anchors.fill: parent
            anchors.leftMargin: appearance.horizontalPadding + appearance.borderWidth
            anchors.rightMargin: anchors.leftMargin
            verticalAlignment: Text.AlignVCenter
            color: appearance.outline
            font: appearance.font
            text: qsTr("Search voices...")
            visible: search.text.length === 0
            renderType: Text.NativeRendering
        }

        TextInput {
            id: search

            objectName: "voicePickerSearch"
            HoverHandler {
                cursorShape: Qt.IBeamCursor
            }
            anchors.fill: parent
            clip: true
            color: appearance.text
            font: appearance.font
            padding: appearance.borderWidth
            leftPadding: appearance.horizontalPadding + appearance.borderWidth
            rightPadding: leftPadding
            topPadding: appearance.verticalPadding + appearance.borderWidth
            bottomPadding: topPadding
            selectionColor: appearance.focus
            selectedTextColor: appearance.text
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
        height: appearance.listHeight
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
            color: appearance.pressedBackground
            radius: appearance.radius
        }

        delegate: Item {
            id: row

            required property int index
            required property int program
            required property string label

            objectName: "voicePickerRow_" + program
            width: list.width
            height: rowText.implicitHeight + 2 * appearance.verticalPadding
            Accessible.role: Accessible.ListItem
            Accessible.name: label
            Accessible.selected: ListView.isCurrentItem

            Text {
                id: rowText

                anchors.left: parent.left
                anchors.leftMargin: appearance.horizontalPadding
                anchors.right: parent.right
                anchors.rightMargin: appearance.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                color: row.ListView.isCurrentItem ? appearance.pressedText : appearance.text
                font: appearance.font
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
            color: appearance.text
            font: appearance.font
            text: qsTr("No matching voices")
            visible: !bridge.hasMatch
            renderType: Text.NativeRendering
        }
    }

    Row {
        spacing: appearance.spacing

        PromptButton {
            id: acceptButton

            objectName: "voicePickerAccept"
            claimsShortcuts: false
            appearance: prompt.appearance
            text: qsTr("OK")
            enabled: bridge.hasMatch
            minimumWidth: cancelButton.labelWidth + 2 * appearance.buttonPadding
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
            minimumWidth: acceptButton.labelWidth + 2 * appearance.buttonPadding
            KeyNavigation.tab: search
            KeyNavigation.backtab: bridge.hasMatch ? acceptButton : list
            onActivated: prompt.cancelDisplayed()
        }
    }
}
