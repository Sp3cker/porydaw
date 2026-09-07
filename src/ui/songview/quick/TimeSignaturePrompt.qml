import QtQuick

Item {
    id: prompt

    required property var bridge

    objectName: "timeSignaturePrompt"
    implicitWidth: content.implicitWidth + 2 * bridge.timeSigPromptAppearance.dialogPadding
    implicitHeight: content.implicitHeight + 2 * bridge.timeSigPromptAppearance.dialogPadding
    focus: true

    property int draftNumerator: bridge.timeSigPromptInitialNumerator
    property int draftDenominatorPow2: bridge.timeSigPromptInitialDenominatorPow2
    property bool finishing: false

    function acceptDisplayed() {
        const numerator = numeratorInput.commitDisplayed()
        if (numerator !== null)
            acceptCommitted(numerator)
    }

    function acceptCommitted(numerator) {
        if (finishing)
            return
        finishing = true
        bridge.acceptTimeSigPrompt(numerator, draftDenominatorPow2)
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelTimeSigPrompt()
    }

    function moveDenominator(from, step) {
        const exponent = Math.max(bridge.timeSigPromptMinimumDenominatorPow2,
                                  Math.min(bridge.timeSigPromptMaximumDenominatorPow2, from + step))
        draftDenominatorPow2 = exponent
        const button = denominatorRepeater.itemAt(exponent)
        if (button)
            button.forceActiveFocus(Qt.OtherFocusReason)
    }

    function activateInitialFocus() {
        numeratorInput.focusInput(Qt.PopupFocusReason)
        numeratorInput.selectAll()
    }

    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // The focused DragInput receives normal numeric editing first. This
    // terminal sink claims declined keys so timeline commands never leak out
    // of the shared popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.timeSigPromptTitle

    Rectangle {
        anchors.fill: parent
        color: bridge.timeSigPromptAppearance.background
        border.width: bridge.timeSigPromptAppearance.borderWidth
        border.color: bridge.timeSigPromptAppearance.outline
        radius: bridge.timeSigPromptAppearance.radius
    }

    Column {
        id: content

        x: bridge.timeSigPromptAppearance.dialogPadding
        y: bridge.timeSigPromptAppearance.dialogPadding
        spacing: bridge.timeSigPromptAppearance.spacing

        Text {
            color: bridge.timeSigPromptAppearance.text
            font: bridge.timeSigPromptAppearance.font
            text: bridge.timeSigPromptTitle
            renderType: Text.NativeRendering
        }

        Text {
            color: bridge.timeSigPromptAppearance.text
            font: bridge.timeSigPromptAppearance.font
            text: bridge.timeSigPromptLabel
            renderType: Text.NativeRendering
        }

        DragInput {
            id: numeratorInput

            appearance: bridge.timeSigPromptAppearance
            value: prompt.draftNumerator
            minimumValue: bridge.timeSigPromptMinimumNumerator
            maximumValue: bridge.timeSigPromptMaximumNumerator
            inputObjectName: "timeSignatureNumerator"
            accessibleName: bridge.timeSigPromptLabel
            accessibleDescription: bridge.timeSigPromptTitle
            onValueCommitted: (committed) => prompt.draftNumerator = committed
            onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
            textInput.KeyNavigation.backtab: cancelButton
        }

        Text {
            color: bridge.timeSigPromptAppearance.text
            font: bridge.timeSigPromptAppearance.font
            text: qsTr("Denominator:")
            renderType: Text.NativeRendering
        }

        Row {
            spacing: bridge.timeSigPromptAppearance.spacing

            Repeater {
                id: denominatorRepeater
                model: [0, 1, 2, 3, 4, 5]

                delegate: Rectangle {
                    id: denominatorButton

                    required property int modelData

                    objectName: "timeSignatureDenominator" + modelData
                    activeFocusOnTab: selected
                    readonly property bool selected: prompt.draftDenominatorPow2 === modelData
                    function select() {
                        prompt.draftDenominatorPow2 = modelData
                    }
                    function activate() {
                        select()
                        forceActiveFocus(Qt.MouseFocusReason)
                    }
                    function selectFromKeyboard(event) {
                        select()
                        event.accepted = true
                    }
                    function acceptFromKeyboard(event) {
                        select()
                        prompt.acceptDisplayed()
                        event.accepted = true
                    }
                    function moveBy(step, event) {
                        prompt.moveDenominator(modelData, step)
                        event.accepted = true
                    }

                    width: denominatorText.implicitWidth
                           + 2 * bridge.timeSigPromptAppearance.buttonPadding
                    height: denominatorText.implicitHeight
                            + 2 * bridge.timeSigPromptAppearance.buttonPadding
                    color: denominatorTap.pressed || selected
                           ? bridge.timeSigPromptAppearance.pressedBackground
                           : bridge.timeSigPromptAppearance.buttonBackground
                    border.width: bridge.timeSigPromptAppearance.borderWidth
                    border.color: activeFocus ? bridge.timeSigPromptAppearance.focus
                                              : bridge.timeSigPromptAppearance.outline
                    radius: bridge.timeSigPromptAppearance.radius

                    Text {
                        id: denominatorText

                        anchors.centerIn: parent
                        color: bridge.timeSigPromptAppearance.buttonText
                        font: bridge.timeSigPromptAppearance.font
                        text: String(1 << denominatorButton.modelData)
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: (event) => denominatorButton.acceptFromKeyboard(event)
                    Keys.onEnterPressed: (event) => denominatorButton.acceptFromKeyboard(event)
                    Keys.onSpacePressed: (event) => denominatorButton.selectFromKeyboard(event)
                    Keys.onLeftPressed: (event) => denominatorButton.moveBy(-1, event)
                    Keys.onRightPressed: (event) => denominatorButton.moveBy(1, event)
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Space || event.key === Qt.Key_Return
                        || event.key === Qt.Key_Enter

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: denominatorText.text
                    Accessible.checked: selected
                    Accessible.focusable: true
                    Accessible.onPressAction: denominatorButton.activate()

                    TapHandler {
                        id: denominatorTap

                        onTapped: denominatorButton.activate()
                    }
                }
            }
        }

        Row {
            spacing: bridge.timeSigPromptAppearance.spacing

            Rectangle {
                id: acceptButton

                objectName: "timeSignatureAccept"
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
                                + 2 * bridge.timeSigPromptAppearance.buttonPadding,
                                numeratorInput.implicitWidth)
                height: acceptText.implicitHeight
                        + 2 * bridge.timeSigPromptAppearance.buttonPadding
                color: acceptTap.pressed ? bridge.timeSigPromptAppearance.pressedBackground
                                         : bridge.timeSigPromptAppearance.buttonBackground
                border.width: bridge.timeSigPromptAppearance.borderWidth
                border.color: activeFocus ? bridge.timeSigPromptAppearance.focus
                                          : bridge.timeSigPromptAppearance.outline
                radius: bridge.timeSigPromptAppearance.radius

                Text {
                    id: acceptText

                    anchors.centerIn: parent
                    color: bridge.timeSigPromptAppearance.buttonText
                    font: bridge.timeSigPromptAppearance.font
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

                objectName: "timeSignatureCancel"
                activeFocusOnTab: true
                KeyNavigation.tab: numeratorInput.textInput
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
                                + 2 * bridge.timeSigPromptAppearance.buttonPadding,
                                numeratorInput.implicitWidth)
                height: cancelText.implicitHeight
                        + 2 * bridge.timeSigPromptAppearance.buttonPadding
                color: cancelTap.pressed ? bridge.timeSigPromptAppearance.pressedBackground
                                         : bridge.timeSigPromptAppearance.buttonBackground
                border.width: bridge.timeSigPromptAppearance.borderWidth
                border.color: activeFocus ? bridge.timeSigPromptAppearance.focus
                                          : bridge.timeSigPromptAppearance.outline
                radius: bridge.timeSigPromptAppearance.radius

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    color: bridge.timeSigPromptAppearance.buttonText
                    font: bridge.timeSigPromptAppearance.font
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
