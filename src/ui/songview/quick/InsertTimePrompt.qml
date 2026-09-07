import QtQuick

Item {
    id: prompt

    required property var bridge

    objectName: "insertTimePrompt"
    implicitWidth: content.implicitWidth + 2 * bridge.insertTimePromptAppearance.dialogPadding
    implicitHeight: content.implicitHeight + 2 * bridge.insertTimePromptAppearance.dialogPadding
    focus: true

    property int draftBars: bridge.insertTimePromptInitialBars
    property int draftBeats: bridge.insertTimePromptInitialBeats
    property int draftBeatFractions: bridge.insertTimePromptInitialBeatFractions
    property bool finishing: false

    readonly property real labelWidth: Math.max(labelMetrics.advanceWidth(qsTr("Bars:")),
                                                labelMetrics.advanceWidth(qsTr("Beats:")),
                                                labelMetrics.advanceWidth(qsTr("Beat fractions (¼ beat):")))
    readonly property real inputWidth: Math.max(barsInput.implicitWidth, beatsInput.implicitWidth,
                                                fractionsInput.implicitWidth)

    FontMetrics {
        id: labelMetrics

        font: bridge.insertTimePromptAppearance.font
    }
    function acceptDisplayed() {
        acceptCommittedDrafts(barsInput.commitDisplayed(), beatsInput.commitDisplayed(),
                              fractionsInput.commitDisplayed())
    }

    function acceptFromEditing(field, committed) {
        acceptCommittedDrafts(field === "bars" ? committed : barsInput.commitDisplayed(),
                              field === "beats" ? committed : beatsInput.commitDisplayed(),
                              field === "fractions" ? committed : fractionsInput.commitDisplayed())
    }

    function acceptCommittedDrafts(bars, beats, fractions) {
        if (bars !== null && beats !== null && fractions !== null)
            acceptCommitted(bars, beats, fractions)
    }

    function acceptCommitted(bars, beats, fractions) {
        if (finishing)
            return
        finishing = true
        bridge.acceptInsertTimePrompt(bars, beats, fractions)
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelInsertTimePrompt()
    }

    function activateInitialFocus() {
        barsInput.focusInput(Qt.PopupFocusReason)
        barsInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // The focused DragInput receives normal numeric editing first. This
    // terminal sink claims declined keys so timeline commands never leak out
    // of the shared popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            acceptDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.insertTimePromptTitle

    Rectangle {
        anchors.fill: parent
        color: bridge.insertTimePromptAppearance.background
        border.width: bridge.insertTimePromptAppearance.borderWidth
        border.color: bridge.insertTimePromptAppearance.outline
        radius: bridge.insertTimePromptAppearance.radius
    }

    Column {
        id: content

        x: bridge.insertTimePromptAppearance.dialogPadding
        y: bridge.insertTimePromptAppearance.dialogPadding
        spacing: bridge.insertTimePromptAppearance.spacing

        Text {
            color: bridge.insertTimePromptAppearance.text
            font: bridge.insertTimePromptAppearance.font
            text: bridge.insertTimePromptTitle
            renderType: Text.NativeRendering
        }

        Row {
            spacing: bridge.insertTimePromptAppearance.spacing

            Text {
                anchors.verticalCenter: barsInput.verticalCenter
                width: prompt.labelWidth
                horizontalAlignment: Text.AlignRight
                color: bridge.insertTimePromptAppearance.text
                font: bridge.insertTimePromptAppearance.font
                text: qsTr("Bars:")
                renderType: Text.NativeRendering
            }

            DragInput {
                id: barsInput

                appearance: bridge.insertTimePromptAppearance
                value: prompt.draftBars
                width: prompt.inputWidth
                minimumValue: bridge.insertTimePromptMinimumBars
                maximumValue: bridge.insertTimePromptMaximumBars
                inputObjectName: "insertTimeBars"
                accessibleName: qsTr("Bars")
                accessibleDescription: bridge.insertTimePromptTitle
                onValueCommitted: (committed) => prompt.draftBars = committed
                onEditingAccepted: (committed) => prompt.acceptFromEditing("bars", committed)
                textInput.KeyNavigation.backtab: cancelButton
            }
        }

        Row {
            spacing: bridge.insertTimePromptAppearance.spacing

            Text {
                anchors.verticalCenter: beatsInput.verticalCenter
                width: prompt.labelWidth
                horizontalAlignment: Text.AlignRight
                color: bridge.insertTimePromptAppearance.text
                font: bridge.insertTimePromptAppearance.font
                text: qsTr("Beats:")
                renderType: Text.NativeRendering
            }

            DragInput {
                id: beatsInput

                appearance: bridge.insertTimePromptAppearance
                value: prompt.draftBeats
                width: prompt.inputWidth
                minimumValue: bridge.insertTimePromptMinimumBeats
                maximumValue: bridge.insertTimePromptMaximumBeats
                inputObjectName: "insertTimeBeats"
                accessibleName: qsTr("Beats")
                accessibleDescription: bridge.insertTimePromptTitle
                onValueCommitted: (committed) => prompt.draftBeats = committed
                onEditingAccepted: (committed) => prompt.acceptFromEditing("beats", committed)
            }
        }

        Row {
            spacing: bridge.insertTimePromptAppearance.spacing

            Text {
                anchors.verticalCenter: fractionsInput.verticalCenter
                width: prompt.labelWidth
                horizontalAlignment: Text.AlignRight
                color: bridge.insertTimePromptAppearance.text
                font: bridge.insertTimePromptAppearance.font
                text: qsTr("Beat fractions (¼ beat):")
                renderType: Text.NativeRendering
            }

            DragInput {
                id: fractionsInput

                appearance: bridge.insertTimePromptAppearance
                value: prompt.draftBeatFractions
                width: prompt.inputWidth
                minimumValue: bridge.insertTimePromptMinimumBeatFractions
                maximumValue: bridge.insertTimePromptMaximumBeatFractions
                inputObjectName: "insertTimeBeatFractions"
                accessibleName: qsTr("Beat fractions")
                accessibleDescription: bridge.insertTimePromptTitle
                onValueCommitted: (committed) => prompt.draftBeatFractions = committed
                onEditingAccepted: (committed) => prompt.acceptFromEditing("fractions", committed)
            }
        }

        Row {
            spacing: bridge.insertTimePromptAppearance.spacing

            Rectangle {
                id: acceptButton

                objectName: "insertTimeAccept"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: acceptText.text
                function activate() {
                    prompt.acceptDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }

                width: Math.max(acceptText.implicitWidth
                                + 2 * bridge.insertTimePromptAppearance.buttonPadding,
                                barsInput.implicitWidth)
                height: acceptText.implicitHeight
                        + 2 * bridge.insertTimePromptAppearance.buttonPadding
                color: acceptTap.pressed ? bridge.insertTimePromptAppearance.pressedBackground
                                         : bridge.insertTimePromptAppearance.buttonBackground
                border.width: bridge.insertTimePromptAppearance.borderWidth
                border.color: activeFocus ? bridge.insertTimePromptAppearance.focus
                                          : bridge.insertTimePromptAppearance.outline
                radius: bridge.insertTimePromptAppearance.radius

                Text {
                    id: acceptText

                    anchors.centerIn: parent
                    color: bridge.insertTimePromptAppearance.buttonText
                    font: bridge.insertTimePromptAppearance.font
                    text: qsTr("OK")
                    renderType: Text.NativeRendering
                }
                Keys.onReturnPressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onEnterPressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onSpacePressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Space || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter

                Accessible.focusable: true
                Accessible.onPressAction: acceptButton.activate()

                TapHandler {
                    id: acceptTap

                    onTapped: acceptButton.activate()
                }
            }

            Rectangle {
                id: cancelButton

                objectName: "insertTimeCancel"
                activeFocusOnTab: true
                KeyNavigation.tab: barsInput.textInput
                Accessible.role: Accessible.Button
                Accessible.name: cancelText.text
                function activate() {
                    prompt.cancelDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }

                width: Math.max(cancelText.implicitWidth
                                + 2 * bridge.insertTimePromptAppearance.buttonPadding,
                                barsInput.implicitWidth)
                height: cancelText.implicitHeight
                        + 2 * bridge.insertTimePromptAppearance.buttonPadding
                color: cancelTap.pressed ? bridge.insertTimePromptAppearance.pressedBackground
                                         : bridge.insertTimePromptAppearance.buttonBackground
                border.width: bridge.insertTimePromptAppearance.borderWidth
                border.color: activeFocus ? bridge.insertTimePromptAppearance.focus
                                          : bridge.insertTimePromptAppearance.outline
                radius: bridge.insertTimePromptAppearance.radius

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    color: bridge.insertTimePromptAppearance.buttonText
                    font: bridge.insertTimePromptAppearance.font
                    text: qsTr("Cancel")
                    renderType: Text.NativeRendering
                }
                Keys.onReturnPressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onEnterPressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onSpacePressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Space || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter

                Accessible.focusable: true
                Accessible.onPressAction: cancelButton.activate()

                TapHandler {
                    id: cancelTap

                    onTapped: cancelButton.activate()
                }
            }
        }
    }
}
